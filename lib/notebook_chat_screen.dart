import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'commentary_sheet.dart';
import 'notebook_chat.dart';
import 'notebook_store.dart';
import 'notebooks_screen.dart';
import 'theme.dart';

const _commentarySheetHeight = 0.85;

/// A conversation inside one notebook. Answers draw on its sources and on Scripture, and cite
/// sources with tags that open the source at the cited section.
class NotebookChatScreen extends StatefulWidget {
  final NotebookStore store;
  final int notebookId;

  /// Makes this screen's conversation; the screen disposes it.
  final NotebookChat Function() createChat;
  final BibleDb db;
  final String Function() translation;
  final CommentaryLibrary commentary;

  /// Shown above the input when no engine is ready, with the way to set one up.
  final Widget? engineNotice;
  const NotebookChatScreen({
    super.key,
    required this.store,
    required this.notebookId,
    required this.createChat,
    required this.db,
    required this.translation,
    required this.commentary,
    this.engineNotice,
  });

  @override
  State<NotebookChatScreen> createState() => _NotebookChatScreenState();
}

class _NotebookChatScreenState extends State<NotebookChatScreen> {
  late final NotebookChat _chat = widget.createChat();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onChange);
  }

  @override
  void dispose() {
    _chat
      ..removeListener(_onChange)
      ..dispose();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChange() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _send() {
    final q = _input.text.trim();
    if (q.isEmpty || !_chat.canSend) return;
    _input.clear();
    _chat.send(q);
    _focus.requestFocus();
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  void _open(ShownSource cited) {
    final c = cited.chunk;
    if (c.fromPack) {
      final ref = c.ref;
      if (ref == null) return _say('That commentary passage cannot be found.');
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => FractionallySizedBox(
          heightFactor: _commentarySheetHeight,
          child: CommentaryPanel(library: widget.commentary, passage: ref),
        ),
      );
      return;
    }
    final source = c.sourceId == null ? null : widget.store.source(c.sourceId!);
    if (source == null) return _say('That source has been removed from the notebook.');
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SourceScreen(store: widget.store, source: source, focusOrdinal: c.ordinal),
      ),
    );
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a new conversation?'),
        content: const Text('This conversation will be deleted from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start')),
        ],
      ),
    );
    if (ok == true) _chat.clear();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.store.notebook(widget.notebookId)?.title ?? 'Notebook';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'New conversation',
            icon: const Icon(Icons.edit_note_outlined),
            onPressed: _chat.turns.isEmpty || _chat.answering ? null : _clear,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: Column(
            children: [
              Expanded(child: _chat.turns.isEmpty ? const _Intro() : _turns()),
              if (!_chat.ready() && widget.engineNotice != null) widget.engineNotice!,
              ChatInputBar(
                controller: _input,
                focus: _focus,
                busy: _chat.answering,
                onSend: _send,
                hint: 'Ask about this notebook',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _turns() => ListView.builder(
    controller: _scroll,
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
    itemCount: _chat.turns.length,
    itemBuilder: (_, i) => TurnView(
      turn: _chat.turns[i],
      db: widget.db,
      translation: widget.translation(),
      onSource: _open,
    ),
  );
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
      children: [
        Icon(Icons.forum_outlined, size: 40, color: scheme.primary),
        const SizedBox(height: 16),
        Text(
          'Ask about your sources',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Answers draw on the sources in this notebook and on Scripture. A source is cited by '
          'its number and place, such as S3 p.14 for page 14 of source 3. Tap a citation to open '
          'the source there. Pin a source to include it in every answer.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
        ),
      ],
    );
  }
}
