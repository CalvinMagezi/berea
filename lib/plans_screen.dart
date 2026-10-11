import 'package:flutter/material.dart';

import 'app_state.dart';
import 'plans.dart';
import 'theme.dart';

/// Pick a reading plan, see today's chapters, tick days off. Progress stays on the device.
class PlansScreen extends StatefulWidget {
  final AppState state;
  const PlansScreen({super.key, required this.state});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  AppState get s => widget.state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plan = s.activePlan;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          plan?.name ?? 'Reading plans',
          style: TextStyle(fontFamilyFallback: scriptureFontFallback),
        ),
        actions: [
          if (plan != null)
            TextButton(onPressed: () => setState(s.stopPlan), child: const Text('Stop plan')),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: plan == null ? _choose(scheme) : _progress(plan, scheme),
        ),
      ),
    );
  }

  Widget _choose(ColorScheme scheme) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      for (final p in readingPlans)
        Card(
          color: scheme.surfaceContainerHighest,
          elevation: 0,
          child: ListTile(
            title: Text(p.name),
            subtitle: Text('${p.description} ${p.days} days.'),
            trailing: FilledButton(
              onPressed: () => setState(() => s.startPlan(p)),
              child: const Text('Start'),
            ),
          ),
        ),
    ],
  );

  Widget _progress(ReadingPlan plan, ColorScheme scheme) {
    final days = s.planSchedule(plan);
    final done = s.study.planDaysDone(plan.id);
    final today = s.planDay(plan);
    return ListView.builder(
      itemCount: days.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              '${done.length} of ${plan.days} days read. Today is day $today.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          );
        }
        final day = i;
        final refs = days[day - 1];
        return CheckboxListTile(
          value: done.contains(day),
          tileColor: day == today ? scheme.surfaceContainerHighest : null,
          onChanged: (v) => setState(() => s.study.setPlanDay(plan.id, day, v ?? false)),
          title: Text('Day $day'),
          subtitle: Text(readingLabel(refs)),
          secondary: IconButton(
            tooltip: 'Read',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () {
              s.setReader(refs.first.book, refs.first.chapter);
              Navigator.pop(context);
            },
          ),
        );
      },
    );
  }
}
