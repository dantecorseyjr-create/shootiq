import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/widgets/shootiq_logo.dart';

void main() {
  testWidgets('ShootIQ logo renders basketball icon', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ShootIQTheme.darkTheme,
        home: const Scaffold(
          body: Center(child: ShootIQLogo()),
        ),
      ),
    );

    expect(find.byIcon(Icons.sports_basketball), findsOneWidget);
  });
}
