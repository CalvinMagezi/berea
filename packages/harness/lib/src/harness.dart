import 'dart:math';

import 'bible_db.dart';
import 'ref_parser.dart';
import 'citation_guard.dart';
import 'engine.dart';
import 'prompt_builder.dart';
import 'retriever.dart';
import 'sources.dart';
import 'tier.dart';
import 'truncation.dart';

class TurnResult {
  final String raw;
  final GuardResult guard;

  /// What the model was shown, after the budget.
  final StudyContext context;
  const TurnResult(this.raw, this.guard, this.context);
  String get text => guard.text;
}

/// A passage worked through in three parts. Missing parts are empty.
class StudyPage {
  final String observation;
  final String interpretation;
  final String application;
  final GuardResult guard;
  const StudyPage(this.observation, this.interpretation, this.application, this.guard);

  static final _heading = RegExp(
    r'^#{1,3}\s*(observation|interpretation|application)\b.*$',
    caseSensitive: false,
    multiLine: true,
  );

  static Map<String, String> sections(String text) {
    final out = <String, String>{};
    final ms = _heading.allMatches(text).toList();
    for (var i = 0; i < ms.length; i++) {
      final end = i + 1 < ms.length ? ms[i + 1].start : text.length;
      out[ms[i][1]!.toLowerCase()] = text.substring(ms[i].end, end).trim();
    }
    return out;
  }
}

String studyPageInstruction(Ref ref) =>
    'Write a study page for ${ref.label} using only the CONTEXT. Use exactly three sections with '
    'these headings: "## Observation" (what the text says: who, what, where, and key words from '
    'the LEXICON), "## Interpretation" (what it means in its context and across Scripture, using '
    'the CROSS REFERENCES), "## Application" (how to live it, ending with two questions). Keep '
    'each section under 150 words.';

class Harness {
  final BibleDb db;
  final LlmEngine engine;
  final Tier tier;
  final Retriever retriever;
  final PromptBuilder builder;
  final CitationGuard guard;
  final history = <ChatMessage>[];

  /// Answers inside a notebook: the prompt carries SOURCES and the guard checks source tags.
  final bool notebook;

  Harness({
    required this.db,
    required this.engine,
    required String systemPrompt,
    this.tier = Tier.mid,
    String translation = defaultTranslation,
    this.notebook = false,
  }) : retriever = Retriever(db, translation: translation),
       builder = PromptBuilder(systemPrompt, translation: translation),
       guard = CitationGuard(db, translation: translation);

  /// [sources] are the notebook chunks to draw on, best first (see [notebookSources]); only a
  /// notebook harness shows them.
  Future<TurnResult> ask(
    String userText, {
    List<SourceChunk> sources = const [],
    void Function(String token)? onToken,
    void Function(StudyContext shown)? onContext,
    AnswerStyle style = AnswerStyle.full,

    /// Drops the last question and answer from the history first, for an answer that takes the
    /// place of the one before it, such as the full study after a brief one.
    bool replacePrevious = false,
  }) async {
    _stopRequested = false;
    final replaced = replacePrevious && history.length >= 2
        ? history.sublist(history.length - 2)
        : null;
    if (replaced != null) history.removeRange(history.length - 2, history.length);
    try {
      final ctx = retriever.retrieve(userText, tier, sources: sources);
      final prompt = builder.build(ctx, history, userText, tier, notebook: notebook, style: style);
      onContext?.call(prompt.shown);
      final maxTokens = style == AnswerStyle.brief
          ? min(tier.maxOutput, briefMaxOutput)
          : tier.maxOutput;
      final buf = StringBuffer();
      var pieces = 0;
      // A stop that came before the model was asked skips asking it.
      if (!_stopRequested) {
        await for (final token in engine.generate(prompt.messages, maxTokens: maxTokens)) {
          pieces++;
          buf.write(token);
          onToken?.call(token);
        }
      }
      var raw = buf.toString();
      // A pieces count at the cap means the model was cut off, not that it finished.
      if (_stopRequested || pieces >= maxTokens) raw = withoutUnfinishedSentence(raw);
      final result = guard.apply(raw, prompt.shown, checkSources: notebook);
      if (result.text.trim().isEmpty) {
        // Nothing was written, as when it was stopped at once: nothing to remember.
        if (replaced != null) history.addAll(replaced);
      } else {
        history
          ..add(ChatMessage.user(userText))
          ..add(ChatMessage.assistant(result.text));
      }
      return TurnResult(raw, result, prompt.shown);
    } catch (_) {
      if (replaced != null) history.addAll(replaced);
      rethrow;
    }
  }

  bool _stopRequested = false;

  /// Ends the answer being written, when the engine can. What was written is kept up to its last
  /// finished sentence.
  Future<void> stop() async {
    _stopRequested = true;
    final Object e = engine;
    if (e is StoppableEngine) await e.stop();
  }

  /// A one-off study page for [ref]. It does not touch the chat history.
  Future<StudyPage> studyPage(Ref ref, {void Function(String token)? onToken}) async {
    final ctx = retriever.retrieve(ref.label, tier);
    final prompt = builder.build(ctx, const [], studyPageInstruction(ref), tier);
    final buf = StringBuffer();
    var pieces = 0;
    await for (final token in engine.generate(prompt.messages, maxTokens: tier.maxOutput)) {
      pieces++;
      buf.write(token);
      onToken?.call(token);
    }
    // A draft that hit its length cap ends mid-sentence, which the citation check cannot judge.
    final raw = pieces >= tier.maxOutput ? withoutUnfinishedSentence(buf.toString()) : buf.toString();
    final guarded = guard.apply(raw, prompt.shown);
    final parts = StudyPage.sections(guarded.text);
    return StudyPage(
      parts['observation'] ?? guarded.text,
      parts['interpretation'] ?? '',
      parts['application'] ?? '',
      guarded,
    );
  }

  /// Starts a fresh conversation.
  void resetConversation() => history.clear();
}
