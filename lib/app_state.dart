import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daily_reminder.dart';
import 'device.dart';
import 'helper_cleanup.dart';
import 'backup.dart';
import 'commentary_packs.dart';
import 'notebook_store.dart';
import 'pinned_download.dart';
import 'reminder_platform.dart';
import 'plans.dart';
import 'prayer_plan_store.dart';
import 'prayer_sheet.dart' show passageText;
import 'prayer_store.dart';
import 'prayer_today.dart';
import 'study_store.dart';
import 'today.dart';

/// What a reader chooses in Settings.
class Settings {
  final String translation;
  const Settings({this.translation = defaultTranslation});

  Settings copyWith({String? translation}) => Settings(translation: translation ?? this.translation);

  static Settings load(SharedPreferences p) =>
      Settings(translation: p.getString('translation') ?? defaultTranslation);

  /// Older builds kept the model's settings and a Hugging Face token here; nothing reads them now.
  static Future<void> dropLegacyKeys(SharedPreferences p) async {
    for (final key in const ['hfToken', 'engine', 'ollamaUrl', 'model', 'deviceModelId', 'tier', 'briefFirst']) {
      await p.remove(key);
    }
  }

  Future<void> save(SharedPreferences p) => p.setString('translation', translation);
}

class ReaderMessage implements Exception {
  final String message;
  const ReaderMessage(this.message);

  @override
  String toString() => message;
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

const notesOpenFailed =
    'Berea could not open your notes. They are still on this device. Close Berea and open it '
    'again, and if this keeps happening, restart the device and try once more.';

const bibleNoSpace =
    'There is not enough space on this device to set up the Bible. Free about 85 MB and open '
    'Berea again.';

/// The notes version the merge starts from, which StudyStore keeps private.
const _beforeNotesMerge = 2;

/// The error code for a full disk on Android, iOS, macOS and Linux.
const _noSpaceErrno = 28;
const _searchMmapBytes = 256 * 1024 * 1024;

/// Plain words for [e], which a reader sees: the message of a failure Berea words itself,
/// otherwise [fallback]. The raw error goes to the debug log only.
String plainFailure(Object e, String fallback) {
  debugPrint('$fallback ($e)');
  return switch (e) {
    BackupException(:final message) ||
    StartupFailure(:final message) ||
    ReaderMessage(:final message) => message,
    _ => fallback,
  };
}

class AppState extends ChangeNotifier {
  late final BibleDb db;
  late final SharedPreferences prefs;
  late Settings settings;
  late final StudyStore study;

  /// Notebooks share study.sqlite, so they are backed up and restored with the notes.
  late final NotebookStore notebooks = NotebookStore(study.db);

  /// Prayers share study.sqlite, so they are backed up and restored with the notes.
  late final PrayerStore prayers = PrayerStore(study.db);
  late final PrayerPlanStore prayerPlans = PrayerPlanStore(study.db);

  /// Said once after an update that removed the helper or the chat; null otherwise.
  String? upgradeNotice;

  /// The prayer lines bundled with the app. Empty when the file cannot be read, so Prayer still
  /// works without them.
  PrayerContent prayerContent = PrayerContent.empty;
  late final Directory supportDir;

  /// Optional public domain commentaries the user has downloaded.
  late final CommentaryShelf commentary;


  int readerBook = 1;
  int readerChapter = 1;

  /// Verse the reader should scroll to and mark once, then clear.
  int? readerTargetVerse;

  /// Second translation shown under or beside the first in the reader. Null when off.
  String? parallelTranslation;



