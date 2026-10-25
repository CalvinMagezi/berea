import 'dart:async';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'export.dart';
import 'markdown_lite.dart';
import 'plans.dart';
import 'settings_sheet.dart';
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
    _voice.addListener(_onVoice);
    // Opens at the newest turn, and follows an answer already streaming (the quick-chat sheet).
    _follower.follow(widget.state.turns.lastOrNull);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onChange);
    widget.state.pendingQuestion.removeListener(_onPending);
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

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.onClose == null,
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'Berea',
              style: TextStyle(fontFamilyFallback: scriptureFontFallback, fontSize: 24),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                '${s.engineLabel} · ${s.settings.tier.name} · ${s.settings.translation}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New study',
            icon: const Icon(Icons.edit_note_outlined),
            onPressed: s.turns.isEmpty ? null : s.clear,
          ),
          if (s.conversationId != null)
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
          child: Column(
            children: [
              Expanded(
                child: s.turns.isEmpty
                    ? _Empty(
                        state: s,
                        db: s.db,
                        translation: s.settings.translation,
                        onPick: (q) {
                          _input.text = q;
                          _send();
                        },
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        itemCount: s.turns.length,
                        itemBuilder: (_, i) => TurnView(
                          turn: s.turns[i],
                          db: s.db,
                          translation: s.settings.translation,
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
                mic: VoiceMicButton(
                  voice: _voice,
                  owner: this,
                  support: voiceSupport(s.settings, s.deviceState, hearsAudio: s.deviceHearsAudio),
                  modelFree: s.ready,
                  onOpenSettings: () => showSettingsSheet(context, s),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final AppState state;
  final BibleDb db;
  final String translation;
  final void Function(String) onPick;
  const _Empty({
    required this.state,
    required this.db,
    required this.translation,
    required this.onPick,
  });

  static const prompts = [
    'Study Acts 17:11. Why were the Bereans called noble?',
    'Do a word study on "created" in Genesis 1:1.',
    'What does Philippians 4:6-7 teach about anxiety?',
    'What does the Bible say about caring for widows?',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final daily = db.dailyVerse(DateTime.now()) ?? RefParser.parse('Acts 17:11').first;
    final verse = db.passage(daily, translation: translation);
    final reading = state.todaysReading;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
      children: [
        Text(
          'VERSE OF THE DAY',
          style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text(
          verse.map((v) => v.text).join(' '),
          style: scriptureStyle(context).copyWith(fontSize: 18, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '${daily.label}, $translation',
              style: TextStyle(color: scheme.primary, letterSpacing: 0.5),
            ),
            const Spacer(),
            TextButton(
              onPressed: () =>
                  onPick('Study ${daily.label}. What does it mean and how does it apply?'),
              child: const Text('Study it'),
            ),
          ],
        ),
        if (reading != null) ...[
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: scheme.surfaceContainerHighest,
            child: ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: Text('Today: ${readingLabel(reading)}'),
              subtitle: Text(state.activePlan!.name),
              onTap: () => state.openInReader(reading.first),
            ),
          ),
        ],
        const SizedBox(height: 32),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in prompts) ActionChip(label: Text(p), onPressed: () => onPick(p)),
          ],
        ),
      ],
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
  const TurnView({
    super.key,
    required this.turn,
    required this.db,
    required this.translation,
    this.onSource,
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
              child: SelectableText(turn.question),
            ),
          ),
          const SizedBox(height: 16),
          if (turn.error != null)
            Text(turn.error!, style: TextStyle(color: scheme.error))
          else if (turn.answer.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'Examining the Scriptures…',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else
            MarkdownLite(turn.answer),
          if (turn.done) _Citations(turn, db, translation, onSource),
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
      _ => 'No model yet. Open settings to download ${state.settings.deviceModel.label}.',
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
  final String hint;
  final Widget? mic;
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focus,
    required this.busy,
    this.canSend = true,
    required this.onSend,
    this.hint = 'Ask about a passage, a word, or a question of life',
    this.mic,
  });

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
            tooltip: 'Send',
            onPressed: busy || !canSend ? null : onSend,
            icon: busy
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
