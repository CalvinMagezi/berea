import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  final String ollamaUrl;
  final String model;
  final Tier tier;
  final String translation;
  const Settings({
    this.ollamaUrl = 'http://localhost:11434',
    this.model = 'gemma4:e2b',
    this.tier = Tier.mid,
    this.translation = defaultTranslation,
  });

  Settings copyWith({String? ollamaUrl, String? model, Tier? tier, String? translation}) =>
      Settings(
        ollamaUrl: ollamaUrl ?? this.ollamaUrl,
        model: model ?? this.model,
        tier: tier ?? this.tier,
        translation: translation ?? this.translation,
      );

  static Settings load(SharedPreferences p) => Settings(
    ollamaUrl: p.getString('ollamaUrl') ?? 'http://localhost:11434',
    model: p.getString('model') ?? 'gemma4:e2b',
    tier: Tier.values.byName(p.getString('tier') ?? Tier.mid.name),
    translation: p.getString('translation') ?? defaultTranslation,
  );

  Future<void> save(SharedPreferences p) async {
    await p.setString('ollamaUrl', ollamaUrl);
    await p.setString('model', model);
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

class AppState extends ChangeNotifier {
  late final BibleDb db;
  late final String systemPrompt;
  late final SharedPreferences prefs;
  late Settings settings;
  late Harness harness;
  final turns = <ChatTurn>[];
  bool busy = false;

  static Future<AppState> bootstrap() async {
    final s = AppState();
    s.db = BibleDb.open(await _ensureDb());
    s.systemPrompt = _stripFrontMatter(await rootBundle.loadString('prompts/system.md'));
    s.prefs = await SharedPreferences.getInstance();
    s.settings = Settings.load(s.prefs);
    s._rebuildHarness();
    return s;
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

  void _rebuildHarness() {
    harness = Harness(
      db: db,
      engine: OllamaEngine(
        model: settings.model,
        baseUrl: settings.ollamaUrl,
        numCtx: settings.tier.promptTokens + settings.tier.maxOutput + 512,
      ),
      systemPrompt: systemPrompt,
      tier: settings.tier,
      translation: settings.translation,
    );
  }

  Future<void> updateSettings(Settings next) async {
    settings = next;
    await next.save(prefs);
    _rebuildHarness();
    notifyListeners();
  }

  Future<void> send(String question) async {
    final turn = ChatTurn(question);
    turns.add(turn);
    busy = true;
    notifyListeners();
    try {
      turn.result = await harness.ask(
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
    harness.history.clear();
    notifyListeners();
  }
}
