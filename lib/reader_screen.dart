import 'dart:math';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'app_state.dart';
import 'commentary_sheet.dart';
import 'interlinear_sheet.dart';
import 'narration_packs.dart';
import 'pinned_download.dart';
import 'note_dialog.dart';
import 'plans_screen.dart';
import 'read_along.dart';
import 'read_along_bar.dart';
import 'study_page_screen.dart';
import 'search_screen.dart';
import 'theme.dart';

/// Where a jumped-to verse lands: a little below the top so the one before is visible.
const verseJumpAlignment = 0.08;
const maxVerseJumpAttempts = 3;

/// Wide enough to set two translations side by side instead of stacked.
const parallelSideBySideWidth = 560.0;

/// The word being read is marked with the highlight colour, a little stronger.
const readAlongWordAlpha = 0.35;
const userHighlightAlpha = 0.18;

/// How long the reader takes to scroll to the verse being read, unless motion is reduced.
const followScrollDuration = Duration(milliseconds: 350);

/// After the user scrolls by hand, the reader leaves the page where they put it this long.
const followPauseAfterDrag = Duration(seconds: 5);

/// Width of the bar marking a selected verse, or the verse being read.
const verseMarkWidth = 3.0;

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

  ReadAlong get readAlong => s.readAlong;

  @override
  void initState() {
    super.initState();
    s.addListener(_refresh);
    readAlong.state.addListener(_refresh);
    readAlong.position.addListener(_follow);
  }

  @override
  void dispose() {
    s.removeListener(_refresh);
    readAlong.state.removeListener(_refresh);
    readAlong.position.removeListener(_follow);
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
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

  /// Keys for each verse's text, so a tap can find the word under it.
  final _textKeys = <int, GlobalKey>{};

  /// Where the last tap on a verse landed while reading along; a screen reader's tap has none.
  Offset? _tapAt;

  /// When the user last scrolled by hand.
  DateTime? _draggedAt;

  bool _onScroll(ScrollNotification n) {
    final byHand = switch (n) {
      ScrollStartNotification(:final dragDetails) => dragDetails != null,
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null,
      _ => false,
    };
    if (byHand) _draggedAt = DateTime.now();
    return false;
  }

  /// Keeps the verse being read on screen, unless it is in view or the user just scrolled.
  void _follow() {
    final at = readAlong.position.value;
    if (at == null || !readAlong.isOn(book.id, chapter) || !_scroll.hasClients) return;
    final dragged = _draggedAt;
    if (dragged != null && DateTime.now().difference(dragged) < followPauseAfterDrag) return;
    final ctx = _verseKeys[at.verse]?.currentContext;
    final box = ctx?.findRenderObject();
    if (ctx == null || box == null) return _scrollToVerse(at.verse);
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    // Between top- and bottom-aligned the verse is fully shown or, if taller, fills the screen.
    final top = viewport.getOffsetToReveal(box, 0).offset;
    final bottom = viewport.getOffsetToReveal(box, 1).offset;
    final pixels = _scroll.position.pixels;
    if (pixels >= min(top, bottom) && pixels <= max(top, bottom)) return;
    final still = MediaQuery.disableAnimationsOf(context);
    Scrollable.ensureVisible(
      ctx,
      alignment: verseJumpAlignment,
      duration: still ? Duration.zero : followScrollDuration,
      curve: Curves.easeInOut,
    );
  }

  /// Seeks the voice to the word tapped in [v], or to the verse's start.
  void _seekTo(Verse v) {
    final tap = _tapAt;
    _tapAt = null;
    final paragraph = _paragraphIn(_textKeys[v.verse]?.currentContext?.findRenderObject());
    if (tap == null || paragraph == null) return _seek(v.verse);
    final local = paragraph.globalToLocal(tap);
    if (!(Offset.zero & paragraph.size).contains(local)) return _seek(v.verse);
    // A word number only means the same word when the voice's words fit the text shown.
    if (!readAlong.wordsFit(v.verse, v.text, s.settings.translation)) return _seek(v.verse);
    final offset = paragraph.getPositionForOffset(local).offset - _verseNumberText(v).length;
    _seek(v.verse, wordAtOffset(wordRanges(v.text), offset) ?? 0);
  }

  void _seek(int verse, [int word = 0]) => readAlong.seek(verse, word);

  RenderParagraph? _paragraphIn(RenderObject? root) {
    if (root == null || root is RenderParagraph) return root as RenderParagraph?;
    RenderParagraph? found;
    root.visitChildren((child) => found ??= _paragraphIn(child));
    return found;
  }

  String _verseNumberText(Verse v) => '${v.verse} ';

  /// Reads the chapter aloud with the installed narration, or asks how to listen.
  Future<void> _listen() async {
    var voice = s.narration.isInstalled(book.id) ? ReadAlongVoice.narration : null;
    voice ??= await showDialog<ReadAlongVoice>(
      context: context,
      builder: (_) => _ListenChoice(
        book: book,
        chapter: chapter,
        pin: narrationPins[book.id],
        translation: s.settings.translation,
      ),
    );
    if (voice == null || !mounted) return;
    setState(_selected.clear);
    await readAlong.start(
      book: book,
      chapter: chapter,
      voice: voice,
      verses: s.db.passage(Ref(book, chapter), translation: s.settings.translation),
      translation: s.settings.translation,
    );
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
    final perVerse = (pos.maxScrollExtent + pos.viewportDimension) / count;
    _scroll.jumpTo(((verse - 1) * perVerse).clamp(0, pos.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToVerse(verse, attempt + 1));
  }

  void _go(Book b, int c) {
    _selected.clear();
    _verseKeys.clear();
    _textKeys.clear();
    if (_scroll.hasClients) _scroll.jumpTo(0);
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
    final marks = (
      highlights: s.study.highlights(book, chapter),
      noted: {
        for (final n in s.study.notes(book: book, chapter: chapter))
          for (var v = n.ref.verseStart!; v <= n.ref.verseEnd!; v++) v,
      },
      second: second,
      parallel: parallel,
      following: readAlong.isOn(book.id, chapter),
    );
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
          if (readAlongSupported)
            IconButton(
              tooltip: 'Listen',
              icon: const Icon(Icons.headphones_outlined),
              onPressed: readAlong.state.value == null ? _listen : null,
            ),
          IconButton(
            tooltip: 'Reading plans',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => PlansScreen(state: s)),
            ),
          ),
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
              : NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 160),
                    itemCount: verses.length,
                    itemBuilder: (_, i) {
                      final v = verses[i];
                      if (!marks.following) return _verseTile(v, marks);
                      return ValueListenableBuilder<ReadAlongPosition?>(
                        valueListenable: readAlong.position,
                        builder: (_, _, _) => _verseTile(v, marks),
                      );
                    },
                  ),
                ),
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (readAlong.state.value case final reading?) _readAlongBar(reading),
          _selected.isEmpty
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
        ],
      ),
    );
  }

  void _goLastChapter(Book b) => _go(b, s.db.chapterCount(b, translation: s.settings.translation));

  /// While reading along, a tap moves the voice to the word tapped instead of selecting.
  Widget _verseTile(Verse v, _Marks m) {
    final scheme = Theme.of(context).colorScheme;
    final on = _selected.contains(v.verse);
    final current = m.following && readAlong.position.value?.verse == v.verse;
    final word = current ? readAlong.wordToShow(v.verse, v.text, s.settings.translation) : null;
    final tile = InkWell(
      key: _verseKeys.putIfAbsent(v.verse, GlobalKey.new),
      onTapUp: m.following ? (d) => _tapAt = d.globalPosition : null,
      onTap: m.following
          ? () => _seekTo(v)
          : () => setState(() => on ? _selected.remove(v.verse) : _selected.add(v.verse)),
      onLongPress: () => showInterlinear(context, s, Ref(book, chapter, v.verse)),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: m.highlights.contains(v.verse)
              ? scheme.primary.withValues(alpha: userHighlightAlpha)
              : (current ? scheme.surfaceContainerHighest : null),
          // The bar marks the verse being read even on a highlighted verse.
          border: on || current
              ? Border(
                  left: BorderSide(color: scheme.primary, width: verseMarkWidth),
                )
              : null,
        ),
        child: _ParallelRow(
          other: m.second[v.verse],
          otherLabel: m.parallel,
          primary: _verseText(v, noted: m.noted.contains(v.verse), word: word),
        ),
      ),
    );
    // A screen reader is told that a tap now moves the voice instead of selecting.
    return m.following ? Semantics(onTapHint: 'read from here', child: tile) : tile;
  }

  Widget _verseText(Verse v, {required bool noted, int? word}) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      key: _textKeys.putIfAbsent(v.verse, GlobalKey.new),
      TextSpan(
        style: scriptureStyle(context).copyWith(fontSize: 18, height: 1.6),
        children: [
          TextSpan(
            text: _verseNumberText(v),
            style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w600),
          ),
          ..._wordSpans(v.text, word, scheme),
          if (noted)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.sticky_note_2_outlined, size: 14, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  /// The verse with [word] marked, split so the text reads the same to a screen reader.
  List<TextSpan> _wordSpans(String text, int? word, ColorScheme scheme) {
    final ranges = wordRanges(text);
    if (word == null || word < 0 || word >= ranges.length) return [TextSpan(text: text)];
    final r = ranges[word];
    return [
      TextSpan(text: text.substring(0, r.start)),
      TextSpan(
        text: text.substring(r.start, r.end),
        style: TextStyle(backgroundColor: scheme.primary.withValues(alpha: readAlongWordAlpha)),
      ),
      TextSpan(text: text.substring(r.end)),
    ];
  }

  Widget _readAlongBar(ReadAlongState reading) => ValueListenableBuilder<ReadAlongPosition?>(
    valueListenable: readAlong.position,
    builder: (_, at, _) => ReadAlongBar(
      state: reading,
      bookName: bookById(reading.book).name,
      verse: at?.verse,
      downloadProgress: s.narration.progress[reading.book],
      onPlayPause: readAlong.togglePlay,
      onPrevious: readAlong.previousVerse,
      onNext: readAlong.nextVerse,
      onSpeed: readAlong.setSpeed,
      onClose: readAlong.stop,
    ),
  );
}

