import 'dart:async';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'commentary_sheet.dart';
import 'extras_hint.dart';
import 'settings_sheet.dart';
import 'theme.dart';
import 'word_study_screen.dart';

const searchResultLimit = 100;
const _minQueryLength = 2;
// Long enough that typing a word does not search each letter, short enough to feel immediate.
const _searchDelay = Duration(milliseconds: 300);

/// Word studies and commentary comments listed under "All" before "Show all"; the rest of each
/// kind is one tap away on its own chip.
const _wordsPreview = 5;
const _commentsPreviewPerWork = 1;
const _commentsPerWork = 5;

/// A query of this many words or fewer is a word or a short phrase to look into, so the word
/// studies and commentary come before the verses; a longer one is most likely a verse being
/// recalled, and the verses come first.
const _deepFirstWords = 2;

/// The kinds of result Search lists, and the chip that shows only one of them.
enum _Kind { all, verses, words, commentary }

/// Search: one box for verses, the Hebrew and Greek words behind a word, and what the installed
/// commentaries say. A reference in the query jumps straight to it.
class SearchScreen extends StatefulWidget {
  final AppState state;

  /// True while Search is the place on screen. It takes the keyboard when it becomes so.
  final bool active;
  const SearchScreen({super.key, required this.state, this.active = true});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  var _query = '';
  var _groups = const <SearchGroup>[];
  Spelling? _spelling;
  var _words = const <WordMatch>[];
  var _commentary = CommentarySearch.empty;
  final _field = TextEditingController();
  final _focus = FocusNode();
  var _kind = _Kind.all;

  /// The searches of the current query that have not answered yet.
  final _waiting = <_Kind>{};
  var _verseSearchFailed = false;
  var _request = 0;
  Timer? _pending;

  bool get _searching => _waiting.isNotEmpty;

  /// The query has been searched in full, not just started.
  bool get _searched => _query.length >= _minQueryLength && !_searching && _pending?.isActive != true;

