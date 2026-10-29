import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'prayer_sheet.dart';
import 'prayer_store.dart';
import 'theme.dart';

const _pagePadding = 16.0;
const _numberSize = 28.0;

/// What the From the Word screens read from the app.
class PrayerEnv {
  final PrayerContent content;
  final PrayerStore store;
  final PassageLookup passage;
  final String Function() translation;
  final ShareText share;
  const PrayerEnv({
    required this.content,
    required this.store,
    required this.passage,
    required this.translation,
    this.share = shareText,
  });
}

/// A numbered prayer point with the verse it stands on, so a group can pray "point 3".
class PointTile extends StatelessWidget {
  final int number;
  final PrayerPoint point;
  const PointTile({super.key, required this.number, required this.point});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _pagePadding, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: _numberSize,
            height: _numberSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(point.text, style: scriptureStyle(context).copyWith(fontSize: 17)),
                const SizedBox(height: 4),
                VerseChip(point.ref),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension PrayerEnvOfApp on AppState {
  /// What the From the Word screens read, in the reader's translation.
  PrayerEnv get prayerEnv => PrayerEnv(
    content: prayerContent,
    store: prayers,
    passage: passageLookupFor(db, () => settings.translation),
    translation: () => settings.translation,
  );
}
