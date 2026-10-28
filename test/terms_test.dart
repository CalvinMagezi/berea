import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/models.dart';
import 'package:berea/terms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _gemma3 = edgeModelById('gemma-3-1b');
final _e2b = edgeModelById('gemma-4-e2b');

void main() {
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState()..prefs = await SharedPreferences.getInstance();
  });

  /// Opens the agreement for [model] from a button and reports what it returned.
  Future<List<bool>> ask(WidgetTester tester, EdgeModel model) async {
    final results = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(await confirmModelTerms(context, state, model)),
            child: const Text('Download'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('a model with no notice needs no agreement', (tester) async {
    final results = await ask(tester, _e2b);
    expect(results, [true]);
    expect(find.text('Before you download'), findsNothing);
  });

  testWidgets('cancelling leaves the terms unaccepted and the download unstarted', (tester) async {
    final results = await ask(tester, _gemma3);
    expect(find.text('Before you download'), findsOneWidget);
    expect(find.textContaining(gemmaUseRestriction), findsOneWidget);
    expect(find.textContaining('you agree to the Gemma Terms of Use'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(results, [false]);
    expect(state.termsAccepted, isFalse);
  });

  testWidgets('agreeing is remembered, so the next download is not asked again', (tester) async {
    var results = await ask(tester, _gemma3);
    await tester.tap(find.textContaining('Agree and download'));
    await tester.pumpAndSettle();
    expect(results, [true]);
    expect(state.termsAccepted, isTrue);

    results = await ask(tester, _gemma3);
    expect(results, [true]);
    expect(find.text('Before you download'), findsNothing);
  });

  testWidgets('reworded terms ask again', (tester) async {
    await state.prefs.setInt('termsAccepted', termsVersion - 1);
    expect(state.termsAccepted, isFalse);
    await ask(tester, _gemma3);
    expect(find.text('Before you download'), findsOneWidget);
  });

  test('a Gemma download does not start without agreement', () async {
    state.settings = Settings(deviceModelId: _gemma3.id);
    final before = state.deviceState;
    await state.downloadDeviceModel();
    expect(state.deviceState, before);
  });

  testWidgets('the terms screen states the restriction and opens the full policy', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TermsScreen()));
    expect(find.text(gemmaUseRestriction), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Gemma Prohibited Use Policy'), 100);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gemma Prohibited Use Policy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('You may not use nor allow others to use Gemma'), findsOneWidget);
  });

  test('the Gemma files shipped with the app and releases are the ones the licence asks for', () {
    expect(File('licenses/gemma/NOTICE').readAsStringSync().trim(), gemmaNotice);
    final terms = File(gemmaTermsAsset).readAsStringSync();
    expect(terms, contains('3.1 Distribution and Redistribution'));
    expect(terms, contains('3.2 Use Restrictions'));
    expect(File(gemmaPolicyAsset).readAsStringSync(), contains('Gemma Prohibited Use Policy'));
  });
}