  @override
  void didUpdateWidget(SearchScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      // The place is on screen only after this frame; focus then, not while it is still hidden.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active) _focus.requestFocus();
      });
    } else if (!widget.active && old.active) {
      _release();
    }
  }

  @override
  void dispose() {
    _pending?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final query = value.trim();
    _request++;
    _pending?.cancel();
    setState(() {
      _query = query;
      _waiting.clear();
      _verseSearchFailed = false;
      if (query.length < _minQueryLength) _clearResults();
    });
    if (query.length >= _minQueryLength) _pending = Timer(_searchDelay, () => _run(query));
  }

  void _clearResults() {
    _groups = const [];
    _spelling = null;
    _words = const [];
    _commentary = CommentarySearch.empty;
    _kind = _Kind.all;
  }

  void _clear() {
    _field.clear();
    _onChanged('');
    _focus.requestFocus();
  }

  Future<void> _run(String query) async {
    final request = ++_request;
    final s = widget.state;
    setState(() {
      _clearResults();
      _waiting.addAll([_Kind.verses, _Kind.words, _Kind.commentary]);
    });
    await Future.wait([
      _answer(
        request,
        _Kind.verses,
        () => s.searchVerses(
          query,
          translation: s.settings.translation,
          perGroup: searchResultLimit,
        ),
        (found) {
          _groups = found.groups;
          _spelling = found.spelling;
        },
        failed: () => _verseSearchFailed = true,
      ),
      _answer(
        request,
        _Kind.words,
        () => s.searchWords(query, limit: _wordsListed),
        (found) => _words = found,
      ),
      _answer(
        request,
        _Kind.commentary,
        () => s.searchCommentary(query, perModule: _commentsPerWork),
        (found) => _commentary = found,
      ),
    ]);
  }

  /// Shows one search's answer as it lands, unless a newer keystroke owns the screen. The searches
  /// are separate, so the quick ones show while the slow one is still running.
  Future<void> _answer<T>(
    int request,
    _Kind kind,
    Future<T> Function() run,
    void Function(T found) apply, {
    void Function()? failed,
  }) async {
    T? found;
    try {
      found = await run();
    } on Object catch (e) {
      debugPrint('Search for $kind failed: $e');
    }
    if (!mounted || request != _request) return;
    setState(() {
      if (found != null) {
        apply(found);
      } else {
        failed?.call();
      }
      _waiting.remove(kind);
    });
  }

  void _submit(String value) {
    final query = value.trim();
    if (query.length < _minQueryLength) return;
    _pending?.cancel();
    _run(query);
  }

  /// Puts the keyboard away by handing focus back to the shell, which owns the place shortcuts.
  /// Unfocusing the field alone would leave focus on the route, above the shortcuts.
  void _release() {
    // The places sit in an IndexedStack, whose own focus node cannot take focus; the next one up
    // is the shell's.
    var holder = Focus.maybeOf(context);
    while (holder != null && !holder.canRequestFocus) {
      holder = holder.parent;
    }
    if (holder != null) {
      holder.requestFocus();
    } else {
      _focus.unfocus();
    }
  }

  void _openVerse(Ref ref) {
    _release();
    widget.state.openInReader(ref);
  }

  /// How many of each kind there are, for the chips.
  int _count(_Kind kind) => switch (kind) {
    _Kind.all => 0,
    _Kind.verses => _groups.fold(0, (n, g) => n + g.total),
    _Kind.words => _words.length,
    _Kind.commentary => _commentary.total,
  };

  bool get _deepFirst =>
      RegExp(r'[\p{L}\p{N}]+', unicode: true).allMatches(_query).length <= _deepFirstWords;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final scheme = Theme.of(context).colorScheme;
    final translation = s.settings.translation;
    final refs = RefParser.parse(_query);
    final kinds = [for (final k in _Kind.values.skip(1)) if (_count(k) > 0) k];
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: widget.active,
          controller: _field,
          focusNode: _focus,
          onChanged: _onChanged,
          onSubmitted: _submit,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search a word, a phrase or a reference',
            filled: false,
            border: InputBorder.none,
            suffixIcon: _field.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: _clear,
                  ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (_searching) const LinearProgressIndicator(),
              if (kinds.length > 1)
                _KindChips(
                  kinds: kinds,
                  selected: _kind,
                  count: _count,
                  onSelected: (k) => setState(() => _kind = k),
                ),
              for (final r in refs)
                ListTile(
                  leading: Icon(Icons.arrow_forward, color: scheme.primary),
                  title: Text('Go to ${r.label}'),
                  onTap: () => _openVerse(r),
                ),
              if (_verseSearchFailed)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'The search could not be run. Try typing it again.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ..._sections(context, translation, refs.isNotEmpty),
            ],
          ),
        ),
      ),
    );
  }

  /// Tapping an example fills the box and searches at once.
  void _try(String example) {
    _field.text = example;
    _field.selection = TextSelection.collapsed(offset: example.length);
    _onChanged(example);
    _submit(example);
  }

  List<Widget> _sections(BuildContext context, String translation, bool hasRefs) {
    final scheme = Theme.of(context).colorScheme;
    if (_query.isEmpty) return [_Examples(onTry: _try)];
    final nothing = _groups.isEmpty && _words.isEmpty && _commentary.hits.isEmpty;
    if (_searched && !_verseSearchFailed && nothing && _spelling == null && !hasRefs) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            searchIsTooCommon(_query)
                ? '"$_query" is in too many verses to list. Add another word.'
                : 'No verse in the $translation has those words.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      ];
    }
    final verses = _verseSection(context, translation);
    final words = _wordSection(context);
    final comments = _commentarySection(context);
    return switch (_kind) {
      _Kind.verses => verses,
      _Kind.words => words,
      _Kind.commentary => comments,
      _Kind.all =>
        _deepFirst
            ? [...words, ...comments, ...verses]
            : [...verses, ...words, ...comments],
    };
  }

  List<Widget> _verseSection(BuildContext context, String translation) {
    final scheme = Theme.of(context).colorScheme;
    return [
      if (_searched && _groups.isEmpty && _spelling != null) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            'No verses have "${_spelling!.word}". Words one letter away that verses do have:',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
        for (final (word, verses) in _spelling!.near)
          ListTile(
            title: Text(word),
            subtitle: Text('$verses ${verses == 1 ? 'verse' : 'verses'}'),
            onTap: () {
              _field.text = _query.replaceAll(phrasePattern([_spelling!.word]), word);
              _onChanged(_field.text);
            },
          ),
      ],
      for (final g in _groups) ...[
        _GroupHeader(group: g),
        for (final v in g.verses)
          ListTile(
            title: Text(
              v.label,
              style: TextStyle(fontFamilyFallback: scriptureFontFallback, color: scheme.primary),
            ),
            subtitle: Text(v.text, style: scriptureStyle(context).copyWith(fontSize: 15)),
            onTap: () => _openVerse(Ref(v.book, v.chapter, v.verse)),
          ),
      ],
    ];
  }

  List<Widget> _wordSection(BuildContext context) {
    if (_words.isEmpty) return const [];
    final preview = _kind == _Kind.all && _words.length > _wordsPreview;
    final shown = preview ? _words.take(_wordsPreview).toList() : _words;
    final capped = _words.length >= _wordsListed;
    return [
      _Header(
        'Word studies · ${_words.length}${capped ? '+' : ''} Hebrew and Greek '
        '${_words.length == 1 ? 'word' : 'words'}',
      ),
      for (final w in shown)
        _WordTile(
          match: w,
          onTap: () {
            _release();
            showWordStudyOf(context, widget.state, w.code, english: w.term.isEmpty ? null : w.term);
          },
        ),
      if (preview)
        _ShowAll(
          'Show all ${_words.length} word studies',
          () => setState(() => _kind = _Kind.words),
        ),
    ];
  }

  List<Widget> _commentarySection(BuildContext context) {
    final s = widget.state;
    if (!_searched && _commentary.hits.isEmpty) return const [];
    if (_commentary.hits.isEmpty) {
      // Nothing found is one thing to say, nothing installed another; and a long query that is
      // most likely a verse being recalled is not the moment to offer a download.
      final asked = _kind == _Kind.commentary || (_kind == _Kind.all && _deepFirst);
      return hasCommentary(s) || !asked
          ? const []
          : [
              const _Header('Commentary'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ExtrasHint(
                  state: s,
                  part: SettingsPart.commentary,
                  text: searchCommentaryHint,
                ),
              ),
            ];
    }
    final modules = {for (final m in s.commentary.library.modules()) m.id: m};
    final byWork = <String, List<CommentaryHit>>{};
    for (final h in _commentary.hits) {
      byWork.putIfAbsent(h.module, () => []).add(h);
    }
    final preview = _kind == _Kind.all;
    final works = byWork.length;
    return [
      _Header(
        'Commentary · ${_plural(_commentary.total, 'comment')} in ${_plural(works, 'work')}, '
        'best matches first',
      ),
      for (final MapEntry(key: id, value: hits) in byWork.entries) ...[
        if (!preview || works > 1 || hits.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '${modules[id]?.title ?? id} · ${_plural(_commentary.totals[id] ?? hits.length, 'comment')}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        for (final h in preview ? hits.take(_commentsPreviewPerWork) : hits)
          _CommentTile(
            hit: h,
            onOpen: () {
              _release();
              showCommentary(context, s, _refOf(h), openIntroductions: h.isIntroduction);
            },
            onRead: () => _openVerse(_refOf(h)),
          ),
      ],
      if (preview && _commentary.hits.length > works * _commentsPreviewPerWork)
        _ShowAll(
          'Show more from these ${_plural(works, 'work')}',
          () => setState(() => _kind = _Kind.commentary),
        ),
    ];
  }
}

