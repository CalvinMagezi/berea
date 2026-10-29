import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Matthew 5:48, James 1:4 and Job 1:1 as Berea's database has them: τέλειος four times in two
/// verses, and the KJV's "perfect" in Job, which the BSB calls "blameless".
BibleDb wordBible() {
  final raw = sqlite3.openInMemory()
    ..execute('''
      CREATE TABLE verses(id INTEGER PRIMARY KEY, translation TEXT, book INTEGER, chapter INTEGER,
        verse INTEGER, text TEXT);
      CREATE VIRTUAL TABLE verses_fts USING fts5(text, content='verses', content_rowid='id');
      CREATE TABLE words(book INTEGER, chapter INTEGER, verse INTEGER, pos INTEGER, original TEXT,
        translit TEXT, gloss TEXT, strongs TEXT, morph TEXT);
      CREATE TABLE lexicon(key TEXT, base TEXT, lemma TEXT, translit TEXT, pos TEXT, gloss TEXT,
        definition TEXT);
      CREATE TABLE xrefs(from_book INTEGER, from_chapter INTEGER, from_verse INTEGER,
        to_book INTEGER, to_chapter INTEGER, to_verse_start INTEGER, to_verse_end INTEGER,
        votes INTEGER);
    ''');
  void verse(int b, int c, int v, String text) => raw.execute(
    "INSERT INTO verses(translation, book, chapter, verse, text) VALUES ('BSB', ?, ?, ?, ?)",
    [b, c, v, text],
  );
  void words(int b, int c, int v, List<List<String>> ws) {
    for (var i = 0; i < ws.length; i++) {
      raw.execute('INSERT INTO words VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', [
        b,
        c,
        v,
        i + 1,
        ...ws[i],
      ]);
    }
  }

  verse(40, 5, 48, 'Be perfect, therefore, as your heavenly Father is perfect.');
  words(40, 5, 48, [
    ['ἔσεσθε', 'esesthe', 'Will be', 'G1510', 'V-FDI-2P'],
    ['οὖν', 'oun', 'therefore', 'G3767', 'CONJ'],
    ['τέλειοι', 'teleioi', 'perfect', 'G5046', 'A-NPM'],
    ['ὡς', 'hōs', 'how', 'G5613', 'PRT'],
    ['πατὴρ', 'patēr', 'Father', 'G3962', 'N-NSM-T'],
    ['οὐράνιος', 'ouranios', 'Heavenly', 'G3770', 'A-NSM'],
    ['τέλειός', 'teleios', 'perfect', 'G5046', 'A-NSM'],
    ['ἐστιν.¶', 'estin', 'is.', 'G1510', 'V-PAI-3S'],
  ]);
  verse(59, 1, 4, 'Allow perseverance to finish its work, so that you may be mature and complete.');
  words(59, 1, 4, [
    ['ἔργον', 'ergon', 'work', 'G2041', 'N-ASN'],
    ['τέλειον', 'teleion', 'perfect', 'G5046', 'A-ASN'],
    ['τέλειοι', 'teleioi', 'mature', 'G5046', 'A-NPM'],
    ['ὁλόκληροι', 'holoklēroi', 'complete', 'G3648', 'A-NPM'],
  ]);
  verse(
    18,
    1,
    1,
    'There was a man in the land of Uz whose name was Job. And this man was blameless.',
  );
  words(18, 1, 1, [
    ['אִ֛ישׁ', "'ish", 'a man', 'H0376G', 'HNcmsa'],
    ['בְ/אֶֽרֶץ\\־', "ve./'e.retz-", 'in/ [the] land of', 'H9003 H0776G H9014', 'HR/Ncfsc'],
    ['הָ/אִ֣ישׁ', "ha./'Ish", 'the/ man', 'H9009 H0376G', 'HTd/Ncmsa'],
    ['תָּ֧ם', 'tam', 'blameless', 'H8535', 'HAamsa'],
    ['וְ/', 've.', 'and/', 'H9002', 'HC'],
  ]);
  for (final l in [
    ['G5046', 'G5046', 'τέλειος', 'teleios', 'G:A', 'perfect', 'having reached its end, mature'],
    ['H8535', 'H8535', 'תָּם', 'tam', 'H:A', 'complete', '1) perfect, complete 1a) sound'],
    ['H0376G', 'H0376', 'אִישׁ', "'ish", 'H:N-M', 'man', '1) man'],
    ['G3648', 'G3648', 'ὁλόκληρος', 'holoklēros', 'G:A', 'complete', 'whole'],
  ]) {
    raw.execute('INSERT INTO lexicon VALUES (?, ?, ?, ?, ?, ?, ?)', l);
  }
  raw.execute("INSERT INTO verses_fts(verses_fts) VALUES('rebuild')");
  return BibleDb(raw);
}

