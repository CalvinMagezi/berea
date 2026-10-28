import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:berea/licences.dart';
import 'package:berea/notebook_store.dart';
import 'package:berea/pdf_text.dart';
import 'package:berea/study_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// The study.sqlite schema exactly as Berea 0.3.0 created it, before notebooks.
const v030Schema = '''
  CREATE TABLE notes(
    id INTEGER PRIMARY KEY, book INTEGER, chapter INTEGER, verse_start INTEGER, verse_end INTEGER,
    text TEXT, created INTEGER, updated INTEGER);
  CREATE INDEX notes_ref ON notes(book, chapter);
  CREATE TABLE highlights(book INTEGER, chapter INTEGER, verse INTEGER,
    PRIMARY KEY(book, chapter, verse)) WITHOUT ROWID;
  CREATE TABLE conversations(id INTEGER PRIMARY KEY, title TEXT, created INTEGER, updated INTEGER);
  CREATE TABLE messages(id INTEGER PRIMARY KEY, conversation_id INTEGER, role TEXT,
    text TEXT, refs TEXT, created INTEGER);
  CREATE INDEX messages_conv ON messages(conversation_id);
  CREATE TABLE plan_progress(plan_id TEXT, day INTEGER, done_at INTEGER,
    PRIMARY KEY(plan_id, day)) WITHOUT ROWID;
  CREATE TABLE study_pages(id INTEGER PRIMARY KEY, book INTEGER, chapter INTEGER,
    verse_start INTEGER, verse_end INTEGER, observation TEXT, interpretation TEXT,
    application TEXT, created INTEGER, updated INTEGER);
''';

/// The PDFium library `flutter test` builds for this host, or null when there is none.
String? hostPdfium() {
  for (final p in [
    'build/native_assets/macos/libpdfium.dylib',
    'build/native_assets/linux/libpdfium.so',
    'build/native_assets/windows/pdfium.dll',
  ]) {
    if (File(p).existsSync()) return File(p).absolute.path;
  }
  return null;
}

