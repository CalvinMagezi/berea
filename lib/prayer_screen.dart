import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'prayer_pray_now.dart';
import 'prayer_sheet.dart';
import 'prayer_store.dart';
import 'theme.dart';

export 'prayer_pray_now.dart' show PrayNowScreen, LordsPrayerScreen;
export 'prayer_sheet.dart' show PassageLookup, ShareText, passageLookupFor, showPrayerSheet;

/// Local rather than the shell's constant, so this screen does not import the shell.
const _wideBreakpoint = 760.0;
const _wideListWidth = 400.0;
const _pagePadding = 16.0;
const _daysInWeek = 7;
const _daysInTwoWeeks = 14;

/// Lines an answer up under its title, past the check mark.
const _answerIndent = 72.0;

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
  const PrayerScreen({
    super.key,
    required this.store,
    required this.passage,
    required this.translation,
    this.share = shareText,
  });

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen> {
  /// Bumped to start a fresh Pray now session in the wide panel.
  var _session = 0;

  PrayerStore get _store => widget.store;

  Future<void> _add() => showPrayerSheet(context, _store, passage: widget.passage);

  void _edit(Prayer p) => showPrayerSheet(context, _store, editing: p, passage: widget.passage);

  void _prayNow() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) =>
          PrayNowScreen(store: _store, passage: widget.passage, translation: widget.translation),
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
      builder: (_) => AnsweredScreen(store: _store, share: widget.share),
    ),
  );

  void _shareList(BuildContext button) =>
      widget.share(prayerListText(_store.praying()), shareOrigin(button));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _store,
    builder: (context, _) => LayoutBuilder(
      builder: (context, c) {
        if (_store.isEmpty) {
          return _FirstTime(
            passage: widget.passage,
            translation: widget.translation,
            onAdd: _add,
            onLordsPrayer: _lordsPrayer,
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
            onDone: () => setState(() => _session++),
          ),
        ),
        const _PrivacyLine(),
      ],
    );
  }

  Widget _list(BuildContext context, {required bool wide}) {
    final praying = _store.praying();
    final answered = _store.answered();
    final now = _store.now();
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
          if (!wide && praying.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(_pagePadding, 4, _pagePadding, 12),
              child: FilledButton.icon(
                onPressed: _prayNow,
                icon: const Icon(Icons.volunteer_activism_outlined),
                label: Text('Pray now · ${_count(praying.length)}'),
              ),
            ),
          _section('Praying · ${praying.length}'),
          for (final p in praying)
            _PrayerRow(
              prayer: p,
              subtitle: lastPrayedLabel(p, now),
              onTap: () => _edit(p),
              onCheck: () => answerPrayer(context, _store, p),
            ),
          if (wide) ...[
            _section('Answered · ${answered.length}'),
            for (final p in answered)
              _PrayerRow(
                prayer: p,
                subtitle: 'answered ${answeredLabel(p, now)}',
                onTap: _answered,
              ),
          ] else if (answered.isNotEmpty)
            ListTile(
              leading: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
              title: Text('Answered · ${answered.length}'),
              subtitle: Text(answered.first.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: _answered,
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
  const _PrayerRow({required this.prayer, required this.subtitle, this.onTap, this.onCheck});

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
              'Prayers stay on this device. Nothing is sent anywhere, and nothing is shared '
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
  const _FirstTime({
    required this.passage,
    required this.translation,
    required this.onAdd,
    required this.onLordsPrayer,
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
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Add a prayer'),
              ),
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

/// Answered prayers, newest first, each with the person's own line and date.
class AnsweredScreen extends StatelessWidget {
  final PrayerStore store;
  final ShareText share;
  const AnsweredScreen({super.key, required this.store, this.share = shareText});

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
                '${answered.length} answered, newest first.',
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
                            onPressed: () => share(testimonyText(p), shareOrigin(button)),
                            icon: const Icon(Icons.share_outlined, size: 18),
                            label: const Text('Share a testimony'),
                          ),
                        ),
                        TextButton(
                          onPressed: () => store.unanswer(p.id),
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
