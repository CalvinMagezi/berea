import 'dart:async';
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

class OllamaEngine implements LlmEngine, StoppableEngine {
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

  http.Client? _client;
  Completer<void> _stopSignal = Completer<void>();

  @override
  String get name => 'ollama:$model';

  /// Ends the answer after the piece being read, and closes the connection so Ollama stops
  /// generating.
  @override
  Future<void> stop() async {
    if (!_stopSignal.isCompleted) _stopSignal.complete();
    _client?.close();
  }

  @override
  Stream<String> generate(List<ChatMessage> messages, {required int maxTokens}) async* {
    final client = _client = http.Client();
    final stopped = _stopSignal = Completer<void>();
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
      final lines = StreamIterator(
        resp.stream.transform(utf8.decoder).transform(const LineSplitter()),
      );
      try {
        while (await Future.any([lines.moveNext(), stopped.future.then((_) => false)])) {
          final line = lines.current;
          if (line.isEmpty) continue;
          final j = jsonDecode(line) as Map<String, dynamic>;
          if (j['error'] != null) throw OllamaException('Ollama: ${j['error']}');
          final content = (j['message'] as Map<String, dynamic>?)?['content'];
          if (content is String && content.isNotEmpty) yield content;
          if (j['done'] == true) break;
        }
      } finally {
        // Not awaited: with the connection closed under it, cancelling can wait on the socket.
        unawaited(lines.cancel());
      }
    } on http.ClientException {
      if (stopped.isCompleted) return;
      // Ollama is the default on a computer, so this is often someone who never installed it.
      throw OllamaException(
        'Berea could not reach Ollama at $baseUrl. Install Ollama and start it, '
        'or choose On device in Settings.',
      );
    } finally {
      client.close();
      if (_client == client) _client = null;
    }
  }
}