/// The search lists at most this many words, so a full list is shown with a plus.
const _wordsListed = 40;

/// 3335 as "3,335", so a long count reads at a glance.
String _n(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

String _plural(int n, String noun) => '${_n(n)} $noun${n == 1 ? '' : 's'}';

/// The passage a hit comments on; a book or chapter introduction opens at the chapter.
Ref _refOf(CommentaryHit h) => Ref(
  bookById(h.book),
  h.chapter == 0 ? 1 : h.chapter,
  h.verseStart == 0 ? null : h.verseStart,
  h.verseStart == 0 ? null : h.verseEnd,
);

/// What Search does and a few things to try, for an empty box.
class _Examples extends StatelessWidget {
  final ValueChanged<String> onTry;
  const _Examples({required this.onTry});

  /// A word, a name of a word, a passage and a Strong's number: one of each way in.
  static const examples = ['holy', 'grace', 'Romans 8', 'G26'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Look a word up in the verses, in the Hebrew and Greek behind it, and in what the '
            'commentaries say. Or type a passage, or a Strong\'s number, to go straight to it.',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
          ),
          const SizedBox(height: 16),
          Text('Try', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final e in examples) ActionChip(label: Text(e), onPressed: () => onTry(e)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// Names how the verses below were found, and how many there are, so the order is checkable.
class _GroupHeader extends StatelessWidget {
  final SearchGroup group;
  const _GroupHeader({required this.group});

  @override
  Widget build(BuildContext context) {
    final shown = group.verses.length;
    final count = shown < group.total
        ? '${_n(shown)} of ${_n(group.total)} verses, in Bible order'
        : '${_n(group.total)} ${group.total == 1 ? 'verse' : 'verses'}, in Bible order';
    return _Header('${group.label} · $count');
  }
}

class _ShowAll extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _ShowAll(this.label, this.onPressed);

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TextButton(onPressed: onPressed, child: Text(label)),
    ),
  );
}

