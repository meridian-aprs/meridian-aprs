import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/connection/connection_registry.dart';
import 'beaconing_service.dart';
import 'meridian_connection_task.dart';
import 'tx_service.dart';

// ---------------------------------------------------------------------------
// ForegroundServiceApi — injectable abstraction for testing
// ---------------------------------------------------------------------------

/// Injectable abstraction over [FlutterForegroundTask] static methods.
abstract interface class ForegroundServiceApi {
  Future<ServiceRequestResult> startService({
    required int serviceId,
    required String notificationTitle,
    required String notificationText,
    required VoidCallback callback,
  });

  Future<ServiceRequestResult> updateService({
    String? notificationTitle,
    String? notificationText,
  });

  Future<ServiceRequestResult> stopService();
}

class _DefaultForegroundServiceApi implements ForegroundServiceApi {
  const _DefaultForegroundServiceApi();

  @override
  Future<ServiceRequestResult> startService({
    required int serviceId,
    required String notificationTitle,
    required String notificationText,
    required VoidCallback callback,
  }) => FlutterForegroundTask.startService(
    serviceId: serviceId,
    notificationTitle: notificationTitle,
    notificationText: notificationText,
    callback: callback,
  );

  @override
  Future<ServiceRequestResult> updateService({
    String? notificationTitle,
    String? notificationText,
  }) => FlutterForegroundTask.updateService(
    notificationTitle: notificationTitle,
    notificationText: notificationText,
  );

  @override
  Future<ServiceRequestResult> stopService() =>
      FlutterForegroundTask.stopService();
}

/// State of the Android foreground service keepalive.
enum BackgroundServiceState {
  /// Service is not running. Normal foreground-app operation.
  stopped,

  /// Permission check or service startup in progress.
  starting,

  /// Foreground service is active; transports are being kept alive.
  running,

  /// Service is running but at least one transport dropped and is reconnecting.
  reconnecting,

  /// Service failed to start (permission denied, startup error, etc.).
  error,
}

