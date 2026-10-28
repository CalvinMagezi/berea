import 'dart:async';
import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/chat_screen.dart';
import 'package:berea/commentary_packs.dart';
import 'package:berea/download_details_sheet.dart';
import 'package:berea/helper_download.dart';
import 'package:berea/models.dart';
import 'package:berea/note_dialog.dart';
import 'package:berea/notebook_store.dart';
import 'package:berea/notebooks_screen.dart';
import 'package:berea/past_questions.dart';
import 'package:berea/pinned_download.dart';
import 'package:berea/settings_sheet.dart';
import 'package:berea/study_store.dart';
import 'package:berea/voice.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/bible.dart';

class _Answer implements LlmEngine {
  final asked = <List<ChatMessage>>[];
  String reply = 'Grace is a gift (John 3:16, BSB).';

  @override
  String get name => 'answer';

  @override
  Stream<String> generate(List<ChatMessage> messages, {required int maxTokens}) {
    asked.add(messages);
    return Stream.value(reply);
  }
}

/// Writes its answer only when [finish] is called, as a slow phone would.
class _Held implements LlmEngine {
  final _answer = StreamController<String>();

  @override
  String get name => 'held';

  @override
  Stream<String> generate(List<ChatMessage> messages, {required int maxTokens}) => _answer.stream;

  Future<void> finish() async {
    _answer.add('Grace is a gift (John 3:16, BSB).');
    await _answer.close();
  }
}

