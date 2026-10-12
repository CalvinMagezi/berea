import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _john316 =
    'For God so loved the world that He gave His one and only Son, that everyone who believes in '
    'Him shall not perish but have eternal life.';

/// John 3:16 and 17, then [extra] long verses of John 4, enough to overflow any budget.
BibleDb _db({int extra = 0}) {
  final raw = sqlite3.openInMemory()
    ..execute('''
      CREATE TABLE verses(id INTEGER PRIMARY KEY, translation TEXT, book INTEGER, chapter INTEGER,
        verse INTEGER, text TEXT);
    ''');
  final insert = raw.prepare(
    "INSERT INTO verses(translation, book, chapter, verse, text) VALUES ('BSB', ?, ?, ?, ?)",
  );
  insert.execute([43, 3, 16, _john316]);
  insert.execute([
    43,
    3,
    17,
    'For God did not send His Son into the world to condemn the world, but to save the world '
        'through Him.',
  ]);
  for (var v = 1; v <= extra; v++) {
    insert.execute([
      43,
      4,
      v,
      'Verse $v of a long chapter: ${List.filled(40, 'word$v').join(' ')}',
    ]);
  }
  insert.dispose();
  return BibleDb(raw);
}

StudyContext _ctx(BibleDb db, String refs, {List<SourceChunk> sources = const []}) {
  final parsed = RefParser.parse(refs);
  return StudyContext(
    refs: parsed,
    passages: [for (final r in parsed) ...db.passage(r)],
    words: const [],
    lexicon: const {},
    xrefVerses: const [],
    searchHits: const [],
    sources: sources,
  );
}

SourceChunk _chunk(int source, int ordinal, String text, {int? page, String title = 'Guide'}) =>
    SourceChunk(
      sourceId: source,
      title: title,
      kind: page == null ? SourceKind.text : SourceKind.pdf,
      ordinal: ordinal,
      page: page,
      text: text,
    );

const _guidePage2 =
    'The Bereans had three habits: they received the word eagerly, they examined the '
    'Scriptures every day, and they compared what they heard with what was written.';
const _misquote = 'My note says John 3:16 promises that whoever believes will become rich.';
const _friendQuote =
    'For God so loved the world that whoever believes in him will become rich and never be sick';

