import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'prayer_points.dart';
import 'prayer_pray_now.dart';
import 'prayer_sheet.dart';
import 'prayer_store.dart';
import 'prayer_today.dart';
import 'prayer_verse.dart';
import 'prayer_words.dart';
import 'setup_screen.dart' show deviceNoun;
import 'theme.dart';

export 'prayer_pray_now.dart' show PrayNowScreen, LordsPrayerScreen;
export 'prayer_sheet.dart' show PassageLookup, ShareText, passageLookupFor, showPrayerSheet;
export 'prayer_points.dart' show PrayerEnv;

/// Measured on the room the Prayer place has beside the sidebar, not the window; local rather
/// than the shell's constant, so this screen does not import the shell.
const _wideBreakpoint = 760.0;
const _wideListWidth = 400.0;
const _topicCardHeight = 124.0;
const _topicCardWidth = 164.0;
const _pagePadding = 16.0;
const _daysInWeek = 7;
const _daysInTwoWeeks = 14;

/// Lines an answer up under its title, past the check mark.
const _answerIndent = 72.0;

/// Room for the latest answer beside the Answered row, as "Job interview, today".
const _answeredDetailWidth = 200.0;

/// The verse the first-time screen opens with.
final _welcomeVerse = Ref(bookById(52), 5, 16, 18);

/// "added today", "prayed yesterday", "prayed 3 days ago", "prayed last week", "prayed 2 October".
String lastPrayedLabel(Prayer p, DateTime now) {
  final prayed = p.lastPrayed;
  final verb = prayed == null ? 'added' : 'prayed';
  final when = prayed ?? p.created;
  final day = DateTime(when.year, when.month, when.day);
  final days = DateTime(now.year, now.month, now.day).difference(day).inDays;
  if (days <= 0) return '$verb today';
  if (days == 1) return '$verb yesterday';
  if (days < _daysInWeek) return '$verb $days days ago';
  if (days < _daysInTwoWeeks) return '$verb last week';
  return '$verb ${dayMonth(day)}';
}

/// Prayer: the first-time screen, the Praying list, Pray now and Answered. Everything stays on
/// the device; Share hands plain text to the OS share sheet only when the person asks.
class PrayerScreen extends StatefulWidget {
  final PrayerStore store;
  final PassageLookup passage;

  /// The reader's translation code, such as BSB, for verse labels.
  final String Function() translation;
  final ShareText share;

  /// The prayer lines bundled with the app. Without them Prayer is the list alone.
  final PrayerContent? content;

  /// Today's prayer, asked for each time the place is built so a new day shows its own.
  final TodayPrayer? Function()? todayPrayer;

