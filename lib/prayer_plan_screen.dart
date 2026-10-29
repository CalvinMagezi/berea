import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'prayer_plan_store.dart';
import 'prayer_points.dart';
import 'prayer_pray_now.dart';
import 'prayer_sheet.dart';
import 'prayer_words.dart';
import 'theme.dart';

const _pagePadding = 16.0;
const _cardRadius = 16.0;
const _dayCircle = 34.0;
const _dayTarget = 48.0;

/// "Day 3 of 7", for a plan that is being prayed.
String planDayLabel(int day, int days) => 'Day $day of $days';

/// A prayer plan: one day at a time with the verse, the points, a prayer of your own linked to
/// it, and Amen. There are no streaks: a missed day is simply the next one to pray.
class PrayerPlanScreen extends StatefulWidget {
  final AppState state;
  final PrayerPlan plan;
  const PrayerPlanScreen({super.key, required this.state, required this.plan});

  @override
  State<PrayerPlanScreen> createState() => _PrayerPlanScreenState();
}

class _PrayerPlanScreenState extends State<PrayerPlanScreen> {
  AppState get s => widget.state;
  PrayerPlan get plan => widget.plan;
  PrayerPlanStore get _plans => s.prayerPlans;

  /// The day on show; null follows the first day not yet prayed.
  int? _picked;

  int _shown(Set<int> done) => _picked ?? _plans.currentDay(plan.id, plan.days.length) ?? 1;

  void _amen(int day) {
    _plans.pray(plan.id, day, plan.days.length);
    final finished = _plans.run(plan.id)?.finished != null;
    sayPrayer(context, finished ? 'Amen. ${plan.title} is finished.' : 'Amen. Day $day done.');
    setState(() => _picked = null);
    if (finished) Navigator.pop(context);
  }

  void _pray(PlanDay day, int number) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => day.points.isEmpty
          ? LordsPrayerScreen(
              passage: s.prayerEnv.passage,
              translation: s.prayerEnv.translation,
              ref: day.passage,
              title: day.title,
            )
          : LinesPrayerScreen(
              env: s.prayerEnv,
              title: day.title,
              points: day.points,
              onAmen: () => _amen(number),
            ),
    ),
  );

  Future<void> _linkPrayer() async {
    final praying = s.prayers.praying();
    final run = _plans.run(plan.id);
    final chosen = await showModalBottomSheet<int?>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Your prayer for this plan')),
            if (praying.isEmpty)
              const ListTile(subtitle: Text('Add a prayer in Prayer, then link it here.')),
            for (final p in praying)
              ListTile(
                title: Text(p.title),
                selected: p.id == run?.prayerId,
                onTap: () => Navigator.pop(context, p.id),
              ),
            if (run?.prayerId != null)
              ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('Unlink'),
                onTap: () => Navigator.pop(context, -1),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    _plans.linkPrayer(plan.id, chosen == -1 ? null : chosen);
  }

  Future<void> _stop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stop ${plan.title}?'),
        content: const Text('The days you prayed are removed from this plan. Your prayers stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop plan')),
        ],
      ),
    );
    if (ok != true) return;
    _plans.stop(plan.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_plans, s.prayers]),
    builder: (context, _) {
      final run = _plans.run(plan.id);
      if (run == null) return Scaffold(appBar: AppBar(title: Text(plan.title)));
      final done = _plans.daysPrayed(plan.id);
      final number = _shown(done);
      final day = plan.days[number - 1];
      final scheme = Theme.of(context).colorScheme;
      final linked = run.prayerId == null ? null : s.prayers.prayer(run.prayerId!);
      final verse = passageText(s.prayerEnv.passage(day.passage));
      return Scaffold(
        appBar: AppBar(
          title: Text(plan.title),
          actions: [
            PopupMenuButton<void>(
              tooltip: 'Plan options',
              itemBuilder: (_) => [PopupMenuItem(onTap: _stop, child: const Text('Stop plan'))],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(_pagePadding, 8, _pagePadding, 24),
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
                  PrayerLabel('Prayer plan · ${planDayLabel(number, plan.days.length)}'),
                  const SizedBox(height: 6),
                  Text(
                    day.title,
                    style: scriptureStyle(context)
                        .copyWith(fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                  if (verse.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(verse, style: scriptureStyle(context).copyWith(fontSize: 16)),
                  ],
                  const SizedBox(height: 4),
                  Text(day.passage.label, style: TextStyle(color: scheme.primary)),
                  if (day.points.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Pray this psalm a verse at a time.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  for (var i = 0; i < day.points.length; i++)
                    Transform.translate(
                      offset: const Offset(-_pagePadding, 0),
                      child: PointTile(number: i + 1, point: day.points[i]),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.volunteer_activism_outlined, color: scheme.primary),
              title: Text(linked?.title ?? 'Link a prayer of your own'),
              subtitle: Text(linked == null ? 'Optional' : 'Your prayer today'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _linkPrayer,
            ),
            if (plan.fasting) _fasting(context, run),
            const SizedBox(height: 12),
            _days(context, number, done),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _pray(day, number),
              icon: const Icon(Icons.volunteer_activism_outlined),
              label: Text(day.points.isEmpty ? 'Pray the psalm' : 'Pray these now'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: done.contains(number) ? null : () => _amen(number),
              icon: const Icon(Icons.check),
              label: Text(done.contains(number) ? 'Day $number done' : 'Amen · day $number done'),
            ),
          ],
        ),
      );
    },
  );

  /// Fasting is off until chosen, and the health note shows whenever it is on.
  Widget _fasting(BuildContext context, PlanRun run) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Fasting with this plan · ${run.fasting ? 'on' : 'off'}'),
            subtitle: const Text('Optional'),
            value: run.fasting,
            onChanged: (on) => _plans.setFasting(plan.id, on),
          ),
          if (run.fasting)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(prayerFastingNote, style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }

  Widget _days(BuildContext context, int now, Set<int> done) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 0,
      runSpacing: 0,
      children: [
        for (var d = 1; d <= plan.days.length; d++)
          Semantics(
            button: true,
            label: 'Day $d${done.contains(d) ? ', done' : ''}',
            onTap: () => setState(() => _picked = d),
            excludeSemantics: true,
            child: InkResponse(
              onTap: () => setState(() => _picked = d),
              child: SizedBox(
                width: _dayTarget,
                height: _dayTarget,
                child: Center(
                  child: Container(
                    width: _dayCircle,
                    height: _dayCircle,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done.contains(d) ? scheme.primary : null,
                      border: done.contains(d)
                          ? null
                          : Border.all(
                              color: d == now
                                  ? scheme.primary
                                  : scheme.outline.withValues(alpha: 0.3),
                              width: d == now ? 2 : 1,
                            ),
                    ),
                    child: done.contains(d)
                        ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                        : Text('$d', style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
