import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'prayer_points.dart';
import 'prayer_pray_now.dart';
import 'prayer_sheet.dart';
import 'prayer_today.dart';
import 'theme.dart';

const _pagePadding = 16.0;
const _cardRadius = 16.0;
const _verseLines = 4;

/// A topic's numbered points with Pray these now and Add to my list. The body of [TopicScreen],
/// and what the Mac shows beside the Praying list.
class TopicView extends StatelessWidget {
  final PrayerEnv env;
  final PrayerTopic topic;
  const TopicView({super.key, required this.env, required this.topic});

  void _pray(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => LinesPrayerScreen(env: env, title: topic.title, points: topic.points),
    ),
  );

  Future<void> _add(BuildContext context) async {
    final id = await showPrayerSheet(
      context,
      env.store,
      title: topic.title,
      verse: topic.points.first.ref,
      topic: topic.id,
      passage: env.passage,
      content: env.content,
    );
    if (id != null && context.mounted) sayPrayer(context, 'Added to your list');
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_pagePadding, 0, _pagePadding, 12),
          child: Text(
            '${topic.points.length} prayer points from the Bible, written for Berea. Each one '
            'stands on the verse beneath it.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(_pagePadding, 0, _pagePadding, 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _pray(context),
                  icon: const Icon(Icons.volunteer_activism_outlined),
                  label: const Text('Pray these now'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add to my list'),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < topic.points.length; i++)
          PointTile(number: i + 1, point: topic.points[i]),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// The text of a topic for a group chat: the title, then the numbered points with their verses.
String topicShareText(PrayerTopic topic) => [
  topic.title,
  for (var i = 0; i < topic.points.length; i++)
    '${i + 1}. ${topic.points[i].text} (${topic.points[i].ref})',
].join('\n');

class TopicScreen extends StatelessWidget {
  final PrayerEnv env;
  final PrayerTopic topic;
  const TopicScreen({super.key, required this.env, required this.topic});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(topic.title),
      actions: [
        Builder(
          builder: (button) => IconButton(
            tooltip: 'Share as text',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => env.share(topicShareText(topic), shareOrigin(button)),
          ),
        ),
      ],
    ),
    body: TopicView(env: env, topic: topic),
  );
}

/// The library: Prayers of the Bible, then the topics by group, found by search too.
class FromTheWordScreen extends StatefulWidget {
  final PrayerEnv env;

  /// Told which topic was chosen instead of opening its page, for the wide layout.
  final ValueChanged<PrayerTopic>? onTopic;
  const FromTheWordScreen({super.key, required this.env, this.onTopic});

  @override
  State<FromTheWordScreen> createState() => _FromTheWordScreenState();
}

class _FromTheWordScreenState extends State<FromTheWordScreen> {
  final _search = TextEditingController();
  var _searching = false;

  PrayerContent get _content => widget.env.content;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(PrayerTopic t) {
    final onTopic = widget.onTopic;
    if (onTopic != null) {
      onTopic(t);
      Navigator.pop(context);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TopicScreen(env: widget.env, topic: t),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typed = _search.text.trim();
    final found = typed.isEmpty ? null : _content.topicsFor(typed);
    final groups = <String, List<PrayerTopic>>{};
    for (final t in _content.topics) {
      (groups[t.group] ??= []).add(t);
    }
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Rain, a job, exams',
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : const Text('From the Word'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search topics',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _search.clear();
            }),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
        children: [
          if (found != null)
            ..._results(found, typed)
          else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Prayer points, each with its verse. No helper needed.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            if (_content.biblePrayers.isNotEmpty) _biblePrayersRow(context),
            for (final g in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 6),
                child: PrayerLabel(g.key),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final t in g.value)
                    ActionChip(label: Text(t.title), onPressed: () => _open(t)),
                ],
              ),
            ],
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  List<Widget> _results(List<PrayerTopic> found, String typed) => found.isEmpty
      ? [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No topic fits "$typed". You can still pray a verse as it is, or in your own words.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ]
      : [
          for (final t in found)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.title),
              subtitle: Text(t.group),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(t),
            ),
        ];

  Widget _biblePrayersRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = _content.biblePrayers.length;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cardRadius)),
      child: ListTile(
        leading: Icon(Icons.menu_book_outlined, color: scheme.primary),
        title: const Text('Prayers of the Bible'),
        subtitle: Text("The Lord's Prayer, Psalm 23 and ${count - 2} more"),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => BiblePrayersScreen(env: widget.env)),
        ),
      ),
    );
  }
}

/// The prayers that are in the Bible, each prayed a verse at a time from the installed text.
class BiblePrayersScreen extends StatelessWidget {
  final PrayerEnv env;
  const BiblePrayersScreen({super.key, required this.env});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Prayers of the Bible')),
    body: ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_pagePadding, 0, _pagePadding, 8),
          child: Text(
            'Prayed a line at a time. The text is the Bible itself.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        for (final p in env.content.biblePrayers)
          ListTile(
            title: Text(p.title),
            trailing: Text(p.passage.label, style: Theme.of(context).textTheme.bodySmall),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LordsPrayerScreen(
                  passage: env.passage,
                  translation: env.translation,
                  ref: p.passage,
                  title: p.title,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Prayer points one at a time: the line, the verse it stands on, and Amen to move on.
class LinesPrayerScreen extends StatefulWidget {
  final PrayerEnv env;
  final String title;
  final List<PrayerPoint> points;

  /// Called when the last line is prayed, such as to tick a plan day.
  final VoidCallback? onAmen;
  const LinesPrayerScreen({
    super.key,
    required this.env,
    required this.title,
    required this.points,
    this.onAmen,
  });

  @override
  State<LinesPrayerScreen> createState() => _LinesPrayerScreenState();
}

class _LinesPrayerScreenState extends State<LinesPrayerScreen> {
  var _index = 0;

  void _next() {
    if (_index < widget.points.length - 1) {
      setState(() => _index++);
      return;
    }
    widget.onAmen?.call();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final point = widget.points[_index];
    final last = _index == widget.points.length - 1;
    final verse = passageText(widget.env.passage(point.verse));
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('${_index + 1} of ${widget.points.length}')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(_pagePadding),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(_cardRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(point.text, style: scriptureStyle(context).copyWith(fontSize: 22)),
                const SizedBox(height: 16),
                PrayerLabel('${point.ref} · ${widget.env.translation()}'),
                if (verse.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    verse,
                    maxLines: _verseLines,
                    overflow: TextOverflow.ellipsis,
                    style: scriptureStyle(context)
                        .copyWith(fontSize: 15, color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _next, child: Text(last ? 'Amen' : 'Amen, next')),
        ],
      ),
    );
  }
}

/// Today's prayer: a line from the reader's own reading, or the verse of the day, with Pray it.
class TodayPrayerCard extends StatelessWidget {
  final TodayPrayer prayer;
  final VoidCallback onPray;
  const TodayPrayerCard({super.key, required this.prayer, required this.onPray});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: _pagePadding),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrayerLabel("Today's prayer · ${prayer.source}"),
          const SizedBox(height: 8),
          Text(prayer.point.text, style: scriptureStyle(context).copyWith(fontSize: 18)),
          const SizedBox(height: 4),
          Row(
            children: [
              VerseChip(prayer.point.ref),
              const Spacer(),
              TextButton(onPressed: onPray, child: const Text('Pray it')),
            ],
          ),
        ],
      ),
    );
  }
}
