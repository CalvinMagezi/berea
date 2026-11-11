import 'dart:async';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';

const searchResultLimit = 100;
const _minQueryLength = 2;
// Long enough that typing a word does not search each letter, short enough to feel immediate.
const _searchDelay = Duration(milliseconds: 300);

/// The search icon some places carry; it shows the Search place.
class SearchButton extends StatelessWidget {
  final AppState state;
  const SearchButton({super.key, required this.state});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Search the Bible',
    icon: const Icon(Icons.search),
    onPressed: state.openSearch,
  );
}

/// Full-text search over the current translation. A reference in the query jumps straight to it.
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
  final _field = TextEditingController();
  final _focus = FocusNode();
  // The empty-state line waits for a finished search, not the pause before it.
  var _searched = false;
  var _searching = false;
  var _failed = false;
  var _request = 0;
  Timer? _pending;

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

  void _onChanged(String value) {
    final query = value.trim();
    _request++;
    setState(() {
      _query = query;
      _searched = false;
      _searching = false;
      _failed = false;
    });
    _pending?.cancel();
    if (query.length < _minQueryLength) {
      setState(() {
        _groups = const [];
        _spelling = null;
      });
      return;
    }
    _pending = Timer(_searchDelay, () => _run(query));
  }

  Future<void> _run(String query) async {
    final request = ++_request;
    setState(() => _searching = true);
    var found = const SearchResult([], null);
    var failed = false;
    try {
      found = await widget.state.searchVerses(
        query,
        translation: widget.state.settings.translation,
        perGroup: searchResultLimit,
      );
    } on Object catch (e) {
      debugPrint('Search failed: $e');
      failed = true;
    }
    // A newer keystroke owns the screen; its answer is the one to show.
    if (!mounted || request != _request) return;
    setState(() {
      _groups = found.groups;
      _spelling = found.spelling;
      _searched = !failed;
      _failed = failed;
      _searching = false;
    });
  }

  void _open(Ref ref) {
    _release();
    widget.state.openInReader(ref);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final scheme = Theme.of(context).colorScheme;
    final translation = s.settings.translation;
    final refs = RefParser.parse(_query);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: widget.active,
          controller: _field,
          focusNode: _focus,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search $translation or type a reference',
            filled: false,
            border: InputBorder.none,
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
              for (final r in refs)
                ListTile(
                  leading: Icon(Icons.arrow_forward, color: scheme.primary),
                  title: Text('Go to ${r.label}'),
                  onTap: () => _open(r),
                ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'The search could not be run. Try typing it again.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              if (_searched && _groups.isEmpty && _spelling == null && refs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    searchIsTooCommon(_query)
                        ? '"$_query" is in too many verses to list. Add another word.'
                        : 'No verse in the $translation has those words.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
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
                      style: TextStyle(
                        fontFamilyFallback: scriptureFontFallback,
                        color: scheme.primary,
                      ),
                    ),
                    subtitle: Text(v.text, style: scriptureStyle(context).copyWith(fontSize: 15)),
                    onTap: () => _open(Ref(v.book, v.chapter, v.verse)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Names how the verses below were found, and how many there are, so the order is checkable.
class _GroupHeader extends StatelessWidget {
  final SearchGroup group;
  const _GroupHeader({required this.group});

  @override
  Widget build(BuildContext context) {
    final shown = group.verses.length;
    final count = shown < group.total
        ? '$shown of ${group.total} verses, in Bible order'
        : '${group.total} ${group.total == 1 ? 'verse' : 'verses'}, in Bible order';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        '${group.label} · $count',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
