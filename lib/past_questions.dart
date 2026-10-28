import 'package:flutter/material.dart';

import 'app_state.dart';
import 'study_store.dart';
import 'today.dart';

const _daysInWeek = 7;
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// When a question was last asked, in words: Today, Yesterday, a weekday, or a date.
String askedWhen(DateTime d, {DateTime? now}) {
  // Calendar days, so the day the clocks change still counts yesterday as Yesterday.
  final days = daysBetween(d, now ?? DateTime.now());
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < _daysInWeek) return _weekdays[d.weekday - 1];
  return '${d.day} ${_months[d.month - 1]}';
}

/// What a scope is called after "Asking about": the Bible, or the notebook's title.
String scopeName(AppState s, int? notebookId) =>
    notebookId == null ? 'the Bible' : s.notebooks.notebook(notebookId)?.title ?? 'a notebook';

/// Opens Past questions as its own page, for the phone and narrow windows.
Future<void> showPastQuestions(BuildContext context, AppState state) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (page) => Scaffold(
      appBar: AppBar(title: const Text('Past questions')),
      body: PastQuestions(state: state, onOpened: () => Navigator.pop(page)),
    ),
  ),
);

/// Every question asked in Study, each labelled with what it asked about, newest first.
/// Opening one loads it into Study, in its scope.
class PastQuestions extends StatelessWidget {
  final AppState state;

  /// Called after a question was opened, so a page can close itself.
  final VoidCallback? onOpened;
  const PastQuestions({super.key, required this.state, this.onOpened});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([state, state.studyScope, state.notebooks]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final asked = state.pastQuestions();
    if (asked.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No past questions yet. What you ask is kept here.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [for (final c in asked) _row(context, c)],
    );
  }

  Widget _row(BuildContext context, Conversation c) => ListTile(
    selected: c.id == state.conversationId,
    title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text('${askedWhen(c.updated)} · ${scopeName(state, c.notebookId)}'),
    trailing: IconButton(
      tooltip: 'Delete',
      icon: const Icon(Icons.delete_outline),
      onPressed: state.busy ? null : () => state.deleteConversation(c.id),
    ),
    onTap: state.canChangeScope
        ? () {
            state.openConversation(c.id);
            onOpened?.call();
          }
        : null,
  );
}