void main() {
  test('stems match the forms a verse and a gloss use', () {
    for (final (a, b) in [
      ('loved', 'love'),
      ('loves', 'loving'),
      ('stopped', 'stop'),
      ('called', 'call'),
      ('blessed', 'bless'),
      ('blesses', 'bless'),
      ('cities', 'city'),
      ('taketh', 'take'),
      ('children', 'child'),
      ('king’s', 'king'),
      ('Perfect', 'perfect'),
    ]) {
      expect(wordStem(a), wordStem(b), reason: '$a and $b');
    }
    expect(wordStem('perfection'), isNot(wordStem('perfect')));
    expect(wordStem('forest'), isNot(wordStem('for')));
  });

  test('Strong numbers are read and reduced to their base', () {
    expect(strongsBase('H8549G'), 'H8549');
    expect(strongsBase('G25'), 'G0025');
    expect(strongsIn('the Greek word τέλειος (teleios, G5046), "perfect"'), 'G5046');
    expect(strongsIn('Study John 3:16'), isNull);
    expect(studyCode(const WordTag('', '', '', 'H9003 H0776G H9014', '')), 'H0776');
    expect(studyCode(const WordTag('', '', '', 'H9002', '')), 'H9002');
    expect(studyCode(const WordTag('', '', '', '', '')), isNull);
  });

  test('the pressed word and which time it occurs in the verse', () {
    const text = 'Be perfect, therefore, as your heavenly Father is perfect.';
    expect(wordAt(text, text.indexOf('perfect') + 2), (
      word: 'perfect',
      start: 3,
      index: 1,
      occurrence: 0,
    ));
    expect(wordAt(text, text.lastIndexOf('perfect'))?.index, 8);
    expect(wordAt(text, text.lastIndexOf('perfect'))?.occurrence, 1);
    // The right edge of the last letter still counts; a space or a comma does not.
    expect(wordAt(text, text.indexOf('Father') + 6)?.word, 'Father');
    expect(wordAt(text, text.indexOf(', as') + 1), isNull);
    expect(wordAt('the king’s house', 6)?.word, 'king’s');
    expect(wordAt('she shall be called ‘woman,’ for', 21)?.word, 'woman');
    expect(wordAt('', 0), isNull);
  });

  test('a pressed word finds the original word behind it', () {
    final db = wordBible();
    final matt = db.words(RefParser.parse('Matthew 5:48').first);
    final first = matchOriginal(matt, 'perfect', lexicon: db.lexicon);
    expect(matt[first.first].original, 'τέλειοι');
    expect(matt[first[1]].original, 'τέλειός');
    // The second "perfect" in the English goes to the second τέλειος.
    final second = matchOriginal(matt, 'perfect', occurrence: 1, lexicon: db.lexicon);
    expect(matt[second.first].original, 'τέλειός');
    expect(matt[matchOriginal(matt, 'heavenly').first].translit, 'ouranios');
    expect(matchOriginal(matt, 'shunning', lexicon: db.lexicon), isEmpty);

    // The KJV's "perfect" in Job 1:1 is תָּם, found through its lexicon definition.
    final job = db.words(RefParser.parse('Job 1:1').first);
    expect(job[matchOriginal(job, 'perfect', lexicon: db.lexicon).first].translit, 'tam');
    // A word STEP marks as supplied still matches, below one it does not.
    expect(job[matchOriginal(job, 'land').first].strongs, 'H9003 H0776G H9014');
  });

  test('BSB table phrases are aligned to the words of the verse', () {
    const verse = 'God blessed them and said to them, “Be fruitful and multiply.”';
    final words = alignBsbWords(verse, const [
      BsbRow('God', 'H0430'),
      BsbRow('blessed', 'H1288'),
      BsbRow('them', ''),
      BsbRow('and said', 'H0559'),
      BsbRow('to them', ''),
      BsbRow('Be fruitful', 'H6509'),
      BsbRow('and multiply', 'H7235'),
    ]);
    expect(
      [for (final w in words) w.code],
      [
        'H0430',
        'H1288',
        '',
        'H0559',
        'H0559',
        '',
        '',
        'H6509',
        'H6509',
        'H7235',
        'H7235', //
      ],
    );
    // A phrase is one row: its words share the row's span, and a single word is its own row.
    expect(
      [for (final w in words) (w.rowStart, w.rowEnd)],
      [
        (0, 1),
        (1, 2),
        (2, 3),
        (3, 5),
        (3, 5),
        (5, 7),
        (5, 7),
        (7, 9),
        (7, 9),
        (9, 11),
        (9, 11), //
      ],
    );
    expect(words[3].inPhrase, isTrue);
    expect(words[0].inPhrase, isFalse);
    // A table word missing from the verse text leaves the rest aligned.
    expect(
      [
        for (final w in alignBsbWords('In the beginning God', const [
          BsbRow('In the very beginning', 'H7225'),
          BsbRow('God', 'H0430'),
        ]))
          w.code,
      ],
      ['H7225', 'H7225', 'H7225', 'H0430'],
    );
    expect(alignBsbWords('', const [BsbRow('God', 'H0430')]), isEmpty);
  });

  test('alignment follows the content, so extra table words do not shift later codes', () {
    // The table carries a variant reading ("and the") the reader text lacks. Placing words in a
    // short window used to hand the verse's own "the" to the variant's row.
    const verse = 'Then she tightened it with a pin and called to him.';
    final words = alignBsbWords(verse, const [
      BsbRow('Then', 'H0000'),
      BsbRow('she tightened', 'H8628'),
      BsbRow('it', ''),
      BsbRow('with the', 'H0111'),
      BsbRow('a pin', 'H3489'),
      BsbRow('and called', 'H0559'),
      BsbRow('to him', 'H0413'),
    ]);
    final byWord = {
      for (var i = 0; i < words.length; i++)
        verseWordPattern.allMatches(verse).elementAt(i)[0]!: words[i].code,
    };
    expect(byWord['pin'], 'H3489');
    expect(byWord['called'], 'H0559');
    expect(byWord['him'], 'H0413');
    expect(byWord['tightened'], 'H8628');
  });

  test('glosses are cleaned and marked in a verse', () {
    expect(cleanGloss('in/ [the] land of'), 'land');
    expect(cleanGloss('<the>/ music', strongs: 'H9009 H2170'), 'music');
    // Parts that line up with the codes pick the word, not the longer suffix.
    expect(cleanGloss('god/ your', strongs: 'H0430G H9033'), 'god');
    expect(cleanGloss('god/ your'), 'god');
    expect(cleanGloss('in/ him'), 'him');
    expect(cleanGloss('a complete'), 'complete');
    expect(cleanGloss('is.'), 'is');
    expect(cleanOriginal('ἐστιν.¶'), 'ἐστιν');
    // The accent goes, the vowels stay.
    expect(cleanOriginal('תָּ֧ם'), 'תָּם');
    expect(cleanOriginal('בְ/אֶֽרֶץ\\־'), 'בְאֶֽרֶץ');
    const text = 'Be perfect, therefore, as your heavenly Father is perfect.';
    expect(glossRanges(text, 'perfect'), [(3, 10), (50, 57)]);
    // Small words in a gloss mark nothing.
    expect(glossRanges(text, 'to perfect').length, 2);
    expect(glossRanges(text, 'the/'), isEmpty);
  });

  test('part of speech and language read as words', () {
    expect(partOfSpeech('G:A'), 'adjective');
    expect(partOfSpeech('H:N-F'), 'noun (feminine)');
    expect(partOfSpeech('N:N-M-P'), 'name of a person');
    expect(partOfSpeech('N:N--L'), 'name of a place');
    expect(partOfSpeech(''), '');
    expect(languageOf('G5046'), 'Greek');
    expect(languageOf('H0376', morph: 'HNcmsa'), 'Hebrew');
    expect(languageOf('H0606', morph: 'ANcmsa'), 'Aramaic');
  });

  test('the concordance counts, lists and samples every use of a word', () {
    final db = wordBible();
    expect(db.wordCount('G5046'), (uses: 4, verses: 2));
    expect(db.wordCount('G5046A'), (uses: 4, verses: 2));
    expect(db.wordBooks('G5046').map((b) => (b.$1.name, b.$2)), [('Matthew', 2), ('James', 2)]);
    expect(db.wordGlosses('G5046'), [('perfect', 3), ('mature', 1)]);

    final uses = db.wordUses('G5046');
    expect(uses.map((u) => u.ref.label), ['Matthew 5:48', 'James 1:4']);
    expect(uses.first.words.map((w) => w.pos), [3, 7]);
    expect(uses.first.text, startsWith('Be perfect'));
    expect(db.wordUses('G5046', limit: 1, offset: 1).single.ref.label, 'James 1:4');
    expect(db.wordUses('G5046', book: bookById(59)).single.ref.label, 'James 1:4');
    // A translation that lacks the verse still lists the use, without text.
    expect(db.wordUses('G5046', translation: 'KJV').first.text, isNull);

    // A prefixed Hebrew word is filed under the word; a bare prefix under itself.
    expect(db.wordCount('H0376').uses, 2);
    expect(db.wordCount('H9009').uses, 0);
    expect(db.wordCount('H9002').uses, 1);

    final sample = db.wordSample('G5046', k: 3, exclude: RefParser.parse('Matthew 5:48').first);
    expect(sample.map((v) => v.label), ['James 1:4']);
    expect(db.wordSample('G5046', k: 0), isEmpty);
  });

  test('other words glossed with the same English are found by stem', () {
    final db = wordBible();
    final perfect = db.wordsGlossed('perfect');
    expect(perfect.map((w) => w.code), ['G5046']);
    expect(perfect.single.glossed, 3);
    expect(perfect.single.uses, 4);
    expect(perfect.single.entry?.lemma, 'τέλειος');
    expect(db.wordsGlossed('complete').map((w) => w.code), ['G3648']);
    expect(db.wordsGlossed('blameless').single.code, 'H8535');
    expect(db.wordsGlossed('nothing'), isEmpty);
  });

  test('a word study question names the word so the chat can find it', () {
    final db = wordBible();
    final q = wordStudyQuestion(
      english: 'perfect',
      ref: RefParser.parse('Matthew 5:48').first,
      entry: db.lexicon('G5046')!,
      language: 'Greek',
    );
    expect(q, contains('Matthew 5:48'));
    expect(q, contains('τέλειος (teleios, G5046)'));
    expect(strongsIn(q), 'G5046');
    expect(RefParser.parse(q).map((r) => r.label), ['Matthew 5:48']);

    final across = wordStudyQuestion(entry: db.lexicon('H8535')!, language: 'Hebrew');
    expect(across, startsWith('Word study: the Hebrew word תָּם (tam, H8535), "complete".'));
    expect(across, contains('used in Scripture'));
    expect(RefParser.parse(across), isEmpty);
    final ctx = Retriever(db).retrieve(across, Tier.low);
    expect(ctx.passages, isEmpty);
    expect(ctx.searchHits.single.label, 'Job 1:1');
  });

  test('a word study question puts the word and its other uses in front of the model', () {
    final db = wordBible();
    final q = wordStudyQuestion(
      english: 'perfect',
      ref: RefParser.parse('Matthew 5:48').first,
      entry: db.lexicon('G5046')!,
      language: 'Greek',
    );
    final ctx = Retriever(db).retrieve(q, Tier.low);
    expect(ctx.passages.single.label, 'Matthew 5:48');
    expect(ctx.lexicon.keys.first, 'G5046');
    // The other use replaces search hits; the verse being studied is not repeated.
    expect(ctx.searchHits.map((v) => v.label), ['James 1:4']);

    final prompt = PromptBuilder('system').build(ctx, const [], q, Tier.low);
    final user = prompt.messages.last.content;
    expect(user, contains('LEXICON\nG5046 τέλειος (teleios)'));
    expect(user, contains('RELATED VERSES\n(James 1:4, BSB)'));
    expect(prompt.shown.searchHits.single.label, 'James 1:4');
  });

  test('a question without a known Strong number searches as before', () {
    final db = wordBible();
    final plain = Retriever(db).retrieve('What does mature mean?', Tier.low);
    expect(plain.searchHits.map((v) => v.label), ['James 1:4']);
    expect(plain.lexicon, isEmpty);
    final unknown = Retriever(db).retrieve('What is G9999 about maturity, mature?', Tier.low);
    expect(unknown.searchHits.map((v) => v.label), ['James 1:4']);
  });

  test('the BSB tables file is read by column name, in English order', () {
    const header =
        'Heb Sort\tGreek Sort\tBSB Sort\tVerse\tLanguage\tWLC\tWLC2\tTranslit\tParsing\tParsing\t'
        'Str Heb\tStr Grk\tVerseId\tHdg\tCrossref\tPar\tSpace\tbegQ\t BSB version \tpnc\tendQ\t'
        'footnotes\tEnd text';
    String row(int sort, int verse, String heb, String grk, String id, String english) =>
        '$sort\t0\t$sort\t$verse\tHebrew\tx\tx\tx\tx\tx\t$heb\t$grk\t$id\t\t\t\t\t\t $english \t\t\t\t';
    final tables = parseBsbTables(
      [
        header,
        row(1, 1, '7225', '', 'Genesis 1:1', 'In the beginning'),
        row(4, 1, '1254', '', '', 'created'),
        row(3, 1, '853', '', '', '-'),
        row(2, 1, '430', '', '', 'God'),
        row(5, 2, '', '', 'Genesis 1:2', 'Now'),
        '',
      ].join('\r\n'),
    );
    final gen11 = RefParser.parse('Genesis 1:1').first;
    List<(String, String, int)> rows(Ref ref) => [
      for (final r in tables[ref]!) (r.english, r.code, r.repeat),
    ];
    expect(rows(gen11), [
      ('In the beginning', 'H7225', 0),
      ('God', 'H0430', 0),
      ('created', 'H1254', 0),
    ]);
    expect(rows(RefParser.parse('Genesis 1:2').first), [('Now', '', 0)]);
    expect(() => parseBsbTables('Verse\tVerseId\n'), throwsFormatException);
  });

  test('the BSB alignment is stored per verse and read back with its phrases and repeats', () {
    final db = wordBible();
    final matt = RefParser.parse('Matthew 5:48').first;
    expect(db.bsbCodes(matt), isNull);
    expect(
      db.importBsbAlignment({
        matt: const [
          BsbRow('Be', 'G1510'),
          BsbRow('perfect', 'G5046'),
          BsbRow(', therefore,', ''),
          BsbRow('as your heavenly', 'G3770'),
          BsbRow('Father', 'G3962'),
          BsbRow('is perfect', 'G5046', 1),
        ],
        RefParser.parse('Genesis 1:1').first: const [BsbRow('In the beginning', 'H7225')],
      }),
      1,
    );
    expect(db.bsbCodes(matt)!.take(4), ['G1510', 'G5046', '', 'G3770']);
    expect(db.bsbCodes(matt)!.length, 9);
    final words = db.bsbWords(matt)!;
    expect((words[3].rowStart, words[3].rowEnd), (3, 6));
    expect(words[5].inPhrase, isTrue);
    expect(words[7].code, 'G5046');
    expect(words[7].repeat, 1);
    expect(words[1].repeat, 0);
    expect(db.bsbCodes(RefParser.parse('Job 1:1').first), isNull);
  });

  test('table rows number repeats of a word in the original order', () {
    String row(int sort, int original, String grk, String english) =>
        '$sort\t$original\t$sort\t7\tGreek\tx\tx\tx\tx\tx\t\t$grk\tJohn 1:1\t\t\t\t\t\t $english \t\t\t\t';
    final header = [
      'Heb Sort',
      'Greek Sort',
      'BSB Sort',
      'Verse',
      'Language',
      'a',
      'b',
      'c',
      'd',
      'e', //
      'Str Heb',
      'Str Grk',
      'VerseId',
      'Hdg',
      'Crossref',
      'Par',
      'Space',
      'begQ',
      'BSB version', 'pnc', 'endQ', 'footnotes', 'End text',
    ].join('\t');
    // English order: the second article-led word comes first, but is later in the Greek. A word
    // the BSB leaves out (blank English) still comes before them in the Greek.
    final tables = parseBsbTables(
      [
        header,
        row(1, 30, '3588', 'the one'),
        row(2, 10, '3588', '-'),
        row(3, 20, '3588', 'the other'),
        row(4, 5, '3588', ''),
        '',
      ].join('\n'),
    );
    final rows = tables[RefParser.parse('John 1:1').first]!;
    expect([for (final r in rows) (r.english, r.repeat)], [('the one', 3), ('the other', 2)]);
  });

  group('a pressed word leads to the original word behind it', () {
    LexEntry? lex(String c) => switch (c) {
      'G2424' => const LexEntry('G2424G', 'Ἰησοῦς', 'Iēsous', 'N:N-M-P', 'Jesus', 'Jesus'),
      'G2036' => const LexEntry('G2036', 'εἶπον', 'eipon', 'G:V', 'to say', 'to say'),
      'G1145' => const LexEntry('G1145', 'δακρύω', 'dakruō', 'G:V', 'to weep', 'to weep'),
      _ => null,
    };
    WordTag tag(int pos, String gloss, String code) => WordTag('', '', gloss, code, '', pos: pos);
    PressedWord press(String english, List<WordTag> tags, List<BsbWord> bsb, int at) =>
        resolvePress(
          english: english,
          translation: defaultTranslation,
          tags: tags,
          lexicon: lex,
          isName: (w) => w.toLowerCase() == 'jesus',
          bsb: bsb,
          wordIndex: at,
        );

    test('the tables decide, and the verse repeats pick by original order', () {
      final tags = [tag(1, 'Wept', 'G1145'), tag(2, '<the> Jesus', 'G2424G')];
      final bsb = [const BsbWord('G2424', 0, 0, 1), const BsbWord('G1145', 0, 1, 2)];
      final jesus = press('Jesus', tags, bsb, 0);
      expect(jesus.kind, PressKind.exact);
      expect(jesus.code, 'G2424');
      expect(jesus.tag, tags[1]);
      expect(press('wept', tags, bsb, 1).code, 'G1145');
    });

    test('a name the BSB wrote onto a verb is not opened as that verb', () {
      // "Jesus replied" is one Greek verb; the Greek has no name here.
      final tags = [tag(1, 'He said', 'G2036')];
      final bsb = [const BsbWord('G2036', 0, 0, 2), const BsbWord('G2036', 0, 0, 2)];
      final p = press('Jesus', tags, bsb, 0);
      expect(p.kind, PressKind.unknown);
      expect(p.code, isNull);
      expect(p.bsb?.code, 'G2036');
      // The verb's other English word still opens the verb.
      expect(press('replied', tags, bsb, 1).kind, PressKind.exact);
    });

    test('a name on a verb falls back to the verse\'s own name when it has one', () {
      final tags = [tag(1, 'He said', 'G2036'), tag(2, 'Jesus', 'G2424G')];
      final bsb = [const BsbWord('G2036', 0, 0, 2), const BsbWord('G2036', 0, 0, 2)];
      final p = press('Jesus', tags, bsb, 0);
      expect(p.kind, PressKind.byMeaning);
      expect(p.code, 'G2424');
    });

    test('words the translators supplied, and other translations, are told apart', () {
      expect(press('this', const [], [const BsbWord('', 0, 0, 1)], 0).kind, PressKind.supplied);
      final kjv = resolvePress(
        english: 'Jesus',
        translation: 'KJV',
        tags: [tag(1, 'Jesus', 'G2424G')],
        lexicon: lex,
        isName: (_) => true,
        wordIndex: 0,
      );
      expect(kjv.kind, PressKind.byMeaning);
      expect(kjv.code, 'G2424');
      expect(press('Jesus', const [], const [], 5).kind, PressKind.unknown);
    });
  });
}
