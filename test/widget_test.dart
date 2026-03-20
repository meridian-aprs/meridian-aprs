import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meridian_aprs/ui/theme/theme_provider.dart';
import 'package:meridian_aprs/screens/map_screen.dart';

void main() {
  testWidgets('MapScreen renders without throwing', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final themeProvider = await ThemeProvider.create();

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: const MaterialApp(
          home: MapScreen(),
        ),
      ),
    );

    // Pump a single frame — enough to verify the widget tree builds without
    // throwing. We do not call pumpAndSettle because MapScreen opens a TCP
    // connection in initState which leaves async timers alive.
    await tester.pump();

    // Verify the screen mounted successfully.
    expect(find.byType(MapScreen), findsOneWidget);
  }, skip: true); // MapScreen opens a real TCP connection in initState; smoke test is integration-only.
}
