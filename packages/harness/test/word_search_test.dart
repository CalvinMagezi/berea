import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// A small Bible whose words are tagged the way STEPBible's are, enough to search by English,
/// by number and by spelling: hagios and qadosh are "holy" in several verses, qodesh is
/// "holiness" and "holy" once, pneuma is "spirit", and the article only fills a slot.
Database wordFixture({bool withIndex = true, String? path}) {
  final raw = path == null ? sqlite3.openInMemory() : sqlite3.open(path);
  createBibleSchema(raw);
  var n = 0;
  void verse(int book, int chapter, int v, List<List<String>> tagged) {
    for (var i = 0; i < tagged.length; i++) {
      raw.execute('INSERT INTO words VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', [
        book,
        chapter,
        v,
        i + 1,
        ...tagged[i],
      ]);
    }
    n++;
  }

  // Greek: three verses glossed "holy" for hagios, one for the Spirit.
  verse(46, 7, 14, [
    ['ἅγια', 'hagia', 'holy', 'G0040', 'A-NPN'],
    ['τὸ', 'to', 'the', 'G3588', 'T-NSN'],
  ]);
  verse(51, 1, 2, [
    ['ἁγίοις', 'hagiois', 'holy', 'G0040', 'A-DPM'],
    ['πνεῦμα', 'pneuma', 'spirit', 'G4151', 'N-NSN'],
  ]);
  verse(44, 2, 4, [
    ['ἁγίου', 'hagiou', 'holy', 'G0040', 'A-GSN'],
    ['πνεύματος', 'pneumatos', 'Spirit', 'G4151', 'N-GSN'],
  ]);
  // Hebrew: two verses for qadosh, one for qodesh.
  verse(3, 19, 2, [
    ['קָדוֹשׁ', 'qa.dosh', 'holy', 'H6918', 'HAamsa'],
  ]);
  verse(19, 99, 9, [
    ['קָדוֹשׁ', 'qa.dosh', 'holy', 'H6918', 'HAamsa'],
    ['רוּחַ', 'ru.ach', 'spirit', 'H7307', 'HNcfsa'],
    ['קֹדֶשׁ', 'qo.desh', 'holy', 'H6944', 'HNcmsa'],
  ]);
  expect(n, 5);
  for (final l in [
    ['G0040G', 'G0040', 'ἅγιος', 'hagios', 'G:A', 'holy', 'set apart, sacred'],
    [
      'G0040H',
      'G0040',
      'ἅγιος',
      'hagios',
      'G:A',
      'holy: saint',
      'a holy person',
    ],
    ['G3588', 'G3588', 'ὁ', 'ho', 'G:T', 'holy', 'the article'],
    [
      'G4151',
      'G4151',
      'πνεῦμα',
      'pneuma',
      'G:N',
      'spirit',
      'wind, breath, spirit',
    ],
    ['H6918G', 'H6918', 'קָדוֹשׁ', 'qa.dosh', 'H:A', 'holy', 'sacred, holy'],
    [
      'H6944G',
      'H6944',
      'קֹדֶשׁ',
      'qo.desh',
      'H:N-M',
      'holiness',
      'apartness, holiness',
    ],
    ['H7307G', 'H7307', 'רוּחַ', 'ru.ach', 'H:N-F', 'spirit', 'wind, spirit'],
    ['G0462', 'G0462', 'ἀνόσιος', 'anosios', 'G:A', 'unholy', 'profane'],
  ]) {
    raw.execute('INSERT INTO lexicon VALUES (?, ?, ?, ?, ?, ?, ?)', l);
  }
  if (withIndex) BibleDb(raw).buildWordIndex();
  return raw;
}