  /// Opens the Bible, notes and settings: everything the first frame needs. The helper loads
  /// later, from [startHelper]. [onFirstSetup] hears when the Bible is being copied into place,
  /// on first launch and after an update. Overrides let a test run the real app without opening
  /// the user's data.
  static Future<AppState> bootstrap({
    Directory? supportDir,
    SharedPreferences? prefs,
    VoidCallback? onFirstSetup,
    PrayerContent? prayerContent,
  }) async {
    final s = AppState();
    s.supportDir = supportDir ?? await getApplicationSupportDirectory();
    await excludeFromBackup(s.supportDir);
    s.db = BibleDb.open(await _ensureDb(s.supportDir, onFirstSetup));
    s.study = openStudy('${s.supportDir.path}/study.sqlite');
    s.prayerContent = prayerContent ?? await _loadPrayerContent();
    // Tests give their own support folder and never touch the notification plugin.
    if (supportDir == null && LocalNotificationsPlatform.supported) {
      s.reminderPlatform = LocalNotificationsPlatform();
    }
    s.prefs = prefs ?? await SharedPreferences.getInstance();
    s.upgradeNotice = upgradeNoticeText(
      freedBytes: await removeHelperFiles(s.supportDir, s.prefs),
      chatsDeleted: s.study.chatsDeleted,
    );
    await Settings.dropLegacyKeys(s.prefs);
    s.settings = Settings.load(s.prefs);
    s._loadReader();
    s.parallelTranslation = s.prefs.getString('parallelTranslation');
    s._restoreImports();
    s._keepTranslationValid();
    s.db.attachFullLexicon(s.lexiconPackPath);
    s.commentary = CommentaryShelf(Directory('${s.supportDir.path}/commentary'), s.touch);
    return s;
  }


  static Future<PrayerContent> _loadPrayerContent() async {
    try {
      final json = jsonDecode(await rootBundle.loadString('assets/prayers.json'));
      return PrayerContent.fromJson((json as Map).cast());
    } on Object catch (e) {
      debugPrint('The prayer lines did not load: $e');
      return PrayerContent.empty;
    }
  }

  /// Opens the notes database. The notes merge first writes a safety copy beside it; if that
  /// copy cannot be written the store throws before migrating, and Berea stops with [StartupFailure]
  /// rather than open notes it could not protect. Only that failure asks for space.
  @visibleForTesting
  static StudyStore openStudy(String path) {
    final Database raw;
    try {
      raw = sqlite3.open(path);
    } on Object catch (e) {
      debugPrint('The notes database did not open: $e');
      throw const StartupFailure(notesOpenFailed);
    }
    try {
      return StudyStore(raw);
    } on Object catch (e) {
      debugPrint('The notes database did not open: $e');
      final copyFailed = _safetyCopyMissing(raw, path);
      raw.dispose();
      throw StartupFailure(copyFailed ? notesCopyFailed : notesOpenFailed);
    }
  }

  /// Whether the notes still wait for the merge and its safety copy was not written, which is
  /// what a full disk leaves.
  static bool _safetyCopyMissing(Database raw, String path) {
    try {
      final version = raw.select('PRAGMA user_version').first.values.first as int;
      return version <= _beforeNotesMerge && !File('$path$preNotesMergeSuffix').existsSync();
    } on Object {
      return false;
    }
  }


  /// Copies the bundled database next to the app when the bundled build changes. The build
  /// stamp is a separate tiny asset, so a normal launch never loads the 81 MB database.
  static Future<String> _ensureDb(Directory dir, VoidCallback? onFirstSetup) async {
    final file = File('${dir.path}/berea.sqlite');
    final stamp = File('${dir.path}/berea.sqlite.asset');
    final bundled = (await rootBundle.loadString('assets/berea.sqlite.version')).trim();
    final current = stamp.existsSync() ? stamp.readAsStringSync() : null;
    if (!file.existsSync() || current != bundled) {
      onFirstSetup?.call();
      final data = await rootBundle.load('assets/berea.sqlite');
      final part = File('${file.path}.part');
      try {
        await part.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        // Renamed only once whole, so a copy cut short never leaves a Bible that opens half-empty.
        await part.rename(file.path);
        await stamp.writeAsString(bundled);
      } on FileSystemException catch (e) {
        debugPrint('The Bible was not copied into place: $e');
        // A cut-short copy would keep taking the room the next attempt needs.
        if (part.existsSync()) part.deleteSync();
        // The stamp is written last, so a copy cut short is made again on the next launch.
        if (e.osError?.errorCode == _noSpaceErrno) throw const StartupFailure(bibleNoSpace);
        rethrow;
      }
    }
    return file.path;
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
      throw ReaderMessage('Use 1 to 8 capital letters or digits for the code, not "$code".');
    }
    if (db.bundledTranslations().contains(code)) {
      throw ReaderMessage('$code is built in. Choose another code.');
    }
  }