class _NoRecorder implements AudioRecorder {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _gb = bytesPerDownloadGb;

/// A model download that never arrives, and ends only when stopped.
Future<void> _stalls(
  EdgeModel m, {
  required Directory modelsDir,
  required void Function(int received, int total) onProgress,
  Future<void>? stop,
  bool recheck = false,
}) async {
  await stop;
  throw const DownloadStopped();
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('berea-study-test'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// A hand-built app on this device's helper, with [helper] where it stands.
  Future<AppState> app({HelperState helper = const HelperNotInstalled(), LlmEngine? engine}) async {
    SharedPreferences.setMockInitialValues({});
    final bible = testBible();
    final s = AppState()
      ..db = bible
      ..study = StudyStore(sqlite3.openInMemory())
      ..prefs = await SharedPreferences.getInstance()
      ..settings = Settings(engine: EngineKind.device)
      ..systemPrompt = 'SYS'
      ..commentary = CommentaryShelf(Directory('${dir.path}/commentary'), () {})
      ..voice = VoiceInput(
        transcribe: (_) async => '',
        recorder: _NoRecorder(),
        cacheDir: () async => dir,
      )
      ..supportDir = dir
      ..mobileDataNow = (() async => false)
      ..mobileDataChanges = (() => const Stream.empty())
      ..modelDownload = _stalls;
    if (engine != null) s.harness = Harness(db: bible, engine: engine, systemPrompt: 'SYS');
    s.helperState = helper;
    return s;
  }

  Future<void> pumpStudy(WidgetTester tester, AppState s) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ChatScreen(state: s)));
  }

  group('the Wi-Fi rule', () {
    test('only mobile data alone holds a download', () {
      expect(mobileOnly([ConnectivityResult.mobile]), isTrue);
      expect(mobileOnly([ConnectivityResult.vpn, ConnectivityResult.mobile]), isTrue);
      expect(mobileOnly([ConnectivityResult.mobile, ConnectivityResult.wifi]), isFalse);
      expect(mobileOnly([ConnectivityResult.ethernet]), isFalse, reason: 'a Mac on a cable');
      expect(mobileOnly([ConnectivityResult.other]), isFalse);
      expect(mobileOnly([ConnectivityResult.none]), isFalse, reason: 'no connection fails');
    });

    test('Wi-Fi only holds on mobile data unless mobile data was chosen once', () {
      expect(holdForWifi(wifiOnly: true, mobileOnly: true, mobileAllowed: false), isTrue);
      expect(holdForWifi(wifiOnly: true, mobileOnly: true, mobileAllowed: true), isFalse);
      expect(holdForWifi(wifiOnly: false, mobileOnly: true, mobileAllowed: false), isFalse);
      expect(holdForWifi(wifiOnly: true, mobileOnly: false, mobileAllowed: false), isFalse);
    });

    test('Wi-Fi only is on by default and remembered', () async {
      final s = await app();
      expect(s.wifiOnly, isTrue);
      await s.setWifiOnly(false);
      expect(s.wifiOnly, isFalse);
      expect(s.prefs.getBool(wifiOnlyKey), isFalse);
    });

    test('a moment on mobile data does not stop the download; lasting mobile data does', () async {
      var mobile = true;
      final net = StreamController<bool>();
      final s = await app()
        ..mobileDataNow = (() async => mobile)
        ..mobileDataChanges = (() => net.stream)
        ..mobileSettle = const Duration(milliseconds: 20);
      await s.downloadDeviceModel();
      s.helperState = HelperDownloading(0.9, model: edgeModels.first, total: 100);

      net.add(true);
      mobile = false;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect((s.helperState as HelperDownloading).moving, isTrue, reason: 'a Wi-Fi handoff');

      mobile = true;
      net.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect((s.helperState as HelperDownloading).waitingForWifi, isTrue);
      await net.close();
    });

    test('a settings change during a download leaves it showing', () async {
      final s = await app(helper: HelperDownloading(0.3, model: edgeModels.first, total: 100));
      await s.updateSettings(s.settings);
      expect(s.helperState, isA<HelperDownloading>());
    });

    test('turning Wi-Fi only back on over mobile data holds the download', () async {
      final s = await app(helper: HelperDownloading(0.3, model: edgeModels.first, total: 100))
        ..mobileDataNow = (() async => true);
      await s.setWifiOnly(true);
      expect((s.helperState as HelperDownloading).waitingForWifi, isTrue);
    });

    test('a download on mobile data waits for Wi-Fi, and pause and cancel leave it', () async {
      final s = await app()
        ..mobileDataNow = (() async => true);
      await s.downloadDeviceModel();
      final held = s.helperState as HelperDownloading;
      expect(held.waitingForWifi, isTrue);
      expect(held.total, s.settings.deviceModel.publishedBytes);
      expect(s.deviceState, DeviceModelState.downloading, reason: 'the ring stays on Study');

      s.pauseDownload();
      expect((s.helperState as HelperDownloading).paused, isTrue);
      s.cancelDownload();
      expect(s.helperState, isA<HelperNotInstalled>());
    });
  });

  group('download progress', () {
    test('maps received bytes onto the helper state', () {
      final h = HelperDownloading.at(11 * _gb ~/ 10, 26 * _gb ~/ 10, model: edgeModels.first);
      expect(h.bytes, 11 * _gb ~/ 10);
      expect(h.total, 26 * _gb ~/ 10);
      expect(h.percent, 42);
      expect(gbOf(h.total! - h.bytes!), '1.5');
      expect(
        HelperDownloading.at(5, 0, model: edgeModels.first).fraction,
        0,
        reason: 'an unknown size is not progress',
      );
      expect(
        HelperDownloading.at(12, 10, model: edgeModels.first).fraction,
        1,
        reason: 'never past the end',
      );
    });

    test('each model reports its pinned size', () {
      expect(edgeModelById('gemma-3-1b').publishedBytes, 584417280);
      expect(edgeModelById('gemma-4-e2b').publishedBytes, 2588147712);
    });
  });

  testWidgets('a download that failed or arrived damaged offers the helper choice again', (
    tester,
  ) async {
    for (final reason in [helperDownloadFailed, helperDownloadDamaged]) {
      final s = await app(helper: HelperFailed(reason));
      await pumpStudy(tester, s);
      expect(find.text(reason), findsOneWidget);
      expect(find.text('Suggested'), findsOneWidget, reason: reason);
    }
    final s = await app(helper: const HelperFailed(helperLoadFailed));
    await pumpStudy(tester, s);
    expect(find.text('Suggested'), findsNothing, reason: 'a load failure is repaired in settings');
  });

  testWidgets('with no helper, Study offers the choice with Wi-Fi only on and Keep reading', (
    tester,
  ) async {
    final s = await app();
    await pumpStudy(tester, s);
    expect(find.text('Ask Berea about the Bible'), findsOneWidget);
    expect(find.text('Suggested'), findsOneWidget);
    final wifi = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Download only on Wi-Fi'),
    );
    expect(wifi.value, isTrue);
    expect(find.textContaining('Download on Wi-Fi · 2.6 GB'), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'nothing can be asked yet');

    final before = s.openReaderRequest.value;
    await tester.tap(find.text('Keep reading'));
    expect(s.openReaderRequest.value, before + 1, reason: 'Keep reading goes to the Bible');
  });

  testWidgets('the Gemma terms page comes only before Gemma 3 1B', (tester) async {
    final s = await app();
    await pumpStudy(tester, s);
    await tester.tap(find.text('Gemma 3 1B'));
    await tester.pump();
    await tester.tap(find.textContaining('Download on Wi-Fi · 0.6 GB'));
    await tester.pumpAndSettle();
    expect(find.text('Before you download'), findsOneWidget);
    expect(find.text('Agree and download on Wi-Fi'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(s.termsAccepted, isFalse);
    expect(s.helperState, isA<HelperNotInstalled>());
    expect(edgeModels.where((m) => m.notice != null).map((m) => m.id), ['gemma-3-1b']);
  });

  testWidgets('a download keeps its own model: the details name it and settings cannot swap it', (
    tester,
  ) async {
    final s = await app(
      helper: HelperDownloading(0.42, model: edgeModelById('gemma-4-e2b'), total: 26 * _gb ~/ 10),
    );
    s.settings = s.settings.copyWith(deviceModelId: 'gemma-3-1b');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DownloadDetails(state: s)),
      ),
    );
    expect(find.text('Gemma 4 E2B · 2.6 GB'), findsOneWidget);
    expect(find.textContaining('and the file is checked before it is used.'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSettingsSheet(context, s),
            child: const Text('Settings'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    final engine = find.text('Engine');
    if (engine.evaluate().isNotEmpty) {
      await tester.ensureVisible(engine.first);
      await tester.tap(engine.first);
      await tester.pumpAndSettle();
    }
    final picker = tester.widget<DropdownButton<String>>(
      find.ancestor(
        of: find.text('Gemma 3 1B · 0.6 GB'),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    expect(picker.onChanged, isNull);
    expect(find.textContaining('Cancel it in Study to choose another model'), findsOneWidget);
  });

  testWidgets('download details show what it waits for, the size left, pause and cancel', (
    tester,
  ) async {
    final s = await app(
      helper: HelperDownloading(
        0.42,
        model: edgeModels.first,
        total: 26 * _gb ~/ 10,
        waitingForWifi: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDownloadDetails(context, s),
            child: const Text('Study'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();
    expect(find.text('Paused, waiting for Wi-Fi'), findsOneWidget);
    expect(find.text('1.1 of 2.6 GB · 1.5 GB to go'), findsOneWidget);
    expect(find.text('Use mobile data for the 1.5 GB left'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);

    await tester.tap(find.text('Cancel download'));
    await tester.pump();
    expect(s.helperState, isA<HelperNotInstalled>());
  });

  testWidgets('Study empty state suggests from where you stopped and has no verse of the day', (
    tester,
  ) async {
    final s = await app(helper: const HelperReady(), engine: _Answer())
      ..readerBook = 43
      ..readerChapter = 3;
    await pumpStudy(tester, s);
    expect(find.text('VERSE OF THE DAY'), findsNothing);
    expect(find.text('Study it'), findsNothing);
    expect(find.text('WHERE YOU STOPPED'), findsOneWidget);
    expect(find.textContaining('John 3'), findsOneWidget);
    expect(find.text('the Bible'), findsNothing, reason: 'the chip reads as one label');
    expect(find.textContaining('Asking about'), findsOneWidget);
  });

  testWidgets('the scope chip switches to a notebook, whose questions are saved in its scope', (
    tester,
  ) async {
    final engine = _Answer();
    final s = await app(helper: const HelperReady(), engine: engine);
    final id = s.notebooks.createNotebook('Romans with the youth');
    await pumpStudy(tester, s);

    expect(find.text('YOUR NOTEBOOKS'), findsOneWidget);
    await tester.tap(find.textContaining('Asking about'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Romans with the youth').last);
    await tester.pumpAndSettle();
    expect(s.studyScope.value, id);
    expect(find.text('Ask about this notebook'), findsOneWidget);
    expect(find.text('Reads its 0 notes and 0 readings, and the Bible.'), findsOneWidget);

    await tester.runAsync(() async {
      await s.send('What is grace?');
    });
    await tester.pump();
    final scoped = s.study.conversations(notebookId: id);
    expect(scoped.single.title, 'What is grace?');
    expect(scoped.single.notebookId, id);
    expect(s.study.conversations(), isEmpty, reason: 'nothing joined the Bible questions');
    expect(s.harness!.history, isEmpty, reason: 'the notebook answered, not the Bible harness');

    await tester.tap(find.textContaining('Asking about'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The Bible'));
    await tester.pumpAndSettle();
    expect(s.studyScope.value, isNull);
    expect(s.turns, isEmpty, reason: 'a study belongs to one scope');
  });

  testWidgets('a notebook answer reads, counts and opens the notes written in the notebook', (
    tester,
  ) async {
    final engine = _Answer();
    final s = await app(helper: const HelperReady(), engine: engine);
    final id = s.notebooks.createNotebook('Romans with the youth');
    final outline = s.study.addNotebookNote(
      id,
      'Thursday: open with the Bereans, who searched the Scriptures daily.',
      title: 'Outline for Thursday',
    );
    s.study.addNotebookNote(id, 'Agape, love', kind: keptWordKind);
    final source = (await tester.runAsync(
      () => s.notebooks.addSource(
        id,
        const SourceRequest(
          SourceKind.text,
          'Study notes',
          text: 'Romans 8 on suffering and glory.',
        ),
      ),
    ))!;
    s.setStudyScope(id);
    await pumpStudy(tester, s);
    expect(find.text('Reads its 2 notes and 1 reading, and the Bible.'), findsOneWidget);

    engine.reply = 'Open with the Bereans [N$outline §1] and glory [S$source §1].';
    await tester.runAsync(() => s.send('What is the outline for Thursday?'));
    await tester.pumpAndSettle();
    expect(engine.asked.single.last.content, contains('searched the Scriptures daily'));
    expect(s.turns.single.unverifiedSources, isEmpty);

    await tester.tap(find.text('N$outline §1 · Outline for Thursday'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditor), findsOneWidget);
    await Navigator.of(tester.element(find.byType(NoteEditor))).maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('S$source §1 · Study notes'));
    await tester.pumpAndSettle();
    expect(find.byType(SourceScreen), findsOneWidget);
    expect(find.text('Romans 8 on suffering and glory.'), findsOneWidget);
  });

  test('note text never goes to an Ollama server on another computer', () async {
    final engine = _Answer();
    final s = await app(helper: const HelperReady(), engine: engine);
    s.settings = Settings(engine: EngineKind.ollama, ollamaUrl: 'http://192.168.1.9:11434');
    final id = s.notebooks.createNotebook('Romans');
    s.study.addNotebookNote(id, 'Private thoughts on Thursday.', title: 'Thursday');
    s.setStudyScope(id);
    await s.send('What about Thursday?');
    expect(engine.asked.single.last.content, isNot(contains('Private thoughts')));
    expect(s.answerNoteCount(id), 0);
  });

  testWidgets('past questions list the saved studies and open one', (tester) async {
    final s = await app(helper: const HelperReady(), engine: _Answer());
    for (final q in ['Who were the Bereans?', 'What does John 3:16 teach?']) {
      final c = s.study.createConversation(q);
      s.study.addMessage(c, 'user', q, const []);
      s.study.addMessage(c, 'assistant', 'An answer to "$q".', const []);
    }
    await pumpStudy(tester, s);
    await tester.tap(find.byTooltip('Past questions'));
    await tester.pumpAndSettle();
    expect(find.text('Who were the Bereans?'), findsOneWidget);
    expect(find.text('What does John 3:16 teach?'), findsOneWidget);
    expect(find.textContaining('Today · the Bible'), findsNWidgets(2));

    await tester.tap(find.text('Who were the Bereans?'));
    await tester.pumpAndSettle();
    expect(find.byType(PastQuestions), findsNothing, reason: 'the page closes on opening one');
    expect(s.turns.single.question, 'Who were the Bereans?');
    expect(find.text('An answer to "Who were the Bereans?".'), findsOneWidget);
  });

  test('past question dates read as words', () {
    final now = DateTime(2026, 10, 28, 9);
    expect(askedWhen(DateTime(2026, 10, 28, 7), now: now), 'Today');
    expect(askedWhen(DateTime(2026, 10, 27, 23), now: now), 'Yesterday');
    expect(askedWhen(DateTime(2026, 10, 26), now: now), 'Mon');
    expect(askedWhen(DateTime(2026, 9, 3), now: now), '3 Sep');
  });

  test('opening a notebook question puts Study in its scope with its sources', () async {
    final s = await app(helper: const HelperReady(), engine: _Answer());
    final id = s.notebooks.createNotebook('Romans 8');
    final c = s.study.createConversation('How does 8:28 fit 8:18?', notebookId: id);
    s.study.addMessage(c, 'user', 'How does 8:28 fit 8:18?', const []);
    s.study.addMessage(c, 'assistant', 'Paul weighs them.', const []);
    s.openConversation(c);
    expect(s.studyScope.value, id);
    expect(s.turns.single.answer, 'Paul weighs them.');
  });

  testWidgets('Keep in a notebook files an answer through the shared Keep sheet', (tester) async {
    final s = await app(helper: const HelperReady(), engine: _Answer());
    final youth = s.notebooks.createNotebook('Romans with the youth');
    await tester.runAsync(() => s.send('What is grace?'));
    await pumpStudy(tester, s);
    await tester.tap(find.text('Keep in a notebook'));
    await tester.pumpAndSettle();
    expect(find.text('Show it beside John 3:16'), findsOneWidget, reason: 'the first cited verse');
    await tester.tap(find.text('Romans with the youth'));
    await tester.tap(find.widgetWithText(FilledButton, 'Keep'));
    await tester.pumpAndSettle();

    final note = s.study.notes().single;
    expect(note.notebookId, youth);
    expect(note.title, 'What is grace?');
    expect(note.text, contains('Grace is a gift'));
  });

  testWidgets('Ask about this notebook during an answer switches once the answer is finished', (
    tester,
  ) async {
    final engine = _Held();
    final s = await app(helper: const HelperReady(), engine: engine);
    final id = s.notebooks.createNotebook('Romans with the youth');
    await pumpStudy(tester, s);
    late Future<void> sent;
    await tester.runAsync(() async {
      sent = s.send('What is grace?');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(s.busy, isTrue);

    s.askAboutNotebook(id);
    await tester.pump();
    expect(s.studyScope.value, isNull, reason: 'the answer being written stays in its study');
    expect(
      find.text('Study will switch to Romans with the youth when this answer is finished.'),
      findsOneWidget,
    );

    await tester.runAsync(() async {
      await engine.finish();
      await sent;
    });
    await tester.pump();
    expect(s.studyScope.value, id);
    expect(s.pendingScope, isNull);
    expect(
      s.study.conversations().single.title,
      'What is grace?',
      reason: 'kept in Past questions',
    );
    expect(find.textContaining('Study will switch'), findsNothing);
  });
}
