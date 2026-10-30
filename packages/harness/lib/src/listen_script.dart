import 'dart:math';

import 'bible_db.dart';
import 'citation_guard.dart';
import 'engine.dart';
import 'prompt_builder.dart';
import 'study_packet.dart';
import 'tier.dart';
import 'truncation.dart';

/// Words a deep dive aims for: about nine minutes at the 160 words a minute the voice reads.
const listenWords = 1400;

/// Words for each beat other than the verse walk, which shares what is left.
const _beatWords = {
  Beat.opening: 220,
  Beat.hardQuestion: 200,
  Beat.witnesses: 180,
  Beat.close: 180,
};

/// A verse walk slice shorter than this says too little, so a long notebook walks fewer slices.
const listenMinWalkWords = 120;

/// The most verse walk slices one deep dive takes; a longer notebook walks its first sections.
const listenMaxWalkSlices = 5;

/// Model tokens per English word, estimated high so a beat is not cut short of its words.
const listenTokensPerWord = 1.6;

/// Outline lines named in each beat's instruction; a longer outline is cut, not the context.
const listenOutlineLines = 8;

/// Said before the script, in a voice the model never words: OpenRAIL-M Attachment A (e) asks
/// that machine-generated content says so.
const listenOpeningNotice =
    'This deep dive was written and read aloud by Berea on this device, from your notebook. '
    'The voice is machine generated.';

/// A deep dive's beats with the words each may use, and how much of the notebook they walk.
class ListenPlan {
  final StudyPacket packet;
  final List<BeatSlice> beats;
  final List<int> words;

  /// Verses of the notebook the verse walk reaches; less than [StudyPacket.verses] when the walk
  /// was capped at [listenMaxWalkSlices].
  final int walkedVerses;
  const ListenPlan(this.packet, this.beats, this.words, this.walkedVerses);

  int get totalVerses => packet.verses.length;
  bool get walksAll => walkedVerses == totalVerses;
}

/// One beat as written and checked: the text keeps its references and source tags for reading,
/// and [sources] names each source it cites.
class ScriptBeat {
  final Beat beat;
  final String text;
  final List<String> sources;
  const ScriptBeat(this.beat, this.text, this.sources);

  Map<String, Object?> toJson() => {'beat': beat.name, 'text': text, 'sources': sources};

  factory ScriptBeat.fromJson(Map<String, Object?> json) => ScriptBeat(
    Beat.values.byName(json['beat']! as String),
    json['text']! as String,
    [for (final s in json['sources']! as List) s as String],
  );
}

/// Writes a deep dive on a notebook beat by beat, each beat from its own small context, and
/// checks each against what it was shown, as a notebook answer is checked.
class ListenWriter {
  final PromptBuilder builder;
  final CitationGuard guard;
  final Tier tier;

  /// The packet is in the BSB, so the prompt and the check read the BSB whatever the reader uses.
  ListenWriter(BibleDb db, String systemPrompt, this.tier)
    : builder = PromptBuilder(systemPrompt, translation: packetTranslation),
      guard = CitationGuard(db, translation: packetTranslation);

  /// The beats of [packet], each fitting the prompt with the widest instruction any beat can get.
  ListenPlan plan(StudyPacket packet) {
    final fits = promptFits(builder, _widestInstruction(packet), tier);
    final all = packetBeats(packet, fits);
    final walk = all.where((b) => b.beat == Beat.verseWalk).toList();
    final fixed = [
      for (final b in all)
        if (b.beat != Beat.verseWalk) _beatWords[b.beat]!,
    ].fold(0, (a, b) => a + b);
    final room = max(listenWords - fixed, listenMinWalkWords);
    final count = min(walk.length, max(1, min(listenMaxWalkSlices, room ~/ listenMinWalkWords)));
    final kept = walk.take(count).toSet();
    final beats = [
      for (final b in all)
        if (b.beat != Beat.verseWalk || kept.contains(b)) b,
    ];
    final walkWords = count == 0 ? 0 : room ~/ count;
    return ListenPlan(packet, beats, [
      for (final b in beats) _beatWords[b.beat] ?? walkWords,
    ], kept.fold(0, (n, b) => n + b.context.passages.length));
  }

  /// The instruction for beat [i] of [plan].
  String instruction(ListenPlan plan, int i) {
    final b = plan.beats[i];
    final section = b.section == null ? null : plan.packet.sections[b.section!];
    return beatInstruction(
      b.beat,
      part: i + 1,
      parts: plan.beats.length,
      outline: plan.packet.outline,
      words: plan.words[i],
      walkTitle: section?.title,
      walkRange: _rangeLabel(b),
    );
  }

