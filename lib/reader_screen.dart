import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'commentary_sheet.dart';
import 'interlinear_sheet.dart';
import 'note_dialog.dart';
import 'prayer_screen.dart';
import 'prayer_sheet.dart' show passageText, shareOrigin, shareText;
import 'selection_bar.dart';
import 'study_page_screen.dart';
import 'search_screen.dart';
import 'theme.dart';
import 'today_card.dart';
import 'word_press.dart';
import 'word_study_screen.dart';

/// Where a jumped-to verse lands: a little below the top so the one before is visible.
const verseJumpAlignment = 0.08;
const maxVerseJumpAttempts = 3;

/// Wide enough to set two translations side by side instead of stacked.
const parallelSideBySideWidth = 560.0;

/// Tip T14, shown once on the first chapter until it is dismissed.
const _tipKey = 'tipT14Done';
const tipsOffKey = 'tipsOff';
const tipT14 = 'Tap a verse to highlight it, write a note, pray it or ask about it.';

/// Where the tip sits above the chapter bar, with no selection card under it.
const _tipGap = 16.0;
const _tipCardGap = 8.0;
const _toolbarTop = 8.0;
const _toolbarInset = 8.0;

/// The verses of [ref] as plain text with the reference and translation, for Copy and Share.
String selectionText(List<Verse> verses, Ref ref, String translation) =>
    '${passageText(verses)}\n${ref.label} ($translation)';

/// Selected verses as runs of neighbours, in order: 1, 2 and 5 are 1-2 and 5.
List<(int, int)> verseRuns(Iterable<int> verses) {
  final runs = <(int, int)>[];
  for (final v in verses.toList()..sort()) {
    if (runs.isNotEmpty && runs.last.$2 == v - 1) {
      runs.last = (runs.last.$1, v);
    } else {
      runs.add((v, v));
    }
  }
  return runs;
}

/// "John 3:1-2, 5" for verses that are not all neighbours; a plain label otherwise.
String versesLabel(Book book, int chapter, Iterable<int> verses) {
  final [(start, end), ...rest] = verseRuns(verses);
  final first = Ref(book, chapter, start, end).label;
  return [first, for (final (a, b) in rest) a == b ? '$a' : '$a-$b'].join(', ');
}

/// Verses that are not all neighbours, each on its own line with its number, for Copy and Share.
String gappedSelectionText(List<Verse> verses, String label, String translation) =>
    '${verses.map((v) => '${v.verse} ${v.text}').join('\n')}\n$label ($translation)';

class ReaderScreen extends StatefulWidget {
  final AppState state;

  /// Opens the quick chat; shown in the chapter bar so it never covers the reader's buttons.
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

  /// Where the reader stopped last session, marked until the reader moves to another chapter.
  late Ref? _resume = s.resumeVerse == null ? null : Ref(book, chapter, s.resumeVerse);
  late bool _tip = !(s.prefs.getBool(_tipKey) ?? false) && !(s.prefs.getBool(tipsOffKey) ?? false);

