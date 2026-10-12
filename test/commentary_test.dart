import 'dart:io';

import 'package:berea/commentary_packs.dart';
import 'package:berea/commentary_sheet.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// Writes a pack declaring [id] with [rows] of (module, book, chapter, start, end, text).
String writePack(Directory dir, String id, List<List<Object>> rows) {
  final path = '${dir.path}/$id-source.sqlite';
  final db = sqlite3.open(path)..execute(commentaryPackSchema);
  db.execute("INSERT INTO meta VALUES ('format', ?), ('pack', ?)", [commentaryPackFormat, id]);
  for (final m in {for (final r in rows) r[0] as String}) {
    final spec = commentaryModuleById(m)!;
    db.execute('INSERT INTO modules VALUES (?, ?, ?, ?, ?, 0)', [
      m,
      spec.title,
      spec.author,
      spec.licence,
      spec.source,
    ]);
  }
  for (final r in rows) {
    db.execute(
      'INSERT INTO entries(module, book, chapter, verse_start, verse_end, html_or_text) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      r,
    );
  }
  db.dispose();
  return path;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('berea_commentary'));
  tearDown(() => dir.deleteSync(recursive: true));

  Widget panel(CommentaryLibrary library, Ref ref) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 800,
        child: CommentaryPanel(library: library, passage: ref),
      ),
    ),
  );

  testWidgets('the panel lists each commentary on the verse with its attribution', (tester) async {
    final library = CommentaryLibrary()
      ..open(
        'core',
        writePack(dir, 'core', [
          ['MHCC', 43, 3, 14, 18, 'Verses 14-18 The love of God.'],
          ['TSK', 43, 3, 16, 16, 'loved. Ro 5:8'],
          ['JFB', 43, 3, 17, 17, 'Not shown for verse 16.'],
          ['MHCC', 43, 0, 0, 0, 'John wrote last of the four.'],
        ]),
      );
    await tester.pumpWidget(panel(library, RefParser.parse('John 3:16').first));

    expect(find.text("Matthew Henry's Concise Commentary"), findsOneWidget);
    expect(find.text('Matthew Henry, 1706-1721 · Public domain'), findsOneWidget);
    expect(find.text('John 3:14-18'), findsOneWidget);
    expect(find.text('Verses 14-18 The love of God.'), findsOneWidget);
    expect(find.text('The Treasury of Scripture Knowledge'), findsOneWidget);
    expect(find.text('Not shown for verse 16.'), findsNothing);
    expect(find.text('Introductions'), findsOneWidget);
    expect(find.text('John wrote last of the four.'), findsNothing);
    library.closeAll();
  });

  testWidgets('a long comment shows a preview and opens in full', (tester) async {
    final long = List.filled(400, 'word').join(' ');
    final library = CommentaryLibrary()
      ..open(
        'core',
        writePack(dir, 'core', [
          ['JFB', 1, 1, 1, 1, long],
        ]),
      );
    await tester.pumpWidget(panel(library, RefParser.parse('Genesis 1:1').first));
    expect(find.text(long), findsNothing);
    await tester.tap(find.text('Read all'));
    await tester.pumpAndSettle();
    expect(find.text(long), findsOneWidget);
    library.closeAll();
  });

  testWidgets('with nothing installed the panel says where to get commentaries', (tester) async {
    await tester.pumpWidget(panel(CommentaryLibrary(), RefParser.parse('John 3:16').first));
    expect(find.textContaining('No commentaries are installed'), findsOneWidget);
  });

  test('a gzipped pack from a file installs under its own id and can be deleted', () async {
    final shelf = CommentaryShelf(Directory('${dir.path}/shelf'), () {});
    final source = writePack(dir, 'wesley', [
      ['Wesley', 40, 5, 3, 3, 'Happy are the poor in spirit.'],
    ]);
    final gz = File('$source.gz')..writeAsBytesSync(gzip.encode(File(source).readAsBytesSync()));

    expect(await shelf.installFromFile(gz.path), 'John Wesley');
    expect(shelf.isInstalled('wesley'), isTrue);
    expect(shelf.library.forRange(40, 5, 3, 3).single.text, 'Happy are the poor in spirit.');

    final spec = commentaryPackSpecs.firstWhere((s) => s.id == 'wesley');
    shelf.delete(spec);
    expect(shelf.isInstalled('wesley'), isFalse);
    expect(File('${dir.path}/shelf/${spec.fileName}').existsSync(), isFalse);
  });

  test('a file that is not a pack is refused and leaves the installed pack alone', () async {
    final shelf = CommentaryShelf(Directory('${dir.path}/shelf'), () {});
    await shelf.installFromFile(
      writePack(dir, 'barnes', [
        ['Barnes', 40, 1, 1, 1, 'Kept.'],
      ]),
    );
    final junk = File('${dir.path}/junk.sqlite')..writeAsStringSync('not a database');
    final stranger = writePack(dir, 'not-in-catalog', [
      ['Barnes', 40, 1, 1, 1, 'Strange.'],
    ]);

    await expectLater(shelf.installFromFile(junk.path), throwsFormatException);
    await expectLater(shelf.installFromFile(stranger), throwsFormatException);
    expect(shelf.library.forRange(40, 1, 1, 1).single.text, 'Kept.');
    expect(Directory('${dir.path}/shelf').listSync().map((f) => f.uri.pathSegments.last), [
      'commentary-barnes.sqlite',
    ]);
  });

  test('every catalog pack has a published pin', () {
    for (final spec in commentaryPackSpecs) {
      expect(commentaryPins[spec.id]?.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: spec.id);
    }
  });
}
