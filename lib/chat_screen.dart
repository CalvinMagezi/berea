import 'dart:async';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'export.dart';
import 'download_details_sheet.dart';
import 'helper_setup.dart';
import 'markdown_lite.dart';
import 'past_questions.dart';
import 'settings_sheet.dart';
import 'setup_screen.dart';
import 'theme.dart';
import 'voice.dart';
import 'voice_composer.dart';

class ChatScreen extends StatefulWidget {
  final AppState state;

  /// Set when shown as the quick-chat sheet; adds a close button.
  final VoidCallback? onClose;
  const ChatScreen({super.key, required this.state, this.onClose});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  late final VoiceInput _voice = widget.state.voice;
  late final _follower = AnswerFollower(_scroll);
  var _voicePhase = VoicePhase.idle;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onChange);
    widget.state.pendingQuestion.addListener(_onPending);
    widget.state.studyScope.addListener(_onChange);
    _voice.addListener(_onVoice);
    // Opens at the newest turn, and follows an answer already streaming (the quick-chat sheet).
    _follower.follow(widget.state.turns.lastOrNull);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onChange);
    widget.state.pendingQuestion.removeListener(_onPending);
    widget.state.studyScope.removeListener(_onChange);
    _voice.removeListener(_onVoice);
    unawaited(_voice.release(this));
    _follower.dispose();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChange() {
    setState(() {});
    _follower.follow(widget.state.turns.lastOrNull);
  }

  /// A fresh transcript joins what was typed for the user to check; it is never sent by itself.
  void _onVoice() {
    // The timer ticks ten times a second; only a phase change concerns the whole screen.
    if (_voice.phase == _voicePhase) return;
    final entered = _voice.phase == VoicePhase.confirm;
    _voicePhase = _voice.phase;
    if (entered && _voice.ownedBy(this)) {
      final typed = _input.text.trim();
      _input.text = typed.isEmpty ? _voice.transcript : '$typed ${_voice.transcript}';
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
      _focus.requestFocus();
    }
    if (!_voice.inUse) _onPending();
    setState(() {});
  }

  /// A question from the reader waits while a voice question is being recorded or transcribed.
  void _onPending() {
    final q = widget.state.pendingQuestion.value;
    if (q == null || _voice.inUse) return;
    widget.state.pendingQuestion.value = null;
    _input.text = q;
    widget.state.ready ? _send() : _focus.requestFocus();
  }

  void _send() {
    final q = _input.text.trim();
    if (q.isEmpty || !widget.state.ready) return;
    if (_voice.ownedBy(this)) _voice.accept();
    _input.clear();
    widget.state.send(q);
    _focus.requestFocus();
  }

  /// Study answers once there is a helper; before that it shows the choice or the download.
  Widget? _withoutHelper(AppState s) => s.harness != null
      ? null
      : switch (s.helperState) {
          HelperNotInstalled() => HelperSetup(state: s, onKeepReading: _keepReading),
          HelperFailed(:final reason) when reason == helperDownloadFailed => HelperSetup(
            state: s,
            onKeepReading: _keepReading,
          ),
          HelperDownloading() => ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              DownloadDetails(state: s),
              const SizedBox(height: 8),
              TextButton(onPressed: _keepReading, child: const Text('Keep reading')),
            ],
          ),
          _ => null,
        };

  void _keepReading() => widget.state.openReaderRequest.value++;

  void _pick(String q) {
    _input.text = q;
    _send();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= pastQuestionsBreakpoint;
        final study = _study(context, s, wide: wide);
        if (!wide || _withoutHelper(s) != null) return study;
        return Row(
          children: [
            SizedBox(
              width: pastQuestionsWidth,
              child: SafeArea(
                right: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: SectionLabel('Past questions'),
                    ),
                    Expanded(child: PastQuestions(state: s)),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: study),
          ],
        );
      },
    );
  }

  Widget _study(BuildContext context, AppState s, {required bool wide}) {
    final setup = _withoutHelper(s);
    final scoped = s.studyScope.value != null;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.onClose == null,
        title: Text(
          'Study',
          style: TextStyle(fontFamilyFallback: scriptureFontFallback, fontSize: 24),
        ),
        actions: [
          if (setup == null && !wide)
            IconButton(
              tooltip: 'Past questions',
              icon: const Icon(Icons.history),
              onPressed: () => showPastQuestions(context, s),
            ),
          if (setup == null)
            IconButton(
              tooltip: 'New study',
              icon: const Icon(Icons.edit_note_outlined),
              onPressed: s.turns.isEmpty || s.busy ? null : s.clear,
            ),
          if (s.conversationId != null && setup == null)
            IconButton(
              tooltip: 'Export study as Markdown',
              icon: const Icon(Icons.ios_share),
              onPressed: () => saveMarkdown(
                'berea-study.md',
                studyMarkdown(s.study, s.db, s.conversationId!, s.settings.translation),
              ),
            ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune),
            onPressed: () => showSettingsSheet(context, s),
          ),
          if (widget.onClose != null)
            IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: widget.onClose),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: setup ?? _conversation(context, s, scoped: scoped),
        ),
      ),
    );
  }

  Widget _conversation(BuildContext context, AppState s, {required bool scoped}) => Column(
    children: [
      ScopeBar(state: s),
      Expanded(
        child: s.turns.isEmpty
            ? Suggestions(state: s, onPick: _pick)
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                itemCount: s.turns.length,
                itemBuilder: (_, i) => TurnView(
                  turn: s.turns[i],
                  db: s.db,
                  translation: s.settings.translation,
                  onDeeper: s.ready && s.canGoDeeperFrom(s.turns[i])
                      ? () => s.goDeeper(s.turns[i])
                      : null,
                ),
              ),
      ),
      if (s.harness == null) EngineNotice(state: s),
      VoiceStatusLine(_voice, owner: this),
      ChatInputBar(
        controller: _input,
        focus: _focus,
        busy: s.busy,
        canSend: !_voice.inUse,
        onSend: _send,
        onStop: s.canStopAnswer ? s.stopAnswer : null,
        hint: scoped ? 'Ask about this notebook' : ChatInputBar.bibleHint,
        mic: VoiceMicButton(
          voice: _voice,
          owner: this,
          support: voiceSupport(s.settings, s.deviceState, hearsAudio: s.deviceHearsAudio),
          modelFree: s.ready,
          onOpenSettings: () => showSettingsSheet(context, s),
        ),
      ),
    ],
  );
}