void main() {
  final db = _db();
  final guide = _chunk(3, 1, _guidePage2, page: 2);
  final note = _chunk(5, 0, _misquote, title: 'Sermon note');
  final commentary = SourceChunk(
    title: 'Test commentary on John 3:16',
    kind: SourceKind.commentary,
    ordinal: 0,
    text: 'Love is the spring of the gift.',
    ref: RefParser.parse('John 3:16').first,
  );
  final cTag = packTag(commentary, <String>{});
  final friend = _chunk(
    6,
    0,
    'A friend wrote: John 3:16 says, "$_friendQuote." Faith brings wealth.',
  );
  final split = [
    _chunk(7, 0, 'The first part ends with grace and'),
    _chunk(7, 1, 'truth for all who listen closely to the word.'),
  ];
  final shown = PromptBuilder('SYS')
      .build(
        _ctx(db, 'John 3:16', sources: [guide, note, commentary, friend, ...split]),
        const [],
        'Q',
        Tier.mid,
        notebook: true,
      )
      .shown;
  final guard = CitationGuard(db);

  GuardResult check(String output) => guard.apply(output, shown, checkSources: true);

  group('budget', () {
    test('only verses that fit the prompt count as shown', () {
      final big = _db(extra: 200);
      final ctx = _ctx(big, 'John 4');
      final built = PromptBuilder('SYS').build(ctx, const [], 'Q', Tier.low);
      expect(built.shown.passages.length, lessThan(ctx.passages.length));
      final cut = ctx.passages.last;
      final kept = built.shown.passages.last;
      final words = cut.text.split(' ').take(12).join(' ');
      // A quote of a verse the budget cut is no longer accepted; one that was shown still is.
      final cutResult = CitationGuard(big).apply('It says "$words".', built.shown);
      expect(cutResult.unverifiedQuotes, hasLength(1));
      final keptWords = kept.text.split(' ').take(12).join(' ');
      expect(
        CitationGuard(big).apply('It says "$keptWords".', built.shown).unverifiedQuotes,
        isEmpty,
      );
      expect(built.messages.last.content, isNot(contains(cut.text)));
    });

    test('the Study prompt has no SOURCES and keeps its system prompt', () {
      final built = PromptBuilder(
        'SYS',
      ).build(_ctx(db, 'John 3:16', sources: [guide]), const [], 'Q', Tier.mid);
      expect(built.messages.first.content, 'SYS');
      expect(built.messages.last.content, isNot(contains('SOURCES')));
      expect(built.shown.sources, isEmpty);
    });

    test('SOURCES follows PASSAGES, keeps to its share, and skips a chunk too long to fit', () {
      final english = List.filled(25, 'Grace teaches us to say no to ungodliness.').join(' ');
      final greek = List.filled(120, 'ἀγάπη').join(' ');
      final chunks = [
        _chunk(1, 0, english),
        _chunk(2, 0, greek),
        for (var i = 1; i < 12; i++) _chunk(1, i, english),
      ];
      final built = PromptBuilder(
        'SYS',
      ).build(_ctx(db, 'John 3:16', sources: chunks), const [], 'Q', Tier.low, notebook: true);
      final user = built.messages.last.content;
      expect(built.messages.first.content, contains(notebookRules));
      expect(user.indexOf('PASSAGES'), lessThan(user.indexOf('SOURCES')));
      final shownChunks = built.shown.sources;
      expect(shownChunks, isNotEmpty);
      expect(shownChunks.length, lessThan(chunks.length));
      expect(shownChunks.any((c) => c.sourceId == 2), isFalse);
      expect(shownChunks.map((c) => c.ordinal), [0, 1]);
      final cost = shownChunks
          .map((c) => estimateTokens('[${notebookTag(c)}] (${c.title}, ${c.kind.label}) ${c.text}'))
          .reduce((a, b) => a + b);
      expect(cost, lessThanOrEqualTo(Tier.low.sourceTokens));
      expect(user, contains('[S1 §1] (Guide, Pasted text) Grace teaches'));
    });

    test('a long passage cannot take the share reserved for sources', () {
      final big = _db(extra: 200);
      final built = PromptBuilder(
        'SYS',
      ).build(_ctx(big, 'John 4', sources: [guide]), const [], 'Q', Tier.mid, notebook: true);
      expect(built.shown.sources.single.text, _guidePage2);
      expect(built.shown.passages, isNotEmpty);
    });

    test('an empty notebook still gets a SOURCES block that says so', () {
      final built = PromptBuilder(
        'SYS',
      ).build(_ctx(db, 'John 3:16'), const [], 'Q', Tier.mid, notebook: true);
      expect(built.messages.last.content, contains('SOURCES\n$noSourcesShown'));
    });

    test('a source too long for a small tier is cut to fit rather than reported missing', () {
      final greek = List.filled(400, 'ἀγάπη').join(' ');
      final built = PromptBuilder('SYS').build(
        _ctx(db, 'John 3:16', sources: [_chunk(2, 0, greek)]),
        const [],
        'Q',
        Tier.low,
        notebook: true,
      );
      final user = built.messages.last.content;
      expect(user, isNot(contains(noSourcesShown)));
      expect(user, contains('[S2 §1] (Guide, Pasted text) ἀγάπη'));
      expect(built.shown.sources.single.text.length, lessThan(greek.length));
      expect(greek, startsWith(built.shown.sources.single.text));
    });

    test('with no verse shown the note against quoting from memory stays beside SOURCES', () {
      final built = PromptBuilder('SYS').build(
        _ctx(db, 'no reference here', sources: [guide]),
        const [],
        'Q',
        Tier.mid,
        notebook: true,
      );
      final user = built.messages.last.content;
      expect(user, contains(noPassagesLoaded));
      expect(user, contains('SOURCES\n[S3 p.2]'));
    });

    test('the whole prompt stays within the budget, however long the question', () {
      final big = _db(extra: 200);
      final longQuestion = List.filled(4000, 'why').join(' ');
      final history = [
        for (var i = 0; i < 4; i++) ChatMessage.user(List.filled(300, 'grace').join(' ')),
      ];
      for (final tier in Tier.values) {
        for (final notebook in [false, true]) {
          final built = PromptBuilder('SYS').build(
            _ctx(big, 'John 4', sources: [guide, note, commentary]),
            history,
            longQuestion,
            tier,
            notebook: notebook,
          );
          final total = built.messages.fold(0, (sum, m) => sum + estimateTokens(m.content));
          expect(total, lessThanOrEqualTo(tier.promptTokens), reason: '${tier.name} $notebook');
          expect(built.messages.last.content, contains('[question shortened]'));
        }
      }
    });

    test('estimates are high for digits, punctuation, Greek and Hebrew', () {
      expect(estimateTokens('grace and peace'), 4);
      expect(estimateTokens('3:16'), 4);
      expect(estimateTokens('ἀγάπη'), 5);
      expect(estimateTokens('בְּרֵאשִׁית'), 'בְּרֵאשִׁית'.length);
    });
  });

  group('tags', () {
    test('a page for a PDF, a section otherwise, and a stable number for commentary', () {
      expect(tagSources(shown.sources).map((s) => s.tag).take(3), ['S3 p.2', 'S5 §1', cTag]);
      expect(cTag, matches(RegExp(r'^C\d{4}$')));
      // The same passage keeps its tag in another answer, wherever it falls in the prompt.
      final other = commentary.withText('x');
      final again = SourceChunk(
        title: 'Another commentary on John 3:16',
        kind: SourceKind.commentary,
        ordinal: 0,
        text: 'Another.',
        ref: commentary.ref,
      );
      expect(tagSources([again, other]).last.tag, cTag);
      final twins = tagSources([commentary, commentary.withText('y')]);
      expect(twins.first.tag, isNot(twins.last.tag));
    });

    test('a tag is never read as a verse reference', () {
      expect(RefParser.parse('[S3 p.14] [C1] (S2 §3) [S12 pp. 4-5]'), isEmpty);
    });

    test('a saved citation reads back with what opens it again', () {
      for (final s in tagSources(shown.sources)) {
        final back = ShownSource.fromJson(s.toJson())!;
        expect(back.tag, s.tag);
        expect(back.chunk.sourceId, s.chunk.sourceId);
        expect(back.chunk.page, s.chunk.page);
        expect(back.chunk.ordinal, s.chunk.ordinal);
        expect(back.chunk.ref, s.chunk.ref);
      }
      expect(ShownSource.fromJson({'tag': 3}), isNull);
      expect(ShownSource.fromJson('S3'), isNull);
    });
  });

  group('source citations', () {
    test('shown sources, pages and sections are kept; anything else is marked', () {
      final r = check(
        'Three habits [S3 p.2]. A note [S5 §1] and [S5]. Henry [$cTag]. '
        'Invented [S3 p.9], [S4], [S5 §2], [C2], [$cTag p.3], [S3 pp. 2-3].',
      );
      expect(r.sources.map((s) => s.tag), ['S3 p.2', 'S5 §1', cTag]);
      expect(r.unverifiedSources, ['S3 p.9', 'S4', 'S5 §2', 'C2', '$cTag p.3', 'S3 pp. 2-3']);
      expect(r.text, contains('Three habits [S3 p.2].'));
      expect(r.text, contains('Invented [unverified source: S3 p.9], [unverified source: S4]'));
      expect(r.inventedCount, 0);
    });

    test('several tags in one bracket are judged one by one, in any common spelling', () {
      final r = check('Both say so [S3, page 2; S8] and [s5 section 1]. Sunday (S8) is prose.');
      expect(r.sources.map((s) => s.tag), ['S3 p.2', 'S5 §1']);
      expect(r.unverifiedSources, ['S8']);
      expect(r.text, contains('[S3, page 2; unverified source: S8]'));
      expect(r.text, contains('Sunday (S8) is prose.'));
    });

    test('brackets that mean a source but are not a tag are marked whole', () {
      const loose = [
        'S99999999999',
        'S3 p.123456',
        'S3 and S9',
        'S 9',
        'Source 9',
        'S9 §2\u2013§4',
      ];
      final r = check(loose.map((t) => 'See [$t].').join(' '));
      expect(r.unverifiedSources, loose);
      for (final t in loose) {
        expect(r.text, contains('[unverified source: $t]'));
      }
      expect(check('A list [1] and [see above] stay.').text, 'A list [1] and [see above] stay.');
    });

    test('a Study answer leaves tags alone, as the site check does', () {
      final r = guard.apply('See [S9 p.4].', shown);
      expect(r.text, 'See [S9 p.4].');
      expect(r.unverifiedSources, isEmpty);
    });
  });

  group('quotes', () {
    test('a quote of a source it cites is supported', () {
      final r = check('The guide says "they examined the Scriptures every day" [S3 p.2].');
      expect(r.unverifiedQuotes, isEmpty);
    });

    test('a source misquoting Scripture cannot support a quote attributed to the verse', () {
      final r = check('John 3:16 says "whoever believes will become rich" and nothing else.');
      expect(r.unverifiedQuotes, ['whoever believes will become rich']);
      expect(r.correctedQuotes, isEmpty);
      // Reporting what the note says, with its tag, is accurate.
      expect(
        check('Your note claims "whoever believes will become rich" [S5 §1].').unverifiedQuotes,
        isEmpty,
      );
    });

    test('a source that misquotes Scripture cannot vouch for the misquote', () {
      final tagged = check('John 3:16 says "$_friendQuote" [S6 §1].');
      expect(tagged.rewordedQuotes, [_friendQuote]);
      expect(tagged.text, contains('" [differs from Scripture] [S6 §1]'));
      final bare = check('The verse says "$_friendQuote".');
      expect(bare.rewordedQuotes, [_friendQuote]);
      expect(bare.correctedQuotes, isEmpty);
    });

    test('a quote may run across two sections that follow each other in one source', () {
      final r = check('It says "ends with grace and truth for all who listen" [S7 §1].');
      expect(r.unverifiedQuotes, isEmpty);
      expect(r.rewordedQuotes, isEmpty);
    });

    test('tag groups that follow a quote cite it together', () {
      final r = check('It says "they examined the Scriptures every day" [S5 §1] [S3 p.2].');
      expect(r.unverifiedQuotes, isEmpty);
    });

    test('a quote in another script is checked like an English one', () {
      const greek = 'Ἐν ἀρχῇ ἦν ὁ λόγος, καὶ ὁ λόγος ἦν πρὸς τὸν θεόν';
      expect(guard.apply('John wrote "$greek".', shown).unverifiedQuotes, [greek]);
      const marks = '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!';
      expect(guard.apply('He shouted "$marks".', shown).unverifiedQuotes, [marks]);
      expect(CitationGuard.normalize('Ἐν ἀρχῇ, Λόγος!'), 'ἐν ἀρχῇ λόγος');
    });

    test('a quote attributed to a source is never corrected toward a verse', () {
      final r = check(
        'The guide says "For God so loved the world that He gave His only Son" [S3 p.2].',
      );
      expect(r.correctedQuotes, isEmpty);
      expect(r.unverifiedQuotes, hasLength(1));
    });

    test('a quote of one source cited to another is flagged', () {
      final r = check('The note says "they examined the Scriptures every day" [S5 §1].');
      expect(r.unverifiedQuotes, hasLength(1));
    });

    test('an unattributed quote may come from any shown source, but not across two', () {
      expect(
        check('Someone wrote "they examined the Scriptures every day" once.').unverifiedQuotes,
        isEmpty,
      );
      final across = check('"what was written. My note says John 3:16 promises" is odd.');
      expect(across.unverifiedQuotes, hasLength(1));
    });

    test('a quote of a chunk the budget cut is not supported', () {
      final cut = PromptBuilder('SYS').build(
        _ctx(db, 'John 3:16', sources: [_chunk(9, 0, List.filled(400, 'filler').join(' ')), guide]),
        const [],
        'Q',
        Tier.low,
        notebook: true,
      );
      expect(cut.shown.sources.map((c) => c.sourceId), [3]);
      final r = guard.apply(
        'It says "filler filler filler filler filler filler" [S9 §1].',
        cut.shown,
        checkSources: true,
      );
      expect(r.unverifiedSources, ['S9 §1']);
      expect(r.unverifiedQuotes, hasLength(1));
    });

    test('without source checks a source quote is held to the verses, as before', () {
      final r = guard.apply('The guide says "they examined the Scriptures every day".', shown);
      expect(r.unverifiedQuotes, hasLength(1));
    });
  });

  group('notebook retrieval', () {
    late Database raw;
    late NotebookIndex index;
    int addSource(String kind, String title, List<String> chunks, {String origin = ''}) {
      raw.execute(
        "INSERT INTO notebook_sources(notebook_id, kind, title, origin, text, created) "
        'VALUES (1, ?, ?, ?, ?, 0)',
        [kind, title, origin, chunks.join('\n\n')],
      );
      final id = raw.lastInsertRowId;
      for (var i = 0; i < chunks.length; i++) {
        raw.execute(
          'INSERT INTO notebook_chunks(source_id, ordinal, start_offset, end_offset, page, text) '
          'VALUES (?, ?, 0, 0, NULL, ?)',
          [id, i, chunks[i]],
        );
      }
      return id;
    }

    setUp(() {
      raw = sqlite3.openInMemory()..execute(notebookSchema);
      raw.execute("INSERT INTO notebooks(title, created, updated) VALUES ('N', 0, 0)");
      index = NotebookIndex(raw, 1);
    });
    tearDown(() => raw.dispose());

    test('pinned matches, pinned openings, hits, then openings, each once', () {
      final book = addSource('text', 'Book', ['Chapter one on prayer.', 'Chapter two on fasting.']);
      final pinned = addSource('note', 'Pinned', ['Abide in me.', 'Prayer without ceasing.']);
      addSource('passage', 'John 3:16 (BSB)', ['16 For God so loved'], origin: 'John 3:16|BSB');
      final got = notebookSources(
        index: index,
        question: 'What about prayer?',
        tier: Tier.mid,
        pinned: [pinned],
      );
      expect(got.map((c) => (c.sourceId, c.ordinal)).toList(), [
        (pinned, 1),
        (pinned, 0),
        (book, 0),
        (book + 2, 0),
        (book, 1),
      ]);
      expect(index.passages().single.label, 'John 3:16');
      expect(index.search('prayer', limit: 5, within: const []), isEmpty);
    });

    test('commentary on the passages in view is cut to chunk size, best match first', () {
      final dir = Directory.systemTemp.createTempSync('berea_sources');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/pack.sqlite';
      final pack = sqlite3.open(path)..execute(commentaryPackSchema);
      pack.execute("INSERT INTO meta VALUES ('format', ?)", [commentaryPackFormat]);
      pack.execute(
        "INSERT INTO modules VALUES ('MHCC', 'Concise', 'Henry', 'Public domain', 'test', 0)",
      );
      final long = List.filled(80, 'The world was lost in sin.').join(' ');
      pack.execute(
        'INSERT INTO entries(module, book, chapter, verse_start, verse_end, html_or_text) '
        "VALUES ('MHCC', 43, 3, 16, 17, ?)",
        ['$long Faith receives eternal life as a gift.'],
      );
      pack.dispose();
      final lib = CommentaryLibrary()..open('core', path);
      addTearDown(lib.closeAll);
      addSource('passage', 'John 3:16 (BSB)', ['16 For God so loved'], origin: 'John 3:16|BSB');
      final got = notebookSources(
        index: index,
        question: 'How does faith receive eternal life?',
        tier: Tier.mid,
        commentary: lib,
      );
      final c = got.where((c) => c.fromPack).single;
      expect(c.title, 'Concise on John 3:16-17');
      expect(c.text, contains('eternal life as a gift'));
      expect(c.text.length, lessThanOrEqualTo(notebookChunkChars));
      expect(c.ref!.label, 'John 3:16-17');
      expect(commentaryChunks(lib, 'faith', const [], Tier.mid.commentaryK), isEmpty);
      expect(
        notebookSources(
          index: index,
          question: 'faith',
          tier: Tier.low,
          commentary: lib,
        ).where((c) => c.fromPack),
        isEmpty,
      );
    });
  });
}
