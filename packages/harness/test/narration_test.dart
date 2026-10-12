import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// The smallest bytes that pass for an MP4 file: a size, then the `ftyp` box type.
final fakeM4a = Uint8List.fromList([0, 0, 0, 24, ...ascii.encode('ftypM4A '), 0, 0, 0, 0]);

String timingsJson(int book, int chapter, List<List<int>> words) =>
    jsonEncode({'book': book, 'chapter': chapter, 'narrator': 'souer', 'words': words});

/// Writes a pack in the published layout with one timed word per chapter.
String writeNarrationPack(
  Directory dir, {
  int book = 43,
  List<int> chapters = const [1, 2, 3],
  String format = narrationPackFormat,
  String? packId,
}) {
  final path = '${dir.path}/souer-$book-${dir.listSync().length}.sqlite';
  final db = sqlite3.open(path)
    ..execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)')
    ..execute(
      'CREATE TABLE chapters(chapter INTEGER PRIMARY KEY, duration_ms INTEGER NOT NULL, '
      'audio BLOB NOT NULL, timings TEXT NOT NULL)',
    );
  final meta = {
    'format': format,
    'pack': packId ?? 'souer-$book',
    'book': '$book',
    'narrator': 'souer',
    'release': 'audio-1',
    'priming_ms': '88.0',
  };
  for (final e in meta.entries) {
    db.execute('INSERT INTO meta VALUES (?, ?)', [e.key, e.value]);
  }
  for (final c in chapters) {
    db.execute('INSERT INTO chapters VALUES (?, ?, ?, ?)', [
      c,
      1000,
      fakeM4a,
      timingsJson(book, c, [
        [1, 0, 100, 200],
      ]),
    ]);
  }
  db.dispose();
  return path;
}