void main() {
  late BibleDb db;
  setUp(() => db = BibleDb(wordFixture()));

  String codes(List<WordMatch> ms) => ms.map((m) => m.code).join(' ');

  test(
    'an English word lists the words STEPBible glosses with it, most often first',
    () {
      final found = db.searchWords('Holy');
      expect(found.first.code, 'G0040', reason: 'glossed "holy" three times');
      expect(found[1].code, 'H6918', reason: 'glossed "holy" twice');
      final hagios = found.first;
      expect(hagios.kind, WordMatchKind.glossed);
      expect(hagios.term, 'holy');
      expect(hagios.glossed, 3);
      expect((hagios.uses, hagios.verses), (3, 3));
      expect(hagios.entry.lemma, 'ἅγιος');
      expect(hagios.language, 'Greek');
      expect(found[1].language, 'Hebrew');
    },
  );

  test(
    'a word glossed the search word once is not listed by the index, and a gloss still is',
    () {
      final found = db.searchWords('holy');
      // qodesh is glossed "holy" once (below the bar for tying two words together) and its own
      // lexicon gloss is "holiness", a different word.
      expect(codes(found), isNot(contains('H6944')));
      // "unholy" is another word, not a form of "holy".
      expect(codes(found), isNot(contains('G0462')));
    },
  );

  test('a function word is not listed for an English word', () {
    // The article is glossed "holy" in the fixture; it only fills a slot in a sentence.
    expect(codes(db.searchWords('holy')), isNot(contains('G3588')));
  });

  test(
    'a word the lexicon glosses, but no verse is tagged with, is listed after the others',
    () {
      final raw = wordFixture();
      raw.execute(
        "INSERT INTO lexicon VALUES ('H6922', 'H6922', 'קַדִּישׁ', 'qad.dish', 'A:A', 'holy', 'holy')",
      );
      final found = BibleDb(raw).searchWords('holy');
      expect(found.last.code, 'H6922');
      expect(found.last.kind, WordMatchKind.defined);
      expect(found.last.uses, 0);
    },
  );

  test('a Strong\'s number lists that word alone, however it is written', () {
    for (final typed in ['G40', 'g0040', 'G0040G', ' G40 ']) {
      final found = db.searchWords(typed);
      expect(found, hasLength(1), reason: typed);
      expect(found.single.code, 'G0040', reason: typed);
      expect(found.single.kind, WordMatchKind.number, reason: typed);
    }
    expect(db.searchWords('G9999'), isEmpty);
  });

  test(
    'a spelling in English letters finds the word, with or without the dots',
    () {
      expect(codes(db.searchWords('hagios')), 'G0040');
      expect(db.searchWords('hagios').single.kind, WordMatchKind.original);
      expect(codes(db.searchWords('qadosh')), 'H6918');
      expect(codes(db.searchWords('qa.dosh')), 'H6918');
      expect(
        codes(db.searchWords('hagi')),
        'G0040',
        reason: 'the start of a word, from 4 letters',
      );
      expect(
        db.searchWords('hag'),
        isEmpty,
        reason: 'three letters must match all of it',
      );
    },
  );

  test('a word in its own script finds it', () {
    expect(codes(db.searchWords('ἅγιος')), 'G0040');
    expect(codes(db.searchWords('קָדוֹשׁ')), 'H6918');
  });

  test(
    'several words list the words for any of them, those holding more of them first',
    () {
      final raw = wordFixture();
      // One word the lexicon calls both, so it holds both words of the search.
      raw.execute(
        "INSERT INTO lexicon VALUES ('G9990', 'G9990', 'x', 'pneuma-hagion', 'G:N', 'Holy Spirit', 'the Spirit')",
      );
      final found = BibleDb(raw).searchWords('holy spirit');
      expect(found.first.code, 'G9990');
      expect([
        for (final m in found) m.code,
      ], containsAll(['G0040', 'G4151', 'H6918', 'H7307']));
    },
  );

  test('a function word, or nothing, lists nothing', () {
    expect(db.searchWords('the'), isEmpty);
    expect(db.searchWords('   '), isEmpty);
    expect(db.searchWords('zzzqqq'), isEmpty);
    expect(db.searchWords('holy', limit: 0), isEmpty);
  });

  test('limit caps the list', () {
    expect(db.searchWords('holy', limit: 1), hasLength(1));
  });

  test('a database with no word index lists nothing', () {
    final bare = BibleDb(wordFixture(withIndex: false));
    expect(bare.searchWords('holy'), isEmpty);
    expect(bare.searchWords('G40'), isEmpty);
  });

  test('a read-only connection searches words and writes nothing', () {
    final dir = Directory.systemTemp.createTempSync('berea_words');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/words.sqlite';
    wordFixture(path: path).dispose();
    final reader = BibleDb(sqlite3.open(path, mode: OpenMode.readOnly));
    addTearDown(reader.close);
    expect(codes(reader.searchWords('holy')), startsWith('G0040 H6918'));
    expect(codes(reader.searchWords('G40')), 'G0040');
  });
}
