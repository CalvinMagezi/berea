import 'dart:async';
import 'dart:typed_data';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

import 'models.dart';

const contextPadding = 512;
const initTimeout = Duration(seconds: 30);

/// CPU, not GPU: Gemma 4 E2B on some phone GPUs corrupts digits (LiteRT-LM #2202, still open in
/// v0.18.0), and a corrupted verse number that still exists would pass the citation check.
const answerBackend = PreferredBackend.cpu;

/// A spoken question is short; this leaves room for about 30 seconds of speech.
const transcriptMaxTokens = 256;

/// Near greedy, so the transcript keeps the words that were said.
const transcriptTemperature = 0.1;
const transcriptTopK = 1;

const transcribeInstruction =
    'Transcribe the speech in this audio word for word. Keep every word, including question '
    'words such as what, who and how, and end a question with a question mark. Do not answer '
    'it or rephrase it. Reply with the transcript only.';

Future<void>? _init;

/// Plugin setup runs once, lazily, and never blocks the first frame.
Future<void> ensureEdgeAiInitialized() =>
    _init ??= FlutterEdgeAi.initialize(inferenceEngines: const [LiteRtLmEngine()]).timeout(
      initTimeout,
      onTimeout: () {
        _init = null;
        throw TimeoutException('flutter_edge_ai did not initialize within $initTimeout');
      },
    );

/// Harness engine backed by a LiteRT-LM model loaded through flutter_edge_ai. Each turn opens a
/// fresh conversation; keeping one open measured slower overall on a phone-sized context.
class EdgeAiEngine implements LlmEngine {
  final InferenceModel model;
  final EdgeModel spec;
  const EdgeAiEngine(this.model, this.spec);

  static Future<bool> isInstalled(EdgeModel m) async {
    await ensureEdgeAiInitialized();
    return FlutterEdgeAi.isModelInstalled(m.installedName);
  }

  static Future<void> download(
    EdgeModel m, {
    String? token,
    required void Function(int) onProgress,
  }) async {
    await ensureEdgeAiInitialized();
    await FlutterEdgeAi.installModel(
      modelType: m.type,
      fileType: ModelFileType.litertlm,
    ).fromHuggingFace(m.repo, file: m.file, token: token).withProgress(onProgress).install();
  }

  /// Loads the active model sized for [tier]. Download it first with [download].
  static Future<EdgeAiEngine> load(EdgeModel m, Tier tier) async {
    final model = await FlutterEdgeAi.getActiveModel(
      maxTokens: tier.promptTokens + tier.maxOutput + contextPadding,
      preferredBackend: answerBackend,
      // The audio encoder is left on its default backend, the CPU.
      supportAudio: m.hearsAudio,
    );
    return EdgeAiEngine(model, m);
  }

  @override
  String get name => 'on-device:${spec.id}';

  @override
  Stream<String> generate(List<ChatMessage> messages, {required int maxTokens}) async* {
    final system = messages.where((m) => m.role == 'system').map((m) => m.content).join('\n');
    final chat = await model.createChat(
      systemInstruction: system.isEmpty ? null : system,
      temperature: 0.3,
      topK: 40,
      topP: 0.95,
      enableThinking: false,
      modelType: spec.type,
      maxOutputTokens: maxTokens,
    );
    try {
      for (final m in messages.where((m) => m.role != 'system')) {
        await chat.addQueryChunk(Message.text(text: m.content, isUser: m.role == 'user'));
      }
      await for (final r in chat.generateChatResponseAsync()) {
        if (r is TextResponse) yield r.token;
      }
    } finally {
      await chat.close();
    }
  }

  /// Words spoken in [wav], a 16 kHz mono 16-bit WAV file. Runs outside the harness so the
  /// question only enters the conversation after the user confirms it.
  Future<String> transcribe(Uint8List wav) async {
    if (!spec.hearsAudio) throw StateError('${spec.label} does not take audio.');
    final chat = await model.createChat(
      temperature: transcriptTemperature,
      topK: transcriptTopK,
      enableThinking: false,
      modelType: spec.type,
      supportAudio: true,
      maxOutputTokens: transcriptMaxTokens,
    );
    try {
      // Without supportAudio on both the model and the chat the plugin drops the audio silently.
      await chat.addQueryChunk(
        Message.withAudio(text: transcribeInstruction, audioBytes: wav, isUser: true),
      );
      final out = StringBuffer();
      await for (final r in chat.generateChatResponseAsync()) {
        if (r is TextResponse) out.write(r.token);
      }
      return out.toString().trim();
    } finally {
      await chat.close();
    }
  }

  Future<void> close() => model.close();
}
