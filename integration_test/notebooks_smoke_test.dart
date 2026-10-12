import 'dart:convert';
import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/home_shell.dart';
import 'package:berea/notebook_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

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

/// Runs in the real app with `flutter test integration_test -d macos`. It uses the app's own
/// data folder and deletes the notebook it makes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('notebooks on the real app: pasted text, a passage and a PDF', (tester) async {
    final s = await AppState.bootstrap();
    // A failed earlier run must not leave its notebook in the app's real data.
    for (final n in s.notebooks.notebooks().where((n) => n.title == 'Smoke test notebook')) {
      s.notebooks.deleteNotebook(n.id);
    }
    await tester.pumpWidget(MaterialApp(home: HomeShell(state: s)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Notebooks').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New notebook'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Smoke test notebook');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Add your first source'), findsOneWidget);
    final id = s.notebooks.notebooks().firstWhere((n) => n.title == 'Smoke test notebook').id;

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

    // The file picker is a native panel; hand the store the file it would return.
    final pdf = File('${(await getTemporaryDirectory()).path}/smoke-two-pages.pdf')
      ..createSync(recursive: true)
      ..writeAsBytesSync(twoPagePdf('Mercy on the first page', 'Peace on the second page'));
    final added = s.notebooks.addSource(
      id,
      SourceRequest(SourceKind.pdf, 'smoke-two-pages.pdf', path: pdf.path),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('smoke-two-pages.pdf'), findsOneWidget);
    await tester.runAsync(() => added);
    await pumpUntil(tester, find.text('PDF · 2 sections'));

    await tester.tap(find.text('smoke-two-pages.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE 1'), findsOneWidget);
    expect(find.text('PAGE 2'), findsOneWidget);
    expect(find.text('Peace on the second page'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    final hits = s.notebooks.search(id, 'loving peace');
    expect(hits.map((h) => h.sourceTitle), containsAll(['smoke-two-pages.pdf']));
    expect(hits.firstWhere((h) => h.kind == SourceKind.pdf).page, 2);
    expect(s.notebooks.search(id, 'separate').map((h) => h.kind).toSet(), {SourceKind.passage});

    await tester.tap(find.byTooltip('Notebook options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(s.notebooks.notebook(id), isNull);
    pdf.deleteSync();
  });
}
