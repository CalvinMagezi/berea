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

const noSourcesShown = "None of the notebook's sources matched this question.";

/// The messages for the engine, and the context the model was actually shown.
class BuiltPrompt {
  final List<ChatMessage> messages;

  /// Only what fit the budget, in the words it was shown. The citation guard checks against this,
  /// so a verse or source the budget cut never counts as shown.
  final StudyContext shown;
  const BuiltPrompt(this.messages, this.shown);
}

class PromptBuilder {
  final String systemPrompt;
  final String translation;
  PromptBuilder(this.systemPrompt, {this.translation = defaultTranslation});

  /// With [notebook], the notebook rules join the system prompt and a SOURCES block follows
  /// PASSAGES, holding a share of the budget that PASSAGES cannot take.
  BuiltPrompt build(
    StudyContext ctx,
    List<ChatMessage> history,
    String userText,
    Tier tier, {
    bool notebook = false,
  }) {
    final system = notebook ? '$systemPrompt\n\n$notebookRules' : systemPrompt;
    var budget = tier.promptTokens - estimateTokens(system) - estimateTokens(userText);
    final blocks = <String>[];

    List<T> add<T>(String title, Iterable<T> items, String Function(T) line) {
      final kept = <T>[];
      final lines = <String>[];
      for (final item in items) {
        final l = line(item);
        final cost = estimateTokens(l);
        if (cost > budget) break;
        budget -= cost;
        kept.add(item);
        lines.add(l);
      }
      if (lines.isNotEmpty) blocks.add('$title\n${lines.join('\n')}');
      return kept;
    }

    final reserve = notebook ? min(tier.sourceTokens, max(0, budget) ~/ 2) : 0;
    budget -= reserve;
    final passages = add('PASSAGES', ctx.passages, _verseLine);
    budget += reserve;
    final sources = notebook ? _addSources(ctx.sources, min(tier.sourceTokens, budget)) : null;
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

    final context = blocks.isEmpty
        ? 'No passages were loaded for this question. Answer in principle and name the passages '
              'the user should open, without quoting them.'
        : blocks.join('\n\n');
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
      ChatMessage.user('CONTEXT (translation: $translation)\n$context\n\nQUESTION\n$userText'),
    ], shown);
  }

  /// Sources in order within [room] tokens. A chunk that does not fit is skipped rather than
  /// ending the block, since a later one may be shorter (Greek or Hebrew text costs more).
  ({String block, List<SourceChunk> shown, int cost}) _addSources(
    List<SourceChunk> chunks,
    int room,
  ) {
    final shown = <SourceChunk>[];
    final lines = <String>[];
    var cost = 0;
    var commentary = 0;
    for (final c in chunks) {
      final flat = c.withText(c.text.replaceAll(_whitespace, ' ').trim());
      final tag = flat.fromPack ? 'C${commentary + 1}' : notebookTag(flat);
      final line = '[$tag] (${flat.title}, ${flat.kind.label}) ${flat.text}';
      final lineCost = estimateTokens(line);
      if (cost + lineCost > room) continue;
      cost += lineCost;
      if (flat.fromPack) commentary++;
      shown.add(flat);
      lines.add(line);
    }
    if (lines.isEmpty) {
      return (
        block: 'SOURCES\n$noSourcesShown',
        shown: shown,
        cost: estimateTokens(noSourcesShown),
      );
    }
    return (block: 'SOURCES\n${lines.join('\n')}', shown: shown, cost: cost);
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
