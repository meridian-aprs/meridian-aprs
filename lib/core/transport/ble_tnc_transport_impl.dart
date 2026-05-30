library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:universal_ble/universal_ble.dart';

import 'aprs_transport.dart' show ConnectionStatus;
import 'ble_constants.dart';
import 'ble_diagnostics.dart';
import 'kiss_framer.dart';
import 'kiss_tnc_transport.dart';

// ---------------------------------------------------------------------------
// Platform-neutral BLE types
// ---------------------------------------------------------------------------
//
// The transport speaks only these FBP-free types, so swapping the underlying
// BLE plugin never reaches past [BleDeviceAdapter]. UUIDs are plain lower-case
// strings (callers compare case-insensitively); there is no plugin-specific
// GUID/characteristic-object type anywhere above the adapter.

/// A discovered GATT service and the UUIDs of its characteristics.
class BleGattService {
  const BleGattService(this.uuid, this.characteristicUuids);

  final String uuid;
  final List<String> characteristicUuids;
}

/// Neutral link state surfaced on [BleDeviceAdapter.connectionState].
enum BleLinkState { connected, disconnected }

// ---------------------------------------------------------------------------
// Testability abstraction
// ---------------------------------------------------------------------------

/// Plugin-agnostic seam for a single BLE peripheral, keyed by its device id.
///
/// Production code uses [UniversalBleDeviceAdapter]; tests inject a fake. The
/// interface is intentionally free of any BLE-plugin type so the transport and
/// everything above it compiles without a plugin dependency.
abstract interface class BleDeviceAdapter {
  /// Stable platform device identifier (MAC on Android, UUID on iOS).
  String get deviceId;

  /// Friendly name for diagnostics/logs (advertised name when known).
  String get displayName;

  Future<void> connect({Duration timeout, bool autoConnect});
  Future<void> disconnect();

  /// Requests an MTU and returns the negotiated ATT MTU (full frame size,
  /// including the 3-byte ATT header — callers subtract it for payload size).
  Future<int> requestMtu(int desired);

  /// Whether the OS reports this device as bonded. On platforms that bond
  /// transparently or expose no system pairing API (iOS/desktop) this returns
  /// `true` so callers skip explicit pairing.
  Future<bool> isPaired();

  /// Bonds with the device via the OS pairing flow. No-op where the OS has no
  /// system pairing API (iOS/desktop). Throws if pairing is rejected/fails.
  Future<void> pair();

  Future<List<BleGattService>> discoverServices();

  /// Enables notifications on [charUuid] and routes its values to
  /// [notifications]. Only one notify characteristic is subscribed at a time.
  Future<void> subscribe(String serviceUuid, String charUuid);

  Future<void> writeValue(
    String serviceUuid,
    String charUuid,
    Uint8List value, {
    required bool withResponse,
  });

  /// Bytes delivered by the subscribed notify characteristic.
  Stream<Uint8List> get notifications;

  /// OS link state for this device. Survives session teardown so a late drop
  /// still reaches the transport's error path — see [BleTncTransport].
  Stream<BleLinkState> get connectionState;
}

/// Production [BleDeviceAdapter] backed by `universal_ble`'s static,
/// device-id-keyed API.
///
/// universal_ble exposes per-device streams keyed by `deviceId`
/// ([UniversalBle.connectionStream] / [UniversalBle.characteristicValueStream]),
/// so this adapter needs no global-callback demultiplexing — each stream is
/// already scoped to this device. The connection stream survives session
/// teardown naturally, which is what lets a late OS-side drop still reach the
/// transport's error path (see [BleTncTransport]).
class UniversalBleDeviceAdapter implements BleDeviceAdapter {
  UniversalBleDeviceAdapter(this.deviceId, {String? displayName})
    : displayName = (displayName == null || displayName.isEmpty)
          ? deviceId
          : displayName;

  @override
  final String deviceId;

  @override
  final String displayName;

