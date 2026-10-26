import 'dart:math';

import 'bible_db.dart';
import 'engine.dart';
import 'retriever.dart';
import 'sources.dart';
import 'tier.dart';

const maxHistoryMessages = 4;

/// Rules added to the system prompt for a notebook answer only, so the Study prompt is unchanged.
/// No example tag: small models copy examples, and a copied tag would cite a source not shown.
const notebookRules = '''## Notebook sources

9. The SOURCES block holds passages from the user's notebook: their notes, pasted text, PDFs,
   books and commentary. Each passage starts with its tag in square brackets.
10. When you use a source, write its tag in square brackets right after the words that use it,
    copied exactly as it appears at the start of that passage. Quote a source only word for word
    from SOURCES.
11. Never cite a source, page or section that is not in SOURCES. If the sources do not cover the
    question, say "The notebook's sources do not cover this." and answer from Scripture alone.
12. Sources are not Scripture. Quote the Bible only from PASSAGES, CROSS REFERENCES and RELATED
    VERSES. If a source quotes or describes a verse differently, say so and give the verse as
    those blocks have it.''';

/// How much the model is asked to write. A phone that decodes a few tokens a second shows the
/// brief answer first and writes the full one only when the reader asks for it.
enum AnswerStyle { full, brief }

/// Added to the system prompt for a brief answer. Measured on a Galaxy A32: this took a Study
/// answer from 538 to 94 tokens and the wait from 161 to 66 seconds, still citing both verses.
const briefRule = '''## Answer length

Answer in at most four short sentences, then stop. Cite the verse or verses you rely on. No
headings, no application section and no reflection questions.''';

const noSourcesShown = "None of the notebook's sources matched this question.";

/// Said when sources matched but none fit, so the model does not claim the notebook is silent.
const sourcesTooLong = 'Sources matched this question but were too long to include here.';

/// Said when no verse fit, so the model does not quote Scripture from memory.
const noPassagesLoaded =
    'No passages were loaded for this question. Answer in principle and name the passages '
    'the user should open, without quoting them.';

/// A question may take at most this share of the prompt budget; the rest is cut from the prompt.
const maxQuestionShare = 4;

/// Below this many tokens of room a cut source would say too little to be worth showing.
const minCutSourceTokens = 60;

const _cutMark = ' ...';
const _questionCut = ' [question shortened]';

/// The messages for the engine, and the context the model was actually shown.
class BuiltPrompt {
  final List<ChatMessage> messages;

  /// Only what fit the budget, in the words it was shown. The citation guard checks against this,
  /// so a verse or source the budget cut never counts as shown.
  final StudyContext shown;
  const BuiltPrompt(this.messages, this.shown);
}

/// The longest prefix of [words] whose text, put into [line], fits [room]; null when none does.
String? _fitWords(List<String> words, String Function(String text) line, int room) {
  var lo = 0, hi = words.length;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (estimateTokens(line(words.take(mid).join(' '))) <= room) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo == 0 ? null : words.take(lo).join(' ');
}

class PromptBuilder {
  final String systemPrompt;
  final String translation;
  PromptBuilder(this.systemPrompt, {this.translation = defaultTranslation});

  /// With [notebook], the notebook rules join the system prompt and a SOURCES block follows
  /// PASSAGES, holding a share of the budget that PASSAGES cannot take. Every line, header and
  /// note counts against the budget, so the prompt never outgrows [Tier.promptTokens].
  BuiltPrompt build(
    StudyContext ctx,
    List<ChatMessage> history,
    String userText,
    Tier tier, {
    bool notebook = false,
    AnswerStyle style = AnswerStyle.full,
  }) {
    final system = [
      systemPrompt,
      if (notebook) notebookRules,
      if (style == AnswerStyle.brief) briefRule,
    ].join('\n\n');
    final question = _capQuestion(userText, tier);
    final frame = 'CONTEXT (translation: $translation)\n\n\nQUESTION\n';
    var budget =
        tier.promptTokens -
        estimateTokens(system) -
        estimateTokens(question) -
        estimateTokens(frame) -
        estimateTokens(noPassagesLoaded);
    final blocks = <String>[];
    var bibleBlocks = 0;

    List<T> add<T>(String title, Iterable<T> items, String Function(T) line) {
      final kept = <T>[];
      final lines = <String>[];
      var header = estimateTokens('$title\n\n\n');
      for (final item in items) {
        final l = line(item);
        final cost = estimateTokens(l) + header;
        if (cost > budget) break;
        budget -= cost;
        header = 0;
        kept.add(item);
        lines.add(l);
      }
      if (lines.isNotEmpty) {
        blocks.add('$title\n${lines.join('\n')}');
        bibleBlocks++;
      }
      return kept;
    }

    // SOURCES keeps a share PASSAGES cannot take, and always room for its header and note.
    final floor = notebook ? estimateTokens('SOURCES\n$sourcesTooLong') : 0;
    final reserve = notebook ? max(floor, min(tier.sourceTokens, max(0, budget) ~/ 2)) : 0;
    budget -= reserve;
    final passages = add('PASSAGES', ctx.passages, _verseLine);
    budget += reserve;
    final sources = notebook
        ? _addSources(ctx.sources, max(floor, min(tier.sourceTokens, budget)))
        : null;
    if (sources != null) {
      budget -= sources.cost;
      blocks.add(sources.block);
    }
    final lexicon = add('LEXICON', ctx.lexicon.entries, (e) => _lexLine(e.value));
    final wordLine = add('WORDS', _wordLines(ctx), (l) => l);
    final xrefs = add('CROSS REFERENCES', ctx.xrefVerses, _verseLine);
    final hits = add('RELATED VERSES', ctx.searchHits, _verseLine);

    final recent = history.length > maxHistoryMessages
        ? history.sublist(history.length - maxHistoryMessages)
        : history;
    final kept = <ChatMessage>[];
    for (final m in recent.reversed) {
      final cost = estimateTokens(m.content);
      if (cost > budget) break;
      budget -= cost;
      kept.insert(0, m);
    }

    // The note is decided on the Bible blocks alone: SOURCES never licenses quoting Scripture.
    final context = [if (bibleBlocks == 0) noPassagesLoaded, ...blocks].join('\n\n');
    final shown = StudyContext(
      refs: ctx.refs,
      passages: passages,
      words: wordLine.isEmpty ? const [] : ctx.words,
      lexicon: Map.fromEntries(lexicon),
      xrefVerses: xrefs,
      searchHits: hits,
      sources: sources?.shown ?? const [],
    );
    return BuiltPrompt([
      ChatMessage.system(system),
      ...kept,
      ChatMessage.user('CONTEXT (translation: $translation)\n$context\n\nQUESTION\n$question'),
    ], shown);
  }

