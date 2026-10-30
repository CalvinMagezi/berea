import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// About the size of the real system prompt, in characters.
const _systemChars = 3000;

/// Six to ten minutes at the 160 words a minute Supertonic 3 read Hebrews 11 on the A32.
const _fewestWords = 960;
const _mostWords = 1600;

/// Replies with [reply] in [pieces] tokens, and keeps what it was asked.
class _Echo implements LlmEngine {
  final String reply;
  final int? pieces;
  _Echo(this.reply, {this.pieces});
  final asked = <List<ChatMessage>>[];
  final caps = <int>[];

  @override
  String get name => 'echo';

  @override
  Stream<String> generate(List<ChatMessage> messages, {required int maxTokens}) async* {
    asked.add(messages);
    caps.add(maxTokens);
    final words = reply.split(' ');
    final n = pieces ?? words.length;
    for (var i = 0; i < n && i < words.length; i++) {
      yield '${i == 0 ? '' : ' '}${words[i]}';
    }
    for (var i = words.length; i < n; i++) {
      yield '';
    }
  }
}

void main() {
  final bible = File('../../assets/berea.sqlite');
  if (!bible.existsSync() || bible.lengthSync() == 0) {
    test('these tests open the built Bible', () {}, skip: 'needs assets/berea.sqlite');
    return;
  }
  late BibleDb db;
  setUpAll(() => db = BibleDb(sqlite3.open(bible.path, mode: OpenMode.readOnly)));
  final system = 'S' * _systemChars;

  StudyPacket packet(String refs) => buildStudyPacket(db, RefParser.parse(refs));
  int total(ListenPlan p) => p.words.fold(0, (a, b) => a + b);

  test('a one-section notebook is planned as a six to ten minute deep dive, walked whole', () {
    final plan = ListenWriter(db, system, Tier.mid).plan(packet('John 3:1-21'));
    final beats = plan.beats.map((b) => b.beat).toList();
    expect(beats.first, Beat.opening);
    expect(beats.last, Beat.close);
    expect(beats, contains(Beat.verseWalk));
    expect(beats, contains(Beat.hardQuestion));
    expect(plan.walksAll, isTrue);
    expect(plan.walkedVerses, 21);
    expect(total(plan), inInclusiveRange(_fewestWords, _mostWords));
  });

  test('Psalm 119 walks only its first sections and says how much', () {
    final plan = ListenWriter(db, system, Tier.mid).plan(packet('Psalm 119'));
    final walk = plan.beats.where((b) => b.beat == Beat.verseWalk).toList();
    expect(walk.length, lessThanOrEqualTo(listenMaxWalkSlices));
    expect(plan.walksAll, isFalse);
    expect(plan.totalVerses, 176);
    expect(plan.walkedVerses, lessThan(176));
    expect(walk.first.context.passages.first.label, 'Psalms 119:1');
    expect(total(plan), inInclusiveRange(_fewestWords, _mostWords));
  });

  test('every beat shows the model its whole slice with its own instruction, on every tier', () {
    for (final tier in Tier.values) {
      final w = ListenWriter(db, system, tier);
      for (final refs in ['John 3:1-21', 'Genesis 22', 'Psalm 119']) {
        final plan = w.plan(packet(refs));
        for (var i = 0; i < plan.beats.length; i++) {
          final ctx = plan.beats[i].context;
          final shown = w.builder
              .build(ctx, const [], w.instruction(plan, i), tier, notebook: true)
              .shown;
          final where = '$refs beat $i on $tier';
          expect(shown.passages.length, ctx.passages.length, reason: where);
          expect(shown.xrefVerses.length, ctx.xrefVerses.length, reason: where);
          expect(shown.lexicon.length, ctx.lexicon.length, reason: where);
          expect(shown.sources.length, ctx.sources.length, reason: where);
        }
      }
    }
  });

  test('a walk instruction names its section and verses; a long outline is cut', () {
    final w = ListenWriter(db, system, Tier.mid);
    final john = w.plan(packet('John 3:1-21'));
    final walk = john.beats.indexWhere((b) => b.beat == Beat.verseWalk);
    final text = w.instruction(john, walk);
    expect(text, contains('Jesus and Nicodemus'));
    expect(text, contains('(John 3:1-'));
    expect(text, contains('part ${walk + 1} of ${john.beats.length}'));
    expect(text, contains('about ${john.words[walk]} words'));
    final psalm = w.plan(packet('Psalm 119'));
    expect(w.instruction(psalm, 0), contains('; and more.'));
  });

  test('a beat is checked against the BSB it was shown, whatever the reader uses', () async {
    final w = ListenWriter(db, system, Tier.mid);
    final plan = w.plan(packet('John 3:1-21'));
    final verse = plan.beats.first.context.passages.first;
    final engine = _Echo('Nicodemus came by night (${verse.label}). See also Hezekiah 4:1.');
    final beat = await w.write(engine, plan, 0);
    expect(beat.beat, Beat.opening);
    expect(beat.text, contains(verse.label));
    expect(beat.text, contains('[unverified'));
    final prompt = engine.asked.single.last.content;
    expect(prompt, contains('CONTEXT (translation: BSB)'));
    expect(prompt, contains('(${verse.label}, BSB) ${verse.text}'));
    expect(engine.caps.single, (plan.words[0] * listenTokensPerWord).ceil());
  });

  test('a beat that hits its token cap loses its unfinished sentence', () async {
    final w = ListenWriter(db, system, Tier.low);
    final plan = w.plan(packet('John 3:1-21'));
    final cap = Tier.low.maxOutput;
    final engine = _Echo('He came by night. And then he', pieces: cap);
    final beat = await w.write(engine, plan, 0);
    expect(engine.caps.single, lessThanOrEqualTo(cap));
    expect(beat.text, 'He came by night.');
  });

  test('a sentence said twice in a row is said once', () {
    expect(
      withoutRepeats('Is it a feeling? Is it a feeling? It is a posture.\nIs it a feeling?'),
      'Is it a feeling? It is a posture.\nIs it a feeling?',
    );
    expect(withoutRepeats('Rejoice! Rejoice in the Lord.'), 'Rejoice! Rejoice in the Lord.');
  });

  test('a written beat survives saving', () {
    const beat = ScriptBeat(Beat.witnesses, 'Text [C1234].', ['C1234: Concise']);
    final back = ScriptBeat.fromJson(beat.toJson());
    expect((back.beat, back.text), (beat.beat, beat.text));
    expect(back.sources, beat.sources);
  });

  test('an empty packet plans nothing', () {
    final plan = ListenWriter(db, system, Tier.mid).plan(buildStudyPacket(db, const []));
    expect(plan.beats, isEmpty);
    expect(plan.walksAll, isTrue);
  });
}
