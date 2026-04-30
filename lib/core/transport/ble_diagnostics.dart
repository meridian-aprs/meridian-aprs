library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Categorical kind of a [BleEvent].
///
/// Names are short on purpose so the resulting log line stays readable when
/// the user copies it to chat / email.
enum BleEventKind {
  connectStart,
  connectSuccess,
  connectFailed,
  disconnectUser,
  disconnectUnexpected,
  disconnectKeepaliveFailed,
  bleStateChanged,
  serviceDiscoveryRetry,
  keepaliveSent,
  keepaliveFailed,
  reconnectScheduled,
  reconnectAttempt,
  waitingPhase,
  sessionConnected,
  note,
  // Append-only — adding values above shifts persisted-log indices and breaks
  // hydration from prior builds.
  connectionPriorityRequested,
  connectionPriorityFailed,
  keepaliveRetried,
  disconnectInternal,
}

/// One entry in the BLE diagnostics log.
@immutable
class BleEvent {
  const BleEvent({
    required this.timestamp,
    required this.kind,
    this.detail = '',
  });

  final DateTime timestamp;
  final BleEventKind kind;
  final String detail;

  /// Encodes this event as a single pipe-delimited line.
  ///
  /// Format: `<ms-epoch-utc>|<kind-index>|<detail>`. Detail is allowed to
  /// contain pipes — only the first two are treated as delimiters.
  String encode() =>
      '${timestamp.toUtc().millisecondsSinceEpoch}|${kind.index}|$detail';

  /// Decodes a previously [encode]d line. Returns `null` for malformed input
  /// so a corrupted prefs blob never crashes startup.
  static BleEvent? tryDecode(String line) {
    final firstPipe = line.indexOf('|');
    if (firstPipe <= 0) return null;
    final secondPipe = line.indexOf('|', firstPipe + 1);
    if (secondPipe <= firstPipe) return null;

    final ms = int.tryParse(line.substring(0, firstPipe));
    final kindIdx = int.tryParse(line.substring(firstPipe + 1, secondPipe));
    if (ms == null || kindIdx == null) return null;
    if (kindIdx < 0 || kindIdx >= BleEventKind.values.length) return null;

    return BleEvent(
      timestamp: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
      kind: BleEventKind.values[kindIdx],
      detail: line.substring(secondPipe + 1),
    );
  }

  /// Human-readable single-line representation suitable for the diagnostics UI
  /// and for clipboard export. Format: `HH:mm:ss.SSS  <kind>  <detail>`.
  String formatHuman() {
    final t = timestamp.toLocal();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    final detailSuffix = detail.isEmpty ? '' : '  $detail';
    return '$hh:$mm:$ss.$ms  ${kind.name}$detailSuffix';
  }
}

/// Ring-buffered diagnostics log for BLE TNC events.
///
/// One per process. The deepest instrumentation sites (inside
/// [BleTncTransport] etc.) cannot reasonably reach a Provider, so this exposes
/// a static [I] singleton for write access. Tests construct fresh instances
/// directly to avoid global state.
///
/// Persistence: events are written to SharedPreferences on a ~1 s debounce so
/// a crash mid-session doesn't lose the log, but we don't pay a write per
/// event during a flurry of state changes.
class BleDiagnostics extends ChangeNotifier {
  BleDiagnostics({
    SharedPreferences? prefs,
    this.maxEvents = _defaultMaxEvents,
    Duration persistDebounce = const Duration(seconds: 1),
    DateTime Function() clock = DateTime.now,
  }) : _prefs = prefs,
       _persistDebounce = persistDebounce,
       _clock = clock;

  static const _defaultMaxEvents = 200;
  static const _prefsKey = 'ble_diagnostics_log_v1';

  /// Process-wide instance. Wired in `main.dart`. Tests should NOT use this —
  /// construct a fresh [BleDiagnostics] directly.
  static BleDiagnostics I = BleDiagnostics();

  final int maxEvents;
  final Duration _persistDebounce;
  final DateTime Function() _clock;

  SharedPreferences? _prefs;
  Timer? _persistTimer;

  final Queue<BleEvent> _events = Queue<BleEvent>();

  /// Snapshot of all events, oldest first. Cheap (bounded by [maxEvents]).
  List<BleEvent> get events => List.unmodifiable(_events);

  /// Restores any previously-persisted log. Safe to call before [SharedPreferences]
  /// is otherwise initialised — re-reads on first call.
  Future<void> hydrate() async {
    _prefs ??= await SharedPreferences.getInstance();
    final lines = _prefs!.getStringList(_prefsKey);
    if (lines == null || lines.isEmpty) return;
    _events.clear();
    for (final line in lines) {
      final ev = BleEvent.tryDecode(line);
      if (ev != null) _events.add(ev);
    }
    while (_events.length > maxEvents) {
      _events.removeFirst();
    }
    notifyListeners();
  }

  /// Append a new event. Trims the oldest entry if the buffer is full.
  void log(BleEventKind kind, [String detail = '']) {
    final event = BleEvent(timestamp: _clock(), kind: kind, detail: detail);
    _events.addLast(event);
    while (_events.length > maxEvents) {
      _events.removeFirst();
    }
    if (kDebugMode) {
      debugPrint('[BLE] ${event.formatHuman()}');
    }
    notifyListeners();
    _schedulePersist();
  }

  /// Clears the log immediately and persists the empty state.
  Future<void> clear() async {
    _events.clear();
    notifyListeners();
    _persistTimer?.cancel();
    _persistTimer = null;
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Forces a synchronous persistence write. Used at app pause so we never
  /// lose the last few events to a process kill.
  Future<void> flush() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      _events.map((e) => e.encode()).toList(),
    );
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, () {
      _persistTimer = null;
      // Fire and forget — persistence failure is non-fatal and the in-memory
      // log is the source of truth for the current session.
      flush();
    });
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _persistTimer = null;
    super.dispose();
  }
}
