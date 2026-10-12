import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device.dart';
import 'backup.dart';
import 'commentary_packs.dart';
import 'edge_engine.dart';
import 'models.dart';
import 'pinned_download.dart';
import 'plans.dart';
import 'study_store.dart';

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
  List<Ref> verified = const [];
  List<Ref> unverified = const [];
  List<String> unknownBooks = const [];
  int unverifiedQuotes = 0;
  int correctedQuotes = 0;
  List<NearMiss> nearMisses = const [];
  bool done = false;
  String? error;
  ChatTurn(this.question);
}

enum DeviceModelState { notInstalled, downloading, loading, ready, failed }

class AppState extends ChangeNotifier {
  late final BibleDb db;
  late final String systemPrompt;
  late final SharedPreferences prefs;
  late Settings settings;
  late final StudyStore study;
  late final Directory supportDir;

  /// Optional public domain commentaries the user has downloaded.
  late final CommentaryShelf commentary;
  Harness? harness;
  final turns = <ChatTurn>[];
  bool busy = false;

  /// The saved study the current turns belong to. Null until the first answer.
  int? conversationId;

  /// Set by the reader; the study tab picks it up and sends it.
  final pendingQuestion = ValueNotifier<String?>(null);

  int readerBook = 1;
  int readerChapter = 1;

  /// Verse the reader should scroll to and mark once, then clear.
  int? readerTargetVerse;

  /// Second translation shown under or beside the first in the reader. Null when off.
  String? parallelTranslation;

  /// Device RAM in GB, or null when the platform does not say.
  double? deviceGb;

  DeviceModelState deviceState = DeviceModelState.notInstalled;
  int downloadProgress = 0;
  String? deviceError;
  EdgeAiEngine? _edge;

  static Future<AppState> bootstrap() async {
    final s = AppState();
    s.supportDir = await getApplicationSupportDirectory();
    await excludeFromBackup(s.supportDir);
    s.db = BibleDb.open(await _ensureDb(s.supportDir));
    s.study = StudyStore.open('${s.supportDir.path}/study.sqlite');
    s.systemPrompt = _stripFrontMatter(await rootBundle.loadString('prompts/system.md'));
    s.prefs = await SharedPreferences.getInstance();
    final bytes = await totalMemoryBytes();
    s.deviceGb = bytes == null ? null : bytes / bytesPerGb;
    s.settings = Settings.load(s.prefs);
    if (!s.prefs.containsKey('deviceModelId')) {
      final m = recommendedModel(s.deviceGb);
      s.settings = s.settings.copyWith(deviceModelId: m.id, tier: m.tier);
    }
    s.readerBook = s.prefs.getInt('readerBook') ?? 1;
    s.readerChapter = s.prefs.getInt('readerChapter') ?? 1;
    s.parallelTranslation = s.prefs.getString('parallelTranslation');
    s._restoreImports();
    s._keepTranslationValid();
    s.db.attachFullLexicon(s.lexiconPackPath);
    s.commentary = CommentaryShelf(Directory('${s.supportDir.path}/commentary'), s.touch);
    await s._rebuildHarness();
    if (kDebugMode) unawaited(s._autorun());
    return s;
  }