/// Past questions sit beside Study when the window has room for both.
const pastQuestionsBreakpoint = 900.0;
const pastQuestionsWidth = 256.0;

/// Suggestions stop at this many per section, so the list stays a glance.
const _suggestionsPerSection = 2;
const _notebookSuggestions = 3;

/// What Study is answering from, with the way to change it, and a line on what it reads.
class ScopeBar extends StatelessWidget {
  final AppState state;
  const ScopeBar({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scope = state.studyScope.value;
    final note = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ActionChip(
            avatar: Icon(scope == null ? Icons.menu_book_outlined : Icons.class_outlined, size: 18),
            label: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Asking about  '),
                  TextSpan(
                    text: scopeName(state, scope),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.expand_more, size: 18),
                  ),
                ],
              ),
            ),
            onPressed: state.canChangeScope ? () => _choose(context) : null,
          ),
          const SizedBox(height: 4),
          Text(_reads(scope), style: note),
          if ((scope, state.offDeviceHost) case (_?, final host?))
            Text(
              'Questions here send sections of your sources to the Ollama server at $host.',
              style: note,
            ),
        ],
      ),
    );
  }

  String _reads(int? scope) {
    if (scope != null) {
      final n = state.notebooks.notebook(scope)?.sourceCount ?? 0;
      return 'Reads its $n ${n == 1 ? 'source' : 'sources'} and the Bible.';
    }
    return switch (state.settings.engine) {
      EngineKind.device => '${state.settings.deviceModel.label} on this $deviceNoun.',
      EngineKind.ollama => switch (state.offDeviceHost) {
        final host? => 'Ollama at $host.',
        null => 'Ollama on this $deviceNoun.',
      },
    };
  }

  Future<void> _choose(BuildContext context) async {
    final current = state.studyScope.value;
    final picked = await showModalBottomSheet<({int? id})>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: SectionLabel('Asking about'),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('The Bible'),
              selected: current == null,
              onTap: () => Navigator.pop(sheet, (id: null)),
            ),
            for (final n in state.notebooks.notebooks())
              ListTile(
                leading: const Icon(Icons.class_outlined),
                title: Text(n.title),
                selected: current == n.id,
                onTap: () => Navigator.pop(sheet, (id: n.id)),
              ),
          ],
        ),
      ),
    );
    if (picked != null) state.setStudyScope(picked.id);
  }
}

