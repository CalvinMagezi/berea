import 'dart:async';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'edge_engine.dart';
import 'models.dart';

enum EngineKind { ollama, device }

/// Phones default to on-device, desktops to Ollama.
final defaultEngine = Platform.isAndroid || Platform.isIOS ? EngineKind.device : EngineKind.ollama;

class Settings {
  final EngineKind engine;
  final String ollamaUrl;
  final String model;
  final String deviceModelId;
  final String hfToken;
  final Tier tier;
  final String translation;
  Settings({
    EngineKind? engine,
    this.ollamaUrl = 'http://localhost:11434',
    this.model = 'gemma4:e2b',
    this.deviceModelId = 'gemma-4-e2b',
    this.hfToken = '',
    this.tier = Tier.mid,
    this.translation = defaultTranslation,
  }) : engine = engine ?? defaultEngine;

  EdgeModel get deviceModel => edgeModelById(deviceModelId);

  Settings copyWith({
    EngineKind? engine,
    String? ollamaUrl,
    String? model,
    String? deviceModelId,
    String? hfToken,
    Tier? tier,
    String? translation,
  }) => Settings(
    engine: engine ?? this.engine,
    ollamaUrl: ollamaUrl ?? this.ollamaUrl,
    model: model ?? this.model,
    deviceModelId: deviceModelId ?? this.deviceModelId,
    hfToken: hfToken ?? this.hfToken,
    tier: tier ?? this.tier,
    translation: translation ?? this.translation,
  );

  static Settings load(SharedPreferences p) {
    final engineName = p.getString('engine');
    return Settings(
      engine: engineName == null ? null : EngineKind.values.byName(engineName),
      ollamaUrl: p.getString('ollamaUrl') ?? 'http://localhost:11434',
      model: p.getString('model') ?? 'gemma4:e2b',
      deviceModelId: p.getString('deviceModelId') ?? 'gemma-4-e2b',
      hfToken: p.getString('hfToken') ?? '',
      tier: Tier.values.byName(p.getString('tier') ?? Tier.mid.name),
      translation: p.getString('translation') ?? defaultTranslation,
    );
  }

  Future<void> save(SharedPreferences p) async {
    await p.setString('engine', engine.name);
    await p.setString('ollamaUrl', ollamaUrl);
    await p.setString('model', model);
    await p.setString('deviceModelId', deviceModelId);
    await p.setString('hfToken', hfToken);
    await p.setString('tier', tier.name);
    await p.setString('translation', translation);
  }
}

class ChatTurn {
  final String question;
  String answer = '';
  TurnResult? result;
  String? error;
  ChatTurn(this.question);
  bool get done => result != null || error != null;
}

enum DeviceModelState { notInstalled, downloading, loading, ready, failed }

class AppState extends ChangeNotifier {
  late final BibleDb db;
  late final String systemPrompt;
  late final SharedPreferences prefs;
  late Settings settings;
  Harness? harness;
  final turns = <ChatTurn>[];
  bool busy = false;

  DeviceModelState deviceState = DeviceModelState.notInstalled;
  int downloadProgress = 0;
  String? deviceError;
  EdgeAiEngine? _edge;

  static Future<AppState> bootstrap() async {
    final s = AppState();
    s.db = BibleDb.open(await _ensureDb());
    s.systemPrompt = _stripFrontMatter(await rootBundle.loadString('prompts/system.md'));
    s.prefs = await SharedPreferences.getInstance();
    s.settings = Settings.load(s.prefs);
    await s._rebuildHarness();
    if (kDebugMode) unawaited(s._autorun());
    return s;
  }