/// What the reader marks on each verse of the chapter.
typedef _Marks = ({
  Set<int> highlights,
  Set<int> noted,
  Map<int, String> second,
  String? parallel,
  bool following,
});

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

/// Asks how to listen without the narration: download it, or use the device voice now.
class _ListenChoice extends StatelessWidget {
  final Book book;
  final int chapter;
  final PackPin? pin;
  final String translation;
  const _ListenChoice({
    required this.book,
    required this.chapter,
    required this.pin,
    required this.translation,
  });

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final size = pin?.sizeLabel;
    final otherTranslation = translation == defaultTranslation
        ? ''
        : ' $translation follows it verse by verse.';
    return SimpleDialog(
      title: Text('Listen to ${book.name} $chapter'),
      children: [
        if (size != null)
          _option(
            context,
            ReadAlongVoice.narration,
            Icons.download_outlined,
            'Download the narration ($size)',
            '$narrationCredit reads the Berean Standard Bible. Downloaded once for '
                '${book.name}, only now, then it plays offline.$otherTranslation',
            muted,
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('No narration is published for ${book.name} yet.', style: muted),
          ),
        _option(
          context,
          ReadAlongVoice.device,
          Icons.record_voice_over_outlined,
          'Use the device voice',
          'Your device reads $translation aloud with its own offline voice. Nothing is downloaded.',
          muted,
        ),
      ],
    );
  }

  Widget _option(
    BuildContext context,
    ReadAlongVoice voice,
    IconData icon,
    String title,
    String detail,
    TextStyle muted,
  ) => SimpleDialogOption(
    onPressed: () => Navigator.pop(context, voice),
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(detail, style: muted),
    ),
  );
}
