import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/notebook_store.dart';
import 'package:berea/notebooks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs Synthesize in the real app with `flutter test integration_test -d macos`, against the
/// bundled Bible copied into a throwaway data folder, so the user's own Berea data is never opened.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('berea-synthesize');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('Synthesize lists the BSB sections of a notebook passage', (tester) async {
    final s = await AppState.bootstrap(
      supportDir: dir,
      prefs: await SharedPreferences.getInstance(),
    );
    final id = s.notebooks.createNotebook('Romans 8');
    await tester.runAsync(
      () => s.notebooks.addSource(id, passageSource(s.db, 'Romans 8:28-39', 'BSB')!),
    );
    await tester.pumpWidget(MaterialApp(home: NotebookScreen(state: s, notebookId: id)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Synthesize'));
    await tester.pumpAndSettle();
    expect(find.text('God Works in All Things'), findsOneWidget);
    expect(find.text('Romans 8:28-34 · 7 verses'), findsOneWidget);
    expect(find.text('More than Conquerors'), findsOneWidget);
    expect(find.text('Romans 8:35-39 · 5 verses'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Key words'), 200);
    await tester.scrollUntilVisible(find.text('Witnesses from the other testament'), 200);
    s.study.close();
    s.db.close();
  });
}
