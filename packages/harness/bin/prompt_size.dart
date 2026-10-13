// Builds real prompts for each tier, Study and notebook, and asks Ollama how many tokens they
// are, so the estimate the budgets use is checked against the model's own tokenizer. Usage:
// dart run bin/prompt_size.dart [--model gemma4:e2b]
import 'dart:convert';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:http/http.dart' as http;

import 'berea.dart';
import 'notebook_fixture.dart';

/// Large enough that Ollama never trims a prompt it is measuring.
const _measureCtx = 32768;

/// Word studies and long passages fill the budget with Hebrew, Greek and digits, the text the
/// estimate is most likely to get wrong.
const _questions = [
  'Do a word study on "created" in Genesis 1:1.',
  'What is the Hebrew word for wisdom in Proverbs 1:7?',
  'What Greek word is used for love in 1 Corinthians 13:4?',
  'Explain Psalm 119:1-40.',
  'What does the Bible say about caring for widows?',
];

const _notebookQuestions = [
  'Do a word study on "created" in Genesis 1:1 using my notes.',
  'What three habits does my small group guide list?',
];

Future<int> _tokens(String model, List<ChatMessage> messages) async {
  final res = await http.post(
    Uri.parse('http://localhost:11434/api/chat'),
    body: jsonEncode({
      'model': model,
      'messages': [for (final m in messages) m.toJson()],
      'stream': false,
      'options': {'num_predict': 1, 'num_ctx': _measureCtx},
    }),
  );
  return (jsonDecode(res.body) as Map<String, dynamic>)['prompt_eval_count'] as int;
}

/// Notebook chunks of original-language text, as a pasted interlinear or a Greek PDF would be.
List<SourceChunk> _scriptChunks(BibleDb db) {
  String words(String ref) => db.words(RefParser.parse(ref).first).map((w) => w.original).join(' ');
  return [
    for (final (i, ref) in ['Genesis 1', 'John 1', 'Genesis 2', 'John 3'].indexed)
      SourceChunk(
        sourceId: 100 + i,
        title: 'Original text of $ref',
        kind: SourceKind.text,
        ordinal: 0,
        text: words(ref).padRight(notebookChunkChars).substring(0, notebookChunkChars).trim(),
      ),
  ];
}

Future<void> main(List<String> args) async {
  final i = args.indexOf('--model');
  final model = i >= 0 && i + 1 < args.length ? args[i + 1] : 'gemma4:e2b';
  final db = BibleDb.open(defaultDb);
  final system = systemPromptFrom(defaultPrompt);
  final retriever = Retriever(db);
  final builder = PromptBuilder(system);
  final notebook = fixtureNotebook(db);
  // A long earlier answer, so history competes for the budget as it does in a real chat.
  final longAnswer = List.filled(60, 'Grace (Ephesians 2:8, BSB) is the gift of God. ').join();
  final history = [
    for (var k = 0; k < maxHistoryMessages ~/ 2; k++) ...[
      const ChatMessage.user('Tell me more about grace.'),
      ChatMessage.assistant(longAnswer),
    ],
  ];
  for (final tier in Tier.values) {
    var worst = 0;
    Future<void> measure(String label, BuiltPrompt prompt) async {
      final estimate = prompt.messages.fold(0, (sum, m) => sum + estimateTokens(m.content));
      final actual = await _tokens(model, prompt.messages);
      if (actual > worst) worst = actual;
      stdout.writeln('${tier.name.padRight(4)} est $estimate actual $actual  $label');
    }

    for (final q in _questions) {
      await measure(q, builder.build(retriever.retrieve(q, tier), history, q, tier));
    }
    for (final q in _notebookQuestions) {
      final sources = [
        ..._scriptChunks(db),
        ...notebookSources(index: notebook, question: q, tier: tier),
      ];
      final ctx = retriever.retrieve(q, tier, sources: sources);
      await measure('notebook: $q', builder.build(ctx, history, q, tier, notebook: true));
    }
    stdout.writeln(
      '${tier.name}: budget ${tier.promptTokens}, worst prompt $worst, plus output '
      '${tier.maxOutput} = ${worst + tier.maxOutput} of a ${tier.contextWindow} window\n',
    );
  }
  notebook.db.dispose();
  db.close();
}
