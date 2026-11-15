import 'dart:io';

import 'package:berea/booklets.dart';
import 'package:berea/notebook_store.dart';
import 'package:berea/study_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Booklet load(String id) =>
    Booklet.parse(File(bookletAssets.firstWhere((p) => p.contains(id))).readAsStringSync());

void main() {
  final inner = load('inner-city');
  final three = load('three-ways');

  test('every booklet file parses, with its own id and sections that are not repeated', () {
    for (final path in bookletAssets) {
      final b = Booklet.parse(File(path).readAsStringSync());
      expect(b.sections, isNotEmpty, reason: path);
      expect({for (final s in b.sections) s.id}.length, b.sections.length, reason: path);
    }
    expect({inner.id, three.id}, {'inner-city', 'three-ways'});
  });

  test('Building the Inner City of God keeps its eight sections and twelve numbered steps', () {
    expect(inner.sections.map((s) => s.id), [
      'introduction',
      'surveying-the-land',
      'stage-1',
      'stage-2',
      'stage-3',
      'stage-4',
      'stage-5',
      'summary',
    ]);
    final steps = [
      for (final s in inner.sections)
        for (final b in s.blocks)
          if (b is BookletHeading && b.level == 3 && RegExp(r'^\d+\. ').hasMatch(b.text)) b.text,
    ];
    expect(steps.length, 12);
    for (var i = 0; i < 12; i++) {
      expect(steps[i], startsWith('${i + 1}. '));
    }
    // The summary table: ten rows, each with the three cells the booklet prints beside its name.
    final rows = inner.section('summary')!.blocks.whereType<BookletList>().toList();
    expect(rows.length, 10);
    expect(rows.every((r) => r.items.length == 3), isTrue);
  });

  test(
    'Three Ways We Fall keeps its eleven sections, the five arenas and the seven-part prayer',
    () {
      expect(three.sections.length, 11);
      final reflections = three.section('reflections')!;
      final arenas = reflections.blocks.whereType<BookletList>().first.items;
      expect(arenas, [
        'Spouse or closest friend',
        'Parent or guardian',
        'Work or study, and those you lead or serve',
        'The family you came from',
        'Anyone weak, sick or struggling within your reach',
      ]);
      final prayer = three.section('prayer')!;
      final parts = prayer.blocks.whereType<BookletHeading>().where((h) => h.level == 3).toList();
      expect(parts.map((h) => h.text), [
        'I. Who you are',
        'II. I have sinned',
        'III. I have done iniquity',
        'IV. I have transgressed',
        'V. What I inherit',
        'VI. Have mercy',
        'VII. Cleansed and sent',
      ]);
      final pauses = prayer.blocks
          .whereType<BookletParagraph>()
          .where((p) => p.plain.startsWith('Pause.'))
          .map((p) => p.plain);
      expect(pauses, [
        'Pause. Name the person, the word, the omission.',
        'Pause. Name the motive, and where it twisted my words or choices.',
        'Pause. Name the line, and who was hurt by it.',
      ]);
    },
  );

  test('the text is whole: anchors from each booklet (the Inner City was checked against its PDF word for word)', () {
    final i = inner.plainText;
    final t = three.plainText;
    for (final line in [
      'God, You are everything and need nothing; I am dust held in existence by Your love.',
      'Lord, You dwell within me; rule my heart in this moment.',
      'humility without obedience is subtle pride',
      'Hyacinth & Amethyst (Burning Charity & Sovereign Humility): Selfless love and deep humility',
      'Night (Inspecting the Stones): Review the day in prayer before sleep',
      'Address small faults promptly; reject despair after failures; renew efforts in peace',
    ]) {
      expect(i, contains(line));
    }
    for (final line in [
      'Anyone weak, sick or struggling within your reach',
      'Where did I willfully cross a known line?',
      'Pardon is not the whole of repentance.',
      'Realign my aim for tomorrow.',
      'Cast my sins into the depths of the sea.',
      'Name it · Confess it · Make it right',
    ]) {
      expect(t, contains(line));
    }
    // Word counts recorded when each file was checked against its PDF. A change to a booklet's
    // words changes these on purpose, so the edit is seen.
    expect((inner.words, three.words), (2784, 2440));
  });

  test('Three Ways We Fall names no one\'s own family, work or health', () {
    final t = three.plainText.toLowerCase();
    for (final word in [
      'wife',
      'husband',
      'sickle',
      'cto',
      'separated parents',
      'both companies',
    ]) {
      expect(t, isNot(contains(word)), reason: word);
    }
  });

  test('Berea\'s own note on the table is not part of the booklet\'s text', () {
    expect(inner.section('summary')!.blocks.whereType<BookletNote>(), hasLength(1));
    expect(inner.plainText, isNot(contains('Berea shows each row')));
    expect(inner.plainText, isNot(contains('*')));
    expect(three.plainText, isNot(contains('*')));
  });

  test('a quotation that names a reference names one the parser reads', () {
    final cites = [
      for (final b in [inner, three])
        for (final s in b.sections)
          for (final q in s.blocks.whereType<BookletQuote>())
            if (q.cite != null) q.cite!,
    ];
    expect(cites.length, 10);
    for (final c in cites) {
      expect(RefParser.parse(c), isNotEmpty, reason: c);
    }
    expect(RefParser.parse(cites.first).first.label, 'Psalms 32:5');
  });

  test('the prayers are three stretches of the booklets, each found and each whole', () {
    final prayers = bookletPrayers([inner, three]);
    expect(prayers.map((p) => p.title), [
      'Prayer: A Prayer of Confession',
      'Simple Everyday Practice',
      '12. Keeping the Sanctuary Fire Ablaze: A Simple Daily & Lifetime Maintenance Rhythm',
    ]);
    expect(prayers[1].blocks.single.plain, contains('God, You are everything and need nothing'));
    final rhythm = prayers[2].blocks.whereType<BookletList>().single.items;
    expect(rhythm.map((r) => r.split(':').first), [
      '**Morning (Opening the Gates)',
      '**Midday (Tending the Sanctuary Fire)',
      '**Afternoon (Sweeping the Streets in Love)',
      '**Night (Inspecting the Stones)',
    ]);
    // A booklet that is missing leaves out its prayers and no others.
    expect(bookletPrayers([three]).map((p) => p.booklet.id).toSet(), {'three-ways'});
    expect(bookletPrayers(const []), isEmpty);
  });

  test('every prayer reference points at a place the booklets have', () {
    for (final r in bookletPrayerRefs) {
      final b = [inner, three].firstWhere((b) => b.id == r.booklet);
      final s = b.section(r.section);
      expect(s, isNotNull, reason: '${r.booklet}/${r.section}');
      if (r.part != null) expect(s!.part(r.part!), isNotNull, reason: r.part);
    }
  });

  test('a mistyped block fails at parse time, not on a reader\'s screen', () {
    expect(() => parseBookletBlocks('::: shout\nHello\n:::'), throwsFormatException);
    expect(() => parseBookletBlocks('::: callout Title\nNever closed'), throwsFormatException);
    expect(() => Booklet.parse('no front matter'), throwsFormatException);
    expect(
      () => Booklet.parse('---\nid: a\ntitle: A\nshort: A\nsubtitle: S\n---\n## One\n'),
      throwsFormatException,
      reason: 'a section needs an id',
    );
    expect(
      () => Booklet.parse(
        '---\nid: a\ntitle: A\nshort: A\nsubtitle: S\n---\n## One {#x}\ntext\n## Two {#x}\ntext\n',
      ),
      throwsFormatException,
      reason: 'two sections with one id',
    );
  });

  test('the label claims no author, and shows one only when the file names one', () {
    expect(bookletLabel, isNot(contains('Calvin')));
    expect(inner.author, isNull);
    expect(three.author, 'Calvin Magezi');
    final named = Booklet.parse(
      '---\nid: a\ntitle: A\nshort: A\nsubtitle: S\nauthor: Someone\n---\n## One {#one}\ntext\n',
    );
    expect(named.author, 'Someone');
  });

  group('reading progress', () {
    late BookletReading reading;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      reading = BookletReading(await SharedPreferences.getInstance());
    });

    test(
      'reads in the booklet\'s order, keeps ticks when stopped and clears them on start over',
      () {
        expect(reading.isStarted('three-ways'), isFalse);
        expect(reading.next(three)!.id, 'cover');
        reading.start('three-ways');
        reading.setRead('three-ways', 'cover', true);
        reading.setRead('three-ways', 'sin', true);
        expect(reading.readCount(three), 2);
        expect(reading.next(three)!.id, 'one-word');

        reading.stop('three-ways');
        expect(reading.isStarted('three-ways'), isFalse);
        expect(reading.readCount(three), 2, reason: 'stopping keeps what was read');
        reading.start('three-ways');
        expect(reading.readCount(three), 2);

        reading.setRead('three-ways', 'sin', false);
        expect(reading.readCount(three), 1);

        reading.startOver('three-ways');
        expect(reading.readCount(three), 0);
        expect(reading.isStarted('three-ways'), isTrue);
      },
    );

    test('a section the booklet no longer has is not counted, and every section read ends it', () {
      reading.setRead('three-ways', 'a-section-that-was-removed', true);
      expect(reading.readCount(three), 0);
      for (final s in three.sections) {
        reading.setRead('three-ways', s.id, true);
      }
      expect(reading.next(three), isNull);
      expect(reading.readCount(three), three.sections.length);
    });

    test('one booklet\'s ticks never reach another', () {
      reading.setRead('three-ways', 'cover', true);
      expect(reading.readCount(inner), 0);
    });

    test('listeners hear a change once and a repeat not at all', () {
      var heard = 0;
      reading.addListener(() => heard++);
      reading.setRead('three-ways', 'cover', true);
      reading.setRead('three-ways', 'cover', true);
      expect(heard, 1);
    });
  });

  test('a booklet added to a notebook keeps its words and says where they came from', () async {
    final dir = Directory.systemTemp.createTempSync('berea_booklet');
    addTearDown(() => dir.deleteSync(recursive: true));
    final study = StudyStore.open('${dir.path}/study.sqlite');
    final store = NotebookStore(study.db, ingest: (r) async => ingestSource(r));
    final nb = store.createNotebook('Confession');
    final id = await store.addSource(
      nb,
      SourceRequest(SourceKind.text, three.short, origin: three.origin, text: three.plainText),
    );
    final source = store.sources(nb).single;
    expect(source.id, id);
    expect(source.title, 'Three Ways We Fall');
    expect(source.origin, contains(bookletLabel));
    expect(source.chunkCount, greaterThan(0));
    final text = store.sourceText(id!);
    expect(text, contains('Father, I have sinned. I have missed the mark.'));
    expect(text, contains('Pause. Name the line, and who was hurt by it.'));
    study.close();
  });
}
