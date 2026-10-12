import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:berea_harness/berea_harness.dart';
import 'package:berea_harness/src/sword.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Every book with one chapter of [verses] verses: small enough to write by hand.
Versification tinyV11n([int verses = 5]) => [
  for (var b = 0; b < otBookCount + ntBookCount; b++) [verses],
];

/// Writes a one-block zCom or zCom4 testament where slot i holds texts[i]. A slot listed in
/// [links] points at the same bytes as the slot it maps to.
String writeModule(
  Directory dir,
  List<SwordKey?> slots,
  Map<SwordKey, String> texts, {
  required bool zCom4,
  Map<SwordKey, SwordKey> links = const {},
}) {
  final block = BytesBuilder();
  final at = <SwordKey, (int, int)>{};
  for (final e in texts.entries) {
    final bytes = utf8.encode(e.value);
    at[e.key] = (block.length, bytes.length);
    block.add(bytes);
  }
  final raw = block.takeBytes();
  final compressed = zlib.encode(raw);
  final width = zCom4 ? 12 : 10;
  final index = ByteData(slots.length * width);
  for (var i = 0; i < slots.length; i++) {
    final key = slots[i];
    final pointer = key == null ? null : at[links[key] ?? key];
    if (pointer == null) continue;
    index.setUint32(i * width, 0, Endian.little);
    index.setUint32(i * width + 4, pointer.$1, Endian.little);
    zCom4
        ? index.setUint32(i * width + 8, pointer.$2, Endian.little)
        : index.setUint16(i * width + 8, pointer.$2, Endian.little);
  }
  final blocks = ByteData(12)
    ..setUint32(0, 0, Endian.little)
    ..setUint32(4, compressed.length, Endian.little)
    ..setUint32(8, raw.length, Endian.little);
  final prefix = '${dir.path}/ot';
  File('$prefix.bzz').writeAsBytesSync(compressed);
  File('$prefix.bzv').writeAsBytesSync(index.buffer.asUint8List());
  File('$prefix.bzs').writeAsBytesSync(blocks.buffer.asUint8List());
  return prefix;
}

