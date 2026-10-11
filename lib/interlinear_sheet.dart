import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';

/// The Hebrew or Greek words of one verse with transliteration and gloss. Tap a word for its
/// lexicon entry. The original-language word order is kept; it is not aligned to the English.
Future<void> showInterlinear(BuildContext context, AppState s, Ref ref) {
  final words = s.db.words(ref);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return FractionallySizedBox(
        heightFactor: 0.75,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ref.label,
                style: TextStyle(fontFamilyFallback: scriptureFontFallback, fontSize: 22),
              ),
              Text(
                ref.book.id < 40 ? 'Hebrew, read right to left' : 'Greek',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: words.isEmpty
                    ? Text(
                        'No original-language words for this verse.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      )
                    : SingleChildScrollView(
                        child: Wrap(
                          textDirection: ref.book.id < 40 ? TextDirection.rtl : TextDirection.ltr,
                          spacing: 8,
                          runSpacing: 8,
                          children: [for (final w in words) _WordCard(s: s, w: w)],
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _WordCard extends StatelessWidget {
  final AppState s;
  final WordTag w;
  const _WordCard({required this.s, required this.w});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _showLexicon(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(w.original, style: const TextStyle(fontSize: 22)),
            Text(w.translit, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            Text(w.gloss, style: TextStyle(fontSize: 13, color: scheme.primary)),
          ],
        ),
      ),
    );
  }

  void _showLexicon(BuildContext context) {
    final entries = [
      for (final code in w.strongs.split(' '))
        if (code.isNotEmpty) ?s.db.lexicon(code),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(w.original),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${w.translit} · ${w.morph}', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                if (entries.isEmpty) const Text('No lexicon entry.'),
                for (final e in entries) ...[
                  Text(
                    '${e.key} ${e.lemma} (${e.translit}) · ${e.gloss}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(e.definition, style: const TextStyle(height: 1.45)),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }
}