  /// Debug builds only: a question in `BEREA_AUTORUN` or in `autorun.txt` under the app's
  /// documents folder downloads the model if needed and asks it. Lets a headless simulator or
  /// emulator exercise the on-device path without tapping.
  Future<void> _autorun() async {
    var q = Platform.environment['BEREA_AUTORUN'];
    if (q == null || q.isEmpty) {
      final f = File('${(await getApplicationDocumentsDirectory()).path}/autorun.txt');
      if (f.existsSync()) q = f.readAsStringSync().trim();
    }
    if (q == null || q.isEmpty) return;
    if (settings.engine == EngineKind.device && deviceState == DeviceModelState.notInstalled) {
      await downloadDeviceModel();
    }
    if (harness != null) await send(q);
  }

  /// Copies the bundled database next to the app once. Length doubles as a version check.
  static Future<String> _ensureDb() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/berea.sqlite');
    final data = await rootBundle.load('assets/berea.sqlite');
    if (!file.existsSync() || file.lengthSync() != data.lengthInBytes) {
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }
    return file.path;
  }

  static String _stripFrontMatter(String raw) {
    final i = raw.indexOf('\n---\n');
    return (i < 0 ? raw : raw.substring(i + 5)).trim();
  }

  String get engineLabel => harness?.engine.name ?? 'no engine';

  bool get ready => harness != null && !busy;

  Future<void> _rebuildHarness() async {
    await _edge?.close();
    _edge = null;
    harness = null;
    final engine = settings.engine == EngineKind.ollama ? _ollama() : await _device();
    if (engine != null) {
      harness = Harness(
        db: db,
        engine: engine,
        systemPrompt: systemPrompt,
        tier: settings.tier,
        translation: settings.translation,
      );
    }
    notifyListeners();
  }

  LlmEngine _ollama() => OllamaEngine(
    model: settings.model,
    baseUrl: settings.ollamaUrl,
    numCtx: settings.tier.promptTokens + settings.tier.maxOutput + contextPadding,
  );

  Future<LlmEngine?> _device() async {
    final m = settings.deviceModel;
    deviceError = null;
    try {
      if (!await EdgeAiEngine.isInstalled(m)) {
        deviceState = DeviceModelState.notInstalled;
        return null;
      }
      deviceState = DeviceModelState.loading;
      notifyListeners();
      _edge = await EdgeAiEngine.load(m, settings.tier);
      deviceState = DeviceModelState.ready;
      return _edge;
    } catch (e) {
      deviceState = DeviceModelState.failed;
      deviceError = e.toString();
      return null;
    }
  }

  Future<void> downloadDeviceModel() async {
    final m = settings.deviceModel;
    deviceState = DeviceModelState.downloading;
    downloadProgress = 0;
    deviceError = null;
    notifyListeners();
    try {
      await EdgeAiEngine.download(
        m,
        token: settings.hfToken.isEmpty ? null : settings.hfToken,
        onProgress: (p) {
          downloadProgress = p;
          notifyListeners();
        },
      );
      await _rebuildHarness();
    } catch (e) {
      deviceState = DeviceModelState.failed;
      deviceError = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateSettings(Settings next) async {
    final sameModel =
        next.engine == settings.engine &&
        next.deviceModelId == settings.deviceModelId &&
        next.tier == settings.tier;
    settings = next;
    await next.save(prefs);
    if (sameModel && settings.engine == EngineKind.device && harness != null) {
      harness = Harness(
        db: db,
        engine: harness!.engine,
        systemPrompt: systemPrompt,
        tier: settings.tier,
        translation: settings.translation,
      );
      notifyListeners();
      return;
    }
    await _rebuildHarness();
  }

  Future<void> send(String question) async {
    final h = harness;
    if (h == null) return;
    final turn = ChatTurn(question);
    turns.add(turn);
    busy = true;
    notifyListeners();
    try {
      turn.result = await h.ask(
        question,
        onToken: (t) {
          turn.answer += t;
          notifyListeners();
        },
      );
      turn.answer = turn.result!.text;
    } catch (e) {
      turn.error = e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void clear() {
    turns.clear();
    harness?.history.clear();
    notifyListeners();
  }
}