const _module = CommentaryModule('TEST', 'Test commentary', 'Nobody');

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('berea_sword'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('SWORD keys', () {
    test('the first verse of each testament sits at slot 4, after the headings', () {
      final ot = testamentSlots(tinyV11n(), newTestament: false);
      final nt = testamentSlots(tinyV11n(), newTestament: true);
      expect(ot.indexOf(const SwordKey(1, 1, 1)), 4);
      expect(ot.indexOf(const SwordKey(1, 0, 0)), 2);
      expect(ot.indexOf(const SwordKey(1, 1, 0)), 3);
      expect(nt.indexOf(const SwordKey(40, 1, 1)), 4);
      expect(ot.length, 2 + otBookCount * (1 + 1 + 5));
    });

    test('the real KJV layout gives the index sizes of CrossWire modules', () {
      final bible = File('../../assets/berea.sqlite');
      if (!bible.existsSync()) return markTestSkipped('needs assets/berea.sqlite');
      final db = sqlite3.open(bible.path, mode: OpenMode.readOnly);
      final v11n = [
        for (var b = 1; b <= 66; b++)
          [
            for (final r in db.select(
              "SELECT COUNT(*) AS n FROM verses WHERE translation = 'KJV' AND book = ? "
              'GROUP BY chapter ORDER BY chapter',
              [b],
            ))
              r['n'] as int,
          ],
      ];
      db.dispose();
      // MHCC's ot.bzv is 241150 bytes and nt.bzv 82460, at 10 bytes a slot.
      expect(testamentSlots(v11n, newTestament: false).length, 24115);
      expect(testamentSlots(v11n, newTestament: true).length, 8246);
      final nt = testamentSlots(v11n, newTestament: true);
      expect(nt.last, const SwordKey(66, 22, 21));
    });
  });

  group('readTestament', () {
    for (final zCom4 in [false, true]) {
      test('reads ${zCom4 ? 'zCom4' : 'zCom'} entries and folds linked verses', () {
        final slots = testamentSlots(tinyV11n(), newTestament: false);
        final prefix = writeModule(
          dir,
          slots,
          {
            const SwordKey(1, 0, 0): 'Genesis intro',
            const SwordKey(1, 1, 1): 'On verse one',
            const SwordKey(1, 1, 3): 'On three to four',
            const SwordKey(2, 1, 2): 'Exodus two',
          },
          zCom4: zCom4,
          links: {const SwordKey(1, 1, 4): const SwordKey(1, 1, 3)},
        );
        final entries = readTestament(prefix, 'b', slots, zCom4: zCom4);
        expect(
          [for (final e in entries) '${e.key}-${e.lastVerse} ${e.text}'],
          [
            '1 0:0-0 Genesis intro',
            '1 1:1-1 On verse one',
            '1 1:3-4 On three to four',
            '2 1:2-2 Exodus two',
          ],
        );
      });
    }

    test('a link never extends a comment across a blank record, a chapter or an intro', () {
      final slots = testamentSlots(tinyV11n(), newTestament: false);
      final prefix = writeModule(
        dir,
        slots,
        {
          const SwordKey(1, 1, 2): 'On verse two',
          const SwordKey(1, 1, 3): '   ',
          const SwordKey(1, 1, 0): 'Chapter one outline',
          const SwordKey(2, 1, 5): 'Last verse of Exodus 1',
          const SwordKey(3, 1, 2): 'Last verse of Exodus 1',
        },
        zCom4: false,
        links: {
          const SwordKey(1, 1, 4): const SwordKey(1, 1, 3),
          const SwordKey(1, 1, 1): const SwordKey(1, 1, 0),
          const SwordKey(3, 1, 1): const SwordKey(2, 1, 5),
        },
      );
      final entries = readTestament(prefix, 'b', slots, zCom4: false);
      expect(
        [for (final e in entries) '${e.key}-${e.lastVerse} ${e.text}'],
        ['1 1:0-0 Chapter one outline', '1 1:2-2 On verse two', '2 1:5-5 Last verse of Exodus 1'],
      );
    });

    test('a module in another versification is refused, not misread', () {
      final slots = testamentSlots(tinyV11n(), newTestament: false);
      final prefix = writeModule(dir, slots, {}, zCom4: false);
      final wrong = testamentSlots(tinyV11n(6), newTestament: false);
      expect(() => readTestament(prefix, 'b', wrong, zCom4: false), throwsFormatException);
    });

    test('a missing testament reads as empty', () {
      final slots = testamentSlots(tinyV11n(), newTestament: true);
      expect(readTestament('${dir.path}/nt', 'b', slots, zCom4: false), isEmpty);
    });
  });

  group('convertSwordEntries', () {
    int five(int book, int chapter) => 5;

    test('front matter before the first verse becomes the chapter introduction', () {
      const raw = [
        SwordEntry(SwordKey(1, 0, 0), 0, '<div type="book"/><title>Genesis</title>'),
        SwordEntry(
          SwordKey(1, 1, 1),
          2,
          '<div type="x-milestone" subType="x-preverse" sID="pv1"/><title>Genesis</title> '
          'The book of beginnings.<div type="x-milestone" subType="x-preverse" eID="pv1"/>'
          '<hi type="bold">Verses 1-2</hi> In the beginning God.',
        ),
        SwordEntry(
          SwordKey(1, 1, 3),
          3,
          '<div type="x-milestone" subType="x-preverse" sID="pv2"/><title>The First Day</title>'
          '<div type="x-milestone" subType="x-preverse" eID="pv2"/>Light.',
        ),
      ];
      final rows = convertSwordEntries(_module, raw, five).entries;
      expect(
        [for (final r in rows) '${r.chapter}:${r.verseStart}-${r.verseEnd} ${r.text}'],
        [
          '0:0-0 Genesis',
          '1:0-0 Genesis\nThe book of beginnings.',
          '1:1-2 Verses 1-2 In the beginning God.',
          '1:3-3 The First Day\nLight.',
        ],
      );
      expect(rows[1].isIntroduction, isTrue);
    });

    test('a range heading extends an unlinked comment, within the chapter only', () {
      const raw = [
        SwordEntry(SwordKey(40, 1, 1), 1, 'Ver. 1-3. The book of the generation.'),
        SwordEntry(SwordKey(40, 1, 4), 4, 'Ver 4-9. Past the end of the chapter.'),
      ];
      final rows = convertSwordEntries(_module, raw, five).entries;
      expect([for (final r in rows) '${r.verseStart}-${r.verseEnd}'], ['1-3', '4-4']);
    });

    test("Henry's section starts run to the verse before the next section", () {
      const henry = CommentaryModule('MHC', 'Henry', 'Henry', sectionKeyed: true);
      const raw = [
        SwordEntry(SwordKey(1, 1, 1), 1, 'Creation in general.'),
        SwordEntry(SwordKey(1, 1, 3), 3, 'The first day.'),
        SwordEntry(SwordKey(2, 1, 2), 2, 'Exodus.'),
      ];
      final rows = convertSwordEntries(henry, raw, five).entries;
      expect(
        [for (final r in rows) '${r.book} ${r.verseStart}-${r.verseEnd}'],
        ['1 1-2', '1 3-5', '2 2-5'],
      );
    });

    test("Calvin's title pages and prefaces are moved off the first verse", () {
      const calvin = CommentaryModule(
        'CalvinCommentaries',
        'Calvin',
        'Calvin',
        annotateKeyed: true,
      );
      const raw = [
        SwordEntry(SwordKey(1, 1, 1), 1, '<div sID="g2"/>COMMENTARIES<lb/>ON GENESIS'),
        SwordEntry(
          SwordKey(19, 1, 1),
          6,
          '<div annotateRef="Bible:Ps.1" sID="a"/>PSALM 1. A preface.'
          '<div annotateRef="Bible:Ps.1.1" sID="b"/>1. Blessed is the man.'
          '<div annotateRef="Bible:Ps.1.1" eID="b"/>',
        ),
      ];
      final converted = convertSwordEntries(calvin, raw, five);
      expect(
        [for (final r in converted.entries) '${r.book} ${r.verseStart}-${r.verseEnd} ${r.text}'],
        [
          '1 0-0 COMMENTARIES\nON GENESIS',
          '19 0-0 PSALM 1. A preface.',
          '19 1-1 1. Blessed is the man.',
        ],
      );
      expect(converted.clampedLinks, 1);
    });
  });

  test("Keil and Delitzsch's book introduction ends at the first verse's heading", () {
    const raw = [
      SwordEntry(
        SwordKey(23, 1, 1),
        1,
        'The Prophecies of Isaiah<lb/>Introduction<lb/>Isaiah 1:1 is quoted later.'
        '<lb/>Isa 1:1 Title of the collection.',
      ),
    ];
    const kd = CommentaryModule('KD', 'KD', 'KD', introBeforeHeading: true);
    final rows = convertSwordEntries(kd, raw, (_, _) => 31).entries;
    expect(
      [for (final r in rows) '${r.verseStart} ${r.text}'],
      [
        '0 The Prophecies of Isaiah\nIntroduction\nIsaiah 1:1 is quoted later.',
        '1 Isa 1:1 Title of the collection.',
      ],
    );
    const clarke = [
      SwordEntry(
        SwordKey(1, 1, 1),
        1,
        'Preface to the Book of Genesis<lb/>Every believer.<lb/>Verse 1<lb/>In the beginning.',
      ),
    ];
    expect(
      [for (final r in convertSwordEntries(kd, clarke, (_, _) => 31).entries) r.text],
      ['Preface to the Book of Genesis\nEvery believer.', 'Verse 1\nIn the beginning.'],
    );
    // TSK starts lines with cross references such as "Isa 1:1; Mic 1:1"; it is not split.
    expect(convertSwordEntries(_module, raw, (_, _) => 31).entries, hasLength(1));
  });

  test("Spurgeon's whole-psalm entry is split at its verse paragraphs", () {
    const spurgeon = CommentaryModule('TDavid', 'Spurgeon', 'Spurgeon', verseParagraphs: true);
    const raw = [
      SwordEntry(
        SwordKey(19, 23, 1),
        1,
        'No title is needed.<lb/>EXPOSITION<lb/>Verse 1. The Lord is my shepherd.'
        '<lb/>More on verse one.<lb/>Verses 2-3. Green pastures.<lb/>'
        'EXPLANATORY NOTES AND QUAINT SAYINGS<lb/>Whole Psalm. Sweetest psalm.'
        '<lb/>Verse 9. Past the end.<lb/>Verse 4. The valley.',
      ),
    ];
    final rows = convertSwordEntries(spurgeon, raw, (_, _) => 6).entries;
    expect(
      [for (final r in rows) '${r.verseStart}-${r.verseEnd} ${r.text}'],
      [
        '0-0 No title is needed.',
        '1-1 EXPOSITION\nVerse 1. The Lord is my shepherd.\nMore on verse one.',
        '2-3 EXPOSITION\nVerses 2-3. Green pastures.',
        '0-0 EXPLANATORY NOTES AND QUAINT SAYINGS\nWhole Psalm. Sweetest psalm.\n'
            'Verse 9. Past the end.',
        '4-4 EXPLANATORY NOTES AND QUAINT SAYINGS\nVerse 4. The valley.',
      ],
    );
  });

  test('plain text keeps paragraphs and notes and drops every tag', () {
    const markup =
        '<p>Grace &amp; peace&#8212;<hi type="italic">to you</hi>.</p>'
        '<note n="1">A <i>footnote</i>.</note><br />'
        '<scripRef passage="Ge 1:1">Ge 1:1</scripRef> &lt;script&gt;';
    expect(
      commentaryPlainText(markup),
      'Grace & peace\u2014to you.\n[A footnote.]\nGe 1:1 <script>',
    );
  });

  group('CommentaryLibrary', () {
    String pack(String name, List<List<Object>> rows, {String format = commentaryPackFormat}) {
      final path = '${dir.path}/$name.sqlite';
      final db = sqlite3.open(path)..execute(commentaryPackSchema);
      db.execute("INSERT INTO meta VALUES ('format', ?)", [format]);
      final modules = {for (final r in rows) r[0] as String};
      for (final m in modules) {
        db.execute("INSERT INTO modules VALUES (?, ?, 'Author', 'Public domain', 'test', 0)", [
          m,
          '$m title',
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

    test('finds every comment whose range covers a verse, in catalog order', () {
      final lib = CommentaryLibrary();
      expect(
        lib.open(
          'core',
          pack('core', [
            ['TSK', 43, 3, 16, 16, 'loved.'],
            ['MHCC', 43, 3, 14, 18, 'Verses 14-18'],
            ['MHCC', 43, 3, 0, 0, 'Chapter outline'],
            ['MHCC', 43, 0, 0, 0, 'John introduction'],
            ['JFB', 43, 3, 17, 17, 'Not this verse'],
          ]),
        ),
        isTrue,
      );
      expect(
        lib.open(
          'mhc',
          pack('mhc', [
            ['MHC', 43, 3, 16, 21, 'Henry'],
          ]),
        ),
        isTrue,
      );
      expect([for (final e in lib.forRange(43, 3, 16, 16)) e.module], ['MHCC', 'TSK', 'MHC']);
      expect(
        [for (final e in lib.introductions(43, 3)) e.text],
        ['John introduction', 'Chapter outline'],
      );
      expect([for (final m in lib.modules()) m.id], ['MHCC', 'JFB', 'TSK', 'MHC']);
      lib.close('mhc');
      expect(lib.installed, ['core']);
      lib.closeAll();
    });

    test('refuses a missing file, a non-pack and a pack from a newer format', () {
      final lib = CommentaryLibrary();
      expect(lib.open('a', '${dir.path}/missing.sqlite'), isFalse);
      File('${dir.path}/junk.sqlite').writeAsStringSync('not a database');
      expect(lib.open('b', '${dir.path}/junk.sqlite'), isFalse);
      expect(lib.open('c', pack('future', const [], format: '99')), isFalse);
      expect(lib.isEmpty, isTrue);
      expect(CommentaryLibrary.packIdOf('${dir.path}/junk.sqlite'), isNull);
    });

    test('a pack names its own id so a file the user picks lands in the right place', () {
      final path = pack('named', [
        ['Wesley', 40, 1, 1, 1, 'Note'],
      ]);
      final db = sqlite3.open(path)..execute("INSERT INTO meta VALUES ('pack', 'wesley')");
      db.dispose();
      expect(CommentaryLibrary.packIdOf(path), 'wesley');
    });
  });
}
