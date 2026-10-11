import 'bible_db.dart';
import 'engine.dart';
import 'retriever.dart';
import 'tier.dart';

const maxHistoryMessages = 4;

class PromptBuilder {
  final String systemPrompt;
  final String translation;
  PromptBuilder(this.systemPrompt, {this.translation = defaultTranslation});

  List<ChatMessage> build(StudyContext ctx, List<ChatMessage> history, String userText, Tier tier) {
    var budget = tier.promptTokens - estimateTokens(systemPrompt) - estimateTokens(userText);
    final blocks = <String>[];

    void add(String title, Iterable<String> lines) {
      final kept = <String>[];
      for (final line in lines) {
        final cost = estimateTokens(line);
        if (cost > budget) break;
        budget -= cost;
        kept.add(line);
      }
      if (kept.isNotEmpty) blocks.add('$title\n${kept.join('\n')}');
    }

    add('PASSAGES', ctx.passages.map(_verseLine));
    add('LEXICON', ctx.lexicon.values.map(_lexLine));
    add('WORDS', _wordLines(ctx));
    add('CROSS REFERENCES', ctx.xrefVerses.map(_verseLine));
    add('RELATED VERSES', ctx.searchHits.map(_verseLine));

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
    return [
      ChatMessage.system(systemPrompt),
      ...kept,
      ChatMessage.user('CONTEXT (translation: $translation)\n$context\n\nQUESTION\n$userText'),
    ];
  }

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
