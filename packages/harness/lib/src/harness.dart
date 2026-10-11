import 'bible_db.dart';
import 'ref_parser.dart';
import 'citation_guard.dart';
import 'engine.dart';
import 'prompt_builder.dart';
import 'retriever.dart';
import 'tier.dart';

class TurnResult {
  final String raw;
  final GuardResult guard;
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

  Harness({
    required this.db,
    required this.engine,
    required String systemPrompt,
    this.tier = Tier.mid,
    String translation = defaultTranslation,
  }) : retriever = Retriever(db, translation: translation),
       builder = PromptBuilder(systemPrompt, translation: translation),
       guard = CitationGuard(db, translation: translation);

  Future<TurnResult> ask(String userText, {void Function(String token)? onToken}) async {
    final ctx = retriever.retrieve(userText, tier);
    final messages = builder.build(ctx, history, userText, tier);
    final buf = StringBuffer();
    await for (final token in engine.generate(messages, maxTokens: tier.maxOutput)) {
      buf.write(token);
      onToken?.call(token);
    }
    final raw = buf.toString();
    final result = guard.apply(raw, ctx);
    history
      ..add(ChatMessage.user(userText))
      ..add(ChatMessage.assistant(result.text));
    return TurnResult(raw, result, ctx);
  }

  /// A one-off study page for [ref]. It does not touch the chat history.
  Future<StudyPage> studyPage(Ref ref, {void Function(String token)? onToken}) async {
    final ctx = retriever.retrieve(ref.label, tier);
    final messages = builder.build(ctx, const [], studyPageInstruction(ref), tier);
    final buf = StringBuffer();
    await for (final token in engine.generate(messages, maxTokens: tier.maxOutput)) {
      buf.write(token);
      onToken?.call(token);
    }
    final guarded = guard.apply(buf.toString(), ctx);
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
