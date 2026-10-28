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
import 'notebook_chat.dart';
import 'notebook_store.dart';
import 'pinned_download.dart';
import 'plans.dart';
import 'prayer_store.dart';
import 'study_store.dart';
import 'voice.dart';

enum EngineKind { ollama, device }

/// Phones default to on-device, desktops to Ollama.
final defaultEngine = Platform.isAndroid || Platform.isIOS ? EngineKind.device : EngineKind.ollama;

class Settings {
  final EngineKind engine;
  final String ollamaUrl;
  final String model;
  final String deviceModelId;
  final Tier tier;
  final String translation;

  /// The reader's choice about brief answers; null until they make one.
  final bool? _briefChoice;

  /// Answer in a few sentences first, with a button for the full study. Unless the reader chose,
  /// on at the low tier, whose phones decode a few tokens a second.
  bool get briefFirst => _briefChoice ?? tier == Tier.low;
  Settings({
    EngineKind? engine,
    this.ollamaUrl = 'http://localhost:11434',
    this.model = 'gemma4:e2b',
    this.deviceModelId = 'gemma-4-e2b',
    this.tier = Tier.mid,
    this.translation = defaultTranslation,
    bool? briefFirst,
  }) : engine = engine ?? defaultEngine,
       _briefChoice = briefFirst;

  EdgeModel get deviceModel => edgeModelById(deviceModelId);

  Settings copyWith({
    EngineKind? engine,
    String? ollamaUrl,
    String? model,
    String? deviceModelId,
    Tier? tier,
    String? translation,
    bool? briefFirst,
  }) => Settings(
    engine: engine ?? this.engine,
    ollamaUrl: ollamaUrl ?? this.ollamaUrl,
    model: model ?? this.model,
    deviceModelId: deviceModelId ?? this.deviceModelId,
    tier: tier ?? this.tier,
    translation: translation ?? this.translation,
    briefFirst: briefFirst ?? _briefChoice,
  );

  static Settings load(SharedPreferences p) {
    final engineName = p.getString('engine');
    return Settings(
      engine: engineName == null ? null : EngineKind.values.byName(engineName),
      ollamaUrl: p.getString('ollamaUrl') ?? 'http://localhost:11434',
      model: p.getString('model') ?? 'gemma4:e2b',
      deviceModelId: p.getString('deviceModelId') ?? 'gemma-4-e2b',
      tier: Tier.values.byName(p.getString('tier') ?? Tier.mid.name),
      translation: p.getString('translation') ?? defaultTranslation,
      briefFirst: p.getBool('briefFirst'),
    );
  }

  /// Older builds kept a Hugging Face token here; nothing needs one now, so it is not kept.
  static Future<void> dropLegacyToken(SharedPreferences p) => p.remove('hfToken');

  Future<void> save(SharedPreferences p) async {
    await p.setString('engine', engine.name);
    await p.setString('ollamaUrl', ollamaUrl);
    await p.setString('model', model);
    await p.setString('deviceModelId', deviceModelId);
    await p.setString('tier', tier.name);
    await p.setString('translation', translation);
    if (_briefChoice case final choice?) await p.setBool('briefFirst', choice);
  }
}

/// Streamed text reaches the screen at most this often. Notifying the whole app per token
/// rebuilt every tab, with their database reads, while the model held the CPU.
const streamRefresh = Duration(milliseconds: 66);

/// Verses shown while the model has not yet written a word.
const readingVerseLimit = 3;

/// The button that asks for the full study, and the question bubble it adds.
const goDeeperLabel = 'Go deeper';

/// A question and its answer. Listeners hear the answer grow while it streams.
class ChatTurn extends ChangeNotifier {
  final String question;

  /// How much the model was asked to write. A brief answer offers to go deeper.
  final AnswerStyle style;

  /// The full study that follows a brief answer, shown under the question "Go deeper".
  final bool deeper;
  ChatTurn(this.question, {this.style = AnswerStyle.full, this.deeper = false});

  /// What the reader sees in the question bubble and what is saved as their message.
  String get shownQuestion => deeper ? goDeeperLabel : question;

  /// The reader ended the answer early; what was written so far is kept.
  bool stopped = false;
  bool deeperAsked = false;

  void markStopped() {
    stopped = true;
    notifyListeners();
  }

  void markDeeperAsked() {
    deeperAsked = true;
    notifyListeners();
  }