  /// [userText] cut to a share of the budget, so a pasted page cannot crowd out every passage or
  /// push the prompt past the model's context.
  static String _capQuestion(String userText, Tier tier) {
    final cap = tier.promptTokens ~/ maxQuestionShare;
    if (estimateTokens(userText) <= cap) return userText;
    final words = userText.split(_whitespace);
    return '${_fitWords(words, (t) => '$t$_questionCut', cap) ?? ''}$_questionCut';
  }

  /// Sources in order within [room] tokens, the header and any note included. A chunk that does
  /// not fit is skipped, since a later one may be shorter. When none fits at all (Greek or Hebrew
  /// on a small tier), the first is cut to the room, so the model is not told the notebook is
  /// silent. What is shown is exactly the text in the prompt.
  ({String block, List<SourceChunk> shown, int cost}) _addSources(
    List<SourceChunk> chunks,
    int room,
  ) {
    const header = 'SOURCES\n';
    final shown = <SourceChunk>[];
    final lines = <String>[];
    final used = <String>{};
    var cost = estimateTokens(header);
    String lineFor(SourceChunk c, String tag, String text) =>
        '[$tag] (${c.title}, ${c.kind.label}) $text';
    final flat = [for (final c in chunks) c.withText(c.text.replaceAll(_whitespace, ' ').trim())];
    for (final c in flat) {
      final tag = c.fromPack ? packTag(c, used) : notebookTag(c);
      final l = lineFor(c, tag, c.text);
      if (cost + estimateTokens(l) > room) continue;
      cost += estimateTokens(l);
      if (c.fromPack) used.add(tag);
      shown.add(c);
      lines.add(l);
    }
    final left = room - cost;
    if (lines.isEmpty && flat.isNotEmpty && left >= minCutSourceTokens) {
      final c = flat.first;
      final tag = c.fromPack ? packTag(c, used) : notebookTag(c);
      final cut = _fitWords(c.text.split(' '), (t) => lineFor(c, tag, '$t$_cutMark'), left);
      if (cut != null) {
        final l = lineFor(c, tag, '$cut$_cutMark');
        cost += estimateTokens(l);
        shown.add(c.withText(cut));
        lines.add(l);
      }
    }
    if (lines.isNotEmpty) return (block: '$header${lines.join('\n')}', shown: shown, cost: cost);
    final note = chunks.isEmpty ? noSourcesShown : sourcesTooLong;
    return (block: '$header$note', shown: shown, cost: cost + estimateTokens(note));
  }

  static final _whitespace = RegExp(r'\s+');

  String _verseLine(Verse v) => '(${v.label}, $translation) ${v.text}';

  String _lexLine(LexEntry e) {
    final def = e.definition.length > 300 ? '${e.definition.substring(0, 300)}...' : e.definition;
    return '${e.key} ${e.lemma} (${e.translit}) ${e.pos}: ${e.gloss}. $def';
  }

  Iterable<String> _wordLines(StudyContext ctx) {
    if (ctx.words.isEmpty) return const [];
    final line = ctx.words
        .map((w) => '${w.original} [${w.translit}, ${w.gloss}, ${w.strongs}, ${w.morph}]')
        .join('; ');
    return ['${ctx.refs.first.label}: $line'];
  }
}
