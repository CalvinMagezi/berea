import 'bible_db.dart';
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
}