  /// Writes beat [i] of [plan] with [engine]. A beat cut off at its token cap loses its unfinished
  /// sentence before the check, which cannot judge half a reference.
  Future<ScriptBeat> write(
    LlmEngine engine,
    ListenPlan plan,
    int i, {
    void Function(String token)? onToken,
  }) async {
    final slice = plan.beats[i];
    final prompt = builder.build(
      slice.context,
      const [],
      instruction(plan, i),
      tier,
      notebook: true,
    );
    final maxTokens = min(tier.maxOutput, (plan.words[i] * listenTokensPerWord).ceil());
    final buf = StringBuffer();
    var pieces = 0;
    await for (final token in engine.generate(prompt.messages, maxTokens: maxTokens)) {
      pieces++;
      buf.write(token);
      onToken?.call(token);
    }
    final raw = pieces >= maxTokens ? withoutUnfinishedSentence(buf.toString()) : buf.toString();
    final checked = guard.apply(raw, prompt.shown, checkSources: true);
    return ScriptBeat(slice.beat, checked.text.trim(), [
      for (final s in checked.sources) '${s.tag}: ${s.chunk.title}',
    ]);
  }

  /// The longest instruction any beat of [packet] could get, so a context that fits it fits all.
  String _widestInstruction(StudyPacket packet) {
    final titles = [for (final s in packet.sections) s.title];
    final longestTitle = titles.fold('', (a, b) => b.length > a.length ? b : a);
    const wideRange = 'Song of Solomon 150:150-150';
    const manyParts = 99;
    const manyWords = 9999;
    return [
      for (final beat in Beat.values)
        beatInstruction(
          beat,
          part: manyParts,
          parts: manyParts,
          outline: packet.outline,
          words: manyWords,
          walkTitle: longestTitle,
          walkRange: wideRange,
        ),
    ].reduce((a, b) => estimateTokens(b) > estimateTokens(a) ? b : a);
  }
}

String? _rangeLabel(BeatSlice b) {
  final ps = b.context.passages;
  if (b.beat != Beat.verseWalk || ps.isEmpty) return null;
  final first = ps.first, last = ps.last;
  if (first.label == last.label) return first.label;
  return first.chapter == last.chapter
      ? '${first.label}-${last.verse}'
      : '${first.label}-${last.chapter}:${last.verse}';
}

/// What the narrator is asked to write in one beat. The opening and close carry two of the style
/// note's beats each: the cold open with the setting, and the recap with the question to take away.
String beatInstruction(
  Beat beat, {
  required int part,
  required int parts,
  required List<String> outline,
  required int words,
  String? walkTitle,
  String? walkRange,
}) {
  final named = outline.take(listenOutlineLines).join('; ');
  final more = outline.length > listenOutlineLines ? '; and more' : '';
  final task = switch (beat) {
    Beat.opening =>
      'This is the opening. Begin with a short everyday scene that leads into the passage, as an '
          'illustration only. Then name the passage, say who first heard it and in what setting as '
          'far as the CONTEXT tells, and say what this deep dive will walk through.',
    Beat.verseWalk =>
      'Walk through ${walkTitle ?? 'the passage'} (${walkRange ?? 'the PASSAGES'}) verse by verse, '
          'in order. Quote each verse word for word from PASSAGES. Where the LEXICON gives a word '
          'of the verse, say "the Greek word here is" or "the Hebrew word here is", then the word '
          'and its meaning. Where SOURCES hold a commentator on the verse, name the commentator '
          'and quote them. Ask the listener one question aloud and answer it from the text. Give '
          'one everyday comparison. End with one short line the listener can sit with.',
    Beat.hardQuestion =>
      'Raise the hardest question this passage leaves a careful reader with, and answer it from '
          'PASSAGES and SOURCES. Say plainly what the text does not settle.',
    Beat.witnesses =>
      'Show how the other testament bears witness to this passage. For each verse in CROSS '
          'REFERENCES, say which verse in PASSAGES points to it and what it adds, quoting both word '
          'for word.',
    Beat.close =>
      'This is the close. Recap the deep dive as a short chain: "We started with ..., we looked '
          'at ..., we saw ...". Then ask the listener one question to reflect on, and stop.',
  };
  return 'You are writing part $part of $parts of a spoken deep dive on a Bible notebook, read '
      'aloud by one narrator. The notebook covers: $named$more.\n\n$task\n\nWrite about $words '
      'words of spoken prose: no headings, lists, bullet points or markdown, and no greeting '
      'unless this is the opening. Cite each verse you use as Book chapter:verse, and put the '
      'source tag right after anything taken from SOURCES. Do not repeat what other parts cover.';
}