/// Manages the Android foreground service that keeps APRS transport connections
/// alive while the app is backgrounded.
///
/// This service is Android-only. On all other platforms every public method
/// is a no-op and [state] remains [BackgroundServiceState.stopped].
///
/// **Architecture:**
/// Listens to [ConnectionRegistry] and [BeaconingService] on the main isolate.
/// Starts/stops the foreground service lifecycle and calls
/// [FlutterForegroundTask.updateService] to push notification content updates.
///
/// **Auto-start/stop:**
/// When [backgroundActivityEnabled] is true (the default), the service starts
/// automatically when beaconing activates in auto or smart mode, and stops
/// when beaconing deactivates.
///
/// **BLE reconnect:**
/// BLE connections self-manage reconnect via [ReconnectableMixin]. BSM tracks
/// only APRS-IS and Serial connections for background reconnect.
///
/// **TNC beaconing via IPC:**
/// When the background isolate sends a [send_tnc_beacon] IPC message, BSM
/// forwards it to [TxService.sendViaTncOnly].
class BackgroundServiceManager extends ChangeNotifier
    with WidgetsBindingObserver {
  BackgroundServiceManager({
    required ConnectionRegistry registry,
    required BeaconingService beaconing,
    required TxService tx,
    ForegroundServiceApi? taskApi,
  }) : _registry = registry,
       _beaconing = beaconing,
       _tx = tx,
       _taskApi = taskApi ?? const _DefaultForegroundServiceApi() {
    _registry.addListener(_onServiceStateChanged);
    _beaconing.addListener(_onServiceStateChanged);
    if (!kIsWeb && Platform.isAndroid) {
      WidgetsBinding.instance.addObserver(this);
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
      SharedPreferences.getInstance().then((prefs) {
        _backgroundActivityEnabled = prefs.getBool(_keyBgActivity) ?? true;
        notifyListeners();
      });
    }
  }

  final ConnectionRegistry _registry;
  final BeaconingService _beaconing;
  final TxService _tx;
  final ForegroundServiceApi _taskApi;

  static const _keyBgActivity = 'bg_activity_enabled';

  BackgroundServiceState _state = BackgroundServiceState.stopped;
  String? _errorMessage;
  Timer? _updateDebounce;

  bool _autoStarted = false;
  bool _needsPermission = false;
  bool _backgroundActivityEnabled = true;

  // ---------------------------------------------------------------------------
  // Background reconnect tracking
  // ---------------------------------------------------------------------------

  bool _isInBackground = false;

  /// IDs of connections that were active when the app went to background.
  /// BLE connections are excluded — they self-reconnect via [ReconnectableMixin].
  Set<String> _reconnectIds = {};

  /// Per-connection pending reconnect timers. Null entry = not scheduled.
  final Map<String, Timer?> _reconnectTimers = {};

  static const _kReconnectDelay = Duration(seconds: 10);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  BackgroundServiceState get state => _state;
  String? get errorMessage => _errorMessage;

  bool get isRunning =>
      _state == BackgroundServiceState.running ||
      _state == BackgroundServiceState.reconnecting;

  bool get backgroundActivityEnabled => _backgroundActivityEnabled;
  bool get needsPermission => _needsPermission;

  // ---------------------------------------------------------------------------
  // Static initialisation — call once before runApp()
  // ---------------------------------------------------------------------------

  static void initOptions() {
    if (!Platform.isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'meridian_connection',
        channelName: 'Connection',
        channelDescription:
            'Keeps APRS connections and beaconing active in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  Future<void> setBackgroundActivityEnabled(bool v) async {
    if (_backgroundActivityEnabled == v) return;
    _backgroundActivityEnabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBgActivity, v);
    if (!v && _autoStarted && isRunning) {
      await stopService();
    } else if (v &&
        !kIsWeb &&
        Platform.isAndroid &&
        _shouldBeRunning &&
        !isRunning) {
      _maybeAutoStart(); // ignore: unawaited_futures
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // shouldBeRunning / session predicates
  // ---------------------------------------------------------------------------

  bool get _shouldBeRunning =>
      _backgroundActivityEnabled &&
      (_registry.available.any(_isSessionActive) ||
          (_beaconing.isActive && _beaconing.mode != BeaconMode.manual));

  /// True while a connection is in any active state: connected, connecting,
  /// reconnecting, or waitingForDevice, or while backgrounded and tracked for
  /// reconnect.
  bool _isSessionActive(MeridianConnection conn) {
    final s = conn.status;
    if (s == ConnectionStatus.connected ||
        s == ConnectionStatus.connecting ||
        s == ConnectionStatus.reconnecting ||
        s == ConnectionStatus.waitingForDevice) {
      return true;
    }
    return _isInBackground && _reconnectIds.contains(conn.id);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<bool> requestStartService(BuildContext context) async {
    if (!Platform.isAndroid) return false;
    if (isRunning) return true;

    final wasAutoStartPending = _needsPermission;
    _needsPermission = false;

    _setState(BackgroundServiceState.starting);

    if (!context.mounted) return false;
    final locStatus = await Permission.locationWhenInUse.status;
    if (!locStatus.isGranted) {
      final result = await Permission.locationWhenInUse.request();
      if (!result.isGranted) {
        _errorMessage =
            'Location permission is required to run the background service.';
        _setState(BackgroundServiceState.error);
        return false;
      }
    }

    final needsGpsInBackground =
        _beaconing.isActive && _beaconing.mode != BeaconMode.manual;
    if (needsGpsInBackground) {
      if (!context.mounted) return false;
      final granted = await _requestBackgroundLocationPermission(context);
      if (!granted) {
        _errorMessage =
            'Background location permission is required for beaconing '
            'while the app is in the background.';
        _setState(BackgroundServiceState.error);
        return false;
      }
    }

    if (Platform.isAndroid) {
      await Permission.notification.request();
    }

    final result = await _taskApi.startService(
      serviceId: 1701,
      notificationTitle: _buildTitle(),
      notificationText: _buildBody(),
      callback: startMeridianConnectionTask,
    );

    if (result is ServiceRequestSuccess) {
      _autoStarted = wasAutoStartPending;
      _setState(BackgroundServiceState.running);
      return true;
    }

    _errorMessage = 'Failed to start background service.';
    _setState(BackgroundServiceState.error);
    return false;
  }

  Future<void> stopService() async {
    if (!Platform.isAndroid) return;
    await _taskApi.stopService();
    _autoStarted = false;
    _setState(BackgroundServiceState.stopped);
  }

  // ---------------------------------------------------------------------------
  // App lifecycle — background/foreground handoff
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb || !Platform.isAndroid || !isRunning) return;
    switch (state) {
      case AppLifecycleState.paused:
        _isInBackground = true;
        // Record which non-BLE connections were active so we can reconnect on
        // resume. BLE self-manages reconnect via ReconnectableMixin.
        _reconnectIds = _registry.all
            .where(
              (c) =>
                  c.type != ConnectionType.bleTnc &&
                  (c.status == ConnectionStatus.connected ||
                      c.status == ConnectionStatus.connecting),
            )
            .map((c) => c.id)
            .toSet();

        if (_beaconing.isActive && _beaconing.mode != BeaconMode.manual) {
          _beaconing.suspendTimerForBackground();
          FlutterForegroundTask.sendDataToTask({
            'type': 'start_beaconing',
            'last_beacon_ts':
                _beaconing.lastBeaconAt?.millisecondsSinceEpoch ?? 0,
          });
        }

      case AppLifecycleState.resumed:
        _isInBackground = false;

        // Cancel all pending reconnect timers — foreground handles reconnect.
        for (final id in _reconnectTimers.keys.toList()) {
          _reconnectTimers[id]?.cancel();
          _reconnectTimers[id] = null;
        }

        FlutterForegroundTask.sendDataToTask({'type': 'stop_beaconing'});
        _resumeBeaconingFromBackground();

        // Reconnect any tracked connection that dropped while backgrounded.
        for (final id in _reconnectIds) {
          final conn = _registry.byId(id);
          if (conn != null && conn.status == ConnectionStatus.disconnected) {
            conn.connect(); // ignore: unawaited_futures
          }
        }
        _reconnectIds = {};

      default:
        break;
    }
  }

  void _resumeBeaconingFromBackground() {
    if (!_beaconing.isActive) return;
    SharedPreferences.getInstance().then((prefs) async {
      await prefs.reload();
      final bgTsMs = prefs.getInt('bg_last_beacon_ts');
      final mainTs = _beaconing.lastBeaconAt;
      final DateTime ts;
      if (bgTsMs != null) {
        final bgTs = DateTime.fromMillisecondsSinceEpoch(bgTsMs);
        ts = (mainTs != null && mainTs.isAfter(bgTs)) ? mainTs : bgTs;
      } else {
        ts = mainTs ?? DateTime.now();
      }
      _beaconing.resumeFromBackground(ts);
    });
  }

  // ---------------------------------------------------------------------------
  // IPC — messages from background isolate
  // ---------------------------------------------------------------------------

  void _onTaskData(Object data) {
    if (data is! Map) return;
    final msg = Map<String, dynamic>.from(data);
    switch (msg['type'] as String?) {
      case 'send_tnc_beacon':
        final aprsLine = msg['aprs_line'] as String?;
        if (aprsLine != null) {
          _tx.sendViaTncOnly(aprsLine); // ignore: unawaited_futures
        }
      case 'beacon_sent':
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Auto-start / auto-stop
  // ---------------------------------------------------------------------------

  Future<void> _maybeAutoStart() async {
    if (!Platform.isAndroid) return;
    if (isRunning || !_backgroundActivityEnabled) return;
    if (!_shouldBeRunning) return;

    final locStatus = await Permission.locationWhenInUse.status;
    if (!locStatus.isGranted) {
      _needsPermission = true;
      notifyListeners();
      return;
    }

    final needsGpsInBackground =
        _beaconing.isActive && _beaconing.mode != BeaconMode.manual;
    if (needsGpsInBackground) {
      final status = await Permission.locationAlways.status;
      if (!status.isGranted) {
        _needsPermission = true;
        notifyListeners();
        return;
      }
    }

    await Permission.notification.request();

    final result = await _taskApi.startService(
      serviceId: 1701,
      notificationTitle: _buildTitle(),
      notificationText: _buildBody(),
      callback: startMeridianConnectionTask,
    );

    if (result is ServiceRequestSuccess) {
      _autoStarted = true;
      _needsPermission = false;
      _setState(BackgroundServiceState.running);
      await _pushNotificationUpdate();
    } else {
      _errorMessage = 'Failed to start background service.';
      _setState(BackgroundServiceState.error);
    }
  }

  // ---------------------------------------------------------------------------
  // Internal state tracking
  // ---------------------------------------------------------------------------

  void _onServiceStateChanged() {
    if (isRunning) {
      final anyIssue = _registry.all.any((c) {
        if (!c.isAvailable) return false;
        final s = c.status;
        if (s == ConnectionStatus.reconnecting ||
            s == ConnectionStatus.waitingForDevice) {
          return true;
        }
        if (_isInBackground &&
            _reconnectIds.contains(c.id) &&
            s == ConnectionStatus.disconnected) {
          return true;
        }
        return false;
      });
      final next = anyIssue
          ? BackgroundServiceState.reconnecting
          : BackgroundServiceState.running;
      if (next != _state) _setState(next);
    }

    if (!kIsWeb && Platform.isAndroid) {
      if (_shouldBeRunning && !isRunning) {
        _maybeAutoStart(); // ignore: unawaited_futures
      } else if (!_shouldBeRunning && _autoStarted && isRunning) {
        stopService(); // ignore: unawaited_futures
      }
    }

    if (_isInBackground && isRunning) {
      _maybeReconnectInBackground();
    }

    _updateDebounce?.cancel();
    if (isRunning) {
      _updateDebounce = Timer(
        const Duration(milliseconds: 500),
        _pushNotificationUpdate,
      );
    }

    notifyListeners();
  }

  void _maybeReconnectInBackground() {
    for (final id in _reconnectIds) {
      if (_reconnectTimers[id] != null) continue;
      final conn = _registry.byId(id);
      if (conn == null || conn.status != ConnectionStatus.disconnected) {
        continue;
      }

      _reconnectTimers[id] = Timer(_kReconnectDelay, () {
        _reconnectTimers[id] = null;
        final c = _registry.byId(id);
        if (_isInBackground &&
            _reconnectIds.contains(id) &&
            c != null &&
            c.status == ConnectionStatus.disconnected) {
          c.connect(); // ignore: unawaited_futures
        }
      });
    }
  }

  Future<void> _pushNotificationUpdate() async {
    if (!isRunning) return;
    await _taskApi.updateService(
      notificationTitle: _buildTitle(),
      notificationText: _buildBody(),
    );
  }

  void _setState(BackgroundServiceState s) {
    _state = s;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Notification content builders
  // ---------------------------------------------------------------------------

  @visibleForTesting
  String buildTitleForTest() => _buildTitle();

  @visibleForTesting
  String buildBodyForTest() => _buildBody();

  @visibleForTesting
  void setStateForTest(BackgroundServiceState s) => _setState(s);

  String _buildTitle() {
    if (_state == BackgroundServiceState.reconnecting) {
      final bleWaiting = _registry.all.any(
        (c) =>
            c.type == ConnectionType.bleTnc &&
            c.status == ConnectionStatus.waitingForDevice,
      );
      if (bleWaiting) return 'Meridian — Searching for TNC\u2026';
      return 'Meridian — Reconnecting\u2026';
    }
    final connected = _registry.connected;
    final hasTnc = connected.any(
      (c) =>
          c.type == ConnectionType.bleTnc || c.type == ConnectionType.serialTnc,
    );
    final hasAprsIs = connected.any((c) => c.type == ConnectionType.aprsIs);
    if (hasTnc && hasAprsIs) return 'Meridian — TNC + APRS-IS';
    if (hasTnc) return 'Meridian — TNC connected';
    if (hasAprsIs) return 'Meridian — APRS-IS connected';
    return 'Meridian — Connected';
  }

  String _buildBody() {
    final beaconPart = _buildBeaconPart();
    final agoPart = _beaconing.lastBeaconAgo;
    if (agoPart != null && _beaconing.isActive) {
      return '$beaconPart · Last beacon: $agoPart';
    }
    return beaconPart;
  }

  String _buildBeaconPart() {
    if (!_beaconing.isActive) return 'Beaconing off';
    return switch (_beaconing.mode) {
      BeaconMode.auto =>
        'Auto beacon every ${_formatInterval(_beaconing.autoIntervalS)}',
      BeaconMode.smart => 'SmartBeaconing\u2122 active',
      BeaconMode.manual => 'Manual mode',
    };
  }

  String _formatInterval(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    return '${minutes}m';
  }

  // ---------------------------------------------------------------------------
  // Permission helper
  // ---------------------------------------------------------------------------

  Future<bool> _requestBackgroundLocationPermission(
    BuildContext context,
  ) async {
    final current = await Permission.locationAlways.status;
    if (current.isGranted) return true;
    if (!context.mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Background location needed'),
        content: const Text(
          'To beacon your position while Meridian is in the background, '
          'tap Continue and select "Allow all the time" on the next screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    final result = await Permission.locationAlways.request();
    return result.isGranted;
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _registry.removeListener(_onServiceStateChanged);
    _beaconing.removeListener(_onServiceStateChanged);
    _updateDebounce?.cancel();
    for (final timer in _reconnectTimers.values) {
      timer?.cancel();
    }
    _reconnectTimers.clear();
    if (!kIsWeb && Platform.isAndroid) {
      WidgetsBinding.instance.removeObserver(this);
      FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    }
    super.dispose();
  }
}
