import 'dart:convert';
import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/home_shell.dart';
import 'package:berea/licences.dart';
import 'package:berea/notebook_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A two page PDF with one line of Helvetica text per page, written by hand so the smoke test
/// needs no file from outside the app's sandbox.
List<int> twoPagePdf(String first, String second) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    for (final content in [5, 6])
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
          '/Resources << /Font << /F1 7 0 R >> >> /Contents $content 0 R >>',
    for (final text in [first, second])
      () {
        final stream = 'BT /F1 18 Tf 72 700 Td ($text) Tj ET';
        return '<< /Length ${stream.length} >>\nstream\n$stream\nendstream';
      }(),
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return latin1.encode(out.toString());
}

Future<void> pumpUntil(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 200 && f.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(f, findsWidgets);
}

Future<void> expectPdfiumLicences(WidgetTester tester) async {
  registerBundledLicences();
  final packages = await tester.runAsync(
    () async => {for (final l in await LicenseRegistry.licenses.toList()) ...l.packages},
  );
  expect(packages, containsAll(['PDFium', 'FreeType (in PDFium)', 'ICU (in PDFium)']));
}

/// Creates a notebook through the UI and returns its id.
Future<int> createNotebook(WidgetTester tester, AppState s, String title) async {
  await tester.tap(find.text('Notebooks').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('New notebook'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), title);
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
  expect(find.text('Add your first source'), findsOneWidget);
  return s.notebooks.notebooks().single.id;
}

Future<void> addTextAndPassage(WidgetTester tester) async {
  await tester.tap(find.text('Add a source'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Pasted text'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, 'Grace upon grace, steadfast love.');
  await tester.tap(find.text('Add'));
  await pumpUntil(tester, find.text('Pasted text · 1 section'));

  await tester.tap(find.text('Add source'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Bible passage'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'Romans 8:28-39');
  await tester.tap(find.text('Add'));
  await pumpUntil(tester, find.textContaining('Romans 8:28-39 ('));
}

/// The file picker is a native panel, so the store gets the path it would return.
Future<void> addPdf(WidgetTester tester, AppState s, int id, Directory dir) async {
  final pdf = File('${dir.path}/smoke-two-pages.pdf')
    ..writeAsBytesSync(twoPagePdf('Mercy on the first page', 'Peace on the second page'));
  final added = s.notebooks.addSource(
    id,
    SourceRequest(SourceKind.pdf, 'smoke-two-pages.pdf', path: pdf.path),
  );
  await tester.pump();
  expect(
    find.byWidgetPredicate(
      (w) => w is LinearProgressIndicator && w.semanticsLabel == 'Reading smoke-two-pages.pdf',
    ),
    findsOneWidget,
  );
  await tester.runAsync(() => added);
  await pumpUntil(tester, find.text('PDF · 2 sections'));

  await tester.tap(find.text('smoke-two-pages.pdf'));
  await tester.pumpAndSettle();
  expect(find.text('PAGE 1'), findsOneWidget);
  expect(find.text('PAGE 2'), findsOneWidget);
  expect(find.text('Peace on the second page'), findsOneWidget);
  await tester.pageBack();
  await tester.pumpAndSettle();
}

Future<void> deleteNotebook(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Notebook options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
  await tester.pumpAndSettle();
}

/// Runs the real app with `flutter test integration_test -d macos`, against a throwaway data
/// folder and in-memory preferences, so the user's own Berea data is never opened.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('berea-smoke');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('notebooks on the real app: pasted text, a passage and a PDF', (tester) async {
    await expectPdfiumLicences(tester);
    final s = await AppState.bootstrap(
      supportDir: dir,
      prefs: await SharedPreferences.getInstance(),
    );
    await tester.pumpWidget(MaterialApp(home: HomeShell(state: s)));
    await tester.pumpAndSettle();

    final id = await createNotebook(tester, s, 'Smoke test notebook');
    await addTextAndPassage(tester);
    await addPdf(tester, s, id, dir);

    final hits = s.notebooks.search(id, 'loving peace');
    expect(hits.map((h) => h.title), contains('smoke-two-pages.pdf'));
    expect(hits.firstWhere((h) => h.kind == SourceKind.pdf).page, 2);
    expect(s.notebooks.search(id, 'separate').map((h) => h.kind).toSet(), {SourceKind.passage});

    await deleteNotebook(tester);
    expect(s.notebooks.notebook(id), isNull);
    s.study.close();
    s.db.close();
  });
}