  /// Rebuilds the place when something besides the prayers changes, such as the day.
  final Listenable? refresh;
  const PrayerScreen({
    super.key,
    required this.store,
    required this.passage,
    required this.translation,
    this.share = shareText,
    this.content,
    this.todayPrayer,
    this.refresh,
  });

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen> {
  /// Bumped to start a fresh Pray now session in the wide panel.
  var _session = 0;

  /// The prayer the wide panel opens on, set by clicking a row.
  int? _startAt;

  /// The prayer the wide panel is showing, marked in the list.
  int? _shown;

  /// The topic the wide panel is showing beside the list, instead of Pray now.
  PrayerTopic? _topic;

  PrayerStore get _store => widget.store;
  PrayerContent get _content => widget.content ?? PrayerContent.empty;

  late final _env = PrayerEnv(
    content: _content,
    store: widget.store,
    passage: widget.passage,
    translation: widget.translation,
    share: widget.share,
  );

  Future<void> _add() =>
      showPrayerSheet(context, _store, passage: widget.passage, content: _content);

  void _edit(Prayer p) =>
      showPrayerSheet(context, _store, editing: p, passage: widget.passage, content: _content);

  void _openTopic(PrayerTopic t, {required bool wide}) => wide
      ? setState(() => _topic = t)
      : Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => TopicScreen(env: _env, topic: t),
          ),
        );

  void _allTopics({required bool wide}) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) =>
          FromTheWordScreen(env: _env, onTopic: wide ? (t) => setState(() => _topic = t) : null),
    ),
  );

  void _prayToday(TodayPrayer t) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => LinesPrayerScreen(env: _env, title: "Today's prayer", points: [t.point]),
    ),
  );

  /// Wide layout: a clicked row opens in the panel beside the list. Edit is in the panel.
  void _showInPanel(Prayer p) => setState(() {
    _startAt = p.id;
    _session++;
  });

  void _onShow(int? id) {
    if (id != _shown) setState(() => _shown = id);
  }

  /// A phone opens Pray now as a page; a wide window starts it over in the panel.
  void _prayNow({required bool wide}) => wide
      ? setState(() {
          _startAt = null;
          _session++;
        })
      : Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => PrayNowScreen(
              store: _store,
              passage: widget.passage,
              translation: widget.translation,
              content: _content,
            ),
          ),
        );

  void _lordsPrayer() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => LordsPrayerScreen(passage: widget.passage, translation: widget.translation),
    ),
  );

  void _answered() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => AnsweredScreen(
        store: _store,
        share: widget.share,
        passage: widget.passage,
        translation: widget.translation,
      ),
    ),
  );

  void _stopped() => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => StoppedScreen(store: _store)),
  );

  void _shareList(BuildContext button) =>
      widget.share(prayerListText(_store.praying()), shareOrigin(button));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_store, ?widget.refresh]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, c) {
        if (_store.isEmpty) {
          return _FirstTime(
            passage: widget.passage,
            translation: widget.translation,
            onAdd: _add,
            onLordsPrayer: _lordsPrayer,
            onWords: _content.topics.isEmpty ? null : () => _allTopics(wide: false),
            today: widget.todayPrayer?.call(),
            onPrayToday: _prayToday,
          );
        }
        final wide = c.maxWidth >= _wideBreakpoint;
        final list = _list(context, wide: wide);
        if (!wide) return list;
        return Row(
          children: [
            SizedBox(width: _wideListWidth, child: list),
            const VerticalDivider(width: 1),
            Expanded(child: _widePanel(context)),
          ],
        );
      },
    ),
  );

  Widget _widePanel(BuildContext context) {
    final topic = _topic;
    if (topic != null) {
      return Column(
        children: [
          ListTile(
            title: Text(topic.title, style: Theme.of(context).textTheme.titleLarge),
            subtitle: Text('From the Word \u00B7 ${topic.group}'),
            trailing: IconButton(
              tooltip: 'Close the topic',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _topic = null),
            ),
          ),
          Expanded(
            child: TopicView(env: _env, topic: topic),
          ),
          const _PrivacyLine(),
        ],
      );
    }
    if (_store.praying().isEmpty) {
      return const Center(child: Text('Nothing on the list right now.'));
    }
    return Column(
      children: [
        Expanded(
          child: PrayNowView(
            key: ValueKey(_session),
            store: _store,
            passage: widget.passage,
            translation: widget.translation,
            content: _content,
            startAt: _startAt,
            keyHint: true,
            onShow: _onShow,
            onDone: () => setState(() {
              _startAt = null;
              _session++;
            }),
          ),
        ),
        const _PrivacyLine(),
      ],
    );
  }

  Widget _list(BuildContext context, {required bool wide}) {
    final praying = _store.praying();
    final answered = _store.answered();
    final stopped = _store.stopped();
    final now = _store.now();
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prayer'),
        actions: [
          Builder(
            builder: (button) => IconButton(
              tooltip: 'Share the list',
              onPressed: praying.isEmpty ? null : () => _shareList(button),
              icon: const Icon(Icons.share_outlined),
            ),
          ),
          IconButton(tooltip: 'Add a prayer', onPressed: _add, icon: const Icon(Icons.add)),
        ],
      ),
      body: ListView(
        children: [
          if (praying.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(_pagePadding, 4, _pagePadding, 12),
              child: FilledButton.icon(
                onPressed: () => _prayNow(wide: wide),
                icon: const Icon(Icons.volunteer_activism_outlined),
                label: Text('Pray now · ${_count(praying.length)}'),
              ),
            ),
          if (widget.todayPrayer?.call() case final today?) ...[
            TodayPrayerCard(prayer: today, onPray: () => _prayToday(today)),
            const SizedBox(height: 8),
          ],
          if (_content.topics.isNotEmpty) _fromTheWord(context, praying, wide: wide),
          _section('Praying · ${praying.length}'),
          for (final p in praying)
            _PrayerRow(
              prayer: p,
              subtitle: lastPrayedLabel(p, now),
              selected: wide && p.id == _shown,
              onTap: wide ? () => _showInPanel(p) : () => _edit(p),
              onCheck: () => answerPrayer(context, _store, p),
            ),
          if (wide && answered.isNotEmpty) ...[
            _section('Answered · ${answered.length}'),
            for (final p in answered)
              _PrayerRow(
                prayer: p,
                subtitle: 'answered ${answeredLabel(p, now)}',
                onTap: _answered,
              ),
          ] else if (answered.isNotEmpty)
            ListTile(
              leading: Icon(Icons.check_circle, color: scheme.primary),
              title: Text('Answered · ${answered.length}'),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _answeredDetailWidth),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The title gives way first, so the day it was answered always shows.
                    Flexible(
                      child: Text(
                        answered.first.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ),
                    Text(', ${answeredLabel(answered.first, now)}', style: muted),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
              onTap: _answered,
            ),
          if (stopped.isNotEmpty)
            ListTile(
              leading: Icon(Icons.pause_circle_outline, color: scheme.onSurfaceVariant),
              title: Text('No longer praying · ${stopped.length}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _stopped,
            ),
          TextButton.icon(
            onPressed: _lordsPrayer,
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text("Pray the Lord's Prayer"),
          ),
        ],
      ),
    );
  }

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(_pagePadding, 12, _pagePadding, 4),
    child: PrayerLabel(text),
  );

  /// Topic cards, those that match the reader's own prayers first.
  Widget _fromTheWord(BuildContext context, List<Prayer> praying, {required bool wide}) {
    final topics = topicsForList(_content, praying);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_pagePadding, 12, 8, 0),
          child: Row(
            children: [
              const Expanded(child: PrayerLabel('From the Word')),
              TextButton(
                onPressed: () => _allTopics(wide: wide),
                child: Text('All ${_content.topics.length} topics'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: MediaQuery.textScalerOf(context).scale(_topicCardHeight),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
            children: [
              for (final t in topics)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: _topicCardWidth,
                    child: Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      color: t.id == _topic?.id
                          ? scheme.secondaryContainer
                          : scheme.surfaceContainerHighest,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(_pagePadding),
                        onTap: () => _openTopic(t, wide: wide),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.volunteer_activism_outlined, color: scheme.primary),
                              const Spacer(),
                              Text(
                                t.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${t.points.length} prayer points',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(_pagePadding, 6, _pagePadding, 0),
          child: Text(
            'First: topics that match what you are praying for.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

String _count(int n) => n == 1 ? '1 prayer' : '$n prayers';

/// "today", "yesterday" or the day and month an answered prayer was answered.
String answeredLabel(Prayer p, DateTime now) {
  final a = p.answered!;
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(a.year, a.month, a.day)).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  return dayMonth(a);
}

class _PrayerRow extends StatelessWidget {
  final Prayer prayer;
  final String subtitle;
  final VoidCallback? onTap;

  /// Marks the prayer answered. Null for one already answered.
  final VoidCallback? onCheck;

  /// The prayer the wide panel is showing.
  final bool selected;
  const _PrayerRow({
    required this.prayer,
    required this.subtitle,
    this.onTap,
    this.onCheck,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return ListTile(
      onTap: onTap,
      selected: selected,
      selectedTileColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.onSurface,
      leading: prayer.isAnswered
          ? Icon(Icons.check_circle, color: scheme.primary)
          : IconButton(
              tooltip: 'Answered',
              onPressed: onCheck,
              icon: const Icon(Icons.radio_button_unchecked),
            ),
      title: Text(prayer.title),
      subtitle: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (prayer.forWhom.isNotEmpty) Text(prayer.forWhom, style: muted),
          if (prayer.verse != null) VerseChip(prayer.verse!),
          Text(subtitle, style: muted),
        ],
      ),
    );
  }
}

class _PrivacyLine extends StatelessWidget {
  const _PrivacyLine();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(_pagePadding),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 16, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Prayers stay on this $deviceNoun. Nothing is sent anywhere, and nothing is shared '
              'unless you share it.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirstTime extends StatelessWidget {
  final PassageLookup passage;
  final String Function() translation;
  final VoidCallback onAdd;
  final VoidCallback onLordsPrayer;
  final VoidCallback? onWords;
  final TodayPrayer? today;
  final void Function(TodayPrayer) onPrayToday;
  const _FirstTime({
    required this.passage,
    required this.translation,
    required this.onAdd,
    required this.onLordsPrayer,
    required this.onWords,
    required this.today,
    required this.onPrayToday,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final verse = passageText(passage(_welcomeVerse));
    return Scaffold(
      appBar: AppBar(title: const Text('Prayer')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(_pagePadding),
            children: [
              Text(
                'Bring it to God, and remember the answer',
                style: t.headlineSmall?.copyWith(
                  fontFamilyFallback: scriptureFontFallback,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Keep what you are praying for, pray through it one at a time, and write down '
                'how each prayer was answered.',
                style: t.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (verse.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(_pagePadding),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(_pagePadding),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PrayerLabel('${_welcomeVerse.label} · ${translation()}'),
                      const SizedBox(height: 8),
                      Text(verse, style: scriptureStyle(context)),
                    ],
                  ),
                ),
              ],
              if (today case final t?) ...[
                const SizedBox(height: 16),
                TodayPrayerCard(prayer: t, onPray: () => onPrayToday(t)),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Add a prayer'),
              ),
              if (onWords != null) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: onWords,
                  icon: const Icon(Icons.volunteer_activism_outlined),
                  label: const Text('Find words to pray'),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onLordsPrayer,
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text("Pray the Lord's Prayer"),
              ),
              const SizedBox(height: 6),
              Text(
                'Matthew 6:9-13, a line at a time',
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              const _PrivacyLine(),
            ],
          ),
        ),
      ),
    );
  }
}

/// "4 answered since August, newest first.", with the year when it is not this one.
String answeredSummary(List<Prayer> answered, DateTime now) {
  if (answered.isEmpty) {
    return 'Nothing is marked answered yet. When a prayer is answered, tick it on the list and '
        'write how. It is kept here with the date.';
  }
  final first = answered.last.answered!;
  final month = monthName(first);
  final since = first.year == now.year ? month : '$month ${first.year}';
  return '${answered.length} answered since $since, newest first.';
}

/// Answered prayers, newest first, each with the person's own line and date.
class AnsweredScreen extends StatelessWidget {
  final PrayerStore store;
  final ShareText share;

  /// Gives a testimony the words of its verse. Without it the verse is shared by reference.
  final PassageLookup? passage;
  final String Function()? translation;
  const AnsweredScreen({
    super.key,
    required this.store,
    this.share = shareText,
    this.passage,
    this.translation,
  });

  /// Back on the list, with Undo bringing back the person's line and the day it was answered.
  void _stillPraying(BuildContext context, Prayer p) {
    store.unanswer(p.id);
    sayPrayer(
      context,
      'Back on the list',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => store.markAnswered(p.id, p.answer ?? '', at: p.answered),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final answered = store.answered();
      final now = store.now();
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Answered'),
          actions: [
            Builder(
              builder: (button) => IconButton(
                tooltip: 'Share answered prayers',
                onPressed: answered.isEmpty
                    ? null
                    : () => share(answered.map(testimonyText).join('\n\n'), shareOrigin(button)),
                icon: const Icon(Icons.share_outlined),
              ),
            ),
          ],
        ),
        body: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
              child: Text(
                answeredSummary(answered, now),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            for (final p in answered) ...[
              _PrayerRow(prayer: p, subtitle: 'answered ${answeredLabel(p, now)}'),
              Padding(
                padding: const EdgeInsets.fromLTRB(_answerIndent, 0, _pagePadding, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p.answer != null)
                      Text(
                        p.answer!,
                        style: scriptureStyle(context).copyWith(fontStyle: FontStyle.italic),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        Builder(
                          builder: (button) => TextButton.icon(
                            onPressed: () => shareTestimony(
                              context,
                              p,
                              share: share,
                              passage: passage,
                              origin: shareOrigin(button),
                            ),
                            icon: const Icon(Icons.share_outlined, size: 18),
                            label: const Text('Share a testimony'),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _stillPraying(context, p),
                          child: const Text('Still praying'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
          ],
        ),
      );
    },
  );
}

/// Prayers the person stopped praying for, each with Resume to put it back on the list.
class StoppedScreen extends StatelessWidget {
  final PrayerStore store;
  const StoppedScreen({super.key, required this.store});

  void _resume(BuildContext context, Prayer p) {
    store.setArchived(p.id, false);
    sayPrayer(
      context,
      'Back on the list',
      action: SnackBarAction(label: 'Undo', onPressed: () => store.setArchived(p.id, true)),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final stopped = store.stopped();
      final muted = Theme.of(context).colorScheme.onSurfaceVariant;
      return Scaffold(
        appBar: AppBar(title: const Text('No longer praying')),
        body: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
              child: Text(
                stopped.isEmpty
                    ? 'Nothing here. Prayers you stop praying for wait here until you resume them.'
                    : 'Kept here, out of the list and Pray now. Resume puts one back.',
                style: TextStyle(color: muted),
              ),
            ),
            for (final p in stopped)
              ListTile(
                title: Text(p.title),
                subtitle: p.forWhom.isEmpty ? null : Text(p.forWhom),
                trailing: TextButton(
                  onPressed: () => _resume(context, p),
                  child: const Text('Resume'),
                ),
              ),
          ],
        ),
      );
    },
  );
}
