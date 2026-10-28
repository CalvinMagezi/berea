import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'commentary_sheet.dart';
import 'interlinear_sheet.dart';
import 'note_dialog.dart';
import 'study_page_screen.dart';
import 'search_screen.dart';
import 'theme.dart';
import 'today_card.dart';
import 'word_study_screen.dart';

/// Where a jumped-to verse lands: a little below the top so the one before is visible.
const verseJumpAlignment = 0.08;
const maxVerseJumpAttempts = 3;

/// Wide enough to set two translations side by side instead of stacked.
const parallelSideBySideWidth = 560.0;

/// The list's first item is today's card, so verse n is item n.
const _cardItems = 1;

/// Tip T14, shown once on the first chapter until it is dismissed.
const _tipKey = 'tipT14Done';
const tipsOffKey = 'tipsOff';
const tipT14 = 'Tap a verse to highlight it, write a note, pray it or ask about it.';

class ReaderScreen extends StatefulWidget {
  final AppState state;

  /// Opens the quick chat; shown in the chapter bar so it never covers the reader's buttons.
  final VoidCallback? onQuickChat;
  const ReaderScreen({super.key, required this.state, this.onQuickChat});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _selected = <int>{};
  final _scroll = ScrollController();

  AppState get s => widget.state;
  Book get book => bookById(s.readerBook);
  int get chapter => s.readerChapter;

  /// Where the reader stopped last session, marked until the reader moves to another chapter.
  late Ref? _resume = s.resumeVerse == null ? null : Ref(book, chapter, s.resumeVerse);
  late bool _tip = !(s.prefs.getBool(_tipKey) ?? false) && !(s.prefs.getBool(tipsOffKey) ?? false);

