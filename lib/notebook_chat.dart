import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/foundation.dart';

import 'app_state.dart';
import 'notebook_store.dart';

/// Writes an answer in a notebook, or returns null when the engine is missing or busy.
typedef NotebookAnswer = Future<TurnResult?> Function(
  String question,
  List<ChatMessage> history,
  void Function(String token) onToken,
);

const engineBusyMessage = 'Berea is answering another question. Try again when it has finished.';

/// One notebook's conversation: its turns, saved in study.sqlite after each answer. The app keeps
/// one per notebook for as long as it runs, so an answer that finishes after its screen closed is
/// there when the screen opens again.
class NotebookChat extends ChangeNotifier {
  final NotebookStore store;
  final int notebookId;
  final NotebookAnswer answer;

  /// Whether an engine is ready to take a question.
  final bool Function() ready;
  final turns = <ChatTurn>[];
  bool answering = false;

  /// The notebook tables this conversation was read from; a restore makes it stale.
  final int epoch;

  NotebookChat({
    required this.store,
    required this.notebookId,
    required this.answer,
    required this.ready,
  }) : epoch = store.epoch {
    _load();
  }

  void _load() {
    ChatTurn? current;
    for (final m in store.messages(notebookId)) {
      if (m.isUser) {
        current = ChatTurn(m.text);
        turns.add(current);
      } else if (current != null) {
        current
          ..answer = m.text
          ..verified = m.refs
          ..sources = m.sources
          ..done = true;
      }
    }
  }

  bool get canSend => ready() && !answering;

  /// Earlier questions and answers, for the model to follow the conversation.
  List<ChatMessage> get _history => [
    for (final t in turns)
      if (t.done && t.error == null) ...[
        ChatMessage.user(t.question),
        ChatMessage.assistant(t.answer),
      ],
  ];

  Future<void> send(String question) async {
    if (!canSend) return;
    final history = _history;
    final turn = ChatTurn(question);
    turns.add(turn);
    answering = true;
    notifyListeners();
    try {
      final result = await answer(question, history, (t) {
        turn.answer += t;
        notifyListeners();
      });
      if (result == null) {
        turn
          ..error = engineBusyMessage
          ..done = true;
        return;
      }
      turn.take(result.guard);
      // A restore during the answer may have given this notebook's id to another notebook.
      if (store.epoch != epoch) return;
      store.addExchange(notebookId, question, turn.answer, turn.verified, turn.sources);
    } catch (e) {
      turn
        ..error = e.toString()
        ..done = true;
    } finally {
      answering = false;
      notifyListeners();
    }
  }

  /// Starts the conversation again; the saved one is deleted.
  void clear() {
    store.clearMessages(notebookId);
    turns.clear();
    notifyListeners();
  }
}
