import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/ui/widgets/battery_optimization_card.dart';

Widget _host(BatteryOptimizationCard card) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 600,
      child: Padding(padding: const EdgeInsets.all(16), child: card),
    ),
  ),
);

void main() {
  group('BatteryOptimizationCard', () {
    testWidgets('collapses to SizedBox.shrink when permission is granted', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(BatteryOptimizationCard(checker: () async => true)),
      );
      // First frame shows nothing while the future is pending; resolve it.
      await tester.pumpAndSettle();

      expect(find.text('Battery optimization is on'), findsNothing);
      expect(find.text('Allow'), findsNothing);
    });

    testWidgets('renders prompt when permission is denied', (tester) async {
      await tester.pumpWidget(
        _host(BatteryOptimizationCard(checker: () async => false)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Battery optimization is on'), findsOneWidget);
      expect(find.text('Allow'), findsOneWidget);
      // The body text mentions the BLE-link consequence so the user
      // understands why we're asking.
      expect(find.textContaining('BLE TNC link'), findsOneWidget);
    });

    testWidgets(
      'renders nothing on the very first frame (before async resolve)',
      (tester) async {
        await tester.pumpWidget(
          _host(BatteryOptimizationCard(checker: () async => false)),
        );
        // Build only — no settle. The future hasn't resolved so _ignored is
        // still null and the card returns SizedBox.shrink to avoid a
        // false-positive flash of the warning.
        expect(find.text('Battery optimization is on'), findsNothing);
      },
    );
  });
}
