import 'dart:convert';

import 'package:http/http.dart' as http;

import 'engine.dart';

/// Why an Ollama answer failed, worded for the person reading it under their question.
class OllamaException implements Exception {
  final String message;
  const OllamaException(this.message);

  @override
  String toString() => message;
}

class OllamaEngine implements LlmEngine {
  final String model;
  final String baseUrl;
  final int numCtx;
  final double temperature;
  OllamaEngine({
    this.model = 'gemma4:e2b',
    this.baseUrl = 'http://localhost:11434',
    this.numCtx = 8192,
    this.temperature = 0.3,
  });

  @override
  String get name => 'ollama:$model';

  @override
  Stream<String> generate(List<ChatMessage> messages, {required int maxTokens}) async* {
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse('$baseUrl/api/chat'))
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({
          'model': model,
          'messages': [for (final m in messages) m.toJson()],
          'stream': true,
          'think': false,
          'options': {'num_ctx': numCtx, 'temperature': temperature, 'num_predict': maxTokens},
        });
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        final body = await resp.stream.bytesToString();
        throw OllamaException('Ollama HTTP ${resp.statusCode}: $body');
      }
      final lines = resp.stream.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lines) {
        if (line.isEmpty) continue;
        final j = jsonDecode(line) as Map<String, dynamic>;
        if (j['error'] != null) throw OllamaException('Ollama: ${j['error']}');
        final content = (j['message'] as Map<String, dynamic>?)?['content'];
        if (content is String && content.isNotEmpty) yield content;
        if (j['done'] == true) break;
      }
    } on http.ClientException {
      // Ollama is the default on a computer, so this is often someone who never installed it.
      throw OllamaException(
        'Berea could not reach Ollama at $baseUrl. Install Ollama and start it, '
        'or choose On device in Settings.',
      );
    } finally {
      client.close();
    }
  }
}
