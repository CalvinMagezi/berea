import 'dart:async';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

import 'models.dart';
import 'pinned_download.dart';

const initTimeout = Duration(seconds: 30);

/// How long a model download may stall, waiting for the response or for the next chunk.
const modelDownloadTimeout = Duration(minutes: 2);

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
    'words such as what, who and how, and punctuate it as it was spoken. Do not answer it or '
    'rephrase it. If there is no speech, reply with nothing. Reply with the transcript only.';

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
class EdgeAiEngine implements LlmEngine, StoppableEngine {
  final InferenceModel model;
  final EdgeModel spec;

  /// The model loaded with its audio encoder, so it can transcribe voice questions.
  final bool hearsAudio;
  EdgeAiEngine(this.model, this.spec, {this.hearsAudio = false});

  /// The conversation writing an answer now, so Stop can end it.
  InferenceChat? _answering;

  /// A stop that arrives before the conversation exists or before writing starts is still
  /// honoured: the answer checks this at each step.
  var _stopRequested = false;

  @override
  Future<void> stop() async {
    _stopRequested = true;
    await _answering?.stopGeneration();
  }

  /// Whether [m] is ready to load, and makes it the plugin's active model. The plugin remembers
  /// only the model it installed last, and 2.1.3 cannot restore one registered from a file, so
  /// after a restart the active model can be missing or another model's. Installing again skips
  /// the download of a file already there and sets the active model, so it is done on every check.
  static Future<bool> isInstalled(EdgeModel m, Directory modelsDir) async {
    await ensureEdgeAiInitialized();
    final source = m.source;
    if (source == null) {
      if (!await FlutterEdgeAi.isModelInstalled(m.installedName)) return false;
      await _installModel(m).fromHuggingFace(m.repo, file: m.file).install();
      return true;
    }
    final file = File('${modelsDir.path}/${m.file}');
    if (hostedModelCurrent(file, sha256: source.sha256, bytes: source.bytes)) {
      await _installModel(m).fromFile(file.path).install();
      _writeNotice(m, modelsDir);
      return true;
    }
    // Berea 0.4.0 downloaded Gemma 3 1B from Hugging Face into the plugin's own folder. With no
    // hosted file at all, that copy is still good and does not need fetching again.
    if (!file.existsSync() && await FlutterEdgeAi.isModelInstalled(m.installedName)) {
      await _installModel(m).fromHuggingFace(m.repo, file: m.file).install();
      return true;
    }
    return false;
  }

  static void _writeNotice(EdgeModel m, Directory modelsDir) {
    if (m.notice case final notice?) writeModelNotice(modelsDir, notice);
  }

  static InferenceInstallationBuilder _installModel(EdgeModel m) =>
      FlutterEdgeAi.installModel(modelType: m.type, fileType: ModelFileType.litertlm);

  /// Fetches [m] into [modelsDir] when Berea hosts it, else from Hugging Face, and installs it.
  /// A hosted file stays where it was put: the plugin registers its path instead of copying it.
  /// [onProgress] hears bytes; Hugging Face reports a percent, read against [m]'s published size.
  /// Once [stop] completes the transfer ends with [DownloadStopped] and nothing is installed.
  static Future<void> download(
    EdgeModel m, {
    required Directory modelsDir,
    required void Function(int received, int total) onProgress,
    Future<void>? stop,
    bool recheck = false,
  }) async {
    await ensureEdgeAiInitialized();
    final source = m.source;
    if (source == null) {
      final cancel = CancelToken();
      unawaited(stop?.then((_) => cancel.cancel('Stopped by the reader')));
      final total = m.publishedBytes;
      try {
        await _installModel(m)
            .fromHuggingFace(m.repo, file: m.file)
            .withProgress((percent) => onProgress(total * percent ~/ 100, total))
            .withCancelToken(cancel)
            .install();
      } on Object {
        if (cancel.isCancelled) throw const DownloadStopped();
        rethrow;
      }
      return;
    }
    final file = await downloadModelFile(
      Uri.parse(source.url),
      modelsDir,
      m.file,
      sha256: source.sha256,
      bytes: source.bytes,
      timeout: modelDownloadTimeout,
      onProgress: (received, total) => onProgress(received, total ?? source.bytes),
      stop: stop,
      recheck: recheck,
    );
    await _installModel(m).fromFile(file.path).install();
    _writeNotice(m, modelsDir);
  }

  /// Loads the model for [tier]; if its audio encoder fails, text still loads and voice is off.
  static Future<EdgeAiEngine> load(EdgeModel m, Tier tier) async {
    final maxTokens = tier.contextWindow;
    if (m.hearsAudio) {
      try {
        // The audio encoder stays on its default backend, the CPU.
        final model = await FlutterEdgeAi.getActiveModel(
          maxTokens: maxTokens,
          preferredBackend: answerBackend,
          supportAudio: true,
        );
        return EdgeAiEngine(model, m, hearsAudio: true);
      } catch (e) {
        debugPrint('${m.label} did not load with audio, so voice is off: ${e.runtimeType}');
      }
    }
    final model = await FlutterEdgeAi.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: answerBackend,
    );
    return EdgeAiEngine(model, m);
  }

  @override
  String get name => 'on-device:${spec.id}';

  @override
  Stream<String> generate(List<ChatMessage> messages, {required int maxTokens}) async* {
    final system = messages.where((m) => m.role == 'system').map((m) => m.content).join('\n');
    _stopRequested = false;
    final chat = await model.createChat(
      systemInstruction: system.isEmpty ? null : system,
      temperature: 0.3,
      topK: 40,
      topP: 0.95,
      enableThinking: false,
      modelType: spec.type,
      maxOutputTokens: maxTokens,
    );
    _answering = chat;
    try {
      if (_stopRequested) return;
      for (final m in messages.where((m) => m.role != 'system')) {
        await chat.addQueryChunk(Message.text(text: m.content, isUser: m.role == 'user'));
      }
      if (_stopRequested) return;
      await for (final r in chat.generateChatResponseAsync()) {
        if (r is TextResponse) yield r.token;
      }
    } finally {
      _answering = null;
      await chat.close();
    }
  }

  /// Words spoken in [wav]; outside the harness, so nothing enters the chat until confirmed.
  Future<String> transcribe(Uint8List wav) async {
    if (!hearsAudio) throw StateError('${spec.label} was loaded without audio.');
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
      await _forget(chat);
    }
  }

  /// The plugin keeps a chat's history, audio included, until cleared; clear it, then close.
  Future<void> _forget(InferenceChat chat) async {
    try {
      await chat.clearHistory();
    } catch (e) {
      debugPrint('Could not clear the transcription chat: ${e.runtimeType}');
    }
    await chat.close();
  }

  Future<void> close() => model.close();
}