void main() {
  test('opening a 0.3.0 study.sqlite adds notebooks and keeps every note', () {
    final dir = Directory.systemTemp.createTempSync('berea_migrate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/study.sqlite';
    sqlite3.open(path)
      ..execute(v030Schema)
      ..execute("INSERT INTO notes VALUES (1, 43, 3, 16, 16, 'Loved first.', 0, 0)")
      ..dispose();

    final store = StudyStore.open(path);
    expect(store.notes().single.text, 'Loved first.');
    expect(store.db.select('PRAGMA user_version').first.values.first, StudyStore.schemaVersion);
    final notebooks = NotebookStore(store.db);
    expect(notebooks.notebooks().single.title, notesOnVersesTitle);
    notebooks.createNotebook('Romans 8');
    store.close();

    // Opening again runs no migration twice and loses nothing.
    final again = StudyStore.open(path);
    expect(
      NotebookStore(again.db).notebooks().map((n) => n.title),
      unorderedEquals(['Romans 8', notesOnVersesTitle]),
    );
    expect(again.notes().single.text, 'Loved first.');
    again.close();
  });

  test('sources are chunked off the UI isolate, searched with stemming, and scoped', () async {
    final store = NotebookStore(StudyStore(sqlite3.openInMemory()).db);
    final romans = store.createNotebook('  Romans   8 ');
    final psalms = store.createNotebook('Psalms');
    expect(store.notebook(romans)!.title, 'Romans 8');
    final long = List.filled(60, 'Nothing can separate us from the love of God.').join(' ');
    final id = await store.addSource(
      romans,
      SourceRequest(SourceKind.text, 'Pasted', text: '$long\n\nNo condemnation remains.'),
    );
    await store.addSource(
      psalms,
      const SourceRequest(SourceKind.text, 'Psalm 23', text: 'The Lord is my shepherd.'),
    );
    expect(store.pending, isEmpty);
    final chunks = store.chunks(romans);
    expect(chunks.length, greaterThan(1));
    final text = store.sourceText(id!);
    for (final c in chunks) {
      expect(text.substring(c.start, c.end), c.text);
      expect(c.page, isNull);
      expect(c.sourceTitle, 'Pasted');
    }
    expect(store.search(romans, 'loving').first.sourceId, id);
    expect(store.search(romans, 'condemnation').single.text, contains('No condemnation'));
    expect(store.search(romans, 'shepherd'), isEmpty);
    expect(store.search(psalms, 'shepherd').single.title, 'Psalm 23');
    expect(store.search(romans, '"AND" (NEAR'), isEmpty);
    expect(store.notebooks().firstWhere((n) => n.id == romans).sourceCount, 1);

    store.renameNotebook(romans, 'Romans 8:31-39');
    expect(store.notebook(romans)!.title, 'Romans 8:31-39');
    expect(() => store.renameNotebook(romans, '   '), throwsFormatException);

    store.removeSource(id);
    expect(store.search(romans, 'love'), isEmpty);
    store.deleteNotebook(psalms);
    expect(store.notebooks().map((n) => n.title), ['Romans 8:31-39']);
    expect(store.db.select('SELECT * FROM notebook_chunks'), isEmpty);
    expect(
      store.db.select(
        "SELECT rowid FROM notebook_chunks_fts WHERE notebook_chunks_fts MATCH 'shepherd'",
      ),
      isEmpty,
    );
  });

  test('a failed source saves nothing and a notebook deleted mid-read gets nothing', () async {
    final gate = Completer<void>();
    final store = NotebookStore(
      StudyStore(sqlite3.openInMemory()).db,
      ingest: (r) async {
        await gate.future;
        return ingestSource(r);
      },
    );
    final kept = store.createNotebook('Kept');
    final id = store.createNotebook('Gone soon');
    final empty = store.addSource(kept, const SourceRequest(SourceKind.text, 'Blank', text: '  '));
    final orphan = store.addSource(id, const SourceRequest(SourceKind.text, 'T', text: 'Grace.'));
    expect(store.pending.map((p) => p.title), ['Blank', 'T']);
    store.deleteNotebook(id);
    gate.complete();
    await expectLater(empty, throwsFormatException);
    expect(await orphan, isNull);
    expect(store.pending, isEmpty);
    expect(store.db.select('SELECT * FROM notebook_sources'), isEmpty);
    expect(store.db.select('SELECT * FROM notebook_chunks'), isEmpty);
  });

  test('sources are read one at a time', () async {
    var running = 0, most = 0;
    final store = NotebookStore(
      StudyStore(sqlite3.openInMemory()).db,
      ingest: (r) async {
        most = ++running > most ? running : most;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
        return ingestSource(r);
      },
    );
    final id = store.createNotebook('Queue');
    await Future.wait([
      for (var i = 0; i < 4; i++)
        store.addSource(id, SourceRequest(SourceKind.text, 'S$i', text: 'Text $i.')),
    ]);
    expect(most, 1);
    expect(store.sources(id).map((s) => s.title), ['S0', 'S1', 'S2', 'S3']);
  });

  test('a PDF keeps its page numbers through a background isolate', () async {
    final pdfium = hostPdfium();
    if (pdfium == null) return markTestSkipped('PDFium was not built for this host');
    final pdf = File('test/fixtures/three-pages.pdf').absolute.path;
    final r = SourceRequest(SourceKind.pdf, 'Sample', path: pdf);
    final chunked = await Isolate.run(() => ingestSource(r, pdfiumPath: pdfium));
    expect(chunked.chunks.map((c) => c.page).toSet(), {1, 2, 3, 4});
    final page2 = chunked.chunks.firstWhere((c) => c.page == 2);
    expect(page2.text, startsWith('Line 62 of page 1'));
    expect(chunked.chunks.first.text, startsWith('Page 1 heading'));
    expect(chunked.chunks.any((c) => c.text.contains('Page 2 heading')), isTrue);
    for (final c in chunked.chunks) {
      expect(chunked.text.substring(c.start, c.end), c.text);
    }
    final bad = SourceRequest(
      SourceKind.pdf,
      'Not a PDF',
      path: File('pubspec.yaml').absolute.path,
    );
    expect(() => ingestSource(bad, pdfiumPath: pdfium), throwsFormatException);
  });

  test('missing and oversized files are refused before they are read', () {
    expect(
      () => ingestSource(const SourceRequest(SourceKind.epub, 'x', path: '/no/such/file.epub')),
      throwsFormatException,
    );
    final dir = Directory.systemTemp.createTempSync('berea_big');
    addTearDown(() => dir.deleteSync(recursive: true));
    final big = File('${dir.path}/big.pdf')..writeAsBytesSync([]);
    big.openSync(mode: FileMode.write)
      ..setPositionSync(maxNotebookFileBytes)
      ..writeByteSync(0)
      ..closeSync();
    expect(
      () => ingestSource(SourceRequest(SourceKind.pdf, 'big', path: big.path)),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('64 MB'))),
    );
  });

  test('commentary becomes one attributed source per work', () {
    final dir = Directory.systemTemp.createTempSync('berea_nb_commentary');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/core.sqlite';
    final db = sqlite3.open(path)..execute(commentaryPackSchema);
    db.execute("INSERT INTO meta VALUES ('format', ?), ('pack', 'core')", [commentaryPackFormat]);
    for (final id in ['MHCC', 'TSK']) {
      final m = commentaryModuleById(id)!;
      db.execute('INSERT INTO modules VALUES (?, ?, ?, ?, ?, 0)', [
        id,
        m.title,
        m.author,
        m.licence,
        m.source,
      ]);
    }
    db.execute(
      'INSERT INTO entries(module, book, chapter, verse_start, verse_end, html_or_text) VALUES '
      "('MHCC', 43, 3, 14, 18, 'The love of God.'), ('TSK', 43, 3, 16, 16, 'loved. Ro 5:8'), "
      "('TSK', 43, 3, 17, 17, 'sent.'), ('TSK', 43, 4, 1, 1, 'Elsewhere.')",
    );
    db.dispose();
    final library = CommentaryLibrary()..open('core', path);
    addTearDown(library.closeAll);

    final verse = commentarySources(library, 'John 3:16');
    expect(verse.map((r) => r.title), [
      "Matthew Henry's Concise Commentary on John 3:16",
      'The Treasury of Scripture Knowledge on John 3:16',
    ]);
    expect(verse.first.origin, 'MHCC|Matthew Henry, 1706-1721|Public domain');
    final chapter = commentarySources(library, 'John 3');
    expect(chapter.last.text, 'loved. Ro 5:8\n\nsent.');
    expect(commentarySources(library, 'not a reference'), isEmpty);
  });

  test('a source read for a deleted notebook never lands in the next one made', () async {
    final gate = Completer<void>();
    final store = NotebookStore(
      StudyStore(sqlite3.openInMemory()).db,
      ingest: (r) async {
        await gate.future;
        return ingestSource(r);
      },
    );
    store.createNotebook('Older');
    final doomed = store.createNotebook('Deleted while reading');
    final late = store.addSource(doomed, const SourceRequest(SourceKind.text, 'T', text: 'x'));
    store.deleteNotebook(doomed);
    final fresh = store.createNotebook('Made afterwards');
    expect(fresh, isNot(doomed));
    expect(store.pendingFor(fresh), isEmpty);
    gate.complete();
    expect(await late, isNull);
    expect(store.sources(fresh), isEmpty);
  });

  test('a restore cancels every source still being read', () async {
    final gate = Completer<void>();
    final store = NotebookStore(
      StudyStore(sqlite3.openInMemory()).db,
      ingest: (r) async {
        await gate.future;
        return ingestSource(r);
      },
    );
    final id = store.createNotebook('Mine');
    final reading = store.addSource(id, const SourceRequest(SourceKind.text, 'T', text: 'x'));
    store.cancelAll();
    expect(store.pendingFor(id), isEmpty);
    gate.complete();
    expect(await reading, isNull);
    expect(store.sources(id), isEmpty);
  });

  test('background reading reports problems and gives up on a source that hangs', () async {
    await expectLater(
      ingestInBackground(const SourceRequest(SourceKind.text, 'Blank', text: '   ')),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('No text'))),
    );
    final big = List.filled(200000, 'word').join(' ');
    await expectLater(
      ingestInBackground(SourceRequest(SourceKind.text, 'Slow', text: big), timeout: Duration.zero),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('too long'))),
    );
    final ok = await ingestInBackground(const SourceRequest(SourceKind.text, 'T', text: 'Grace.'));
    expect(ok.chunks.single.text, 'Grace.');
  });

  test('every PDFium licence the app registers is in the repository and the asset list', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- licenses/pdfium/'));
    for (final file in pdfiumLicences.keys) {
      expect(File('licenses/pdfium/$file').existsSync(), isTrue, reason: file);
    }
  });

  test('shipped migrations are never edited', () async {
    // Append only: when a schema change is needed, add a migration and pin it here.
    const pinned = [
      'nmY8srEE0IlsNADuGRT2qEZiWJaRUfFUtXqgjuRfsVU=',
      'A240KlyJsB1gIQ3D4PbpGMO5Y1lM/IEDcPIp8K4pKVs=',
      'nqwGTAa44RwwDcMnEHXNLoJhErV5x0Jmc/E6CqwWDRo=',
      'QAyzQtbwdF1vaLBE6nuGIbtMOyb2sGcP4Jcs11JfI7Q=',
      'reHdjSz/j8+T394BiJ25Ajl2ozf9YjP7NLiJrxQjP4U=',
      'lMRcUfwDlFY9T39cwoI1P06LSSc1g0AWCXuLgq0lq78=',
    ];
    final actual = [
      for (final m in StudyStore.migrations)
        base64.encode((await Sha256().hash(utf8.encode(m.replaceAll('\r\n', '\n')))).bytes),
    ];
    expect(actual.take(pinned.length), pinned);
    expect(actual.length, greaterThanOrEqualTo(pinned.length));
  });

  test('PDF text past the character budget is refused before it is copied', () async {
    final pdfium = hostPdfium();
    if (pdfium == null) return markTestSkipped('PDFium was not built for this host');
    final pdf = File('test/fixtures/three-pages.pdf').absolute.path;
    final all = await Isolate.run(
      () => pdfPageTexts(pdf, maxPages: 10, maxChars: 1 << 20, libraryPath: pdfium),
    );
    final firstTwo = all[0].length + all[1].length;
    expect(
      () => pdfPageTexts(pdf, maxPages: 10, maxChars: firstTwo + 1, libraryPath: pdfium),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', tooLongMessage)),
    );
    expect(
      () => pdfPageTexts(pdf, maxPages: 2, maxChars: 1 << 20, libraryPath: pdfium),
      throwsFormatException,
    );
  });

  test('the next source waits until the last reading isolate has exited', () async {
    final exited = Completer<void>();
    final started = <String>[];
    final store = NotebookStore(
      StudyStore(sqlite3.openInMemory()).db,
      ingest: (r) async {
        started.add(r.title);
        return ingestSource(r);
      },
      idle: () => exited.future,
    );
    final id = store.createNotebook('Serial');
    final first = store.addSource(id, const SourceRequest(SourceKind.text, 'A', text: 'One.'));
    final second = store.addSource(id, const SourceRequest(SourceKind.text, 'B', text: 'Two.'));
    await first;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(started, ['A']);
    exited.complete();
    await second;
    expect(started, ['A', 'B']);
  });
}
