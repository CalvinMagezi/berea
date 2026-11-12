import 'package:berea_harness/berea_harness.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';

/// One topic of Nave's Topical Bible or Torrey's New Topical Textbook: the author's own lines and
/// the passages after each, every passage a tap from the reader. Berea adds no words of its own.
class TopicScreen extends StatelessWidget {
  final AppState state;
  final TopicMatch topic;
  const TopicScreen({super.key, required this.state, required this.topic});

  void _open(BuildContext context, TopicRef r) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    state.openInReader(Ref(bookById(r.book), r.chapter, r.verse == 0 ? 1 : r.verse, r.verse == 0 ? 1 : r.verse));
  }

  void _openTopic(BuildContext context, TopicMatch t) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TopicScreen(state: state, topic: t)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = state.db.topicLines(topic.id);
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 13);
    return Scaffold(
      appBar: AppBar(title: Text(topic.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(BibleDb.topicWorkName(topic.work), style: muted),
          const SizedBox(height: 12),
          for (final line in lines) ...[
            if (line.label.isNotEmpty) _label(context, line.label),
            if (line.refs.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 2,
                children: [
                  for (final r in line.refs)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(topicRefLabel(r)),
                      onPressed: () => _open(context, r),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String label) {
    final target = _seeTarget(label);
    if (target == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(label, style: Theme.of(context).textTheme.titleSmall),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        style: TextButton.styleFrom(padding: EdgeInsets.zero),
        onPressed: () {
          final found = state.db.topicsNamed(target);
          if (found.isNotEmpty) _openTopic(context, found.first);
        },
        child: Text(label),
      ),
    );
  }

  /// The topic a "See NAME" or "Also see NAME, below" line sends to, when it names one.
  static String? _seeTarget(String label) {
    final m = RegExp(r'^(?:Also see|See)\s+(.+?)\s*(?:,\s*below)?\s*$', caseSensitive: false).firstMatch(label);
    return m?[1];
  }
}