  /// The full study failed, so the button comes back.
  void markDeeperFailed() {
    deeperAsked = false;
    notifyListeners();
  }

  /// A finished brief answer can be followed by the full study, once.
  bool get canGoDeeper =>
      done &&
      error == null &&
      answer.trim().isNotEmpty &&
      style == AnswerStyle.brief &&
      !deeperAsked;

  /// A full study that failed or wrote nothing, so the brief answer may ask for it again.
  bool get failedDeeper => deeper && (error != null || (done && answer.trim().isEmpty));
  String answer = '';
  Timer? _refresh;
  List<Ref> verified = const [];
  List<Ref> unverified = const [];
  List<String> unknownBooks = const [];
  int unverifiedQuotes = 0;
  int correctedQuotes = 0;
  List<NearMiss> nearMisses = const [];

  /// Notebook answers only: the chunks cited, and tags naming nothing that was shown.
  List<ShownSource> sources = const [];
  List<String> unverifiedSources = const [];
  int rewordedQuotes = 0;
  bool done = false;
  String? error;

  /// Verses the model is about to read, shown while it works through them.
  List<Verse> reading = const [];

  /// Puts the passages the model was shown on screen; on a slow phone the model needs minutes.
  void read(StudyContext shown) {
    final verses = shown.passages.isNotEmpty ? shown.passages : shown.searchHits;
    reading = verses.take(readingVerseLimit).toList();
    notifyListeners();
  }

  /// Adds a streamed [token]; listeners hear of it within [streamRefresh].
  void append(String token) {
    answer += token;
    _refresh ??= Timer(streamRefresh, () {
      _refresh = null;
      notifyListeners();
    });
  }

  /// Takes the checked answer and what the check found.
  void take(GuardResult g) {
    _refresh?.cancel();
    _refresh = null;
    answer = g.text;
    verified = g.verified;
    unverified = g.unverified;
    unknownBooks = g.unknownBooks;
    unverifiedQuotes = g.unverifiedQuotes.length;
    correctedQuotes = g.correctedQuotes.length;
    nearMisses = g.nearMisses;
    sources = g.sources;
    unverifiedSources = g.unverifiedSources;
    rewordedQuotes = g.rewordedQuotes.length;
    done = true;
    notifyListeners();
  }
}

enum DeviceModelState { notInstalled, downloading, loading, ready, failed }

/// Where the helper (the model that answers in Study) stands. The Bible never waits for it.
sealed class HelperState {
  const HelperState();
}

final class HelperNotInstalled extends HelperState {
  const HelperNotInstalled();
}

final class HelperDownloading extends HelperState {
  /// How much has arrived, from 0 to 1.
  final double fraction;

  /// The download's size in bytes, or null when the source does not say.
  final int? total;

  /// Always false for now: nothing yet holds a download back for Wi-Fi.
  final bool waitingForWifi;
  const HelperDownloading(this.fraction, {this.total, this.waitingForWifi = false});

  int? get bytes => total == null ? null : (total! * fraction).round();
  int get percent => (fraction * 100).round();
}

/// Looking for the model files before loading them.
final class HelperChecking extends HelperState {
  const HelperChecking();
}

final class HelperLoading extends HelperState {
  const HelperLoading();
}

final class HelperReady extends HelperState {
  const HelperReady();
}

final class HelperFailed extends HelperState {
  /// Plain words for the reader.
  final String reason;

  /// The underlying error, for settings and bug reports.
  final String? detail;
  const HelperFailed(this.reason, {this.detail});
}

/// A start that cannot go on, told in plain words.
class StartupFailure implements Exception {
  final String message;
  const StartupFailure(this.message);

  @override
  String toString() => message;
}

const notesCopyFailed =
    'Berea could not make a safety copy of your notes before updating them, so nothing was '
    'changed. Free some space on this device and open Berea again.';

const helperDownloadFailed = 'The download stopped. Check the connection and try again.';
const helperLoadFailed = 'The helper could not start on this device. Open settings to repair it.';
const helperNotAvailable = 'The helper is not set up yet, so this question was not answered.';

class AppState extends ChangeNotifier {
  late final BibleDb db;
  late final String systemPrompt;
  late final SharedPreferences prefs;
  late Settings settings;
  late final StudyStore study;

  /// Notebooks share study.sqlite, so they are backed up and restored with the notes.
  late final NotebookStore notebooks = NotebookStore(study.db);

