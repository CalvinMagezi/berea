import 'dart:async';

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'plans.dart';
import 'theme.dart';
import 'today.dart';

const _cardRadius = 16.0;
const _labelSpacing = 1.4;

/// Below this the folded card shortens book names.
const _fullNamesWidth = 560.0;

/// A moment past midnight, so the new day has begun when the card looks again.
const _pastMidnight = Duration(seconds: 1);

/// Today on the Bible: the verse of the day and today's reading. In full on the first look of
/// the day, then one line that opens it again. Left open past midnight, it turns to the new day.
class TodayCard extends StatefulWidget {
  final AppState state;
  final bool full;
  final ValueChanged<bool> onFull;
  const TodayCard({super.key, required this.state, required this.full, required this.onFull});

  @override
  State<TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<TodayCard> {
  Timer? _midnight;

  AppState get state => widget.state;
  bool get full => widget.full;
  ValueChanged<bool> get onFull => widget.onFull;

  @override
  void initState() {
    super.initState();
    _waitForMidnight();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    super.dispose();
  }

  void _waitForMidnight() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + _pastMidnight, () {
      // A new day unfolds the card again, with the new verse and reading.
      state.openTodayIfNewDay();
      if (!mounted) return;
      setState(() {});
      _waitForMidnight();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(_cardRadius),
      clipBehavior: Clip.antiAlias,
      child: full ? _full(context, scheme) : _folded(context, scheme),
    );
  }

  Widget _folded(BuildContext context, ColorScheme scheme) {
    final daily = verseOfTheDay(state.db, DateTime.now());
    final reading = state.todaysReading;
    return InkWell(
      onTap: () => onFull(true),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: LayoutBuilder(
          builder: (context, c) {
            // A phone shortens book names, as the board does, so the line keeps the reference.
            final short = c.maxWidth < _fullNamesWidth;
            return Row(
              children: [
                Icon(Icons.wb_sunny_outlined, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Today',
                          style: TextStyle(fontWeight: FontWeight.w600, color: scheme.primary),
                        ),
                        TextSpan(text: ' · ${short ? shortLabel(daily) : daily.label}'),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (reading != null)
                  ActionChip(
                    avatar: const Icon(Icons.calendar_month_outlined, size: 16),
                    label: Text(readingLabel(reading, short: short)),
                    onPressed: () => state.openInReader(state.planProgress?.next ?? reading.first),
                  ),
                IconButton(
                  tooltip: 'Show today',
                  icon: const Icon(Icons.expand_more),
                  onPressed: () => onFull(true),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _full(BuildContext context, ColorScheme scheme) {
    final now = DateTime.now();
    final daily = verseOfTheDay(state.db, now);
    final translation = state.settings.translation;
    final text = state.db.passage(daily, translation: translation).map((v) => v.text).join(' ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'VERSE OF THE DAY · ${shortDate(now).toUpperCase()}',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: _labelSpacing,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Fold today',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.expand_less),
                onPressed: () => onFull(false),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              text,
              style: scriptureStyle(context).copyWith(fontSize: 18, fontStyle: FontStyle.italic),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(daily.label, style: TextStyle(color: scheme.primary)),
              ),
              TextButton(
                onPressed: () => state.openInReader(daily),
                child: const Text('Read in context'),
              ),
            ],
          ),
          Divider(height: 1, color: scheme.outline.withValues(alpha: 0.2)),
          _planRow(scheme),
        ],
      ),
    );
  }

  Widget _planRow(ColorScheme scheme) {
    final plan = state.activePlan;
    final reading = state.todaysReading;
    void openPlans() => state.openPlansRequest.value++;
    final (title, subtitle) = plan == null || reading == null
        ? ('Start a reading plan', _choiceSummary())
        : (
            'Today: ${readingLabel(reading)}',
            '${plan.name} · day ${state.planDay(plan)} of ${plan.days}',
          );
    return ListTile(
      contentPadding: const EdgeInsets.only(right: 8),
      leading: Icon(Icons.calendar_month_outlined, color: scheme.onSurfaceVariant),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: reading == null
          ? openPlans
          : () => state.openInReader(state.planProgress?.next ?? reading.first),
      trailing: reading == null
          ? const Icon(Icons.chevron_right)
          : TextButton(onPressed: openPlans, child: const Text('Open Plans')),
    );
  }

  static String _choiceSummary() {
    final days = [for (final p in readingPlans) p.days]..sort();
    final count = readingPlans.length;
    final many = count < _countWords.length ? _countWords[count] : '$count';
    return '$many to choose from, ${days.first} to ${days.last} days';
  }

  /// Small counts in words, as the card's line is drawn: "Three to choose from".
  static const _countWords = ['None', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven'];
}

/// The quiet line above the verse the reader stopped at in an earlier session.
String stoppedLabel(DateTime? at, DateTime now) {
  if (at == null) return 'Where you stopped';
  return switch (daysBetween(at, now)) {
    0 => 'Where you stopped',
    1 => 'Where you stopped yesterday',
    _ => 'Where you stopped on ${shortDate(at)}',
  };
}
