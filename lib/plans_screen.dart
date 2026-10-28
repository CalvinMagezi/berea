import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'plans.dart';
import 'setup_screen.dart' show deviceNoun;
import 'theme.dart';
import 'today.dart';

/// Wide enough for today's portion and Start another side by side.
const _twoColumnWidth = 900.0;
const _cardRadius = 16.0;
const _labelSpacing = 1.4;
const _wordsPerMinute = 200;
const _weekDays = 7;
const _weekCircle = 30.0;
const plansCaption = 'Miss a day and Berea offers to catch up. No streak to lose.';

/// The Plans place: today's portion with chapter ticks, this week, catching up on missed days
/// and the other plans. Progress stays on the device.
class PlansScreen extends StatefulWidget {
  final AppState state;
  const PlansScreen({super.key, required this.state});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    s.addListener(_refresh);
  }

  @override
  void dispose() {
    s.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final progress = s.planProgress;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Plans',
          style: TextStyle(fontFamilyFallback: scriptureFontFallback, fontSize: 26),
        ),
        actions: [
          if (progress != null)
            PopupMenuButton<void>(
              tooltip: 'Plan options',
              itemBuilder: (_) => [
                PopupMenuItem(onTap: s.stopPlan, child: const Text('Stop plan')),
              ],
            ),
        ],
      ),
      body: progress == null
          ? _list([_section('Choose a plan'), ..._planTiles(readingPlans)])
          : LayoutBuilder(
              builder: (_, c) => c.maxWidth >= _twoColumnWidth
                  ? _wide(progress)
                  : _list([..._running(progress), ..._others(progress.plan)]),
            ),
    );
  }

  Widget _list(List<Widget> children) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: contentMaxWidth),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: children),
    ),
  );

  Widget _wide(PlanProgress progress) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _running(progress)),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._others(progress.plan, wide: true),
                const Divider(),
                Text(
                  'Progress stays on this $deviceNoun. Plans are whole chapters spread evenly '
                  'over the days.',
                  style: _muted(context),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _running(PlanProgress p) => [
    _TodayPortion(state: s, progress: p, onTick: _tick, minutes: _minutes(p)),
    if (p.missed.isNotEmpty) _catchUp(p),
    _section('This week'),
    _Week(state: s, progress: p),
    Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(plansCaption, style: _muted(context)),
    ),
  ];

  List<Widget> _others(ReadingPlan current, {bool wide = false}) => [
    _section('Start another'),
    ..._planTiles(readingPlans.where((p) => p.id != current.id), wide: wide),
  ];

  void _tick(Ref chapter, bool done) {
    final plan = s.activePlan;
    if (plan == null) return;
    s.study.setPlanChapter(plan.id, chapter, done);
    setState(() {});
  }

  /// Reading time for today's unread chapters.
  int? _minutes(PlanProgress p) {
    final unread = p.portion.where((r) => !p.done.contains(r));
    final words = unread
        .expand((r) => s.db.passage(r, translation: s.settings.translation))
        .fold(0, (n, v) => n + v.text.split(' ').length);
    return words == 0 ? null : (words / _wordsPerMinute).ceil();
  }

  Widget _catchUp(PlanProgress p) {
    final days = p.missed.length;
    final chapters = p.catchUp;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              days == 1 ? 'One earlier day to catch up' : '$days earlier days to catch up',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(readingLabel(chapters), style: _muted(context)),
            const SizedBox(height: 8),
            _Ticks(chapters: chapters, done: p.done, onTick: _tick),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => s.openInReader(chapters.first),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Catch up'),
            ),
          ],
        ),
      ),
    );
  }

  /// A wide window offers Start on each row, as the Mac board draws it; a phone row is a
  /// chevron, the whole row being the button.
  Iterable<Widget> _planTiles(Iterable<ReadingPlan> plans, {bool wide = false}) => [
    for (final p in plans)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.menu_book_outlined),
        title: Text(p.name),
        subtitle: Text('${p.chapters} chapters · about ${p.dailyLoad} a day'),
        trailing: wide
            ? TextButton(onPressed: () => _start(p), child: const Text('Start'))
            : const Icon(Icons.chevron_right),
        onTap: () => _start(p),
      ),
  ];

  /// Starting a plan begins it again from day 1, so replacing a running one asks first.
  Future<void> _start(ReadingPlan plan) async {
    final current = s.activePlan;
    if (current != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Start ${plan.name}?'),
          content: Text('This stops ${current.name}. ${plan.name} starts from day 1 today.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start')),
          ],
        ),
      );
      if (ok != true) return;
    }
    s.startPlan(plan);
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: _labelSpacing,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );
}