  /// Set by [subscribe]; identifies the notify characteristic whose values
  /// flow on [notifications].
  String? _notifyCharUuid;

  @override
  Stream<BleLinkState> get connectionState =>
      UniversalBle.connectionStream(deviceId).map(
        (isConnected) =>
            isConnected ? BleLinkState.connected : BleLinkState.disconnected,
      );

  @override
  Stream<Uint8List> get notifications {
    final charUuid = _notifyCharUuid;
    if (charUuid == null) return const Stream<Uint8List>.empty();
    return UniversalBle.characteristicValueStream(deviceId, charUuid);
  }

  @override
  Future<void> connect({
    Duration timeout = const Duration(seconds: 15),
    bool autoConnect = false,
  }) => UniversalBle.connect(
    deviceId,
    timeout: timeout,
    autoConnect: autoConnect,
  );

  @override
  Future<void> disconnect() => UniversalBle.disconnect(deviceId);

  @override
  Future<int> requestMtu(int desired) =>
      UniversalBle.requestMtu(deviceId, desired);

  @override
  Future<bool> isPaired() async {
    // Only Android exposes a system bond-state API. On iOS/macOS CoreBluetooth
    // bonds transparently on encrypted-characteristic access (no system pairing
    // API), so report "paired" to skip the explicit flow.
    if (!Platform.isAndroid) return true;
    return (await UniversalBle.isPaired(deviceId)) ?? false;
  }

  @override
  Future<void> pair() async {
    if (!Platform.isAndroid) return;
    await UniversalBle.pair(deviceId);
  }

