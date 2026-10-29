import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'prayer_points.dart';
import 'prayer_pray_now.dart';
import 'prayer_sheet.dart';
import 'prayer_store.dart';
import 'prayer_words.dart';
import 'theme.dart';

const _sheetPadding = 20.0;
const _maxSheetHeight = 0.8;

/// Prayers of the reader's own that stand on [verse], from the mark and the selection bar.
List<Prayer> prayersOnVerse(List<Prayer> praying, Ref verse) => [
  for (final p in praying)
    if (p.ref case final r? when r.overlaps(verse)) p,
];

/// Pray this verse: the points written for it, or the verse as it is when there are none, with
/// Add to my list and Pray now. Any prayer of the reader's own on the verse is shown first.
Future<void> showPrayVerseSheet(BuildContext context, PrayerEnv env, Ref verse) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * _maxSheetHeight),
      builder: (sheet) => _PrayVerseSheet(env: env, verse: verse, page: context),
    );

class _PrayVerseSheet extends StatelessWidget {
  final PrayerEnv env;
  final Ref verse;

  /// The screen under the sheet, which stays mounted to open the next page from.
  final BuildContext page;
  const _PrayVerseSheet({required this.env, required this.verse, required this.page});

  void _pray(BuildContext sheet, List<PrayerPoint> points) {
    Navigator.pop(sheet);
    Navigator.push(
      page,
      MaterialPageRoute<void>(
        builder: (_) => points.isEmpty
            ? LordsPrayerScreen(
                passage: env.passage,
                translation: env.translation,
                ref: verse,
                title: verse.label,
              )
            : LinesPrayerScreen(env: env, title: verse.label, points: points),
      ),
    );
  }

  Future<void> _add(BuildContext sheet) async {
    Navigator.pop(sheet);
    final id = await showPrayerSheet(
      page,
      env.store,
      verse: verse.label,
      passage: env.passage,
      content: env.content,
    );
    if (id != null && page.mounted) sayPrayer(page, 'Added to your list');
  }

  @override
  Widget build(BuildContext context) {
    final points = env.content.pointsForVerse(verse);
    final own = prayersOnVerse([...env.store.praying(), ...env.store.answered()], verse);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: _sheetPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _sheetPadding),
            child: Text('Pray ${verse.label}', style: Theme.of(context).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(_sheetPadding, 2, _sheetPadding, 8),
            child: Text(
              points.isEmpty
                  ? 'No prayer points for this verse. Pray it as it is, or in your own words.'
                  : '${points.length == 1 ? 'One prayer point' : '${points.length} prayer points'} '
                        'from the Word, written for Berea',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in own)
                  ListTile(
                    leading: const Icon(Icons.volunteer_activism),
                    title: Text(p.title),
                    subtitle: Text(p.isAnswered ? 'Answered' : 'Your prayer'),
                  ),
                if (points.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _sheetPadding, vertical: 4),
                    child: Text(
                      passageText(env.passage(verse)),
                      style: scriptureStyle(context).copyWith(fontSize: 17),
                    ),
                  ),
                for (var i = 0; i < points.length; i++) PointTile(number: i + 1, point: points[i]),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(_sheetPadding - 4, 12, _sheetPadding - 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _add(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add to my list'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _pray(context, points),
                    icon: const Icon(Icons.volunteer_activism_outlined),
                    label: const Text('Pray now'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
