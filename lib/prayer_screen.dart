import 'package:berea_harness/berea_harness.dart';
import 'package:material_ui/material_ui.dart';

import 'prayer_sheet.dart';
import 'prayer_store.dart';
import 'prayer_support.dart';
import 'setup_screen.dart' show deviceNoun;
import 'theme.dart';

export 'prayer_sheet.dart' show PassageLookup, ShareText, passageLookupFor, showPrayerSheet;

/// Measured on the room the Prayer place has beside the sidebar, not the window; local rather
/// than the shell's constant, so this screen does not import the shell.
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

  /// Rebuilds the place when something besides the prayers changes, such as the day.
  final Listenable? refresh;

  /// Opens Settings from the app bar; null hides the button.
  final VoidCallback? onSettings;

  /// Opens the Bible search, so it is one tap from here.
  const PrayerScreen({
    super.key,
    required this.store,
    required this.passage,
    required this.translation,
    this.share = shareText,
    this.refresh,
    this.onSettings,
  });

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen> {
  PrayerStore get _store => widget.store;

  Future<void> _add() => showPrayerSheet(context, _store, passage: widget.passage);

  void _edit(Prayer p) =>
      showPrayerSheet(context, _store, editing: p, passage: widget.passage);

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
    builder: (context, _) => _store.isEmpty
        ? _FirstTime(
            passage: widget.passage,
            translation: widget.translation,
            onAdd: _add,
            onSettings: widget.onSettings,
          )
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: contentMaxWidth),
              child: _list(context),
            ),
          ),
  );

  Widget _list(BuildContext context) {
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
          if (widget.onSettings case final open?)
            IconButton(tooltip: 'Settings', icon: const Icon(Icons.tune), onPressed: open),
        ],
      ),
      body: ListView(
        children: [
          _section('Praying · ${praying.length}'),
          for (final p in praying)
            _PrayerRow(
              prayer: p,
              subtitle: lastPrayedLabel(p, now),
              onTap: () => _edit(p),
              onCheck: () => answerPrayer(context, _store, p),
            ),
          if (answered.isNotEmpty)
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
        ],
      ),
    );
  }

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(_pagePadding, 12, _pagePadding, 4),
    child: PrayerLabel(text),
  );
}


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

  const _PrayerRow({
    required this.prayer,
    required this.subtitle,
    this.onTap,
    this.onCheck,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return ListTile(
      onTap: onTap,
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
  final VoidCallback? onSettings;
  const _FirstTime({
    required this.passage,
    required this.translation,
    required this.onAdd,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final verse = passageText(passage(_welcomeVerse));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prayer'),
        actions: [
          if (onSettings case final open?)
            IconButton(tooltip: 'Settings', icon: const Icon(Icons.tune), onPressed: open),
        ],
      ),
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
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Add a prayer'),
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