  @override
  void initState() {
    super.initState();
    s.addListener(_refresh);
    final resume = _resume;
    if (resume != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToVerse(resume.verseStart!));
    }
  }

  void _dismissTip({bool allTips = false}) {
    s.prefs.setBool(_tipKey, true);
    if (allTips) s.prefs.setBool(tipsOffKey, true);
    setState(() => _tip = false);
  }

  /// Remembers the verse at the top of the list once a scroll settles.
  bool _onScrollEnd(ScrollEndNotification n) {
    final top = (n.context?.findRenderObject() as RenderBox?)?.localToGlobal(Offset.zero).dy;
    if (top == null) return false;
    final shown = _verseKeys.entries.where((e) {
      final box = e.value.currentContext?.findRenderObject() as RenderBox?;
      return box != null && box.attached && box.localToGlobal(Offset(0, box.size.height)).dy > top;
    });
    final first = shown.map((e) => e.key).fold<int?>(null, (a, v) => a == null || v < a ? v : a);
    if (first != null) s.rememberVerse(first);
    return false;
  }

  @override
  void dispose() {
    s.removeListener(_refresh);
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    if (_resume case final r? when r.book.id != book.id || r.chapter != chapter) _resume = null;
    setState(() {});
    final target = s.readerTargetVerse;
    if (target == null) return;
    s.readerTargetVerse = null;
    _selected
      ..clear()
      ..add(target);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToVerse(target));
  }

  /// Keys for the verses currently built, so a jump can align to the real widget.
  final _verseKeys = <int, GlobalKey>{};

  /// Keys for each verse's own text, so a long press can find the word under the finger.
  final _textKeys = <int, GlobalKey>{};
  Offset? _pressAt;

  /// A long press on a word studies that word; anywhere else in the verse it shows the verse's
  /// Hebrew or Greek words, as before.
  void _longPress(Verse v) {
    final ref = Ref(book, chapter, v.verse);
    final ctx = _textKeys[v.verse]?.currentContext;
    final at = _pressAt;
    final hit = ctx == null || at == null
        ? null
        : pressedWord(ctx, at, v.text, '${v.verse} '.length);
    if (hit == null) {
      showInterlinear(context, s, ref);
    } else {
      showWordStudy(
        context,
        s,
        ref,
        english: hit.word,
        occurrence: hit.occurrence,
        wordIndex: hit.index,
      );
    }
  }

  /// Item heights vary and the list builds lazily, so this jumps to an estimate first (which
  /// builds the verse) and then aligns exactly once the verse's widget exists.
  void _scrollToVerse(int verse, [int attempt = 0]) {
    if (!_scroll.hasClients) return;
    final ctx = _verseKeys[verse]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: verseJumpAlignment);
      return;
    }
    if (attempt >= maxVerseJumpAttempts) return;
    final count = s.db.passage(Ref(book, chapter), translation: s.settings.translation).length;
    if (count < 2) return;
    final pos = _scroll.position;
    final perItem = (pos.maxScrollExtent + pos.viewportDimension) / (count + _cardItems);
    _scroll.jumpTo(((verse - 1 + _cardItems) * perItem).clamp(0, pos.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToVerse(verse, attempt + 1));
  }

  void _go(Book b, int c) {
    _selected.clear();
    _verseKeys.clear();
    _textKeys.clear();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _resume = null;
    s.todayCardFull = false;
    s.rememberVerse(1);
    s.setReader(b, c);
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
    final parallel = s.parallelTranslation;
    final second = parallel == null || parallel == translation
        ? const <int, String>{}
        : {
            for (final v in s.db.passage(Ref(book, chapter), translation: parallel))
              v.verse: v.text,
          };
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
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => SearchScreen(state: s)),
            ),
          ),
          PopupMenuButton<String?>(
            tooltip: 'Parallel translation',
            icon: Icon(parallel == null ? Icons.view_agenda_outlined : Icons.view_agenda),
            onSelected: (t) => s.setParallel(t == '' ? null : t),
            itemBuilder: (_) => [
              const PopupMenuItem(value: '', child: Text('No parallel')),
              for (final t in s.db.translations())
                if (t != translation) PopupMenuItem(value: t, child: Text('Parallel $t')),
            ],
          ),
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
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: contentMaxWidth),
              child: verses.isEmpty
                  ? Center(
                      child: Text(
                        'No text for ${book.name} $chapter in $translation.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : NotificationListener<ScrollEndNotification>(
                      onNotification: _onScrollEnd,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 160),
                        itemCount: verses.length + _cardItems,
                        itemBuilder: (_, i) {
                          if (i < _cardItems) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TodayCard(
                                state: s,
                                full: s.todayCardFull,
                                onFull: (full) => setState(() => s.todayCardFull = full),
                              ),
                            );
                          }
                          final v = verses[i - _cardItems];
                          final on = _selected.contains(v.verse);
                          final other = second[v.verse];
                          final stopped = _resume?.verseStart == v.verse;
                          // Listener only notes where the finger went down; InkWell still decides.
                          final item = Listener(
                            key: _verseKeys.putIfAbsent(v.verse, GlobalKey.new),
                            onPointerDown: (e) => _pressAt = e.position,
                            child: InkWell(
                              onTap: () => setState(
                                () => on ? _selected.remove(v.verse) : _selected.add(v.verse),
                              ),
                              onLongPress: () => _longPress(v),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: highlights.contains(v.verse)
                                      ? scheme.primary.withValues(alpha: 0.18)
                                      : stopped
                                      ? scheme.surfaceContainerHighest
                                      : null,
                                  border: on
                                      ? Border(left: BorderSide(color: scheme.primary, width: 3))
                                      : null,
                                ),
                                child: _ParallelRow(
                                  other: other,
                                  otherLabel: parallel,
                                  primary: Text.rich(
                                    key: _textKeys.putIfAbsent(v.verse, GlobalKey.new),
                                    TextSpan(
                                      style: scriptureStyle(context)
                                          .copyWith(fontSize: 18, height: 1.6),
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
                              ),
                            ),
                          );
                          return stopped ? _StoppedMarker(at: s.resumeAt, child: item) : item;
                        },
                      ),
                    ),
            ),
          ),
          if (_tip && verses.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _Tip(onGotIt: _dismissTip, onTurnOff: () => _dismissTip(allTips: true)),
            ),
        ],
      ),
      bottomNavigationBar: _selected.isEmpty
          ? _ChapterNav(
              onQuickChat: widget.onQuickChat,
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
              onCommentary: () => showCommentary(context, s, _selection),
              onNote: () async {
                final ref = _selection;
                final existing = s.study
                    .notes(book: book, chapter: chapter)
                    .where((n) => n.ref == ref)
                    .firstOrNull;
                await showNoteDialog(context, s, ref: ref, note: existing);
                setState(_selected.clear);
              },
              onStudyPage: () {
                final ref = _selection;
                setState(_selected.clear);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => StudyPageScreen(state: s, ref: ref),
                  ),
                );
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