  @override
  Future<List<BleGattService>> discoverServices() async {
    final services = await UniversalBle.discoverServices(deviceId);
    return services
        .map(
          (s) => BleGattService(
            s.uuid,
            s.characteristics.map((c) => c.uuid).toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> subscribe(String serviceUuid, String charUuid) async {
    _notifyCharUuid = charUuid;
    await UniversalBle.subscribeNotifications(deviceId, serviceUuid, charUuid);
  }

  @override
  Future<void> writeValue(
    String serviceUuid,
    String charUuid,
    Uint8List value, {
    required bool withResponse,
  }) => UniversalBle.write(
    deviceId,
    serviceUuid,
    charUuid,
    value,
    withoutResponse: !withResponse,
  );
}

// ---------------------------------------------------------------------------
// BleTncTransport
// ---------------------------------------------------------------------------

/// BLE KISS TNC transport.
///
/// Implements [KissTncTransport], emitting raw AX.25 frame payloads on
/// [frameStream]. Connects to BLE TNCs from either supported GATT family —
/// the `aprs-specs` BLE-KISS API (Mobilinkd, PicoAPRS, B.B. Link, RPC,
/// CA2RXU) and the older Benshi/BTECH family (UV-Pro, Vero VR-N76, VR-N7500,
/// Radioddity GA-5WB). The family is autodetected at connect time from the
/// discovered service list, or selected explicitly via the `family`
/// constructor argument when known from advertisement data.
///
/// Connection flow:
///   scan → connect → discoverServices
///   → subscribe to TX characteristic → ready
///
/// Incoming BLE chunks are reassembled into complete KISS frames by the
/// existing [KissFramer]. Outgoing frames are KISS-encoded and split into
/// MTU-sized chunks before writing to the RX characteristic.
class BleTncTransport extends KissTncTransport {
  /// Construct a transport for a given device id.
  ///
  /// [deviceName] is a friendly label used only for diagnostics/logs.
  ///
  /// [family] selects the BLE-KISS GATT family. When `null` (default), the
  /// transport autodetects the family at connect time by scanning the
  /// discovered service list. Pass a non-null value when the family is already
  /// known from advertisement data — it skips one round of service-list
  /// inspection and produces clearer error messages on mismatch.
  BleTncTransport(
    String deviceId, {
    String? deviceName,
    BleDeviceAdapter? adapter,
    BleKissFamily? family,
  }) : _adapter =
           adapter ??
           UniversalBleDeviceAdapter(deviceId, displayName: deviceName),
       _hintedFamily = family;

  final BleDeviceAdapter _adapter;
  final BleKissFamily? _hintedFamily;

  /// The active GATT profile, resolved either from [_hintedFamily] or by
  /// scanning the post-discovery service list. Null until [connect] succeeds
  /// far enough to pick one. Exposed as [activeFamily] for diagnostics.
  BleKissProfile? _profile;

  /// Which BLE-KISS family the live session is using, or `null` when not
  /// connected. Useful for diagnostics and family-aware UI hints.
  BleKissFamily? get activeFamily => _profile?.family;

  // Effective MTU for outgoing chunk size (payload bytes, not ATT frame size).
  int _mtu = 20;

  // Keepalive: reset on every write; fires if the link is idle for too long.
  // The cadence is purely an application-level self-watchdog — the OS already
  // surfaces a true link drop via the connection-state stream within the BLE
  // supervision timeout, so we don't need to race that. 4 s is well under the
  // 5.12 s supervision timeout, halves radio wakes vs the prior 2 s cadence,
  // and still gives a fast indicator if the peripheral has wedged its TX path
  // independent of the OS link state.
  static const _keepaliveInterval = Duration(seconds: 4);
  Timer? _keepaliveTimer;

  final _kissFramer = KissFramer();
  StreamSubscription<Uint8List>? _framesSub;
  StreamSubscription<Uint8List>? _notifySub;
  StreamSubscription<BleLinkState>? _connStateSub;

  final _framesController = StreamController<Uint8List>.broadcast();
  final _stateController = StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _status = ConnectionStatus.disconnected;

  @override
  Stream<Uint8List> get frameStream => _framesController.stream;

  @override
  Stream<ConnectionStatus> get connectionState => _stateController.stream;

  @override
  ConnectionStatus get currentStatus => _status;

  @override
  bool get isConnected => _status == ConnectionStatus.connected;

  /// Connect using OS background scanning (autoConnect mode).
  ///
  /// Emits [ConnectionStatus.waitingForDevice] while the OS scans, then
  /// transitions to [ConnectionStatus.connected] once the device is found.
  /// The wait is up to one hour; calling [disconnect] cancels it.
  @override
  Future<void> connectBackground() => _connect(autoConnect: true);

  @override
  Future<void> connect() => _connect(autoConnect: false);

  Future<void> _connect({required bool autoConnect}) async {
    BleDiagnostics.I.log(
      BleEventKind.connectStart,
      'device=${_adapter.displayName} autoConnect=$autoConnect',
    );
    _setStatus(
      autoConnect
          ? ConnectionStatus.waitingForDevice
          : ConnectionStatus.connecting,
    );
    try {
      // 1. Connect to the device.
      //    autoConnect: true — OS manages background scanning; no explicit
      //    timeout needed beyond a ceiling to avoid hanging forever if the
      //    device is turned off permanently.
      //
      //    NOTE: There is no GATT-cache clear here. The previous BLE plugin
      //    offered clearGattCache() to dodge Android GATT status 133 on stale
      //    service tables; universal_ble has no equivalent. The reconnect cascade in
      //    BleConnection (ReconnectableMixin) absorbs a transient 133 by
      //    retrying, so the practical impact is an occasional extra retry.
      await _adapter.connect(
        timeout: autoConnect
            ? const Duration(hours: 1)
            : const Duration(seconds: 15),
        autoConnect: autoConnect,
      );

      // 1a. Subscribe to BLE connection-state events as soon as the OS
      //     considers the link established. The subscription is intentionally
      //     attached BEFORE the rest of setup so an early adverse event
      //     (e.g. a peer-side drop during service discovery) is captured.
      //     It is also intentionally NOT torn down by [_cleanupSubscriptions]
      //     so that a late OS state event still drives the error path. The
      //     adapter keeps its underlying global callback alive until its own
      //     disconnect() runs, which only happens via [disconnect] /
      //     transport teardown — never from [_cleanupSubscriptions].
      _connStateSub ??= _adapter.connectionState.listen(_onBleConnectionState);

      // 1b. Connection-priority request is deliberately not made. The Mobilinkd
      //     TNC4 dropped the link within the 5.12 s LINK_SUPERVISION_TIMEOUT
      //     when a high-priority connection was requested immediately after
      //     connect (2026-04-30 drive-test diagnostics: identical 5.4 s drop
      //     cycles with HIGH priority enabled, stable 110 s with it disabled).
      //     universal_ble DOES expose a priority API
      //     (`UniversalBle.requestConnectionPriority` / `BleConnectionPriority`),
      //     but we deliberately neither call it nor surface it on
      //     [BleDeviceAdapter] — the seam has no priority method, so this hazard
      //     cannot be reintroduced without consciously widening the interface.
      //     Re-enabling it needs family-aware gating proven safe on hardware.

      // 2. Request and read the negotiated MTU.
      //    Unlike the previous BLE plugin (which auto-negotiated MTU inside
      //    connect() and exposed it via a getter), universal_ble only surfaces the MTU as
      //    the return value of an explicit requestMtu(). A failed/declined
      //    request falls back to the 23-byte ATT default (20-byte payload),
      //    which still carries APRS-sized frames fine. ATT overhead is 3 bytes.
      int negotiated;
      try {
        negotiated = await _adapter.requestMtu(512);
      } catch (e) {
        debugPrint(
          'BleTncTransport: requestMtu failed ($e); using ATT default',
        );
        negotiated = 23;
      }
      _mtu = max(20, negotiated - 3);
      debugPrint('BleTncTransport: MTU $negotiated, using $_mtu byte chunks');

      // 3. Discover services (retry up to 3× — Android BLE stacks sometimes
      //    need a moment after connect() before the GATT cache is ready).
      List<BleGattService>? services;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          if (attempt == 1) {
            // Brief settle time before first attempt — Android BLE timing.
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          services = await _adapter.discoverServices();
          break;
        } catch (e) {
          debugPrint(
            'BleTncTransport: discoverServices attempt $attempt failed: $e',
          );
          BleDiagnostics.I.log(
            BleEventKind.serviceDiscoveryRetry,
            'attempt=$attempt error=$e',
          );
          if (attempt == 3) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      // 4. Resolve the GATT profile (which BLE-KISS family this device speaks)
      //    and find the matching service. When [_hintedFamily] was provided we
      //    look for that exact service; otherwise we scan the discovered list
      //    for the first known family service and adopt it.
      final profile = _resolveProfile(services!);
      if (profile == null) {
        throw Exception(
          'BleTncTransport: no supported BLE-KISS service found on '
          '${_adapter.displayName}. Make sure KISS mode is enabled — '
          'BTECH/Vero radios require enabling KISS in the radio menu.',
        );
      }
      _profile = profile;

      // 5. Confirm the notify (host RX) and write (host TX) characteristics
      //    exist on the resolved service.
      final service = services.firstWhere(
        (s) => s.uuid.toLowerCase() == profile.serviceUuid.toLowerCase(),
      );
      final chars = service.characteristicUuids
          .map((c) => c.toLowerCase())
          .toSet();
      final hasNotify = chars.contains(profile.notifyCharUuid.toLowerCase());
      final hasWrite = chars.contains(profile.writeCharUuid.toLowerCase());
      if (!hasNotify || !hasWrite) {
        throw Exception(
          'BleTncTransport: notify or write characteristic not found for '
          '${profile.family.name}. notify=$hasNotify write=$hasWrite',
        );
      }

      // 5b. Ensure the device is bonded BEFORE any write, for families that
      //     require it. The Benshi/BTECH family (UV-Pro, Vero, Radioddity) gates
      //     its write characteristic behind an encrypted link: if we let bonding
      //     happen lazily on the first beacon write, the pairing handshake stalls
      //     the link mid-stream and the connection drops. Pairing up-front while
      //     idle avoids that. The aprs-specs family (Mobilinkd etc.) uses
      //     unencrypted characteristics and must NOT be bonded — calling pair()
      //     there would pop a spurious OS dialog the previous plugin never showed.
      //     isPaired() short-circuits on iOS/desktop (transparent bonding / no
      //     system pairing API), so this only acts on Android.
      if (profile.family == BleKissFamily.benshi &&
          !await _adapter.isPaired()) {
        BleDiagnostics.I.log(
          BleEventKind.pairingStarted,
          'device=${_adapter.displayName}',
        );
        try {
          await _adapter.pair();
          BleDiagnostics.I.log(BleEventKind.pairingSucceeded);
        } catch (e) {
          BleDiagnostics.I.log(BleEventKind.pairingFailed, 'error=$e');
          rethrow;
        }
      }

      // 6. Subscribe to TX (notify) characteristic notifications.
      await _adapter.subscribe(profile.serviceUuid, profile.notifyCharUuid);
      _notifySub = _adapter.notifications.listen(_onBleChunk);

      // 7. Wire KissFramer output → frameStream.
      _framesSub = _kissFramer.frames.listen(_framesController.add);

      _setStatus(ConnectionStatus.connected);
      debugPrint(
        'BleTncTransport: connected to ${_adapter.displayName}, starting keepalive timer',
      );
      BleDiagnostics.I.log(
        BleEventKind.connectSuccess,
        'device=${_adapter.displayName} family=${profile.family.name} mtu=$_mtu',
      );

      // 8. Start the idle keepalive timer.
      //    Acts as an application-level self-watchdog so a wedged peripheral
      //    TX path is detected promptly without waiting on the OS supervision
      //    timeout. The keepalive sends a single TXDELAY frame every
      //    [_keepaliveInterval] (currently 4 s — see field doc).
      //
      //    NOTE: Do NOT call _sendKissInit() here on any family. On the
      //    Mobilinkd TNC4 (aprs-specs family), sending the five standard KISS
      //    parameter frames (TXDELAY/PERSIST/SLOTTIME/TXTAIL/FULLDUPLEX)
      //    causes the modem to reinitialise — its BLE radio goes dark for
      //    ~5 s, long enough for the supervision timeout (5.12 s) to expire
      //    and drop the connection. The Mobilinkd retains its own
      //    configuration persistently. The Benshi family is untested for KISS
      //    init behaviour; default to skipping until proven safe.
      //    DO NOT use command 0x06 (SETHARDWARE) on any family either — it is
      //    Mobilinkd's proprietary config protocol and causes an immediate
      //    disconnect on aprs-specs hardware. Benshi devices ignore unknown
      //    KISS commands today but that's incidental, not contractual.
      _resetKeepalive();
    } catch (e) {
      debugPrint('BleTncTransport connect failed: $e');
      BleDiagnostics.I.log(
        BleEventKind.connectFailed,
        'device=${_adapter.displayName} error=$e',
      );
      _setStatus(ConnectionStatus.error);
      // Best-effort cleanup before rethrowing — including the connection-state
      // listener and the adapter's global callbacks, since a failed connect
      // produces no live session for them to observe.
      await _cleanupSubscriptions();
      await _cancelConnStateSub();
      try {
        await _adapter.disconnect();
      } catch (_) {}
      rethrow;
    }
  }

  /// Marks the next [disconnect] call as an internal teardown (e.g. mid-reconnect)
  /// so the diagnostics log records [BleEventKind.disconnectInternal] instead of
  /// [BleEventKind.disconnectUser]. The flag is consumed (cleared) by [disconnect].
  ///
  /// Used by the [BleConnection] layer when rebuilding the transport during a
  /// reconnect attempt — without this, the log was misleadingly attributing
  /// every reconnect cycle's teardown to a user action.
  void markInternalTeardown() {
    _internalTeardown = true;
  }

  bool _internalTeardown = false;

  @override
  Future<void> disconnect() async {
    if (_status == ConnectionStatus.disconnected) return;
    final wasInternal = _internalTeardown;
    _internalTeardown = false;
    BleDiagnostics.I.log(
      wasInternal
          ? BleEventKind.disconnectInternal
          : BleEventKind.disconnectUser,
      'device=${_adapter.displayName}',
    );
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    _setStatus(ConnectionStatus.disconnected);
    await _cleanupSubscriptions();
    await _cancelConnStateSub();
    _profile = null;
    try {
      await _adapter.disconnect();
    } catch (_) {}
    _kissFramer.dispose();
  }

  @override
  Future<void> sendFrame(Uint8List ax25Frame) async {
    final profile = _profile;
    if (profile == null || !isConnected) {
      throw StateError('BleTncTransport: not connected');
    }
    _keepaliveTimer?.cancel();
    try {
      final kissFrame = KissFramer.encode(ax25Frame);
      final chunks = (kissFrame.length + _mtu - 1) ~/ _mtu;
      debugPrint(
        'BleTncTransport: sendFrame ${ax25Frame.length}B → ${kissFrame.length}B KISS in $chunks chunk(s)',
      );
      // Split into MTU-sized chunks and write sequentially with response.
      int offset = 0;
      while (offset < kissFrame.length) {
        final end = min(offset + _mtu, kissFrame.length);
        final chunk = Uint8List.sublistView(kissFrame, offset, end);
        await _adapter.writeValue(
          profile.serviceUuid,
          profile.writeCharUuid,
          chunk,
          withResponse: true,
        );
        offset = end;
      }
    } finally {
      // Always reschedule the keepalive — even on write failure — so the
      // timer isn't left permanently cancelled if the caller catches the error
      // and keeps the connection open.
      _resetKeepalive();
    }
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  /// Pick the GATT profile to use for this connection.
  ///
  /// Honours [_hintedFamily] when provided — that's the path scan-driven
  /// connects take, since the family is already known from advertisement data.
  /// When no hint is provided (cold reconnect from persisted device id),
  /// scan the discovered service list for the first known family.
  BleKissProfile? _resolveProfile(List<BleGattService> services) {
    final advertised = services.map((s) => s.uuid.toLowerCase()).toSet();
    if (_hintedFamily != null) {
      final hinted = BleKissProfile.forFamily(_hintedFamily);
      if (advertised.contains(hinted.serviceUuid.toLowerCase())) {
        return hinted;
      }
      // Hint was wrong — fall through to autodetect rather than fail outright.
      // This is forgiving when a user's saved device ID belongs to a model
      // whose family they later changed (e.g. firmware swap).
    }
    for (final profile in BleKissProfile.all) {
      if (advertised.contains(profile.serviceUuid.toLowerCase())) {
        return profile;
      }
    }
    return null;
  }

  void _onBleChunk(Uint8List chunk) {
    _kissFramer.addBytes(chunk);
  }

  void _onBleConnectionState(BleLinkState state) {
    BleDiagnostics.I.log(BleEventKind.bleStateChanged, state.name);
    if (state == BleLinkState.disconnected &&
        _status == ConnectionStatus.connected) {
      debugPrint(
        'BleTncTransport: unexpected disconnect from ${_adapter.displayName}',
      );
      BleDiagnostics.I.log(
        BleEventKind.disconnectUnexpected,
        'device=${_adapter.displayName}',
      );
      // _status is set synchronously before the unawaited cleanup, so a
      // second delivery of this event cannot re-enter (guard is already false).
      // The keepalive timer is also cancelled synchronously on the first line
      // of _cleanupSubscriptions, so no keepalive can fire mid-cleanup.
      _status = ConnectionStatus.error;
      _stateController.add(ConnectionStatus.error);
      _cleanupSubscriptions(); // unawaited — safe, see above
    }
  }

  /// Cancels per-session subscriptions (notify / framer / keepalive).
  ///
  /// Intentionally does NOT cancel [_connStateSub] — that listener is the
  /// only path by which a late OS-side disconnect can drive the error stream
  /// after this method runs, and it must survive session teardown for that to
  /// work. The listener is cancelled in [disconnect] / [_cancelConnStateSub].
  Future<void> _cleanupSubscriptions() async {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    await _notifySub?.cancel();
    _notifySub = null;
    await _framesSub?.cancel();
    _framesSub = null;
  }

  Future<void> _cancelConnStateSub() async {
    await _connStateSub?.cancel();
    _connStateSub = null;
  }

  /// Cancels any pending keepalive and schedules a new one.
  ///
  /// Call after every outbound write so the timer only fires during genuine
  /// silence. When real APRS traffic is flowing the timer is continuously
  /// reset and never actually fires.
  void _resetKeepalive() {
    _keepaliveTimer?.cancel();
    if (!isConnected) return;
    _keepaliveTimer = Timer(_keepaliveInterval, _onKeepalive);
  }

  // Static so tests can override without making _onKeepalive any wider.
  @visibleForTesting
  static Duration keepaliveRetryDelay = const Duration(milliseconds: 200);

  /// Fires when the link has been idle for [_keepaliveInterval].
  ///
  /// Sends a single KISS TXDELAY frame — harmless to any KISS TNC and
  /// sufficient to reset the peripheral's idle timer. Uses write-without-response
  /// to avoid ATT round-trip latency on a fire-and-forget keepalive.
  ///
  /// On write failure the keepalive retries exactly once after a short delay
  /// before declaring the link dead. This absorbs a single transient stall
  /// (Doze transition, brief OS scheduling hiccup) without tripping the full
  /// reconnect cascade. If the retry also fails the link is marked as error.
  Future<void> _onKeepalive() async {
    if (!isConnected) return;
    final profile = _profile;
    if (profile == null) return;
    final payload = Uint8List.fromList([0xC0, 0x01, 30, 0xC0]);
    try {
      await _adapter.writeValue(
        profile.serviceUuid,
        profile.writeCharUuid,
        payload,
        withResponse: false,
      );
      BleDiagnostics.I.log(BleEventKind.keepaliveSent);
      _resetKeepalive();
      return;
    } catch (e) {
      BleDiagnostics.I.log(BleEventKind.keepaliveFailed, 'attempt=1 error=$e');
    }

    // Retry once after a short delay — rebind state in case status changed
    // mid-delay (e.g. user tapped disconnect).
    await Future<void>.delayed(keepaliveRetryDelay);
    if (!isConnected) return;
    final retryProfile = _profile;
    if (retryProfile == null) return;
    try {
      await _adapter.writeValue(
        retryProfile.serviceUuid,
        retryProfile.writeCharUuid,
        payload,
        withResponse: false,
      );
      BleDiagnostics.I.log(BleEventKind.keepaliveRetried, 'recovered=true');
      _resetKeepalive();
      return;
    } catch (e) {
      debugPrint(
        'BleTncTransport: keepalive write failed twice, marking link dropped: $e',
      );
      BleDiagnostics.I.log(BleEventKind.keepaliveFailed, 'attempt=2 error=$e');
      if (_status == ConnectionStatus.connected) {
        BleDiagnostics.I.log(
          BleEventKind.disconnectKeepaliveFailed,
          'device=${_adapter.displayName}',
        );
        _status = ConnectionStatus.error;
        _stateController.add(ConnectionStatus.error);
        await _cleanupSubscriptions();
      }
    }
  }

  void _setStatus(ConnectionStatus status) {
    _status = status;
    _stateController.add(status);
  }
}