/// Choose one kind of result, or all of them. The chips wrap, so on a narrow phone every kind is
/// in view and none hides off the side.
class _KindChips extends StatelessWidget {
  final List<_Kind> kinds;
  final _Kind selected;
  final int Function(_Kind kind) count;
  final ValueChanged<_Kind> onSelected;
  const _KindChips({
    required this.kinds,
    required this.selected,
    required this.count,
    required this.onSelected,
  });

  static String _label(_Kind k) => switch (k) {
    _Kind.all => 'All',
    _Kind.verses => 'Verses',
    _Kind.words => 'Word studies',
    _Kind.commentary => 'Commentary',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 8,
        children: [
          for (final k in [_Kind.all, ...kinds])
            ChoiceChip(
              label: Text(k == _Kind.all ? _label(k) : '${_label(k)} ${_n(count(k))}'),
              selected: selected == k,
              showCheckmark: false,
              onSelected: (_) => onSelected(k),
            ),
        ],
      ),
    );
  }
}

class _WordTile extends StatelessWidget {
  final WordMatch match;
  final VoidCallback onTap;
  const _WordTile({required this.match, required this.onTap});

  /// Why the word is listed, in the words of what was done to find it.
  String get _why => switch (match.kind) {
    WordMatchKind.number => "the Strong's number you typed",
    WordMatchKind.original => 'the spelling you typed',
    WordMatchKind.glossed =>
      'STEPBible glosses it "${match.term}" ${_times(match.glossed)}',
    WordMatchKind.defined => 'its lexicon gloss has "${match.term}"',
  };

  static String _times(int n) => n == 1 ? 'once' : (n == 2 ? 'twice' : '$n times');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = match.entry;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5);
    return ListTile(
      isThreeLine: true,
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: e.lemma,
              style: TextStyle(
                fontFamilyFallback: scriptureFontFallback,
                fontSize: 20,
                color: scheme.primary,
              ),
            ),
            if (e.translit.isNotEmpty) TextSpan(text: '   ${e.translit}', style: muted),
          ],
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (e.gloss.isNotEmpty) Text(e.gloss, style: TextStyle(color: scheme.onSurface)),
          Text(
            '${match.language} · ${match.code} · used ${_plural(match.uses, 'time')} in '
            '${_plural(match.verses, 'verse')}${match.text == null ? '' : ' of ${match.text}'} · $_why',
            style: muted,
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _CommentTile extends StatelessWidget {
  final CommentaryHit hit;
  final VoidCallback onOpen;
  final VoidCallback onRead;
  const _CommentTile({required this.hit, required this.onOpen, required this.onRead});

  String get _label {
    final book = bookById(hit.book).name;
    if (hit.chapter == 0) return '$book, introduction';
    if (hit.verseStart == 0) return '$book ${hit.chapter}, introduction';
    return _refOf(hit).label;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = hit.snippet;
    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in hit.marks) {
      if (start < at) continue;
      spans
        ..add(TextSpan(text: text.substring(at, start)))
        ..add(
          TextSpan(
            text: text.substring(start, end),
            style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface),
          ),
        );
      at = end;
    }
    spans.add(TextSpan(text: text.substring(at)));
    return ListTile(
      isThreeLine: true,
      title: Text(
        _label,
        style: TextStyle(fontFamilyFallback: scriptureFontFallback, color: scheme.primary),
      ),
      subtitle: Text.rich(
        TextSpan(children: spans),
        style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
      ),
      trailing: IconButton(
        tooltip: 'Open in the Bible',
        icon: const Icon(Icons.menu_book_outlined),
        onPressed: onRead,
      ),
      onTap: onOpen,
    );
  }
}
