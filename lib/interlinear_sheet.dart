import 'package:berea_harness/berea_harness.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'theme.dart';
import 'word_study_screen.dart';

/// The Hebrew or Greek words of one verse with transliteration and gloss. Tap a word for its
/// lexicon entry and, from there, its full word study. The original-language word order is kept; it is not aligned to the English.
/// The Psalms' book id, whose titles are verse 0 in the Hebrew text.
const _psalmsBookId = 19;

Future<void> showInterlinear(BuildContext context, AppState s, Ref ref) {
  final words = s.db.words(ref);
  // A psalm's title is verse 0 in the Hebrew text and has no verse in English; it shows with verse 1.
  final title = ref.book.id == _psalmsBookId && ref.verseStart == 1
      ? s.db.words(Ref(ref.book, ref.chapter, 0, 0))
      : const <WordTag>[];
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
              Text(
                ref.book.id < 40
                    ? 'Parsing: ETCBC morphology, through STEPBible (CC BY-NC upstream).'
                    : "Parsing: Tyndale House's morphology, published by STEPBible.",
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (title.isNotEmpty) ...[
                              Text(
                                "The psalm's title, in the Hebrew text",
                                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                              ),
                              const SizedBox(height: 6),
                              _wordWrap(s, title, ref),
                              const SizedBox(height: 16),
                              Text(
                                'Verse 1',
                                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                              ),
                              const SizedBox(height: 6),
                            ],
                            _wordWrap(s, words, ref),
                          ],
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

Widget _wordWrap(AppState s, List<WordTag> words, Ref ref) => Wrap(
  textDirection: ref.book.id < 40 ? TextDirection.rtl : TextDirection.ltr,
  spacing: 8,
  runSpacing: 8,
  children: [for (final w in words) _WordCard(s: s, w: w, ref: ref)],
);

class _WordCard extends StatelessWidget {
  final AppState s;
  final WordTag w;
  final Ref ref;
  const _WordCard({required this.s, required this.w, required this.ref});

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
            if (s.db.verbParsing(w.morph) case final sense?)
              Text(sense, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
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
                Text(
                  [
                    w.translit,
                    if (partOfSpeech(entries.firstOrNull?.pos ?? '') case final p when p.isNotEmpty)
                      p,
                  ].join(' · '),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                if (entries.isEmpty) const Text('No lexicon entry.'),
                for (final e in entries) ...[
                  Text(
                    e.gloss.isEmpty ? e.lemma : 'STEPBible lists it as "${e.gloss}"',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  // The lexicons as written stay a tap away for those who read them.
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text("Scholar's lexicon entry"),
                    subtitle: Text("Strong's ${e.key}"),
                    children: [
                      SelectableText(e.definition, style: const TextStyle(height: 1.45)),
                      if (s.db.fullLexicon(e.key) case final full?) ...[
                        const SizedBox(height: 12),
                        const Text('Full LSJ entry', style: TextStyle(fontWeight: FontWeight.w600)),
                        SelectableText(full, style: const TextStyle(height: 1.45)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              showWordStudy(context, s, ref, pos: w.pos);
            },
            child: const Text('Word study'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }
}