  /// Searches the Bible off the UI isolate, on a read-only connection of its own, so a slow
  /// search cannot freeze the screen. A database held in memory is searched in place.
  Future<SearchResult> searchVerses(String query, {required String translation, int perGroup = 100}) {
    final path = db.filePath;
    if (path == null) {
      return Future.value(db.searchResult(query, translation: translation, perGroup: perGroup));
    }
    return Isolate.run(() {
      final reader = BibleDb(sqlite3.open(path, mode: OpenMode.readOnly));
      // Lets the system's file cache serve the index instead of this connection's small one.
      reader.db.execute('PRAGMA mmap_size = $_searchMmapBytes');
      try {
        return reader.searchResult(query, translation: translation, perGroup: perGroup);
      } finally {
        reader.close();
      }
    });
  }

  /// Imports a user-owned translation from CSV, USFM, OSIS, Zefania or a zip of those, and keeps
  /// a normalised CSV copy so it survives database rebuilds. Parsing runs off the UI isolate, and
  /// an existing copy is only replaced once the new one has imported. Returns the verse count.
  Future<int> importTranslation(List<({String name, Uint8List bytes})> files, String code) async {
    validateImportCode(code);
    final rows = await Isolate.run(
      () => [for (final f in files) ...parseBibleFile(f.name, f.bytes)],
    );
    if (rows.isEmpty) throw const ReaderMessage('No verses were found in those files.');
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

  /// John: where the Bible opens the very first time.
  static const firstOpenBook = 43;

  /// The verse the reader stopped at in an earlier session, and when; marked once on opening.
  int? resumeVerse;
  DateTime? resumeAt;

  /// Today's card shows in full on the first look of the day, then folds to one line.
  bool todayCardFull = false;

  /// Asks the shell to show Plans.
  final openPlansRequest = ValueNotifier<int>(0);

  /// Asks the shell to show Search, with the keyboard up.
  final openSearchRequest = ValueNotifier<int>(0);

  void openSearch() => openSearchRequest.value++;

  /// Bumped when what Prayer shows for today may have changed: a new day, a plan started or stopped
  /// or a restore. The Prayer place listens to this, not to every change of the app.
  final dayChanged = ValueNotifier<int>(0);

  /// The reader keys are written at once, so a first open that never turns a page is still
  /// remembered as opened.
  void _loadReader() {
    final firstOpen = !prefs.containsKey('readerBook');
    readerBook = prefs.getInt('readerBook') ?? firstOpenBook;
    readerChapter = prefs.getInt('readerChapter') ?? 1;
    prefs.setInt('readerBook', readerBook);
    prefs.setInt('readerChapter', readerChapter);
    resumeVerse = firstOpen ? null : prefs.getInt('readerVerse');
    resumeAt = DateTime.tryParse(prefs.getString('readerReadAt') ?? '');
    openTodayIfNewDay();
  }

  /// Unfolds today's card on the first look of a new day; true when it did.
  bool openTodayIfNewDay() {
    final today = dayKey(DateTime.now());
    if (prefs.getString('todayCardFullOn') == today) return false;
    todayCardFull = true;
    prefs.setString('todayCardFullOn', today);
    dayChanged.value++;
    notifyListeners();
    return true;
  }

  /// The verse at the top of the reader, so the next open resumes there.
  void rememberVerse(int verse) {
    prefs.setInt('readerVerse', verse);
    prefs.setString('readerReadAt', DateTime.now().toIso8601String());
  }

  void setReader(Book book, int chapter, [int? verse]) {
    readerBook = book.id;
    readerChapter = chapter;
    readerTargetVerse = verse;
    prefs.setInt('readerBook', book.id);
    prefs.setInt('readerChapter', chapter);
    rememberVerse(verse ?? 1);
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

  /// Switching from a running plan starts the new one afresh. With none running, ticks the
  /// plan already has (restored from a backup, or kept from before it stopped) stay.
  void startPlan(ReadingPlan plan) {
    if (activePlan != null) study.clearPlan(plan.id);
    _setPlan(plan.id, DateTime.now());
    dayChanged.value++;
    notifyListeners();
  }

  void _setPlan(String id, DateTime start) {
    prefs.setString('activePlan', id);
    prefs.setString('activePlanStart', start.toIso8601String());
  }

  void stopPlan() {
    prefs.remove('activePlan');
    prefs.remove('activePlanStart');
    dayChanged.value++;
    notifyListeners();
  }

  List<List<Ref>> planSchedule(ReadingPlan plan) => plan.schedule();

  DateTime get planStart =>
      DateTime.tryParse(prefs.getString('activePlanStart') ?? '') ?? DateTime.now();

  /// Day of [plan] for today, counting the start day as day 1 and stopping at the last day.
  int planDay(ReadingPlan plan, {DateTime? on}) =>
      (daysBetween(planStart, on ?? DateTime.now()) + 1).clamp(1, plan.days);

  /// The running plan's ticks against its days, or null when no plan runs.
  PlanProgress? get planProgress {
    final plan = activePlan;
    return plan == null ? null : PlanProgress(plan, study.planChaptersDone(plan.id), planDay(plan));
  }

  /// Today's chapters if a plan is running.
  List<Ref>? get todaysReading {
    final plan = activePlan;
    return plan == null ? null : planSchedule(plan)[planDay(plan) - 1];
  }

  /// The first verse of the plan's reading for [date], which is the verse shown for the day.
  /// Null when no plan runs: nothing stands in for it.
  Ref? readingVerse(DateTime date) {
    final plan = activePlan;
    if (plan == null) return null;
    final first = planSchedule(plan)[planDay(plan, on: date) - 1].firstOrNull;
    return first == null ? null : Ref(first.book, first.chapter, 1, 1);
  }

  /// Today's prayer: a line from the chapters of today's plan.
  TodayPrayer? get prayerOfTheDay => prayerOn(DateTime.now());

  /// The prayer for [date]: a line from the reading plan's chapters that day; null with no plan.
  TodayPrayer? prayerOn(DateTime date) {
    final plan = activePlan;
    if (plan == null) return null;
    final day = planDay(plan, on: date);
    return todaysPrayer(prayerContent, reading: planSchedule(plan)[day - 1], day: day);
  }

  /// The daily notification the reader chose, kept on this device. Off until turned on.
  ReminderSettings get reminder => ReminderSettings(
    on: prefs.getBool('reminderOn') ?? false,
    minutes: prefs.getInt('reminderMinutes') ?? defaultReminderMinutes,
    referenceOnly: prefs.getBool('reminderReferenceOnly') ?? false,
  );

  /// How notifications are scheduled here; null where they are not offered, and in tests.
  ReminderPlatform? reminderPlatform;

  /// Turns the daily notification on at [minutes], asking to allow notifications first. False
  /// when the person says no or there is nothing to schedule with; nothing is changed then.
  Future<bool> turnOnReminder(int minutes, {required bool referenceOnly}) => _reminderRun(() async {
    final platform = reminderPlatform;
    if (platform == null) return false;
    final chosen = ReminderSettings(on: true, minutes: minutes, referenceOnly: referenceOnly);
    try {
      if (!await platform.requestPermission()) return false;
      // Scheduled before saved, so a failure leaves the earlier choice as it was.
      await _scheduleReminder(platform, chosen);
      await prefs.setBool('reminderOn', true);
      await prefs.setInt('reminderMinutes', minutes);
      await prefs.setBool('reminderReferenceOnly', referenceOnly);
    } on Object catch (e) {
      debugPrint('The daily notification could not be turned on: $e');
      return false;
    } finally {
      notifyListeners();
    }
    return true;
  });

  Future<void> turnOffReminder() => _reminderRun(() async {
    await prefs.setBool('reminderOn', false);
    try {
      await reminderPlatform?.replaceAll(const []);
    } on Object catch (e) {
      debugPrint('The daily notification could not be cleared: $e');
    } finally {
      notifyListeners();
    }
  });

  /// Schedules the next days of notifications again, as when Berea opens or the time changes.
  /// If the person has since turned notifications off in the system, the schedule is dropped.
  Future<void> syncReminder() => _reminderRun(() async {
    final platform = reminderPlatform;
    if (platform == null) return;
    try {
      await _scheduleReminder(platform, reminder);
    } on Object catch (e) {
      debugPrint('The daily notification could not be scheduled: $e');
    }
  });

  /// Reminder work runs one job at a time, each reading the settings when it starts, so a sync
  /// that began before Turn off cannot schedule from a copy that was on.
  Future<void>? _reminderQueue;

  Future<T> _reminderRun<T>(Future<T> Function() job) {
    final run = (_reminderQueue ?? Future<void>.value()).then((_) => job());
    _reminderQueue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _scheduleReminder(ReminderPlatform platform, ReminderSettings settings) async {
    // Off schedules nothing: turning it off already cancelled, and the plugin is not loaded for
    // readers who never turned it on.
    if (!settings.on) return;
    if (!await platform.allowed()) {
      await platform.replaceAll(const []);
      return;
    }
    await platform.replaceAll(
      buildReminders(
        now: DateTime.now(),
        settings: settings,
        verseOn: readingVerse,
        textOf: (v) => passageText(db.passage(v, translation: this.settings.translation)),
      ),
    );
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
      throw const ReaderMessage('That file is too large to be a Berea lexicon pack.');
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
      if (!ok) throw const ReaderMessage('That file is not a Berea lexicon pack.');
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

  Future<Uint8List> backup(String passphrase) => createBackup(
    study,
    importedTranslations,
    passphrase,
    plan: switch (activePlan) {
      final plan? => (id: plan.id, start: planStart),
      null => null,
    },
  );

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
    // The restored ticks belong to the plan that was running; an older backup leaves it be.
    if (contents.plan case final plan?) _setPlan(plan.id, plan.start);
    // A source still being read belongs to a notebook id the backup may have reused.
    if (contents.hasNotebooks) notebooks.cancelAll();
    // Restoring an older backup merges its notes into notebooks, which may add one.
    notebooks.refresh();
    prayers.refresh();
    prayerPlans.refresh();
    dayChanged.value++;
    _keepTranslationValid();
    return skipped;
  }

  /// Keeps the reader's choices (the translation) and tells listeners.
  Future<void> updateSettings(Settings next) async {
    settings = next;
    await next.save(prefs);
    notifyListeners();
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



  /// Set to a notebook's id to open it in Notes, under the bar or beside the sidebar, so the
  /// places stay in reach; the shell sets it back to null once it has opened it.
  final openNotebookRequest = ValueNotifier<int?>(null);

  void openNotebook(int id) => openNotebookRequest.value = id;


  /// Notes and highlights change outside this class; callers poke listeners through here. A
  /// first note on a verse or a saved study page can create the notes on verses notebook.
  void touch() {
    notebooks.refresh();
    notifyListeners();
  }



  /// The study packet of notebook [id], built from its Bible readings, the verses its notes are
  /// on and the passages of its study pages, in that order.
  StudyPacket studyPacket(int id) => buildStudyPacket(db, [
    ...NotebookIndex(notebooks.db, id).passages(),
    for (final n in study.notebookNotes(id)) ?n.verse,
    for (final p in study.studyPages(notebookId: id)) p.ref,
  ], commentary: commentary.library);


  /// The readings of notebook [id] as its page lists them: a reading that links one of the
  /// notebook's own notes is shown, and read, as that note.
  List<NotebookSource> notebookReadings(int id) {
    final own = {for (final n in study.notebookNotes(id)) n.id};
    return [
      for (final r in notebooks.sources(id))
        if (r.noteId == null || !own.contains(r.noteId)) r,
    ];
  }

}
