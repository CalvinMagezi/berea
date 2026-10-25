import 'dart:convert';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:test/test.dart';

/// A local stand-in for Ollama that answers every request with [status] and [body].
Future<HttpServer> _ollama(int status, String body) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    await req.drain<void>();
    req.response
      ..statusCode = status
      ..write(body);
    await req.response.close();
  });
  return server;
}

Future<String> _answer(OllamaEngine e) =>
    e.generate([ChatMessage.user('What does John 3:16 mean?')], maxTokens: 8).join();

void main() {
  test('Ollama not running says so in words, not as a socket error', () async {
    // A port that was free a moment ago, so nothing answers on it.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final url = 'http://127.0.0.1:${probe.port}';
    await probe.close();

    final failure = _answer(OllamaEngine(baseUrl: url));
    await expectLater(
      failure,
      throwsA(
        isA<OllamaException>().having(
          (e) => e.toString(),
          'message',
          'Berea could not reach Ollama at $url. Install Ollama and start it, '
              'or choose On device in Settings.',
        ),
      ),
    );
  });

  test('an Ollama error reads without a programming prefix', () async {
    final server = await _ollama(404, '{"error":"model \'gemma4:e2b\' not found"}');
    addTearDown(server.close);
    final failure = _answer(OllamaEngine(baseUrl: 'http://127.0.0.1:${server.port}'));
    await expectLater(
      failure,
      throwsA(
        isA<OllamaException>().having(
          (e) => e.toString(),
          'message',
          'Ollama HTTP 404: {"error":"model \'gemma4:e2b\' not found"}',
        ),
      ),
    );
  });

  test('a streamed answer arrives piece by piece', () async {
    final lines = [
      {
        'message': {'content': 'For God '},
        'done': false,
      },
      {
        'message': {'content': 'so loved.'},
        'done': true,
      },
    ].map(jsonEncode).join('\n');
    final server = await _ollama(200, lines);
    addTearDown(server.close);
    expect(
      await _answer(OllamaEngine(baseUrl: 'http://127.0.0.1:${server.port}')),
      'For God so loved.',
    );
  });
}