/// Study with nothing asked yet: questions from today's reading, from where the reader stopped,
/// and about their notebooks.
class Suggestions extends StatelessWidget {
  final AppState state;
  final void Function(String) onPick;
  const Suggestions({super.key, required this.state, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final scope = state.studyScope.value;
    final sections = scope == null ? _bible() : _notebook(scope);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        for (final (label, rows) in sections)
          if (rows.isNotEmpty) ...[SectionLabel(label), ...rows, const SizedBox(height: 16)],
      ],
    );
  }

  List<(String, List<Widget>)> _bible() {
    final reading = state.todaysReading ?? const <Ref>[];
    final stopped = Ref(bookById(state.readerBook), state.readerChapter);
    return [
      (
        'From today\'s reading',
        [
          for (final r in reading.take(_suggestionsPerSection))
            _Suggestion(Icons.menu_book_outlined, 'What does ${r.label} teach?', onPick),
        ],
      ),
      (
        'Where you stopped',
        [
          _Suggestion(
            Icons.menu_book_outlined,
            'What is happening in ${stopped.label}, and why does it matter?',
            onPick,
          ),
        ],
      ),
      (
        'Your notebooks',
        [
          for (final n in state.notebooks.notebooks().take(_notebookSuggestions))
            _Suggestion(
              Icons.class_outlined,
              'Ask about ${n.title}',
              (_) => state.askAboutNotebook(n.id),
            ),
        ],
      ),
    ];
  }

  List<(String, List<Widget>)> _notebook(int id) {
    final title = scopeName(state, id);
    return [
      (
        'In this notebook',
        [
          _Suggestion(Icons.class_outlined, 'What are the main points of $title?', onPick),
          _Suggestion(
            Icons.class_outlined,
            'Which passages does $title come back to, and what do they say?',
            onPick,
          ),
        ],
      ),
    ];
  }
}

class _Suggestion extends StatelessWidget {
  final IconData icon;
  final String question;
  final void Function(String) onPick;
  const _Suggestion(this.icon, this.question, this.onPick);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onPick(question),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(child: Text(question)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A question and its answer, with chips for what the answer cites.
class TurnView extends StatelessWidget {
  final ChatTurn turn;
  final BibleDb db;
  final String translation;

  /// Opens a cited notebook source or commentary passage; notebook chats set it.
  final void Function(ShownSource source)? onSource;

  /// Asks for the full study after a brief answer; only the Study chat sets it.
  final VoidCallback? onDeeper;
  const TurnView({
    super.key,
    required this.turn,
    required this.db,
    required this.translation,
    this.onSource,
    this.onDeeper,
  });

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: turn, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SelectableText(turn.shownQuestion),
            ),
          ),
          const SizedBox(height: 16),
          if (turn.error != null)
            Text(turn.error!, style: TextStyle(color: scheme.error))
          else if (turn.answer.trim().isEmpty)
            _Waiting(
              turn.reading,
              status: turn.done
                  ? (turn.stopped ? null : 'The model wrote no answer. Try again.')
                  : (turn.stopped ? 'Stopping…' : 'Examining the Scriptures…'),
            )
          else
            MarkdownLite(turn.answer),
          if (turn.done) _Citations(turn, db, translation, onSource),
          if (turn.stopped && (turn.done || turn.answer.trim().isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                !turn.done
                    ? 'Stopping…'
                    : turn.answer.isEmpty
                    ? 'Stopped before an answer was written.'
                    : 'Stopped. Finished sentences are kept.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
          if (turn.canGoDeeper && onDeeper != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: onDeeper,
                  icon: const Icon(Icons.unfold_more),
                  label: const Text(goDeeperLabel),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A reader this close to the end is still reading the newest text, so the view keeps up.
const followSlack = 48.0;

/// Keeps a chat at its end while the newest answer streams in, unless the reader scrolled up.
class AnswerFollower {
  final ScrollController scroll;
  ChatTurn? _turn;

  /// Where the last jump put the view. A jump to the end of a lazy list can land short while its
  /// extent is still an estimate, and a view left there is still following.
  double? _jumpedTo;
  AnswerFollower(this.scroll);

  /// Call with the newest turn whenever the chat changes. A new turn scrolls to the end; any other
  /// change, or [last] growing, keeps the view at the end only if the reader is still there.
  void follow(ChatTurn? last) {
    if (identical(last, _turn)) return _keepUp();
    _detach();
    _turn = last?..addListener(_keepUp);
    _toEnd();
  }

  // Runs before the change is laid out, so the position says where the reader was.
  void _keepUp() {
    if (!scroll.hasClients) return;
    final p = scroll.position;
    if (p.pixels == _jumpedTo || p.maxScrollExtent - p.pixels <= followSlack) _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (scroll.hasClients) scroll.jumpTo(_jumpedTo = scroll.position.maxScrollExtent);
  });

  void _detach() => _turn?.removeListener(_keepUp);

  void dispose() {
    _detach();
    _turn = null;
  }
}

/// What the reader sees before the model's first word: the verses it is working from.
class _Waiting extends StatelessWidget {
  final List<Verse> reading;

  /// What the model is doing, or null once the answer ended with nothing written.
  final String? status;
  const _Waiting(this.reading, {required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final v in reading)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${v.label} ',
                      style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: v.text),
                  ],
                ),
                style: TextStyle(color: scheme.onSurface),
              ),
            ),
          if (status case final text?) Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Source chip labels stop here so one long file name cannot fill the row.
