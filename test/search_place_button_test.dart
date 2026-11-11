import 'package:berea/search_place_button.dart';
import 'package:berea/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, {bool selected = false, VoidCallback? onPressed}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: bereaTheme(Brightness.light),
        home: Scaffold(
          body: Center(child: SearchPlaceButton(selected: selected, onPressed: onPressed ?? () {})),
        ),
      ),
    );

BoxDecoration _circle(WidgetTester tester) =>
    tester.widget<DecoratedBox>(find.byKey(const ValueKey('search-circle'))).decoration
        as BoxDecoration;

void main() {
  testWidgets('at rest: no ring, it says Search, and a tap presses it', (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await _pump(tester, onPressed: () => taps++);
    expect(_circle(tester).border, isNull);
    expect(
      tester.getSemantics(find.byType(SearchPlaceButton)),
      matchesSemantics(
        label: 'Search',
        isButton: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    expect(tester.hasRunningAnimations, isFalse);
    await tester.tap(find.byType(SearchPlaceButton));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('selected: a gold ring, and the button says it is selected', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, selected: true);
    final border = _circle(tester).border! as Border;
    expect(border.top.color, bereaTheme(Brightness.light).colorScheme.primary);
    expect(
      tester.getSemantics(find.byType(SearchPlaceButton)),
      matchesSemantics(
        label: 'Search',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('its size leaves room for the ring around the circle', (tester) async {
    await _pump(tester);
    expect(tester.getSize(find.byType(SearchPlaceButton)), const Size.square(searchButtonSize));
    expect(searchButtonSize, searchCircle + 2 * searchRing);
  });
}