void main() {
  group('word ranges', () {
    test('count words as the timings do, punctuation attached', () {
      const text = '  “For God so loved the world, that He gave—His one and only Son.”  ';
      final ranges = wordRanges(text);
      final words = [for (final r in ranges) text.substring(r.start, r.end)];
      expect(words, text.trim().split(RegExp(r'\s+')));
      expect(words.first, '“For');
      expect(words[5], 'world,');
      expect(words[8], 'gave—His');
      expect(ranges.first.start, 2);
    });

    test('an empty verse has no words, unlike a plain split', () {
      expect(''.split(RegExp(r'\s+')), ['']);
      expect(wordRanges(''), isEmpty);
      expect(wordRanges('   '), isEmpty);
    });

    test('a character offset maps to the word it falls in or follows', () {
      final ranges = wordRanges('In the beginning');
      expect(wordAtOffset(ranges, 0), 0);
      expect(wordAtOffset(ranges, 3), 1);
      expect(wordAtOffset(ranges, 6), 1);
      expect(wordAtOffset(ranges, 7), 2);
      expect(wordAtOffset(ranges, 99), 2);
      expect(wordAtOffset(wordRanges('  word'), 0), isNull);
      expect(wordAtOffset(const [], 0), isNull);
    });
  });

  group('chapter timings', () {
    ChapterTimings parse(List<List<int>> words, {int durationMs = 10000}) => ChapterTimings.parse(
      timingsJson(43, 5, words),
      book: 43,
      chapter: 5,
      durationMs: durationMs,
    );

    // Verse 4 is empty in the BSB, so it has no entries; verse 5 has a zero-length dash.
    final timings = parse([
      [3, 0, 1000, 1200],
      [3, 1, 1300, 1500],
      [5, 0, 2000, 2300],
      [5, 1, 2300, 2300],
      [5, 2, 2400, 2600],
    ]);

    test('parse words in reading order and count each verse', () {
      expect(timings.words, hasLength(5));
      expect(timings.wordsPerVerse, {3: 2, 5: 3});
    });

    test('the current word is the last one started, held until the next', () {
      expect(timings.indexAt(0), isNull, reason: 'the chapter is still being announced');
      expect(timings.indexAt(999), isNull);
      expect(timings.indexAt(1000), 0);
      expect(timings.indexAt(1250), 0, reason: 'between two words, the earlier one holds');
      expect(timings.indexAt(1300), 1);
      expect(timings.indexAt(1999), 1, reason: 'the gap for the empty verse');
      expect(timings.indexAt(2300), 3, reason: 'a zero-length word at the same start wins');
      expect(timings.indexAt(9999), 4);
    });

    test('a verse and word find their timing', () {
      expect(timings.indexOf(3), 0);
      expect(timings.indexOf(5, 2), 4);
      expect(timings.indexOf(5, 9), 2, reason: 'out of range falls back to the verse start');
      expect(timings.indexOf(4), isNull);
    });

    test('reject timings that are malformed, out of order or outside the audio', () {
      final bad = <List<List<int>>>[
        [
          [3, 1, 0, 10],
        ],
        [
          [3, 0, 500, 600],
          [3, 1, 400, 450],
        ],
        [
          [3, 0, 500, 400],
        ],
        [
          [3, 0, 500, 20000],
        ],
        [
          [4, 0, 500, 600],
          [3, 0, 700, 800],
        ],
        [
          [0, 0, 1, 2],
        ],
        [
          [3, 0, 1],
        ],
      ];
      for (final words in bad) {
        expect(() => parse(words), throwsFormatException, reason: '$words');
      }
      expect(
        () => ChapterTimings.parse(timingsJson(43, 6, []), book: 43, chapter: 5, durationMs: 1),
        throwsFormatException,
      );
      expect(
        () => ChapterTimings.parse('not json', book: 43, chapter: 5, durationMs: 1),
        throwsFormatException,
      );
    });
  });

  group('narration packs', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('berea_narration'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a good pack reads its id, book, chapters and priming', () {
      final info = readNarrationPack(writeNarrationPack(dir), expectedBook: 43);
      expect(info.id, 'souer-43');
      expect(info.book, 43);
      expect(info.narrator, 'souer');
      expect(info.chapters, [1, 2, 3]);
      expect(info.primingMs, 88);
      checkNarrationChapters(info, 3);
    });

    test('a pack for another book is refused when a book is expected', () {
      final path = writeNarrationPack(dir, book: 1);
      expect(readNarrationPack(path).book, 1);
      expect(
        () => readNarrationPack(path, expectedBook: 43),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('Genesis'))),
      );
    });

    test('a missing or extra chapter fails the chapter check', () {
      final info = readNarrationPack(writeNarrationPack(dir, chapters: [1, 3]));
      expect(
        () => checkNarrationChapters(info, 3),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('John 2'))),
      );
      expect(() => checkNarrationChapters(info, 1), throwsFormatException);
    });

    test('junk, other formats, foreign ids and bad audio are refused', () {
      final junk = File('${dir.path}/junk.sqlite')..writeAsStringSync('not a database at all');
      expect(() => readNarrationPack(junk.path), throwsFormatException);
      expect(() => readNarrationPack('${dir.path}/absent.sqlite'), throwsFormatException);
      expect(() => readNarrationPack(writeNarrationPack(dir, format: '2')), throwsFormatException);
      expect(
        () => readNarrationPack(writeNarrationPack(dir, packId: '../../evil')),
        throwsFormatException,
      );
      final empty = sqlite3.open('${dir.path}/empty.sqlite')
        ..execute('CREATE TABLE meta(key TEXT, value TEXT)');
      empty.dispose();
      expect(() => readNarrationPack('${dir.path}/empty.sqlite'), throwsFormatException);

      final noAudio = writeNarrationPack(dir);
      final db = sqlite3.open(noAudio)
        ..execute("UPDATE chapters SET audio = x'00' WHERE chapter = 2");
      db.dispose();
      expect(() => readNarrationPack(noAudio), throwsFormatException);
    });

    test('a priming time that is not a small number of milliseconds is refused', () {
      for (final bad in ['NaN', 'Infinity', '1e300', '-5', 'soon']) {
        final path = writeNarrationPack(dir);
        final db = sqlite3.open(path)
          ..execute("UPDATE meta SET value = ? WHERE key = 'priming_ms'", [bad]);
        db.dispose();
        expect(() => readNarrationPack(path), throwsFormatException, reason: bad);
      }
    });

    test('a chapter reads back its audio and timings', () {
      final path = writeNarrationPack(dir);
      final c = readNarrationChapter(path, 43, 2);
      expect(c.audio, fakeM4a);
      expect(c.durationMs, 1000);
      expect(c.primingMs, 88);
      expect(c.timings.chapter, 2);
      expect(c.timings.words.single.startMs, 100);
      expect(() => readNarrationChapter(path, 43, 9), throwsFormatException);
    });
  });
}
