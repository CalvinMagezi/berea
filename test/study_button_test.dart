import 'package:berea/app_state.dart';
import 'package:berea/study_button.dart';
import 'package:berea/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  HelperState helper, {
  bool selected = false,
  bool writing = false,
  bool reduceMotion = false,
  VoidCallback? onPressed,
}) => tester.pumpWidget(
  MaterialApp(
    theme: bereaTheme(Brightness.light),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: Center(
          child: StudyButton(
            helper: helper,
            selected: selected,
            writing: writing,
            onPressed: onPressed ?? () {},
          ),
        ),
      ),
    ),
  ),
);

BoxDecoration _circle(WidgetTester tester) =>
    tester.widget<DecoratedBox>(find.byKey(const ValueKey('study-circle'))).decoration
        as BoxDecoration;

void main() {
  testWidgets('at rest: no ring, no badge, and the reader hears the helper is ready', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await _pump(tester, const HelperReady(), onPressed: () => taps++);
    expect(find.bySemanticsLabel('Study, ask Berea, helper ready'), findsOneWidget);
    expect(_circle(tester).border, isNull);
    expect(find.byKey(const ValueKey('study-download-ring')), findsNothing);
    expect(find.byKey(const ValueKey('study-wifi-badge')), findsNothing);
    expect(find.byKey(const ValueKey('study-failed-badge')), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.tap(find.byType(StudyButton));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('selected: a gold ring, and the button says it is selected', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, const HelperReady(), selected: true);
    final border = _circle(tester).border! as Border;
    expect(border.top.color, bereaTheme(Brightness.light).colorScheme.primary);
    expect(
      tester.getSemantics(find.byType(StudyButton)),
      matchesSemantics(
        label: 'Study, ask Berea, helper ready',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('downloading: the ring fills with the bytes and the percent is spoken', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, const HelperDownloading(0.42, total: 1000));
    final ring = tester.widget<CircularProgressIndicator>(
      find.byKey(const ValueKey('study-download-ring')),
    );
    expect(ring.value, 0.42);
    expect(find.bySemanticsLabel('Study, ask Berea, helper downloading, 42 percent'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('waiting for Wi-Fi: the ring holds and a Wi-Fi badge shows', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, const HelperDownloading(0.42, total: 1000, waitingForWifi: true));
    expect(find.byKey(const ValueKey('study-wifi-badge')), findsOneWidget);
    expect(find.byKey(const ValueKey('study-download-ring')), findsNothing);
    expect(find.bySemanticsLabel('Study, ask Berea, helper waiting for Wi-Fi'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('failed: an ember badge and "needs a look"', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, const HelperFailed(helperLoadFailed));
    expect(find.byKey(const ValueKey('study-failed-badge')), findsOneWidget);
    expect(find.bySemanticsLabel('Study, ask Berea, helper needs a look'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('writing: the flame glows in a slow pulse', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, const HelperReady(), writing: true);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isTrue);
    expect(_circle(tester).boxShadow, isNotEmpty);
    expect(find.bySemanticsLabel('Study, ask Berea, writing an answer'), findsOneWidget);

    await _pump(tester, const HelperReady());
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(_circle(tester).boxShadow, isEmpty);
    semantics.dispose();
  });

  testWidgets('reduce motion turns the glow off', (tester) async {
    await _pump(tester, const HelperReady(), writing: true, reduceMotion: true);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
    expect(_circle(tester).boxShadow, isEmpty);
  });
}
