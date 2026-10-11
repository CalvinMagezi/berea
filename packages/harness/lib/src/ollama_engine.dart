import 'dart:convert';

import 'package:http/http.dart' as http;

import 'engine.dart';

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
        throw StateError('Ollama HTTP ${resp.statusCode}: $body');
      }
      final lines = resp.stream.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lines) {
        if (line.isEmpty) continue;
        final j = jsonDecode(line) as Map<String, dynamic>;
        if (j['error'] != null) throw StateError('Ollama: ${j['error']}');
        final content = (j['message'] as Map<String, dynamic>?)?['content'];
        if (content is String && content.isNotEmpty) yield content;
        if (j['done'] == true) break;
      }
    } finally {
      client.close();
    }
  }
}
