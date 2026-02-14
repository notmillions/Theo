// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:drone_control/main.dart';

void main() {
  testWidgets('Drone Control app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const DroneControlApp());

    // Verify that the app launches and displays the AppBar
    expect(find.text('🚁 Drone Control'), findsOneWidget);

    // Verify that buttons are present
    expect(find.text('🟢 ARMER LES MOTEURS'), findsOneWidget);
    expect(find.text('⬇ ATTERRISSAGE AUTO'), findsOneWidget);
  });
}
