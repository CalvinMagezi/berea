import 'package:flutter/material.dart';

import 'app_state.dart';
import 'chat_screen.dart';

/// Said when Study is busy with another scope, so the question waits rather than being lost.
const askPanelBusy = 'Berea is answering in Study. Ask here once it has finished.';

/// Beside a notebook's list on a wide screen: the conversation about this notebook, the same one
/// Study holds when it is scoped here. The first question asked here scopes Study to it.
class NotebookAskPanel extends StatefulWidget {
  final AppState state;
  final int notebookId;

  /// Focused when the notebook's Ask button is pressed.
  final FocusNode focus;
  const NotebookAskPanel({
    super.key,
    required this.state,
    required this.notebookId,
    required this.focus,
  });

  @override
  State<NotebookAskPanel> createState() => _NotebookAskPanelState();
}

class _NotebookAskPanelState extends State<NotebookAskPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final _follower = AnswerFollower(_scroll);

  AppState get _s => widget.state;
  bool get _here => _s.studyScope.value == widget.notebookId;

  @override
  void initState() {
    super.initState();
    _s.addListener(_onChange);
    _s.studyScope.addListener(_onChange);
    if (_here) _follower.follow(_s.turns.lastOrNull);
  }

  @override
  void dispose() {
    _s.removeListener(_onChange);
    _s.studyScope.removeListener(_onChange);
    _follower.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChange() {
    setState(() {});
    if (_here) _follower.follow(_s.turns.lastOrNull);
  }

  void _send() {
    final q = _input.text.trim();
    if (q.isEmpty || !_s.ready || !_s.canChangeScope) return;
    _s.setStudyScope(widget.notebookId);
    _input.clear();
    _s.send(q);
    widget.focus.requestFocus();
  }

  void _pick(String q) {
    _input.text = q;
    _send();
  }

  @override
  Widget build(BuildContext context) {
    final turns = _here ? _s.turns : const <ChatTurn>[];
    final waiting = !_here && !_s.canChangeScope;
    return Column(
      children: [
        Expanded(
          child: turns.isEmpty
              ? Suggestions(state: _s, onPick: _pick, notebookId: widget.notebookId)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  itemCount: turns.length,
                  itemBuilder: (context, i) => TurnView(
                    turn: turns[i],
                    db: _s.db,
                    translation: _s.settings.translation,
                    onDeeper: _s.ready && _s.canGoDeeperFrom(turns[i])
                        ? () => _s.goDeeper(turns[i])
                        : null,
                    onKeep: () => keepTurn(context, _s, turns[i]),
                    onSource: (cited) => openCitedSource(context, _s, cited),
                  ),
                ),
        ),
        if (_s.harness == null) EngineNotice(state: _s),
        if (waiting)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              askPanelBusy,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ChatInputBar(
          controller: _input,
          focus: widget.focus,
          busy: _s.busy,
          canSend: !waiting,
          onSend: _send,
          onStop: _here && _s.canStopAnswer ? _s.stopAnswer : null,
          hint: 'Ask about this notebook',
        ),
      ],
    );
  }
}