  /// Prayers share study.sqlite, so they are backed up and restored with the notes.
  late final PrayerStore prayers = PrayerStore(study.db);
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

  HelperState _helper = const HelperNotInstalled();

  /// Whether the helper was last built on this device rather than Ollama.
  bool _helperOnDevice = false;

  HelperState get helperState => _helper;

  set helperState(HelperState next) {
    _helper = next;
    notifyListeners();
    _releaseHeld();
  }

  /// The helper is checking or loading, so a question can wait for it.
  bool get helperComing => _helper is HelperChecking || _helper is HelperLoading;

  /// The older view of [helperState] that settings and the composer still read.
  DeviceModelState get deviceState => switch (_helper) {
    HelperNotInstalled() => DeviceModelState.notInstalled,
    HelperDownloading() => DeviceModelState.downloading,
    HelperChecking() || HelperLoading() => DeviceModelState.loading,
    HelperReady() => _helperOnDevice ? DeviceModelState.ready : DeviceModelState.notInstalled,
    HelperFailed() => DeviceModelState.failed,
  };

  set deviceState(DeviceModelState next) => helperState = switch (next) {
    DeviceModelState.notInstalled => const HelperNotInstalled(),
    DeviceModelState.downloading => const HelperDownloading(0),
    DeviceModelState.loading => const HelperLoading(),
    DeviceModelState.ready => const HelperReady(),
    DeviceModelState.failed => const HelperFailed(helperLoadFailed),
  };

  int get downloadProgress => switch (_helper) {
    HelperDownloading(:final percent) => percent,
    _ => 0,
  };

  String? get deviceError => switch (_helper) {
    HelperFailed(:final detail, :final reason) => detail ?? reason,
    _ => null,
  };

  EdgeAiEngine? _edge;

  /// The single voice session, shared by every composer so only one recorder runs.
  late VoiceInput voice = VoiceInput(transcribe: transcribeVoice);

  /// Whatever is using the model now; a rebuild waits for it before closing the model.
  Future<void>? _modelUse;

  @visibleForTesting
  set debugEdge(EdgeAiEngine? engine) => _edge = engine;

  /// The loaded Gemma 4 model came up with its audio encoder.
  bool get deviceHearsAudio => _edge?.hearsAudio ?? false;

  /// Set once bootstrap has opened everything [startHelper] needs.
  bool _canStartHelper = false;
  bool _helperStarted = false;

  /// Debug autorun reads the user's own data, so a test's bootstrap never runs it.
  bool _autorunAllowed = false;

  /// Opens the Bible, notes and settings: everything the first frame needs. The helper loads
  /// later, from [startHelper]. [onFirstSetup] hears when the Bible is being copied into place,
  /// on first launch and after an update. Overrides let a test run the real app without opening
  /// the user's data.
  static Future<AppState> bootstrap({
    Directory? supportDir,
    SharedPreferences? prefs,
    VoidCallback? onFirstSetup,
  }) async {
    final s = AppState();
    s.supportDir = supportDir ?? await getApplicationSupportDirectory();
    await excludeFromBackup(s.supportDir);
    s.db = BibleDb.open(await _ensureDb(s.supportDir, onFirstSetup));
    s.study = _openStudy('${s.supportDir.path}/study.sqlite');
    s.systemPrompt = _stripFrontMatter(await rootBundle.loadString('prompts/system.md'));
    s.prefs = prefs ?? await SharedPreferences.getInstance();
    final bytes = await totalMemoryBytes();
    s.deviceGb = bytes == null ? null : bytes / bytesPerGb;
    await Settings.dropLegacyToken(s.prefs);
    s.settings = Settings.load(s.prefs);
    if (!s.prefs.containsKey('deviceModelId')) {
      final m = recommendedModel(s.deviceGb);
      s.settings = s.settings.copyWith(deviceModelId: m.id, tier: recommendedTier(m, s.deviceGb));
    }
    s.readerBook = s.prefs.getInt('readerBook') ?? 1;
    s.readerChapter = s.prefs.getInt('readerChapter') ?? 1;
    s.parallelTranslation = s.prefs.getString('parallelTranslation');
    s._restoreImports();
    s._keepTranslationValid();
    s.db.attachFullLexicon(s.lexiconPackPath);
    s.commentary = CommentaryShelf(Directory('${s.supportDir.path}/commentary'), s.touch);
    s._canStartHelper = true;
    s._autorunAllowed = kDebugMode && supportDir == null;
    // A question asked before the shell starts the helper waits for it.
    s._helper = const HelperChecking();
    return s;
  }

