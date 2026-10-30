import 'package:flutter/material.dart';

import 'app_state.dart';
import 'settings_sheet.dart';

const commentaryHint =
    'No commentaries are downloaded yet. They are free, and add what Matthew Henry, Barnes and '
    'others wrote on each passage.';
const listenCommentaryHint =
    'The deep dive can quote commentators once commentaries are downloaded. They are free.';
const lexiconHint =
    'The complete Greek lexicon gives the full entry for every New Testament word. It is free, '
    'about 9 MB.';

/// Whether any commentary pack is installed.
bool hasCommentary(AppState s) => s.commentary.library.modules().isNotEmpty;

/// A quiet line saying what an optional download would add, with a button to it in Settings.
class ExtrasHint extends StatelessWidget {
  final AppState state;
  final SettingsPart part;
  final String text;
  const ExtrasHint({super.key, required this.state, required this.part, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: Icon(Icons.download_outlined, size: 18, color: scheme.onSurfaceVariant),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => showSettingsSheet(context, state, show: part),
                  child: const Text('Download in Settings'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