  @override
  void initState() {
    super.initState();
    s.addListener(_refresh);
    _lifecycle = AppLifecycleListener(onResume: _newDay);
    _shown = (book.id, chapter);
    final resume = _resume;
    // Read once: a remount, as when a Mac window crosses the wide layout, must not mark again.
    s.resumeVerse = null;
    if (resume != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToVerse(resume.verseStart!));
    }
  }

  late final AppLifecycleListener _lifecycle;

  /// The book and chapter last built, so a jump from elsewhere starts the new chapter at the top.
  var _shown = (0, 0);

  void _newDay() {
    if (s.openTodayIfNewDay()) setState(() {});
  }

  void _dismissTip({bool allTips = false}) {
    s.prefs.setBool(_tipKey, true);
    if (allTips) s.prefs.setBool(tipsOffKey, true);
    setState(() => _tip = false);
  }

  /// Folds today's card once the reader starts reading, and remembers the verse at the top of
  /// the list once a scroll settles.
  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification) WordPressRegion.cancelActive();
    if (n is ScrollStartNotification && n.dragDetails != null && s.todayCardFull) {
      setState(() => s.todayCardFull = false);
    }
    if (n is! ScrollEndNotification) return false;
    final viewport = n.context;
    // After layout, since a jump ends before the list has laid out at its new offset.
    WidgetsBinding.instance.addPostFrameCallback((_) => _rememberTop(viewport));
    return false;
  }

  void _rememberTop(BuildContext? viewport) {
    if (!mounted || viewport == null || !viewport.mounted) return;
    final top = (viewport.findRenderObject() as RenderBox?)?.localToGlobal(Offset.zero).dy;
    if (top == null) return;
    final shown = _verseKeys.entries.where((e) {
      final box = e.value.currentContext?.findRenderObject() as RenderBox?;
      return box != null && box.attached && box.localToGlobal(Offset(0, box.size.height)).dy > top;
    });
    final first = shown.map((e) => e.key).fold<int?>(null, (a, v) => a == null || v < a ? v : a);
    if (first != null) s.rememberVerse(first);
  }

  @override
  void dispose() {
    s.removeListener(_refresh);
    _lifecycle.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    if (_resume case final r? when r.book.id != book.id || r.chapter != chapter) _resume = null;
    final changed = _shown != (book.id, chapter);
    _shown = (book.id, chapter);
    if (changed && s.readerTargetVerse == null) _startChapter();
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

  /// What a press on [hit] (or off every word, when null) will open, in a few words, so the
  /// reader sees what is being pressed before the study opens. It asks the same question the
  /// study asks, so the two cannot disagree.
  String _pressLabel(Verse v, ({String word, int index, int occurrence})? hit) {
    if (hit == null) return wholeVerseLabel;
    final press = pressedStudy(
      s.db,
      Ref(book, chapter, v.verse),
      english: hit.word,
      translation: s.settings.translation,
      occurrence: hit.occurrence,
      wordIndex: hit.index,
    );
    final code = press.code;
    final lemma = code == null ? null : s.db.lexicon(code)?.lemma;
    return [hit.word, ?lemma, ?code].join(' · ');
  }

  void _studyWord(Verse v, ({String word, int index, int occurrence}) hit) => showWordStudy(
    context,
    s,
    Ref(book, chapter, v.verse),
    english: hit.word,
    occurrence: hit.occurrence,
    wordIndex: hit.index,
  );

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
    final perVerse = (pos.maxScrollExtent + pos.viewportDimension) / count;
    _scroll.jumpTo(((verse - 1) * perVerse).clamp(0, pos.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToVerse(verse, attempt + 1));
  }

  /// Jumps again after layout: the list corrects its offset to the old chapter's item sizes.
  void _startChapter() {
    _selected.clear();
    _verseKeys.clear();
    _textKeys.clear();
    void top() => _scroll.hasClients ? _scroll.jumpTo(0) : null;
    top();
    WidgetsBinding.instance.addPostFrameCallback((_) => top());
  }

  void _go(Book b, int c) {
    _startChapter();
    _resume = null;
    s.todayCardFull = false;
    s.setReader(b, c);
  }

  Ref get _selection {
    final sorted = _selected.toList()..sort();
    return Ref(book, chapter, sorted.first, sorted.last);
  }

  bool get _gapped => verseRuns(_selected).length > 1;

  String get _selectionLabel => versesLabel(book, chapter, _selected);

  String get _selectionText {
    final translation = s.settings.translation;
    final ref = _selection;
    final verses = s.db.passage(ref, translation: translation);
    if (!_gapped) return selectionText(verses, ref, translation);
    final chosen = verses.where((v) => _selected.contains(v.verse)).toList();
    return gappedSelectionText(chosen, _selectionLabel, translation);
  }

  /// Runs [act] for an action that takes one passage; with gaps in the selection it says so
  /// rather than act on verses that were never chosen.
  void _onePassage(String action, void Function() act) {
    if (!_gapped) return act();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$action works on verses next to each other. Choose one verse or a run of verses.',
        ),
      ),
    );
  }

  Future<void> _note() async {
    final ref = _selection;
    final existing = s.study
        .notes(book: book, chapter: chapter)
        .where((n) => n.ref == ref)
        .firstOrNull;
    await showNoteDialog(context, s, ref: ref, note: existing);
    setState(_selected.clear);
  }

  Future<void> _pray() async {
    await showPrayerSheet(
      context,
      s.prayers,
      verse: _selection.label,
      passage: passageLookupFor(s.db, () => s.settings.translation),
    );
    if (mounted) setState(_selected.clear);
  }

  void _studyPage() {
    final ref = _selection;
    setState(_selected.clear);
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => StudyPageScreen(state: s, ref: ref)),
    );
  }

  Future<void> _copy() async {
    final label = _selectionLabel;
    await Clipboard.setData(ClipboardData(text: _selectionText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $label.')));
    setState(_selected.clear);
  }

  void _share(BuildContext button) {
    shareText(_selectionText, shareOrigin(button));
    setState(_selected.clear);
  }

  Widget _selectionBar({required bool wide}) => SelectionBar(
    label: _selectionLabel,
    count: _selected.length,
    wide: wide,
    onHighlight: () {
      for (final v in _selected) {
        s.study.toggleHighlight(book, chapter, v);
      }
      setState(_selected.clear);
    },
    onNote: () => _onePassage('Note', _note),
    onPray: () => _onePassage('Pray', _pray),
    onAsk: () => _onePassage('Ask', () {
      s.askAbout(_selection);
      setState(_selected.clear);
    }),
    onWords: () => _onePassage('Words', () => showInterlinear(context, s, _selection)),
    onCommentary: () => _onePassage('Commentary', () => showCommentary(context, s, _selection)),
    onStudyPage: () => _onePassage('Study page', _studyPage),
    onCopy: _copy,
    onShare: _share,
    onClear: () => setState(_selected.clear),
  );

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
    final wide = MediaQuery.sizeOf(context).width >= wideLayoutBreakpoint;
    final card = _selected.isEmpty || wide ? null : _selectionBar(wide: false);
    final tip = _tip && verses.isNotEmpty;
    final noted = {
      for (final n in s.study.notes(book: book, chapter: chapter))
        for (var v = n.ref.verseStart!; v <= n.ref.verseEnd!; v++) v,
    };
    return Scaffold(
      appBar: AppBar(
        title: TextButton(
          onPressed: _pickChapter,
          child: _ReaderTitle(name: book.name, chapter: chapter),
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
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                    child: TodayCard(
                      state: s,
                      full: s.todayCardFull,
                      onFull: (full) => setState(() => s.todayCardFull = full),
                    ),
                  ),
                  Expanded(
                    child: verses.isEmpty
                        ? Center(
                            child: Text(
                              'No text for ${book.name} $chapter in $translation.',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          )
                        : NotificationListener<ScrollNotification>(
                            onNotification: _onScroll,
                            child: ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 160),
                              itemCount: verses.length,
                              itemBuilder: (_, i) {
                                final v = verses[i];
                                final on = _selected.contains(v.verse);
                                final other = second[v.verse];
                                final stopped = _resume?.verseStart == v.verse;
                                final item = WordPressRegion(
                                  key: _verseKeys.putIfAbsent(v.verse, GlobalKey.new),
                                  text: v.text,
                                  prefixLength: '${v.verse} '.length,
                                  textKey: _textKeys.putIfAbsent(v.verse, GlobalKey.new),
                                  labelFor: (hit) => _pressLabel(v, hit),
                                  onWord: (hit) => _studyWord(v, hit),
                                  onVerse: () => showInterlinear(context, s, Ref(book, chapter, v.verse)),
                                  onTap: () => setState(
                                    () => on ? _selected.remove(v.verse) : _selected.add(v.verse),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: highlights.contains(v.verse)
                                          ? scheme.primary.withValues(alpha: 0.18)
                                          : stopped
                                          ? scheme.surfaceContainerHighest
                                          : null,
                                      border: on
                                          ? Border(
                                              left: BorderSide(color: scheme.primary, width: 3),
                                            )
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
                                );
                                return stopped ? _StoppedMarker(at: s.resumeAt, child: item) : item;
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          if (tip || card != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: card == null
                  ? _tipGap
                  : selectionBarGap + MediaQuery.paddingOf(context).bottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tip)
                    _Tip(onGotIt: _dismissTip, onTurnOff: () => _dismissTip(allTips: true)),
                  if (tip && card != null) const SizedBox(height: _tipCardGap),
                  ?card,
                ],
              ),
            ),
          if (wide && _selected.isNotEmpty)
            Positioned(
              top: _toolbarTop,
              left: _toolbarInset,
              right: _toolbarInset,
              // A narrow Mac window leaves the reader less room than the toolbar's full width.
              child: Center(
                child: FittedBox(fit: BoxFit.scaleDown, child: _selectionBar(wide: true)),
              ),
            ),
        ],
      ),
      bottomNavigationBar: card == null
          ? _ChapterNav(
              canPrev: chapter > 1 || book.id > 1,
              canNext: chapter < chapters || book.id < books.length,
              onPrev: () =>
                  chapter > 1 ? _go(book, chapter - 1) : _goLastChapter(bookById(book.id - 1)),
              onNext: () =>
                  chapter < chapters ? _go(book, chapter + 1) : _go(bookById(book.id + 1), 1),
            )
          : null,
    );
  }

  void _goLastChapter(Book b) => _go(b, s.db.chapterCount(b, translation: s.settings.translation));
}

const _titleSize = 22.0;

/// How far the title shrinks to fit before the book name is cut short.
const _titleFloor = 0.8;

/// Scaled text measured to the exact width can round over it and be cut; a pixel spare avoids it.
const _titleSlack = 1.0;

/// One line on a phone: the whole title scales down to [_titleFloor] first, then only the book
/// name gives way; the chapter number is never cut.
class _ReaderTitle extends StatelessWidget {
  final String name;
  final int chapter;
  const _ReaderTitle({required this.name, required this.chapter});

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style
        .merge(const TextStyle(fontFamilyFallback: scriptureFontFallback, fontSize: _titleSize));
    final label = '$name $chapter';
    return LayoutBuilder(
      builder: (context, c) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: base),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final width = painter.width;
        painter.dispose();
        final room = c.maxWidth - _titleSlack;
        final scale = width <= room ? 1.0 : (room / width).clamp(_titleFloor, 1.0);
        return DefaultTextStyle.merge(
          style: base.copyWith(fontSize: _titleSize * scale),
          maxLines: 1,
          softWrap: false,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
              Text(' $chapter'),
            ],
          ),
        );
      },
    );
  }
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
