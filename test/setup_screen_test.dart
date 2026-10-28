import 'package:berea/app_state.dart';
import 'package:berea/setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('first setup says how much it takes, and a full disk says what to free', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SetupScreen(settingUp: true)));
    expect(find.textContaining('About 85 MB, already inside the app'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SetupScreen(failure: bibleNoSpace)));
    expect(find.text(bibleNoSpace), findsOneWidget);
    expect(bibleNoSpace, contains('Free about 85 MB'));
  });
}
