import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import 'beaconing_service.dart';
import 'meridian_connection_task.dart';
import 'station_service.dart';
import 'tnc_service.dart';

// ---------------------------------------------------------------------------
// ForegroundServiceApi — injectable abstraction for testing
// ---------------------------------------------------------------------------

/// Injectable abstraction over [FlutterForegroundTask] static methods.
///
/// The default production implementation delegates to [FlutterForegroundTask]
/// directly. Inject a [ForegroundServiceApi] test double via the
/// [BackgroundServiceManager] constructor to avoid platform channel
/// dependencies in unit tests.
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
/// The [flutter_foreground_task] [TaskHandler] runs in a background isolate
/// and cannot access Provider-hosted services. This manager therefore acts as
/// the sole bridge: it listens to [TncService], [StationService], and
/// [BeaconingService] on the main isolate, starts/stops the foreground service
/// lifecycle, and calls [FlutterForegroundTask.updateService] directly to push
/// notification content updates — no round-trip through the background isolate.
class BackgroundServiceManager extends ChangeNotifier {
  BackgroundServiceManager({
    required TncService tnc,
    required StationService station,
    required BeaconingService beaconing,
    ForegroundServiceApi? taskApi,
  }) : _tnc = tnc,
       _station = station,
       _beaconing = beaconing,
       _taskApi = taskApi ?? const _DefaultForegroundServiceApi() {
    _tnc.addListener(_onServiceStateChanged);
    _station.addListener(_onServiceStateChanged);
    _beaconing.addListener(_onServiceStateChanged);
  }

  final TncService _tnc;
  final StationService _station;
  final BeaconingService _beaconing;
  final ForegroundServiceApi _taskApi;

  BackgroundServiceState _state = BackgroundServiceState.stopped;
  String? _errorMessage;
  Timer? _updateDebounce;

  BackgroundServiceState get state => _state;
  String? get errorMessage => _errorMessage;

  bool get isRunning =>
      _state == BackgroundServiceState.running ||
      _state == BackgroundServiceState.reconnecting;

  // ---------------------------------------------------------------------------
  // Static initialisation — call once before runApp()
  // ---------------------------------------------------------------------------

  /// Initialises [FlutterForegroundTask] options. Safe to call on all
  /// platforms (no-op on non-Android).
  ///
  /// Must be called before any [requestStartService] call.
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
        // onRepeatEvent fires every 60 s as a heartbeat.
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Requests that the Android foreground service be started.
  ///
  /// If Auto or Smart beaconing is configured, prompts for
  /// [Permission.locationAlways] (background location) before starting.
  ///
  /// Returns `true` if the service is running after this call. Returns `false`
  /// and sets [state] to [BackgroundServiceState.error] if a required
  /// permission is denied or the service fails to start.
  ///
  /// On non-Android platforms this is a no-op that returns `false`.
  Future<bool> requestStartService(BuildContext context) async {
    if (!Platform.isAndroid) return false;
    if (isRunning) return true;

    _setState(BackgroundServiceState.starting);

    // Background location is required for GPS beaconing while backgrounded.
    if (_beaconing.mode != BeaconMode.manual) {
      final granted = await _requestBackgroundLocationPermission(context);
      if (!granted) {
        _errorMessage =
            'Background location permission is required for beaconing '
            'while the app is in the background.';
        _setState(BackgroundServiceState.error);
        return false;
      }
    }

    // POST_NOTIFICATIONS is needed to show the notification on Android 13+.
    // Non-fatal: the keepalive still works even if the notification is hidden.
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
      _setState(BackgroundServiceState.running);
      return true;
    }

    _errorMessage = 'Failed to start background service.';
    _setState(BackgroundServiceState.error);
    return false;
  }

  /// Stops the Android foreground service.
  ///
  /// On non-Android platforms this is a no-op.
  Future<void> stopService() async {
    if (!Platform.isAndroid) return;
    await _taskApi.stopService();
    _setState(BackgroundServiceState.stopped);
  }

  // ---------------------------------------------------------------------------
  // Internal state tracking
  // ---------------------------------------------------------------------------

  void _onServiceStateChanged() {
    if (isRunning) {
      final tncReconnecting = _tnc.currentStatus == ConnectionStatus.connecting;
      final aprsReconnecting =
          _station.currentConnectionStatus == ConnectionStatus.connecting;
      final next = (tncReconnecting || aprsReconnecting)
          ? BackgroundServiceState.reconnecting
          : BackgroundServiceState.running;
      if (next != _state) _setState(next);
    }

    // Debounce: many rapid ChangeNotifier pings (BLE scanning, packet arrival)
    // must not spam updateService().
    _updateDebounce?.cancel();
    _updateDebounce = Timer(
      const Duration(milliseconds: 500),
      _pushNotificationUpdate,
    );

    notifyListeners();
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

  /// The notification title text for the current service state.
  ///
  /// Exposed for testing via [@visibleForTesting].
  @visibleForTesting
  String buildTitleForTest() => _buildTitle();

  /// The notification body text for the current service state.
  ///
  /// Exposed for testing via [@visibleForTesting].
  @visibleForTesting
  String buildBodyForTest() => _buildBody();

  /// Forces the internal state for unit testing without platform channel calls.
  @visibleForTesting
  void setStateForTest(BackgroundServiceState s) => _setState(s);

  String _buildTitle() {
    if (_state == BackgroundServiceState.reconnecting) {
      return 'Meridian — Reconnecting\u2026';
    }
    final tncOk = _tnc.currentStatus == ConnectionStatus.connected;
    final aprsOk =
        _station.currentConnectionStatus == ConnectionStatus.connected;
    if (tncOk && aprsOk) return 'Meridian — TNC + APRS-IS';
    if (tncOk) return 'Meridian — TNC connected';
    if (aprsOk) return 'Meridian — APRS-IS connected';
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

    // Show rationale before sending the user to Settings (Android 11+ always
    // redirects to Settings; the dialog explains what will happen).
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
    _tnc.removeListener(_onServiceStateChanged);
    _station.removeListener(_onServiceStateChanged);
    _beaconing.removeListener(_onServiceStateChanged);
    _updateDebounce?.cancel();
    super.dispose();
  }
}