/// A quiet line above the verse the reader stopped at last time.
class _StoppedMarker extends StatelessWidget {
  final DateTime? at;
  final Widget child;
  const _StoppedMarker({required this.at, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              Container(width: 12, height: 1.5, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                stoppedLabel(at, DateTime.now()),
                style: TextStyle(fontSize: 12, color: scheme.primary),
              ),
            ],
          ),
        ),
        child,
      ],
    );
  }
}

/// Tip T14: a dark bubble over the first chapter until it is dismissed.
class _Tip extends StatelessWidget {
  final VoidCallback onGotIt;
  final VoidCallback onTurnOff;
  const _Tip({required this.onGotIt, required this.onTurnOff});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = TextButton.styleFrom(foregroundColor: scheme.surface);
    return Material(
      color: scheme.onSurface,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, size: 18, color: scheme.surface),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(tipT14, style: TextStyle(color: scheme.surface)),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(style: button, onPressed: onTurnOff, child: const Text('Turn off tips')),
                TextButton(style: button, onPressed: onGotIt, child: const Text('Got it')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The primary verse with the parallel translation beside it on wide screens, below it on phones.
class _ParallelRow extends StatelessWidget {
  final Widget primary;
  final String? other;
  final String? otherLabel;
  const _ParallelRow({required this.primary, this.other, this.otherLabel});

  @override
  Widget build(BuildContext context) {
    final text = other;
    if (text == null) return primary;
    final scheme = Theme.of(context).colorScheme;
    final secondary = Text(
      text,
      style: scriptureStyle(context)
          .copyWith(fontSize: 16, height: 1.5, color: scheme.onSurfaceVariant),
      semanticsLabel: '$otherLabel: $text',
    );
    return LayoutBuilder(
      builder: (_, c) => c.maxWidth >= parallelSideBySideWidth
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: primary),
                const SizedBox(width: 16),
                Expanded(child: secondary),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                primary,
                Padding(padding: const EdgeInsets.only(top: 4, left: 12), child: secondary),
              ],
            ),
    );
  }
}

class _ChapterNav extends StatelessWidget {
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onQuickChat;
  const _ChapterNav({
    this.onQuickChat,
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
            if (onQuickChat != null)
              FilledButton.tonalIcon(
                onPressed: onQuickChat,
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Ask'),
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
  final VoidCallback onCommentary;
  final VoidCallback onNote;
  final VoidCallback onStudyPage;
  final VoidCallback onHighlight;
  final VoidCallback onClear;
  const _SelectionBar({
    required this.onStudyPage,
    required this.label,
    required this.onAsk,
    required this.onCommentary,
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
                tooltip: 'Commentary',
                icon: const Icon(Icons.library_books_outlined),
                onPressed: onCommentary,
              ),
              IconButton(
                tooltip: 'Note',
                icon: const Icon(Icons.sticky_note_2_outlined),
                onPressed: onNote,
              ),
              IconButton(
                tooltip: 'Study page',
                icon: const Icon(Icons.article_outlined),
                onPressed: onStudyPage,
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
