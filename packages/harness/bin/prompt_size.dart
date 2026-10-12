// Builds real prompts for each tier and asks Ollama how many tokens they are, so the estimate
// the budgets use can be checked against the model's own tokenizer. Usage:
// dart run bin/prompt_size.dart [--model gemma4:e2b]
import 'dart:convert';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:http/http.dart' as http;

import 'berea.dart';

/// Large enough that Ollama never trims a prompt it is measuring.
const _measureCtx = 32768;

const _questions = [
  'Do a word study on "created" in Genesis 1:1.',
  'What is the Hebrew word for wisdom in Proverbs 1:7?',
  'What Greek word is used for love in 1 Corinthians 13:4?',
  'Explain Psalm 119:1-40.',
  'What does the Bible say about caring for widows?',
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

Future<void> main(List<String> args) async {
  final i = args.indexOf('--model');
  final model = i >= 0 && i + 1 < args.length ? args[i + 1] : 'gemma4:e2b';
  final db = BibleDb.open(defaultDb);
  final system = systemPromptFrom(defaultPrompt);
  final retriever = Retriever(db);
  final builder = PromptBuilder(system);
  // A long earlier answer, so history competes for the budget as it does in a real chat.
  final longAnswer = List.filled(60, 'Grace (Ephesians 2:8, BSB) is the gift of God. ').join();
  final history = [
    for (var k = 0; k < maxHistoryMessages ~/ 2; k++) ...[
      const ChatMessage.user('Tell me more about grace.'),
      ChatMessage.assistant(longAnswer),
    ],
  ];
  for (final tier in Tier.values) {
    final window = tier.contextWindow;
    var worst = 0;
    for (final q in _questions) {
      final messages = builder.build(retriever.retrieve(q, tier), history, q, tier).messages;
      final estimate = messages.fold(0, (sum, m) => sum + estimateTokens(m.content));
      final actual = await _tokens(model, messages);
      if (actual > worst) worst = actual;
      stdout.writeln('${tier.name.padRight(4)} est $estimate actual $actual  $q');
    }
    stdout.writeln(
      '${tier.name}: budget ${tier.promptTokens}, worst prompt $worst, plus output '
      '${tier.maxOutput} = ${worst + tier.maxOutput} of a $window window\n',
    );
  }
  db.close();
}
