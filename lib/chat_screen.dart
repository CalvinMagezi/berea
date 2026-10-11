import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'markdown_lite.dart';
import 'settings_sheet.dart';
import 'theme.dart';

class ChatScreen extends StatefulWidget {
  final AppState state;
  const ChatScreen({super.key, required this.state});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onChange);
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
    if (q.isEmpty || widget.state.busy) return;
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
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'Berea',
              style: TextStyle(fontFamilyFallback: scriptureFontFallback, fontSize: 24),
            ),
            const SizedBox(width: 12),
            Text(
              '${s.harness.engine.name} · ${s.settings.tier.name} · ${s.settings.translation}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New study',
            icon: const Icon(Icons.edit_note_outlined),
            onPressed: s.turns.isEmpty ? null : s.clear,
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune),
            onPressed: () => showSettingsSheet(context, s),
          ),
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
                        itemBuilder: (_, i) => _TurnView(s.turns[i], s.db, s.settings.translation),
                      ),
              ),
              _InputBar(controller: _input, focus: _focus, busy: s.busy, onSend: _send),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final BibleDb db;
  final String translation;
  final void Function(String) onPick;
  const _Empty({required this.db, required this.translation, required this.onPick});

  static const prompts = [
    'Study Acts 17:11. Why were the Bereans called noble?',
    'Do a word study on "created" in Genesis 1:1.',
    'What does Philippians 4:6-7 teach about anxiety?',
    'What does the Bible say about caring for widows?',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final motto = db.passage(RefParser.parse('Acts 17:11').first, translation: translation);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            motto.map((v) => v.text).join(' '),
            style: scriptureStyle(context).copyWith(fontSize: 20, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 6),
          Text(
            'Acts 17:11, $translation',
            style: TextStyle(color: scheme.primary, letterSpacing: 0.5),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in prompts) ActionChip(label: Text(p), onPressed: () => onPick(p)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TurnView extends StatelessWidget {
  final ChatTurn turn;
  final BibleDb db;
  final String translation;
  const _TurnView(this.turn, this.db, this.translation);

  @override
  Widget build(BuildContext context) {
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
          if (turn.result != null) _Citations(turn.result!, db, translation),
        ],
      ),
    );
  }
}

class _Citations extends StatelessWidget {
  final TurnResult result;
  final BibleDb db;
  final String translation;
  const _Citations(this.result, this.db, this.translation);

  @override
  Widget build(BuildContext context) {
    final g = result.guard;
    final scheme = Theme.of(context).colorScheme;
    if (g.verified.isEmpty && g.unverified.isEmpty && g.unverifiedQuotes.isEmpty) {
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
            ],
          ),
          if (g.unverified.isNotEmpty || g.unverifiedQuotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                [
                  if (g.unverified.isNotEmpty)
                    'Not in Scripture: ${g.unverified.map((e) => e.label).join(', ')}',
                  if (g.unverifiedQuotes.isNotEmpty)
                    '${g.unverifiedQuotes.length} quoted phrase(s) not found verbatim',
                ].join(' · '),
                style: TextStyle(color: scheme.error, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

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

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool busy;
  final VoidCallback onSend;
  const _InputBar({
    required this.controller,
    required this.focus,
    required this.busy,
    required this.onSend,
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
              autofocus: true,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Ask about a passage, a word, or a question of life',
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filled(
            onPressed: busy ? null : onSend,
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
