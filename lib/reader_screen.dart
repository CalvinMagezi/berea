import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'note_dialog.dart';
import 'theme.dart';

class ReaderScreen extends StatefulWidget {
  final AppState state;
  const ReaderScreen({super.key, required this.state});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _selected = <int>{};
  final _scroll = ScrollController();

  AppState get s => widget.state;
  Book get book => bookById(s.readerBook);
  int get chapter => s.readerChapter;

  @override
  void initState() {
    super.initState();
    s.addListener(_refresh);
  }

  @override
  void dispose() {
    s.removeListener(_refresh);
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _go(Book b, int c) {
    _selected.clear();
    s.setReader(b, c);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Ref get _selection {
    final sorted = _selected.toList()..sort();
    return Ref(book, chapter, sorted.first, sorted.last);
  }

  Future<void> _pickChapter() async {
    final picked = await showDialog<(Book, int)>(
      context: context,
      builder: (_) => _ChapterPicker(s: s, initial: book),
    );
    if (picked != null) _go(picked.$1, picked.$2);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final translation = s.settings.translation;
    final verses = s.db.passage(Ref(book, chapter), translation: translation);
    final chapters = s.db.chapterCount(book, translation: translation);
    final highlights = s.study.highlights(book, chapter);
    final noted = {
      for (final n in s.study.notes(book: book, chapter: chapter))
        for (var v = n.ref.verseStart!; v <= n.ref.verseEnd!; v++) v,
    };
    return Scaffold(
      appBar: AppBar(
        title: TextButton(
          onPressed: _pickChapter,
          child: Text(
            '${book.name} $chapter',
            style: TextStyle(fontFamilyFallback: scriptureFontFallback, fontSize: 22),
          ),
        ),
        actions: [
          DropdownButton<String>(
            value: translation,
            underline: const SizedBox.shrink(),
            items: [
              for (final t in s.db.translations()) DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: (t) => s.updateSettings(s.settings.copyWith(translation: t)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: verses.isEmpty
              ? Center(
                  child: Text(
                    'No text for ${book.name} $chapter in $translation.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                  itemCount: verses.length,
                  itemBuilder: (_, i) {
                    final v = verses[i];
                    final on = _selected.contains(v.verse);
                    return InkWell(
                      onTap: () =>
                          setState(() => on ? _selected.remove(v.verse) : _selected.add(v.verse)),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: highlights.contains(v.verse)
                              ? scheme.primary.withValues(alpha: 0.18)
                              : null,
                          border: on
                              ? Border(left: BorderSide(color: scheme.primary, width: 3))
                              : null,
                        ),
                        child: Text.rich(
                          TextSpan(
                            style: scriptureStyle(context).copyWith(fontSize: 18, height: 1.6),
                            children: [
                              TextSpan(
                                text: '${v.verse} ',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(text: v.text),
                              if (noted.contains(v.verse))
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Icon(
                                      Icons.sticky_note_2_outlined,
                                      size: 14,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
      bottomNavigationBar: _selected.isEmpty
          ? _ChapterNav(
              canPrev: chapter > 1 || book.id > 1,
              canNext: chapter < chapters || book.id < books.length,
              onPrev: () =>
                  chapter > 1 ? _go(book, chapter - 1) : _goLastChapter(bookById(book.id - 1)),
              onNext: () =>
                  chapter < chapters ? _go(book, chapter + 1) : _go(bookById(book.id + 1), 1),
            )
          : _SelectionBar(
              label: _selection.label,
              onAsk: () {
                s.askAbout(_selection);
                setState(_selected.clear);
              },
              onNote: () async {
                final ref = _selection;
                final existing = s.study
                    .notes(book: book, chapter: chapter)
                    .where((n) => n.ref == ref)
                    .firstOrNull;
                await showNoteDialog(context, s, ref: ref, note: existing);
                setState(_selected.clear);
              },
              onHighlight: () {
                for (final v in _selected) {
                  s.study.toggleHighlight(book, chapter, v);
                }
                setState(_selected.clear);
              },
              onClear: () => setState(_selected.clear),
            ),
    );
  }

  void _goLastChapter(Book b) => _go(b, s.db.chapterCount(b, translation: s.settings.translation));
}

class _ChapterNav extends StatelessWidget {
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _ChapterNav({
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: canPrev ? onPrev : null,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Previous'),
            ),
            TextButton.icon(
              onPressed: canNext ? onNext : null,
              icon: const Icon(Icons.chevron_right),
              label: const Text('Next'),
              iconAlignment: IconAlignment.end,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final String label;
  final VoidCallback onAsk;
  final VoidCallback onNote;
  final VoidCallback onHighlight;
  final VoidCallback onClear;
  const _SelectionBar({
    required this.label,
    required this.onAsk,
    required this.onNote,
    required this.onHighlight,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
                ),
              ),
              IconButton(
                tooltip: 'Ask Berea',
                icon: const Icon(Icons.auto_stories_outlined),
                onPressed: onAsk,
              ),
              IconButton(
                tooltip: 'Note',
                icon: const Icon(Icons.sticky_note_2_outlined),
                onPressed: onNote,
              ),
              IconButton(
                tooltip: 'Highlight',
                icon: const Icon(Icons.border_color_outlined),
                onPressed: onHighlight,
              ),
              IconButton(
                tooltip: 'Clear selection',
                icon: const Icon(Icons.close),
                onPressed: onClear,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChapterPicker extends StatefulWidget {
  final AppState s;
  final Book initial;
  const _ChapterPicker({required this.s, required this.initial});

  @override
  State<_ChapterPicker> createState() => _ChapterPickerState();
}

class _ChapterPickerState extends State<_ChapterPicker> {
  Book? _book;

  @override
  Widget build(BuildContext context) {
    final b = _book;
    return AlertDialog(
      title: Text(b == null ? 'Book' : b.name),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 420,
        height: 480,
        child: b == null
            ? ListView.builder(
                itemCount: books.length,
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  title: Text(books[i].name),
                  selected: books[i].id == widget.initial.id,
                  onTap: () => setState(() => _book = books[i]),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (
                      var c = 1;
                      c <= widget.s.db.chapterCount(b, translation: widget.s.settings.translation);
                      c++
                    )
                      ActionChip(
                        label: Text('$c'),
                        onPressed: () => Navigator.pop(context, (b, c)),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        if (b != null)
          TextButton(onPressed: () => setState(() => _book = null), child: const Text('Books')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
