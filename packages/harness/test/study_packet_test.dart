import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// About the size of the real system prompt and a beat instruction, in characters.
const _systemChars = 3000;
const _instructionChars = 800;

void main() {
  final bible = File('../../assets/berea.sqlite');
  if (!bible.existsSync() || bible.lengthSync() == 0) {
    test('these tests open the built Bible', () {}, skip: 'needs assets/berea.sqlite');
    return;
  }
  late BibleDb db;
  late Directory dir;
  setUpAll(() {
    db = BibleDb(sqlite3.open(bible.path, mode: OpenMode.readOnly));
    dir = Directory.systemTemp.createTempSync('berea_packet');
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  StudyPacket packet(String refs, {CommentaryLibrary? commentary}) =>
      buildStudyPacket(db, RefParser.parse(refs), commentary: commentary);

  /// A pack with long comments on John 3 from two works, so beats must cut or split.
  CommentaryLibrary longPack() {
    final path = '${dir.path}/pack-${DateTime.now().microsecondsSinceEpoch}.sqlite';
    final pack = sqlite3.open(path)..execute(commentaryPackSchema);
    pack.execute("INSERT INTO meta VALUES ('format', ?)", [commentaryPackFormat]);
    pack.execute("INSERT INTO modules VALUES ('MHCC', 'Concise', 'Henry', 'PD', 'test', 0)");
    pack.execute("INSERT INTO modules VALUES ('Clarke', 'Clarke', 'Clarke', 'PD', 'test', 1)");
    final long = List.filled(60, 'The new birth is the work of the Spirit.').join(' ');
    for (final (module, start, end) in [
      ('MHCC', 1, 8),
      ('MHCC', 9, 21),
      ('Clarke', 3, 3),
      ('Clarke', 16, 16),
    ]) {
      pack.execute(
        'INSERT INTO entries(module, book, chapter, verse_start, verse_end, html_or_text) '
        'VALUES (?, 43, 3, ?, ?, ?)',
        [module, start, end, 'On $start. $long'],
      );
    }
    pack.execute(
      'INSERT INTO entries(module, book, chapter, verse_start, verse_end, html_or_text) '
      "VALUES ('MHCC', 43, 3, 0, 0, 'Chapter introduction.')",
    );
    pack.execute(
      'INSERT INTO entries(module, book, chapter, verse_start, verse_end, html_or_text) '
      "VALUES ('MHCC', 43, 0, 0, 0, 'Book introduction.')",
    );
    pack.dispose();
    final lib = CommentaryLibrary()..open('core', path);
    addTearDown(lib.closeAll);
    return lib;
  }

  test('a reading is cut at its BSB headings, with parallels and key words', () {
    final p = packet('John 3:1-21');
    expect(p.outline, ['John 3:1-21: Jesus and Nicodemus']);
    final s = p.sections.single;
    expect(s.verses, hasLength(21));
    expect(s.parallelVerses.map((v) => v.label), ['Genesis 22:1', 'Romans 5:6']);
    expect(s.crossReferences, hasLength(sectionCrossReferences));
    final codes = p.keyWords.map((k) => k.entry.key).toList();
    expect(codes, containsAll(['G1080', 'G4100']), reason: 'born and believe');
    expect(codes, isNot(contains('G1510')), reason: '"to be" is too common to study');
    expect(codes.where((c) => c.startsWith('G3530')), isEmpty, reason: 'Nicodemus is a name');
    expect(p.keyWords.every((k) => k.uses.length <= keyWordUses), isTrue);
    expect(p.witnesses, isNotEmpty);
    expect(p.witnesses.every((w) => w.to.book.id <= 39), isTrue, reason: 'Old Testament');
  });

  test('a reading that starts inside a section keeps that heading, marked continued', () {
    final p = packet('John 3:5-12');
    expect(p.outline, ['John 3:5-12: Jesus and Nicodemus (continued)']);
    expect(p.sections.single.verses.first.verse, 5);
  });

  test('Psalm 119 splits by its letters, and a long chapter is read whole', () {
    expect(packet('Psalm 119:1-24').outline, [
      'Psalms 119:1-8: Your Word Is a Lamp to My Feet, ALEPH',
      'Psalms 119:9-16: BETH',
      'Psalms 119:17-24: GIMEL',
    ]);
    expect(packet('Genesis 24').verses, hasLength(67), reason: 'past the prompt cap of 40');
  });

  test('an Old Testament reading takes its witnesses from the New', () {
    final p = packet('Psalm 119:1-24');
    expect(p.witnesses, isNotEmpty);
    expect(p.witnesses.every((w) => w.to.book.id > 39), isTrue);
  });

  test('readings repeat once, and the packet is the same every time', () {
    String dump(StudyPacket p) => [
      p.inputs.fingerprint,
      ...p.outline,
      for (final s in p.sections) ...[
        ...s.crossReferences.map((v) => v.label),
        ...s.commentary.map((c) => c.key),
      ],
      ...p.keyWords.map((k) => '${k.entry.key}${k.uses.map((v) => v.label)}'),
      ...p.witnesses.map((w) => '${w.from.label}>${w.to.label}'),
    ].join('\n');
    final lib = longPack();
    final a = packet('John 3:1-21; John 3:16', commentary: lib);
    expect(a.inputs.readings.map((r) => r.label), ['John 3:1-21']);
    expect(dump(a), dump(packet('John 3:1-21; John 3:16', commentary: lib)));
    expect(a.inputs.packs, ['core']);
    expect(a.inputs.bible, isNotEmpty, reason: 'the build stamp');
  });

  test('commentary sits with the section it starts in; none installed leaves it empty', () {
    final p = packet('John 3:1-21', commentary: longPack());
    final s = p.sections.single;
    expect(s.commentary.map((c) => c.ref!.label).toSet(), {
      'John 3:1-8',
      'John 3:9-21',
      'John 3:3',
      'John 3:16',
    });
    expect(p.introductions.map((c) => c.text), ['Book introduction.', 'Chapter introduction.']);
    final bare = packet('John 3:1-21');
    expect(bare.introductions, isEmpty);
    expect(bare.sections.single.commentary, isEmpty);
  });

  test('readings that overlap or touch merge; a reading inside another goes', () {
    String readings(String refs) => packet(refs).inputs.readings.map((r) => r.label).join('; ');
    expect(readings('John 3:16; John 3:1-21'), 'John 3:1-21');
    expect(readings('John 3:1-10; John 3:8-21'), 'John 3:1-21');
    expect(readings('John 3:1-5; John 3:6-8'), 'John 3:1-8');
    expect(
      readings('John 3:1-5; Romans 8:1; John 3:16-18'),
      'John 3:1-5; Romans 8:1; John 3:16-18',
    );
    expect(readings('John 3:20; John 3'), 'John 3');
  });

  test('a comment on two readings of a chapter is given once, and a book introduction once', () {
    final p = packet('John 3:1-5; John 3:16-18; John 3:20-21', commentary: longPack());
    final keys = [for (final s in p.sections) ...s.commentary.map((c) => c.key)];
    expect(keys.toSet(), hasLength(keys.length));
    final holding = p.sections.where((s) => s.commentary.any((c) => c.ref!.label == 'John 3:9-21'));
    expect(holding, hasLength(1), reason: 'the comment on 9 to 21 touches two readings');
    expect(p.introductions.where((c) => c.text == 'Book introduction.'), hasLength(1));
  });

  test('witnesses are each verse once, beside one verse that points to them', () {
    for (final reading in ['John 3:1-21', 'Psalm 119:1-24', 'Romans 8']) {
      final p = packet(reading);
      final to = p.witnesses.map((w) => w.to.label).toList();
      expect(to.toSet(), hasLength(to.length), reason: reading);
      expect(p.witnesses.every((w) => p.verses.any((v) => v.label == w.from.label)), isTrue);
      final fits = promptFits(PromptBuilder('x' * _systemChars), 'y' * _instructionChars, Tier.mid);
      final beat = packetBeats(p, fits).where((b) => b.beat == Beat.witnesses).single;
      final shown = beat.context.passages.map((v) => v.label).toList();
      expect(shown.toSet(), hasLength(shown.length), reason: 'no verse twice');
    }
  });

  test('a whole long chapter builds and cuts quickly', () {
    final sw = Stopwatch()..start();
    final p = packet('Psalm 119');
    final fits = promptFits(PromptBuilder('x' * _systemChars), 'y' * _instructionChars, Tier.low);
    final beats = packetBeats(p, fits);
    expect(p.sections, hasLength(22));
    expect(beats.where((b) => b.beat == Beat.verseWalk).length, greaterThanOrEqualTo(22));
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
  });

  for (final tier in Tier.values) {
    test('every beat reaches the $tier prompt whole, and the walk keeps every verse once', () {
      final builder = PromptBuilder('x' * _systemChars);
      final fits = promptFits(builder, 'y' * _instructionChars, tier);
      for (final reading in ['John 3:1-21', 'Genesis 24', 'Psalm 119:1-24']) {
        final p = packet(reading, commentary: longPack());
        final beats = packetBeats(p, fits);
        expect(beats.first.beat, Beat.opening);
        expect(beats.last.beat, Beat.close);
        for (final b in beats) {
          expect(fits(b.context), isTrue, reason: '$reading ${b.beat} on $tier');
        }
        final walked = [
          for (final b in beats.where((b) => b.beat == Beat.verseWalk)) ...b.context.passages,
        ];
        expect(walked.map((v) => v.label), p.verses.map((v) => v.label), reason: reading);
      }
    });
  }

  test('the low tier still shows commentary in the verse walk', () {
    final fits = promptFits(PromptBuilder('x' * _systemChars), 'y' * _instructionChars, Tier.low);
    final beats = packetBeats(packet('John 3:1-21', commentary: longPack()), fits);
    expect(
      beats.where((b) => b.beat == Beat.verseWalk).expand((b) => b.context.sources),
      isNotEmpty,
    );
  });

  test('an empty packet has no beats', () {
    final p = buildStudyPacket(db, const []);
    expect(p.isEmpty, isTrue);
    expect(packetBeats(p, (_) => true), isEmpty);
  });
}