const _sourceChipMaxWidth = 280.0;

class _Citations extends StatelessWidget {
  final ChatTurn g;
  final BibleDb db;
  final String translation;
  final void Function(ShownSource source)? onSource;
  const _Citations(this.g, this.db, this.translation, this.onSource);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notInScripture = [...g.unverified.map((e) => e.label), ...g.unknownBooks];
    if (g.verified.isEmpty &&
        notInScripture.isEmpty &&
        g.unverifiedQuotes == 0 &&
        g.correctedQuotes == 0 &&
        g.sources.isEmpty &&
        g.unverifiedSources.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in g.verified)
                ActionChip(
                  avatar: Icon(Icons.menu_book_outlined, size: 16, color: scheme.primary),
                  label: Text(r.label),
                  onPressed: () => _showPassage(context, r),
                ),
              for (final s in g.sources) _sourceChip(s, scheme),
            ],
          ),
          if (notInScripture.isNotEmpty ||
              g.unverifiedQuotes > 0 ||
              g.correctedQuotes > 0 ||
              g.rewordedQuotes > 0 ||
              g.nearMisses.isNotEmpty ||
              g.unverifiedSources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                [
                  if (notInScripture.isNotEmpty) 'Not in Scripture: ${notInScripture.join(', ')}',
                  if (g.unverifiedSources.isNotEmpty)
                    'Not among the sources shown: ${g.unverifiedSources.join(', ')}',
                  if (g.correctedQuotes > 0)
                    '${g.correctedQuotes} misquote(s) replaced with the exact words',
                  if (g.rewordedQuotes > 0)
                    '${g.rewordedQuotes} quote(s) from a source differ from the verse shown',
                  if (g.unverifiedQuotes > 0)
                    '${g.unverifiedQuotes} quoted phrase(s) not found verbatim',
                  if (g.nearMisses.isNotEmpty) nearMissNotice(g.nearMisses)!,
                ].join(' · '),
                style: TextStyle(color: scheme.error, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sourceChip(ShownSource s, ColorScheme scheme) => ActionChip(
    avatar: Icon(
      s.chunk.fromPack ? Icons.history_edu_outlined : Icons.description_outlined,
      size: 16,
      color: scheme.primary,
    ),
    tooltip: s.chunk.title,
    label: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _sourceChipMaxWidth),
      child: Text('${s.tag} · ${s.chunk.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    onPressed: onSource == null ? null : () => onSource!(s),
  );

  void _showPassage(BuildContext context, Ref ref) {
    final verses = db.passage(ref, translation: translation);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ref.label, style: TextStyle(fontFamilyFallback: scriptureFontFallback)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: SelectableText.rich(
              TextSpan(
                style: scriptureStyle(ctx),
                children: [
                  for (final v in verses) ...[
                    TextSpan(
                      text: '${v.verse} ',
                      style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.primary),
                    ),
                    TextSpan(text: '${v.text} '),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }
}

/// Why there is no engine yet, with the way to fix it.
class EngineNotice extends StatelessWidget {
  final AppState state;
  const EngineNotice({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = switch (state.deviceState) {
      DeviceModelState.downloading =>
        'Downloading ${state.settings.deviceModel.label}: ${state.downloadProgress}%',
      DeviceModelState.loading => 'Loading ${state.settings.deviceModel.label}\u2026',
      DeviceModelState.failed => 'Model failed to load. Open settings for details.',
      _ => 'No helper yet. Choose one in Study.',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          ),
          if (state.deviceState != DeviceModelState.downloading &&
              state.deviceState != DeviceModelState.loading)
            TextButton(
              onPressed: () => showSettingsSheet(context, state),
              child: const Text('Settings'),
            ),
        ],
      ),
    );
  }
}

class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool busy;
  final bool canSend;
  final VoidCallback onSend;

  /// Ends the answer being written; set only while there is one to end.
  final VoidCallback? onStop;
  final String hint;
  final Widget? mic;
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focus,
    required this.busy,
    this.canSend = true,
    required this.onSend,
    this.onStop,
    this.hint = bibleHint,
    this.mic,
  });

  static const bibleHint = 'Ask about a passage, a word, or a question of life';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              autofocus: !(Platform.isAndroid || Platform.isIOS),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(hintText: hint),
            ),
          ),
          if (mic case final m?) ...[const SizedBox(width: 4), m],
          const SizedBox(width: 6),
          IconButton.filled(
            tooltip: busy && onStop != null ? 'Stop' : 'Send',
            onPressed: busy && onStop != null ? onStop : (busy || !canSend ? null : onSend),
            icon: busy && onStop != null
                ? const Icon(Icons.stop_rounded)
                : busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_upward),
          ),
        ],
      ),
    );
  }
}
