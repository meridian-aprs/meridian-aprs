import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/transport/ble_diagnostics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BleEvent', () {
    test('encode/decode round-trip preserves all fields', () {
      final original = BleEvent(
        timestamp: DateTime.utc(2026, 4, 30, 12, 34, 56, 789),
        kind: BleEventKind.connectSuccess,
        detail: 'device=FakeTNC mtu=512',
      );
      final decoded = BleEvent.tryDecode(original.encode());
      expect(decoded, isNotNull);
      expect(decoded!.timestamp, original.timestamp);
      expect(decoded.kind, original.kind);
      expect(decoded.detail, original.detail);
    });

    test('detail containing pipes survives round-trip', () {
      final original = BleEvent(
        timestamp: DateTime.utc(2026, 1, 1),
        kind: BleEventKind.note,
        detail: 'has|pipes|in|it',
      );
      final decoded = BleEvent.tryDecode(original.encode());
      expect(decoded, isNotNull);
      expect(decoded!.detail, 'has|pipes|in|it');
    });

    test('tryDecode returns null for malformed input', () {
      expect(BleEvent.tryDecode(''), isNull);
      expect(BleEvent.tryDecode('no-pipes-at-all'), isNull);
      expect(BleEvent.tryDecode('only|one-pipe'), isNull);
      expect(BleEvent.tryDecode('not-a-number|0|x'), isNull);
      expect(BleEvent.tryDecode('1234|not-int|x'), isNull);
      // Out-of-range kind index.
      expect(BleEvent.tryDecode('1234|9999|x'), isNull);
    });

    test('formatHuman includes time, kind, and detail', () {
      final event = BleEvent(
        timestamp: DateTime(2026, 4, 30, 12, 34, 56, 789),
        kind: BleEventKind.keepaliveSent,
        detail: 'extra',
      );
      final s = event.formatHuman();
      expect(s, contains('keepaliveSent'));
      expect(s, contains('extra'));
      // Time format HH:mm:ss.SSS — local time, so just check delimiters.
      expect(s, matches(RegExp(r'\d{2}:\d{2}:\d{2}\.\d{3}')));
    });

    test(
      'formatHuman omits trailing detail separator when detail is empty',
      () {
        final event = BleEvent(
          timestamp: DateTime(2026, 4, 30),
          kind: BleEventKind.keepaliveSent,
        );
        // No double-space-detail suffix at the end.
        expect(event.formatHuman(), endsWith('keepaliveSent'));
      },
    );
  });

  group('BleDiagnostics', () {
    late BleDiagnostics diag;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      diag = BleDiagnostics(
        prefs: prefs,
        maxEvents: 5,
        persistDebounce: const Duration(milliseconds: 10),
      );
    });

    test('log() appends events in order and notifies listeners', () {
      var notifyCount = 0;
      diag.addListener(() => notifyCount++);

      diag.log(BleEventKind.connectStart, 'a');
      diag.log(BleEventKind.connectSuccess, 'b');

      expect(diag.events, hasLength(2));
      expect(diag.events[0].kind, BleEventKind.connectStart);
      expect(diag.events[0].detail, 'a');
      expect(diag.events[1].kind, BleEventKind.connectSuccess);
      expect(notifyCount, 2);
    });

    test('ring buffer evicts oldest when maxEvents exceeded', () {
      for (var i = 0; i < 8; i++) {
        diag.log(BleEventKind.note, 'msg-$i');
      }
      expect(diag.events, hasLength(5));
      // First 3 should have been evicted; we keep msg-3..msg-7.
      expect(diag.events.first.detail, 'msg-3');
      expect(diag.events.last.detail, 'msg-7');
    });

    test('clear() empties the buffer and notifies', () async {
      diag.log(BleEventKind.note, 'x');
      var cleared = false;
      diag.addListener(() => cleared = diag.events.isEmpty);

      await diag.clear();
      expect(diag.events, isEmpty);
      expect(cleared, isTrue);
    });

    test('flush() writes the current buffer to SharedPreferences', () async {
      diag.log(BleEventKind.connectStart, 'a');
      diag.log(BleEventKind.connectSuccess, 'b');
      await diag.flush();

      // Build a fresh instance against the same backing store; hydrate must
      // see the two persisted events.
      final prefs = await SharedPreferences.getInstance();
      final restored = BleDiagnostics(prefs: prefs, maxEvents: 5);
      await restored.hydrate();
      expect(restored.events, hasLength(2));
      expect(restored.events[0].kind, BleEventKind.connectStart);
      expect(restored.events[0].detail, 'a');
      expect(restored.events[1].kind, BleEventKind.connectSuccess);
      expect(restored.events[1].detail, 'b');
    });

    test('debounced persist eventually writes after log()', () async {
      diag.log(BleEventKind.note, 'persisted-by-debounce');
      // Debounce was set to 10ms in setUp; wait safely longer.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final prefs = await SharedPreferences.getInstance();
      final restored = BleDiagnostics(prefs: prefs, maxEvents: 5);
      await restored.hydrate();
      expect(restored.events, hasLength(1));
      expect(restored.events.single.detail, 'persisted-by-debounce');
    });

    test('hydrate() ignores corrupt entries but keeps valid ones', () async {
      final prefs = await SharedPreferences.getInstance();
      // Pre-seed prefs with a mix of valid and invalid lines.
      final goodLine = BleEvent(
        timestamp: DateTime.utc(2026, 4, 30),
        kind: BleEventKind.sessionConnected,
        detail: 'survivor',
      ).encode();
      await prefs.setStringList('ble_diagnostics_log_v1', [
        'corrupt-line',
        goodLine,
        '|',
      ]);

      final restored = BleDiagnostics(prefs: prefs, maxEvents: 5);
      await restored.hydrate();
      expect(restored.events, hasLength(1));
      expect(restored.events.single.detail, 'survivor');
    });
  });
}
