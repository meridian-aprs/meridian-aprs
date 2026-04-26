// Spot-check that an injected `Clock` advances service-level retention logic
// deterministically. Full per-service coverage lands in PR 4 (#60) and PR 5
// (#52); this test exists to prove the seam works end-to-end.
//
// Picks `StationService._withinAge` because it's the simplest reachable
// retention probe — `setPacketHistoryDays(1)` triggers `_withinAge` against
// the rolling buffer using the injected clock, so we can drive packet
// pruning by advancing time without sleeping.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/packet/aprs_packet.dart';
import 'package:meridian_aprs/services/station_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MutableClock {
  _MutableClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'StationService prunes the packet buffer using the injected clock',
    () async {
      final clock = _MutableClock(DateTime.utc(2026, 1, 1, 12));
      SharedPreferences.setMockInitialValues({});

      final service = StationService(clock: clock.call);
      await service.loadPersistedHistory(await SharedPreferences.getInstance());

      service.ingestLine(
        'N0CALL>APRS:!4903.50N/07201.75W-clock-injection-test',
      );

      // Buffer is fresh at the injected `now`.
      expect(service.recentPackets, isNotEmpty);
      expect(service.recentPackets.first, isA<PositionPacket>());

      // Advance 2 days, then narrow the retention window to 1 day.
      // `_withinAge` uses _clock(); after the advance, the entry is stale.
      clock.advance(const Duration(days: 2));
      await service.setPacketHistoryDays(1);

      expect(service.recentPackets, isEmpty);
    },
  );
}