  /// Loads the helper once, after the first frame, so the Bible never waits for the model.
  Future<void> startHelper() async {
    if (!_canStartHelper || _helperStarted) return;
    _helperStarted = true;
    await _rebuildHarness();
    if (_autorunAllowed) unawaited(_autorun());
  }

  /// Opens the notes database. The notes merge first writes a safety copy beside it; if that
  /// copy cannot be written the store throws before migrating, and Berea stops with [StartupFailure]
  /// rather than open notes it could not protect.
  static StudyStore _openStudy(String path) {
    final raw = sqlite3.open(path);
    try {
      return StudyStore(raw);
    } on Object catch (e) {
      raw.dispose();
      debugPrint('The notes database did not open: $e');
      throw const StartupFailure(notesCopyFailed);
    }
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
  static Future<String> _ensureDb(Directory dir, VoidCallback? onFirstSetup) async {
    final file = File('${dir.path}/berea.sqlite');
    final stamp = File('${dir.path}/berea.sqlite.asset');
    final bundled = (await rootBundle.loadString('assets/berea.sqlite.version')).trim();
    final current = stamp.existsSync() ? stamp.readAsStringSync() : null;
    if (!file.existsSync() || current != bundled) {
      onFirstSetup?.call();
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
    // A source still being read belongs to a notebook id the backup may have reused.
    if (contents.hasNotebooks) notebooks.cancelAll();
    // Restoring an older backup merges its notes into notebooks, which may add one.
    notebooks.refresh();
    prayers.refresh();
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

  /// Sends a word study's question (see [wordStudyQuestion]) to the Study tab.
  void askAboutWord(String question) => pendingQuestion.value = question;

  /// Notes and highlights change outside this class; callers poke listeners through here. A
  /// first note on a verse or a saved study page can create the notes on verses notebook.
  void touch() {
    notebooks.refresh();
    notifyListeners();
  }

  void openConversation(int id) {
    // Switching studies under an answer being written, or one waiting, would put it in the wrong one.
    if (busy || _held != null) return;
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
    if ((busy || _held != null) && conversationId == id) return;
    study.deleteConversation(id);
    if (conversationId == id) clear();
    notifyListeners();
  }

  String get engineLabel => harness?.engine.name ?? 'no engine';

  /// Whether a question can be sent now. While the helper loads one question may be sent; it
  /// waits and is answered once the helper is ready.
  bool get ready => (harness != null || (helperComing && _held == null)) && !busy && !voice.inUse;

  /// Runs [work] as the only user of the model, holding [busy] until it settles.
  Future<T> useModel<T>(Future<T> Function() work) async {
    if (busy) throw StateError('The model is busy.');
    busy = true;
    notifyListeners();
    final running = work();
    _modelUse = running.then((_) {}, onError: (_) {});
    try {
      return await running;
    } finally {
      busy = false;
      _modelUse = null;
      notifyListeners();
    }
  }

  Future<void>? _rebuilding;

  /// Rebuilds run one at a time: with the shell live during a load, a settings change or a
  /// download could otherwise start a second load that finishes first and is then replaced.
  Future<void> _rebuildHarness() {
    final previous = _rebuilding ?? Future<void>.value();
    final next = previous.then((_) {}, onError: (_) {}).then((_) => _buildHarness());
    _rebuilding = next;
    return next;
  }

  Future<void> _buildHarness() async {
    final old = _edge;
    _edge = null;
    harness = null;
    await voice.cancel();
    // Never close the model under an answer or a transcription.
    await _modelUse;
    await old?.close();
    _helperOnDevice = settings.engine == EngineKind.device;
    final engine = _helperOnDevice ? await _device() : _ollama();
    if (engine == null) {
      notifyListeners();
      _releaseHeld();
      return;
    }
    harness = Harness(
      db: db,
      engine: engine,
      systemPrompt: systemPrompt,
      tier: settings.tier,
      translation: settings.translation,
    );
    helperState = const HelperReady();
  }

  LlmEngine _ollama() => OllamaEngine(
    model: settings.model,
    baseUrl: settings.ollamaUrl,
    numCtx: settings.tier.contextWindow,
  );

  /// Sets [helperState] on the way, except ready, which waits until the harness exists.
  Future<LlmEngine?> _device() async {
    final m = settings.deviceModel;
    try {
      helperState = const HelperChecking();
      if (!await EdgeAiEngine.isInstalled(m, modelsDir)) {
        helperState = const HelperNotInstalled();
        return null;
      }
      helperState = const HelperLoading();
      return _edge = await EdgeAiEngine.load(m, settings.tier);
    } catch (e) {
      debugPrint('The helper did not load: $e');
      helperState = HelperFailed(helperLoadFailed, detail: e.toString());
      return null;
    }
  }

  /// Model files Berea hosts stay here, since the plugin registers their path and does not copy.
  Directory get modelsDir => Directory('${supportDir.path}/models');

  /// Whether the user agreed to the current terms, which a Gemma download needs.
  bool get termsAccepted => prefs.getInt('termsAccepted') == termsVersion;

  Future<void> acceptTerms() => prefs.setInt('termsAccepted', termsVersion);

  bool _downloadStarting = false;

  /// Applies [draft] and downloads its model. A second request while one is under way, such as a
  /// double tap, does nothing.
  Future<void> downloadModelFor(Settings draft) async {
    if (_downloadStarting || deviceState == DeviceModelState.downloading) return;
    _downloadStarting = true;
    try {
      await updateSettings(draft);
      await downloadDeviceModel();
    } finally {
      _downloadStarting = false;
    }
  }

  Future<void> downloadDeviceModel() async {
    final m = settings.deviceModel;
    if (m.notice != null && !termsAccepted) return;
    if (deviceState == DeviceModelState.downloading) return;
    // A model that failed to load may have a damaged file, so its hash is checked again.
    final repair = deviceState == DeviceModelState.failed;
    // The plugin reports a percent; the size comes from the pinned source when Berea hosts it.
    final total = m.source?.bytes;
    helperState = HelperDownloading(0, total: total);
    try {
      await EdgeAiEngine.download(
        m,
        modelsDir: modelsDir,
        recheck: repair,
        onProgress: (p) {
          // The plugin repeats a percent for every chunk; redraw the app only when it moves.
          if (p == downloadProgress) return;
          helperState = HelperDownloading(p / 100, total: total);
        },
      );
      await _rebuildHarness();
    } catch (e) {
      debugPrint('The helper download stopped: $e');
      helperState = HelperFailed(helperDownloadFailed, detail: e.toString());
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

  /// Transcribes a spoken question with the loaded Gemma 4 model; the audio goes in memory.
  Future<String> transcribeVoice(Uint8List wav) async {
    final edge = _edge;
    if (edge == null || !edge.hearsAudio) {
      throw StateError('The on-device model cannot hear audio.');
    }
    return useModel(() => edge.transcribe(wav));
  }

  /// Runs [answer] through [useModel] unless the model is busy or recording; null when nothing ran.
  Future<T?> runExclusive<T>(Future<T> Function(Harness h) answer) async {
    final h = harness;
    if (h == null || !ready) return null;
    return useModel(() => answer(h));
  }

  Future<void> send(String question) async {
    final h = harness;
    if (!ready) return;
    final style = settings.briefFirst ? AnswerStyle.brief : AnswerStyle.full;
    final turn = ChatTurn(question, style: style);
    turns.add(turn);
    if (h == null) return _hold(turn);
    await useModel(() => _answer(h, turn));
  }

  /// A question sent while the helper loads, and what completes once it is answered or dropped.
  ChatTurn? _held;
  Completer<void>? _heldDone;

  Future<void> _hold(ChatTurn turn) {
    _held = turn;
    _heldDone = Completer<void>();
    notifyListeners();
    return _heldDone!.future;
  }

  /// Forgets a held question whose study was cleared away.
  void _dropHeld() {
    final done = _heldDone;
    _held = null;
    _heldDone = null;
    done?.complete();
  }

  /// Answers the held question once the helper settles, or says in plain words why it cannot.
  void _releaseHeld() {
    final turn = _held;
    final done = _heldDone;
    if (turn == null || done == null || helperComing) return;
    _held = null;
    _heldDone = null;
    final h = harness;
    if (h == null || busy) {
      turn.error = switch (_helper) {
        HelperFailed(:final reason) => reason,
        _ => helperNotAvailable,
      };
      notifyListeners();
      done.complete();
      return;
    }
    done.complete(useModel(() => _answer(h, turn)));
  }

  /// Whether [turn] is the newest answer, so the full study can follow it. A full study that
  /// failed does not count; it is removed when the reader tries again.
  bool canGoDeeperFrom(ChatTurn turn) {
    final at = turns.indexOf(turn);
    return at >= 0 && turn.canGoDeeper && turns.skip(at + 1).every((later) => later.failedDeeper);
  }

  /// Writes the full study for [brief], which stays above it. The brief answer leaves the
  /// harness history, so a follow-up question sees one answer to this one.
  Future<void> goDeeper(ChatTurn brief) async {
    final h = harness;
    if (h == null || !ready || !canGoDeeperFrom(brief)) return;
    turns.removeRange(turns.indexOf(brief) + 1, turns.length);
    brief.markDeeperAsked();
    final turn = ChatTurn(brief.question, deeper: true);
    turns.add(turn);
    await useModel(() => _answer(h, turn));
    if (turn.failedDeeper) brief.markDeeperFailed();
  }

  Harness? _answering;

  /// True while a question is being answered, which the Stop button can end.
  bool get answering => busy && turns.isNotEmpty && !turns.last.done && turns.last.error == null;

  /// Whether the answer being written can be stopped, and has not been asked to stop yet.
  bool get canStopAnswer {
    final Object? engine = _answering?.engine;
    return answering && engine is StoppableEngine && !turns.last.stopped;
  }

  /// Ends the answer being written early. It is the harness that began the answer that stops,
  /// even if a settings change has since replaced the current one.
  Future<void> stopAnswer() async {
    final h = _answering;
    if (h == null || !canStopAnswer) return;
    turns.last.markStopped();
    notifyListeners();
    await h.stop();
  }

  Future<void> _answer(Harness h, ChatTurn turn) async {
    _answering = h;
    try {
      final result = await h.ask(
        turn.question,
        onToken: turn.append,
        onContext: turn.read,
        style: turn.style,
        replacePrevious: turn.deeper,
      );
      turn.take(result.guard);
      // An answer stopped before it wrote anything leaves no empty message in the saved study.
      if (turn.answer.trim().isEmpty) return;
      conversationId ??= study.createConversation(turn.question);
      study.addMessage(conversationId!, 'user', turn.shownQuestion, const []);
      study.addMessage(conversationId!, 'assistant', turn.answer, turn.verified);
    } catch (e) {
      turn.error = e.toString();
    } finally {
      _answering = null;
    }
  }

  final _notebookChats = <int, NotebookChat>{};

  /// The conversation of notebook [id], kept while the app runs so an answer that finishes after
  /// its screen closed is still shown; read again after a restore replaced the notebooks.
  NotebookChat notebookChat(int id) {
    final kept = _notebookChats[id];
    if (kept != null && kept.epoch == notebooks.epoch) return kept;
    return _notebookChats[id] = NotebookChat(
      store: notebooks,
      notebookId: id,
      answer: (q, history, onToken) => answerInNotebook(id, q, history, onToken),
      ready: () => harness != null,
    );
  }

  /// The Ollama host notebook answers go to when it is not this device, else null.
  String? get offDeviceHost {
    if (settings.engine != EngineKind.ollama) return null;
    final host = Uri.tryParse(settings.ollamaUrl)?.host.toLowerCase() ?? '';
    final local =
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host == '::1' ||
        host == '[::1]' ||
        host.startsWith('127.');
    return local ? null : (host.isEmpty ? settings.ollamaUrl : host);
  }

  /// Answers [question] inside notebook [notebookId] from its sources, pinned ones first, and
  /// installed commentary on the passages in view, after [history]. Null when the engine is
  /// missing or busy with another answer.
  Future<TurnResult?> answerInNotebook(
    int notebookId,
    String question,
    List<ChatMessage> history,
    void Function(String token) onToken,
  ) => runExclusive((base) {
    final h = Harness(
      db: db,
      engine: base.engine,
      systemPrompt: systemPrompt,
      tier: settings.tier,
      translation: settings.translation,
      notebook: true,
    )..history.addAll(history);
    final sources = notebookSources(
      index: NotebookIndex(notebooks.db, notebookId),
      question: question,
      tier: settings.tier,
      pinned: notebooks.pinnedSources(notebookId),
      commentary: commentary.library,
    );
    return h.ask(question, sources: sources, onToken: onToken);
  });

  void clear() {
    _dropHeld();
    turns.clear();
    harness?.resetConversation();
    conversationId = null;
    notifyListeners();
  }
}
