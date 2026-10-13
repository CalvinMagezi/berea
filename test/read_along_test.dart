import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:berea/narration_packs.dart';
import 'package:berea/read_along.dart';
import 'package:berea/read_along_bar.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

final _fakeM4a = Uint8List.fromList([0, 0, 0, 24, ...ascii.encode('ftypM4A '), 0, 0, 0, 0]);

/// Writes a narration pack in the published layout: verse 1 of each chapter is two words.
String writeNarrationPack(Directory dir, {int book = 43, List<int> chapters = const [1, 2]}) {
  final path = '${dir.path}/pack-$book-${dir.listSync().length}.sqlite';
  final db = sqlite3.open(path)
    ..execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)')
    ..execute(
      'CREATE TABLE chapters(chapter INTEGER PRIMARY KEY, duration_ms INTEGER NOT NULL, '
      'audio BLOB NOT NULL, timings TEXT NOT NULL)',
    );
  final meta = {'format': '1', 'pack': 'souer-$book', 'book': '$book', 'narrator': 'souer'};
  for (final e in {...meta, 'priming_ms': '88.0'}.entries) {
    db.execute('INSERT INTO meta VALUES (?, ?)', [e.key, e.value]);
  }
  for (final c in chapters) {
    final timings = {
      'book': book,
      'chapter': c,
      'words': [
        [1, 0, 100, 200],
        [1, 1, 250, 400],
      ],
    };
    db.execute('INSERT INTO chapters VALUES (?, ?, ?, ?)', [
      c,
      1000,
      _fakeM4a,
      jsonEncode(timings),
    ]);
  }
  db.dispose();
  return path;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('berea_read_along'));
  tearDown(() => dir.deleteSync(recursive: true));

  NarrationShelf shelf() =>
      NarrationShelf(Directory('${dir.path}/narration'), () {}, chapterCount: (_) => 2);

  group('pins', () {
    test('every pin names a book and a SHA-256 within the size cap', () {
      final sha = RegExp(r'^[0-9a-f]{64}$');
      for (final e in narrationPins.entries) {
        expect(e.key, inInclusiveRange(1, books.length));
        expect(sha.hasMatch(e.value.sha256), isTrue, reason: '${e.key}');
        expect(e.value.bytes, inInclusiveRange(1, maxNarrationPackBytes));
      }
      expect(narrationPins[43]!.bytes, 27140096);
      expect(narrationFileName(43), 'souer-43.sqlite');
      expect(narrationReleaseUrl, endsWith('/releases/download/audio-1'));
    });
  });

  group('shelf', () {
    test('a pack from a file lands under its own book and plays back a chapter', () async {
      final s = shelf();
      expect(await s.installFromFile(writeNarrationPack(dir)), 'John');
      expect(s.isInstalled(43), isTrue);
      expect(s.availableBooks, contains(43));
      final track = await s.track(43, 2);
      expect(track.file.readAsBytesSync(), _fakeM4a);
      expect(track.file.path, endsWith('.m4a'));
      expect(track.primingMs, 88);
      expect(track.timings.words, hasLength(2));
      final next = await s.track(43, 1);
      expect(next.file.path, isNot(track.file.path), reason: 'the open file is never overwritten');
      expect(track.file.existsSync(), isTrue);
      s.prunePlayed(keep: next.file);
      expect(track.file.existsSync(), isFalse);
      expect(next.file.existsSync(), isTrue);
      s.delete(43);
      expect(s.isInstalled(43), isFalse);
    });

    test('a bad file is refused and leaves the installed pack alone', () async {
      final s = shelf();
      await s.installFromFile(writeNarrationPack(dir));
      final before = File('${dir.path}/narration/souer-43.sqlite').readAsBytesSync();
      final junk = File('${dir.path}/junk.sqlite')..writeAsStringSync('no');
      await expectLater(s.installFromFile(junk.path), throwsFormatException);
      final missing = writeNarrationPack(dir, chapters: [1]);
      await expectLater(s.installFromFile(missing), throwsFormatException);
      expect(File('${dir.path}/narration/souer-43.sqlite').readAsBytesSync(), before);
      final leftovers = Directory('${dir.path}/narration').listSync().map((f) => f.path);
      expect(leftovers.where((p) => p.endsWith('.part')), isEmpty);
    });

    test('only temporary files are swept at start, judged by their own names', () {
      final parent = Directory('${dir.path}/x.part')..createSync();
      final shelfDir = Directory('${parent.path}/narration')..createSync();
      final kept = File('${shelfDir.path}/souer-43.sqlite')..writeAsStringSync('pack');
      final stale = File('${shelfDir.path}/incoming-0.sqlite.part-wal')..writeAsStringSync('x');
      NarrationShelf(shelfDir, () {}, chapterCount: (_) => 2);
      expect(kept.existsSync(), isTrue, reason: 'a folder name with .part in it is not a reason');
      expect(stale.existsSync(), isFalse);
    });

    test('a file over the size cap is refused before it is copied', () async {
      final small = NarrationShelf(
        Directory('${dir.path}/narration'),
        () {},
        chapterCount: (_) => 2,
        maxPackBytes: 8,
      );
      await expectLater(small.installFromFile(writeNarrationPack(dir)), throwsFormatException);
    });
  });

  group('player', () {
    test('the edit list check adds the priming only when the player reports it', () {
      int offset(int? reportedMs) => primingOffsetMs(
        reported: reportedMs == null ? null : Duration(milliseconds: reportedMs),
        durationMs: 272213,
        primingMs: 88,
      );
      expect(offset(272213), 0);
      expect(offset(272213 + aacFrameMs), 0);
      expect(offset(272341), 88, reason: 'priming and the last frame padding, untrimmed');
      expect(offset(null), 0);
    });

    test('words are marked only where the timings fit the shown text', () {
      final r = ReadAlong(shelf())
        ..timings = ChapterTimings.parse(
          jsonEncode({
            'book': 43,
            'chapter': 3,
            'words': [
              [16, 0, 100, 200],
              [16, 1, 200, 300],
            ],
          }),
          book: 43,
          chapter: 3,
          durationMs: 1000,
        );
      r.position.value = (verse: 16, word: 1);
      expect(r.wordToShow(16, 'For God', 'BSB'), 1);
      expect(
        r.wordToShow(16, 'For God', 'KJV'),
        isNull,
        reason: 'other translations follow verses',
      );
      expect(r.wordToShow(16, 'For God so', 'BSB'), isNull, reason: 'the words do not line up');
      expect(r.wordToShow(17, 'For God', 'BSB'), isNull);
      expect(r.wordsFit(16, 'For God', 'BSB'), isTrue);
      expect(r.wordsFit(16, 'For God', 'KJV'), isFalse, reason: 'a tap seeks to the verse start');
      r.timings = null;
      expect(
        r.wordToShow(16, 'For God so', 'KJV'),
        1,
        reason: 'the device voice reads what is shown',
      );
    });
  });

  group('bar', () {
    Future<void> pumpBar(
      WidgetTester tester,
      ReadAlongState state, {
      int? verse,
      double? progress,
      List<String>? taps,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ReadAlongBar(
            state: state,
            bookName: 'John',
            verse: verse,
            downloadProgress: progress,
            onPlayPause: () => taps?.add('play'),
            onPrevious: () => taps?.add('previous'),
            onNext: () => taps?.add('next'),
            onSpeed: (s) => taps?.add('speed $s'),
            onClose: () => taps?.add('close'),
          ),
        ),
      ),
    );

    const playing = ReadAlongState(
      book: 43,
      chapter: 3,
      voice: ReadAlongVoice.narration,
      status: ReadAlongStatus.playing,
    );

    testWidgets('playing narration shows the verse, the narrator and working controls', (
      tester,
    ) async {
      final taps = <String>[];
      await pumpBar(tester, playing, verse: 16, taps: taps);
      expect(find.text('John 3:16'), findsOneWidget);
      expect(find.text('Narrated by Bob Souer'), findsOneWidget);
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause'));
      await tester.tap(find.byTooltip('Next verse'));
      await tester.tap(find.byTooltip('Previous verse'));
      await tester.tap(find.byTooltip('Stop reading aloud'));
      expect(taps, ['play', 'next', 'previous', 'close']);
    });

    testWidgets('speed is chosen from a menu', (tester) async {
      final taps = <String>[];
      await pumpBar(tester, playing, taps: taps);
      expect(find.text('1x'), findsOneWidget);
      await tester.tap(find.byTooltip('Speed 1x'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.25x').last);
      await tester.pumpAndSettle();
      expect(taps, ['speed 1.25']);
    });

    testWidgets('paused shows Play; the device voice is labelled as such', (tester) async {
      await pumpBar(
        tester,
        const ReadAlongState(
          book: 43,
          chapter: 3,
          voice: ReadAlongVoice.device,
          status: ReadAlongStatus.paused,
        ),
      );
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(find.text('Device voice, offline'), findsOneWidget);
      expect(find.text('John 3'), findsOneWidget);
    });

    testWidgets('downloading shows progress and disables the verse buttons', (tester) async {
      await pumpBar(tester, playing.copyWith(status: ReadAlongStatus.loading), progress: 0.4);
      expect(find.text('Downloading the narration of John'), findsOneWidget);
      expect(find.bySemanticsLabel('Downloading the narration'), findsOneWidget);
      final next = tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(Icons.skip_next), matching: find.byType(IconButton)),
      );
      expect(next.onPressed, isNull);
    });

    testWidgets('a failure says why and cannot be played', (tester) async {
      await pumpBar(
        tester,
        playing.copyWith(status: ReadAlongStatus.failed, error: 'The download failed (HTTP 404).'),
      );
      expect(find.text('The download failed (HTTP 404).'), findsOneWidget);
      final play = tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(Icons.play_arrow), matching: find.byType(IconButton)),
      );
      expect(play.onPressed, isNull);
      expect(find.byTooltip('Stop reading aloud'), findsOneWidget);
    });
  });
}
