import 'package:berea_harness/berea_harness.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'commentary_sheet.dart';
import 'study_store.dart';
import 'today.dart';
import 'theme.dart';

const _sheetHeight = 0.85;
const _crossReferenceCap = 200;

/// One verse with everything printed or kept beside it, each part folded under a line that says
/// how many there are: the verse in each translation on this phone, what the BSB publisher prints
/// with it, the cross reference list, the commentaries, and the reader's own notes. [onOpen] takes
/// the reader to a passage it names.
Future<void> showThisVerse(
  BuildContext context,
  AppState s,
  Ref ref, {
  required void Function(Ref) onOpen,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => FractionallySizedBox(
      heightFactor: _sheetHeight,
      child: ThisVerse(
        state: s,
        verse: ref,
        onOpen: (r) {
          Navigator.pop(ctx);
          onOpen(r);
        },
        onCommentary: () => showCommentary(ctx, s, ref),
      ),
    ),
  );
}

class ThisVerse extends StatelessWidget {
  final AppState state;
  final Ref verse;
  final void Function(Ref) onOpen;
  final VoidCallback onCommentary;
  const ThisVerse({
    super.key,
    required this.state,
    required this.verse,
    required this.onOpen,
    required this.onCommentary,
  });

  int get _verseNumber => verse.verseStart ?? 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 13);
    final db = state.db;
    final bsb = defaultTranslation;
    final empty = db.emptyVerseNote(verse.book.id, verse.chapter, _verseNumber);
    final notes = db.footnotes(verse.book.id, verse.chapter, _verseNumber);
    final parallels = _parallels(db);
    final crossRefs = _crossReferences(db);
    final translations = [
      for (final t in db.translations())
        if (db
            .passage(verse, translation: t)
            .map((v) => v.text)
            .join(' ')
            .trim()
            .isNotEmpty)
          t,
    ];
    final mine = [
      for (final n in state.study.notes(
        book: verse.book,
        chapter: verse.chapter,
      ))
        if (n.verse != null && _overlaps(n.verse!)) n,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(
          verse.label,
          style: TextStyle(
            fontFamilyFallback: scriptureFontFallback,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 4),
        if (empty != null) ...[
          Text(
            'The $bsb prints this verse in a footnote at ${verse.book.name} ${verse.chapter}:${empty.host}.',
            style: muted,
          ),
          const SizedBox(height: 4),
          Text(
            empty.text,
            style: scriptureStyle(context).copyWith(fontSize: 16),
          ),
          const SizedBox(height: 8),
        ],
        _Fold(
          title: 'In each translation on this phone',
          count: translations.length,
          open: true,
          children: [
            for (final t in translations)
              _Line(
                label: t,
                text: db
                    .passage(verse, translation: t)
                    .map((v) => v.text)
                    .join(' '),
                scripture: true,
              ),
          ],
        ),
        if (notes.isNotEmpty)
          _Fold(
            title: "$bsb translators' footnote${notes.length == 1 ? '' : 's'}",
            count: notes.length,
            open: true,
            children: [for (final n in notes) _Line(text: n.text)],
          ),
        if (parallels.isNotEmpty)
          _Fold(
            title: 'Parallel passages printed by the $bsb under this heading',
            count: parallels.length,
            children: [
              for (final r in parallels)
                _Line(text: r.label, onTap: () => onOpen(r), arrow: true),
            ],
          ),
        _Fold(
          title: 'Cross references',
          count: crossRefs.length,
          subtitle:
              'List published by OpenBible.info · Bible order · the votes are that site\'s '
              'visitors\', who are not named.',
          children: [
            for (final x in crossRefs)
              _Line(
                text: x.label,
                trailing:
                    '${x.votes} ${x.votes == 1 ? 'vote' : 'votes'} by site visitors'
                    '${_noteLine(x.to)}',
                onTap: () => onOpen(x.to),
                arrow: true,
              ),
          ],
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Commentary'),
          subtitle: Text('The commentaries you have downloaded', style: muted),
          trailing: const Icon(Icons.chevron_right),
          onTap: onCommentary,
        ),
        _Fold(
          title: 'Your notes',
          count: mine.length,
          children: [for (final n in mine) _Line(text: n.text)],
        ),
        const SizedBox(height: 12),
        Text(
          'In this order: the verse in each translation on this phone; what the $bsb publisher '
          'prints with its text; cross reference lists; named writers; then your notes.',
          style: muted,
        ),
      ],
    );
  }

  /// A second line on a cross reference row when the reader has a note on that passage.
  String _noteLine(Ref target) {
    final note = state.study
        .notes(book: target.book, chapter: target.chapter)
        .where((n) => _touches(n.verse, target))
        .fold<Note?>(
          null,
          (a, n) => a == null || n.updated.isAfter(a.updated) ? n : a,
        );
    return note == null
        ? ''
        : '\nYou wrote a note here on ${_noteDate(note.updated)}.';
  }

  bool _touches(Ref? note, Ref target) {
    if (note == null) return false;
    final from = target.verseStart ?? 0, to = target.verseEnd ?? from;
    final noteTo = note.verseEnd ?? note.verseStart ?? 0;
    return (note.verseStart ?? 0) <= to && noteTo >= from;
  }

  bool _overlaps(Ref n) {
    final from = n.verseStart ?? 0, to = n.verseEnd ?? from;
    return _verseNumber >= from && _verseNumber <= to;
  }

  List<Ref> _parallels(BibleDb db) {
    final raw = db
        .parallelPassages(verse.book, verse.chapter, _verseNumber)
        .replaceAll('(', '')
        .replaceAll(')', '');
    return raw.isEmpty ? const [] : RefParser.parse(raw);
  }

  List<XRef> _crossReferences(BibleDb db) {
    final all = db.xrefs(
      Ref(verse.book, verse.chapter, _verseNumber, _verseNumber),
      k: _crossReferenceCap,
    );
    int key(XRef x) =>
        x.to.book.id * 1000000 + x.to.chapter * 1000 + (x.to.verseStart ?? 0);
    return all..sort((a, b) => key(a).compareTo(key(b)));
  }
}

/// A folded line: its title, how many are inside, and the rows when opened.
class _Fold extends StatelessWidget {
  final String title;
  final int count;
  final String? subtitle;
  final bool open;
  final List<Widget> children;
  const _Fold({
    required this.title,
    required this.count,
    required this.children,
    this.subtitle,
    this.open = false,
  });

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 13,
    );
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      initiallyExpanded: open && count > 0,
      enabled: count > 0,
      title: Text('$title · $count'),
      subtitle: subtitle == null ? null : Text(subtitle!, style: muted),
      children: children,
    );
  }
}

class _Line extends StatelessWidget {
  final String? label;
  final String text;
  final String? trailing;
  final bool scripture;
  final bool arrow;
  final VoidCallback? onTap;
  const _Line({
    required this.text,
    this.label,
    this.trailing,
    this.scripture = false,
    this.arrow = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        text,
        style: scripture
            ? scriptureStyle(context).copyWith(fontSize: 16)
            : null,
      ),
      subtitle: label == null && trailing == null
          ? null
          : Text(label ?? trailing!, style: muted),
      trailing: arrow ? const Icon(Icons.chevron_right) : null,
      onTap: onTap,
    );
  }
}

String _noteDate(DateTime d) => '${d.day} ${monthName(d)} ${d.year}';