TextStyle _muted(BuildContext context) =>
    TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant);

/// A Material, not a decorated box, so list tiles inside it show their ink.
Widget _card(Widget child) => Builder(
  builder: (context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(_cardRadius),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: SizedBox(width: double.infinity, child: child),
    ),
  ),
);

class _TodayPortion extends StatelessWidget {
  final AppState state;
  final PlanProgress progress;
  final int? minutes;
  final void Function(Ref, bool) onTick;
  const _TodayPortion({
    required this.state,
    required this.progress,
    required this.minutes,
    required this.onTick,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plan = progress.plan;
    final next = progress.next;
    final total = plan.chapters;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${plan.name} · day ${progress.today} of ${plan.days}'.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              letterSpacing: _labelSpacing,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            readingLabel(progress.portion),
            style: scriptureStyle(context).copyWith(fontSize: 30, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _Ticks(chapters: progress.portion, done: progress.done, onTick: onTick),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (next != null)
                FilledButton.icon(
                  onPressed: () => state.openInReader(next),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: Text('Read ${next.label}'),
                )
              else
                Text('Today\'s chapters are read.', style: TextStyle(color: scheme.primary)),
              if (next != null && minutes != null)
                Text(minutes == 1 ? 'About 1 minute' : 'About $minutes minutes', style: _muted(context)),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: total == 0 ? 0 : progress.chaptersDone / total,
            backgroundColor: scheme.outline.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 6),
          Text('${progress.chaptersDone} of $total chapters', style: _muted(context)),
        ],
      ),
    );
  }
}

/// A chip for each chapter; ticked ones are filled.
class _Ticks extends StatelessWidget {
  final List<Ref> chapters;
  final Set<Ref> done;
  final void Function(Ref, bool) onTick;
  const _Ticks({required this.chapters, required this.done, required this.onTick});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final r in chapters)
          FilterChip(
            label: Text(r.label),
            selected: done.contains(r),
            onSelected: (v) => onTick(r, v),
            selectedColor: scheme.secondary,
            checkmarkColor: scheme.onSecondary,
            labelStyle: TextStyle(color: done.contains(r) ? scheme.onSecondary : scheme.onSurface),
            backgroundColor: scheme.surface,
          ),
      ],
    );
  }
}

/// Monday to Sunday of this week: read days ticked, today ringed, no count of days in a row.
class _Week extends StatelessWidget {
  final AppState state;
  final PlanProgress progress;
  const _Week({required this.state, required this.progress});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < _weekDays; i++)
          _day(context, DateTime(monday.year, monday.month, monday.day + i), now),
      ],
    );
  }

  Widget _day(BuildContext context, DateTime date, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final day = daysBetween(state.planStart, date) + 1;
    final inPlan = day >= 1 && day <= progress.plan.days;
    final done = inPlan && progress.dayDone(day);
    final today = daysBetween(date, now) == 0;
    final circle = Container(
      width: _weekCircle,
      height: _weekCircle,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? scheme.primary : null,
        border: done
            ? null
            : Border.all(
                color: today ? scheme.primary : scheme.outline.withValues(alpha: 0.3),
                width: today ? 2 : 1,
              ),
      ),
      child: done
          ? Icon(Icons.check, size: 16, color: scheme.onPrimary, semanticLabel: 'Read')
          : Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: today ? FontWeight.w700 : null,
                color: inPlan ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
    );
    return Column(
      children: [
        Text(weekdayName(date), style: _muted(context)),
        const SizedBox(height: 6),
        circle,
      ],
    );
  }
}