  /// Debug builds only: questions in `BEREA_AUTORUN` or `autorun.txt` (one per line) under the
  /// app's documents folder download the model if needed and are asked in order. Lets a headless
  /// simulator or emulator exercise the on-device path without tapping.
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
    for (final line in q.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty)) {
      if (harness == null) return;
      await send(line);
    }
  }

  /// Copies the bundled database next to the app when the bundled build changes. The build
  /// stamp is a separate tiny asset, so a normal launch never loads the 67 MB database.
  static Future<String> _ensureDb(Directory dir) async {
    final file = File('${dir.path}/berea.sqlite');
    final stamp = File('${dir.path}/berea.sqlite.asset');
    final bundled = (await rootBundle.loadString('assets/berea.sqlite.version')).trim();
    final current = stamp.existsSync() ? stamp.readAsStringSync() : null;
    if (!file.existsSync() || current != bundled) {
      final data = await rootBundle.load('assets/berea.sqlite');
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      await stamp.writeAsString(bundled);
    }
    return file.path;
  }

  static String _stripFrontMatter(String raw) {
    final i = raw.indexOf('\n---\n');
    return (i < 0 ? raw : raw.substring(i + 5)).trim();
  }

  Directory get importsDir => Directory('${supportDir.path}/imports')..createSync(recursive: true);

  /// Imported translations that could not be loaded, shown in settings.
  final setAsideImports = <String>[];

  /// A rebuilt bundled database drops imported translations; the kept CSVs bring them back. Codes
  /// from older versions are normalised. A copy that no longer parses is set aside and reported,
  /// so it cannot stop the app from starting.
  void _restoreImports() {
    final have = db.translations().toSet();
    for (final f in importsDir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.csv')) continue;
      final stored = f.uri.pathSegments.last.replaceAll('.csv', '');
      final code = normalizeImportCode(stored);
      if (have.contains(code) && code == stored) continue;
      final target = File('${importsDir.path}/$code.csv');
      if (code != stored && target.existsSync()) {
        // An older copy under a free-form name duplicates one already normalised; keep the newer.
        setAsideImports.add(stored);
        f.renameSync('${f.path}.duplicate');
        continue;
      }
      try {
        final csv = f.readAsStringSync();
        if (!have.contains(code)) db.importCsv(csv, code);
        if (code != stored) f.renameSync(target.path);
        have.add(code);
      } on Object catch (e) {
        debugPrint('Setting aside imported translation $stored: $e');
        setAsideImports.add(stored);
        f.renameSync('${f.path}.invalid');
      }
    }
  }

  /// A valid code for [raw]: capitals and digits, at most 8, never a built-in translation's code.
  /// Older versions accepted any text.
  String normalizeImportCode(String raw) {
    var code = raw.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (code.isEmpty) code = 'IMPORT';
    if (code.length > translationCodeMax) code = code.substring(0, translationCodeMax);
    if (db.bundledTranslations().contains(code)) {
      code = 'MY$code';
      if (code.length > translationCodeMax) code = code.substring(0, translationCodeMax);
    }
    return code;
  }

  /// Throws [FormatException] unless [code] is a valid name that does not replace a bundled
  /// translation; a bundled one would otherwise be overwritten and the citation check with it.
  void validateImportCode(String code) {
    if (!translationCode.hasMatch(code)) {
      throw FormatException('Use 1 to 8 capital letters or digits for the code, not "$code".');
    }
    if (db.bundledTranslations().contains(code)) {
      throw FormatException('$code is built in. Choose another code.');
    }
  }

  /// Imports a user-owned translation from CSV, USFM, OSIS, Zefania or a zip of those, and keeps
  /// a normalised CSV copy so it survives database rebuilds. Parsing runs off the UI isolate, and
  /// an existing copy is only replaced once the new one has imported. Returns the verse count.
  Future<int> importTranslation(List<({String name, Uint8List bytes})> files, String code) async {
    validateImportCode(code);
    final rows = await Isolate.run(
      () => [for (final f in files) ...parseBibleFile(f.name, f.bytes)],
    );
    if (rows.isEmpty) throw const FormatException('No verses were found in those files.');
    final csv = toCsv([
      ['Book', 'Chapter', 'Verse', 'Text'],
      for (final r in rows) [r.book.name, '${r.chapter}', '${r.verse}', r.text],
    ]);
    final staged = File('${importsDir.path}/$code.csv.part')..writeAsStringSync(csv);
    try {
      final n = db.importRows(rows, code);
      staged.renameSync('${importsDir.path}/$code.csv');
      notifyListeners();
      return n;
    } finally {
      if (staged.existsSync()) staged.deleteSync();
    }
  }

  void setReader(Book book, int chapter, [int? verse]) {
    readerBook = book.id;
    readerChapter = chapter;
    readerTargetVerse = verse;
    prefs.setInt('readerBook', book.id);
    prefs.setInt('readerChapter', chapter);
    notifyListeners();
  }

  void setParallel(String? translation) {
    parallelTranslation = translation;
    translation == null
        ? prefs.remove('parallelTranslation')
        : prefs.setString('parallelTranslation', translation);
    notifyListeners();
  }

  ReadingPlan? get activePlan => planById(prefs.getString('activePlan'));

  void startPlan(ReadingPlan plan) {
    study.clearPlan(plan.id);
    prefs.setString('activePlan', plan.id);
    prefs.setString('activePlanStart', DateTime.now().toIso8601String());
    notifyListeners();
  }

  void stopPlan() {
    prefs.remove('activePlan');
    prefs.remove('activePlanStart');
    notifyListeners();
  }

  List<List<Ref>> planSchedule(ReadingPlan plan) =>
      plan.schedule((b) => db.chapterCount(b, translation: defaultTranslation));

  /// Day of [plan] for today, counting the start day as day 1 and stopping at the last day.
  int planDay(ReadingPlan plan) {
    final start = DateTime.tryParse(prefs.getString('activePlanStart') ?? '') ?? DateTime.now();
    final days = DateTime.now().difference(DateTime(start.year, start.month, start.day)).inDays;
    return (days + 1).clamp(1, plan.days);
  }

  /// Today's chapters if a plan is running.
  List<Ref>? get todaysReading {
    final plan = activePlan;
    return plan == null ? null : planSchedule(plan)[planDay(plan) - 1];
  }

  static const maxLexiconPackBytes = 64 * 1024 * 1024;
  static const lexiconDownloadTimeout = Duration(minutes: 5);

  /// The optional full Greek lexicon: a data-only release pinned by tag and checked by hash, so
  /// what arrives is exactly what was published.
  static const lexiconPackUrl =
      'https://github.com/CalvinMagezi/berea/releases/download/lexicon-1/lexicon-lsj.sqlite';
  static const lexiconPackSha256 =
      '39da044337aad1bcd2753451365608c10052d31dbfb3f50747b82e55060751a1';

  String get lexiconPackPath => '${supportDir.path}/lexicon-lsj.sqlite';

  /// Downloads the pack only when the user asks, or installs one they picked from a file.
  /// The file is checked by attaching it before it replaces anything.
  Future<void> installLexiconPack({Uint8List? bytes}) async {
    if (bytes != null && bytes.length > maxLexiconPackBytes) {
      throw const FormatException('That file is too large to be a Berea lexicon pack.');
    }
    final tmp = File('$lexiconPackPath.part');
    try {
      if (bytes == null) {
        await downloadPinned(
          Uri.parse(lexiconPackUrl),
          tmp,
          sha256: lexiconPackSha256,
          maxBytes: maxLexiconPackBytes,
          timeout: lexiconDownloadTimeout,
        );
      } else {
        tmp.writeAsBytesSync(bytes);
      }
      final probe = BibleDb(sqlite3.openInMemory());
      final ok = probe.attachFullLexicon(tmp.path);
      probe.close();
      if (!ok) throw const FormatException('That file is not a Berea lexicon pack.');
      // The old pack is held open while attached; let go of it before replacing the file.
      db.detachFullLexicon();
      tmp.renameSync(lexiconPackPath);
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
      db.attachFullLexicon(lexiconPackPath);
      notifyListeners();
    }
  }

  /// Imported translations as code to CSV, for backups.
  Map<String, String> get importedTranslations => {
    for (final f in importsDir.listSync().whereType<File>())
      if (f.path.endsWith('.csv'))
        f.uri.pathSegments.last.replaceAll('.csv', ''): f.readAsStringSync(),
  };

  Future<Uint8List> backup(String passphrase) =>
      createBackup(study, importedTranslations, passphrase);

  /// Decrypts and checks a backup without changing anything, so the user can confirm what it
  /// holds. Throws [BackupException] or [FormatException] if it cannot be used.
  Future<BackupContents> openBackup(Uint8List bytes, String passphrase) async {
    final contents = await readBackup(bytes, passphrase);
    study.validateTables(contents.tables);
    return contents;
  }

  /// Applies a checked backup. Translations go in first and notes and studies last, so a late
  /// failure leaves the old notes in place and is safe to retry. Returns the imported
  /// translations that were skipped because they no longer parse.
  List<String> applyBackup(BackupContents contents) {
    final imports = <String, ({List<VerseRow> rows, String csv})>{};
    final skipped = <String>[];
    for (final e in contents.imports.entries) {
      try {
        final rows = parseCsvBible(e.value);
        if (rows.isEmpty) throw const FormatException('empty');
        imports[_uniqueCode(normalizeImportCode(e.key), imports.keys)] = (rows: rows, csv: e.value);
      } on FormatException {
        skipped.add(e.key);
      }
    }
    for (final e in imports.entries) {
      db.importRows(e.value.rows, e.key);
      File('${importsDir.path}/${e.key}.csv').writeAsStringSync(e.value.csv);
    }
    study.importTables(contents.tables);
    _keepTranslationValid();
    clear();
    return skipped;
  }

  /// Two codes that normalise alike ("niv" and "NIV") stay apart as NIV and NIV2.
  String _uniqueCode(String code, Iterable<String> taken) {
    if (!taken.contains(code)) return code;
    for (var i = 2; ; i++) {
      final suffix = '$i';
      final base = code.length + suffix.length > translationCodeMax
          ? code.substring(0, translationCodeMax - suffix.length)
          : code;
      if (!taken.contains('$base$suffix')) return '$base$suffix';
    }
  }

  /// A translation renamed or set aside must not leave the reader pointing at nothing.
  void _keepTranslationValid() {
    final have = db.translations();
    String fix(String t) => have.contains(t) ? t : defaultTranslation;
    final next = settings.copyWith(translation: fix(settings.translation));
    if (next.translation != settings.translation) {
      settings = next;
      unawaited(next.save(prefs));
    }
    if (parallelTranslation != null && !have.contains(parallelTranslation)) setParallel(null);
  }

  /// Asks the shell to show the Bible tab at [ref].
  final openReaderRequest = ValueNotifier<int>(0);

  void openInReader(Ref ref) {
    setReader(ref.book, ref.chapter, ref.verseStart);
    openReaderRequest.value++;
  }

  void askAbout(Ref ref) =>
      pendingQuestion.value = 'Study ${ref.label}. What does it mean and how does it apply?';

  /// Notes and highlights change outside this class; callers poke listeners through here.
  void touch() => notifyListeners();

  void openConversation(int id) {
    turns.clear();
    harness?.resetConversation();
    conversationId = id;
    ChatTurn? current;
    for (final m in study.messages(id)) {
      if (m.isUser) {
        current = ChatTurn(m.text);
        turns.add(current);
        harness?.history.add(ChatMessage.user(m.text));
      } else if (current != null) {
        current
          ..answer = m.text
          ..verified = m.refs
          ..done = true;
        harness?.history.add(ChatMessage.assistant(m.text));
      }
    }
    notifyListeners();
  }

  void deleteConversation(int id) {
    study.deleteConversation(id);
    if (conversationId == id) clear();
    notifyListeners();
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
      final result = await h.ask(
        question,
        onToken: (t) {
          turn.answer += t;
          notifyListeners();
        },
      );
      turn
        ..answer = result.text
        ..verified = result.guard.verified
        ..unverified = result.guard.unverified
        ..unknownBooks = result.guard.unknownBooks
        ..unverifiedQuotes = result.guard.unverifiedQuotes.length
        ..correctedQuotes = result.guard.correctedQuotes.length
        ..nearMisses = result.guard.nearMisses
        ..done = true;
      conversationId ??= study.createConversation(question);
      study.addMessage(conversationId!, 'user', question, const []);
      study.addMessage(conversationId!, 'assistant', turn.answer, turn.verified);
    } catch (e) {
      turn.error = e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void clear() {
    turns.clear();
    harness?.resetConversation();
    conversationId = null;
    notifyListeners();
  }
}
