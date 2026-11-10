import 'dart:async';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';

const searchResultLimit = 100;
const _minQueryLength = 2;
// Long enough that typing a word does not search each letter, short enough to feel immediate.
const _searchDelay = Duration(milliseconds: 300);

/// Opens the Bible search from any place.
void openSearch(BuildContext context, AppState state) => Navigator.of(context).push(
  MaterialPageRoute<void>(builder: (_) => SearchScreen(state: state)),
);

/// The search button every place carries, so search is one tap away wherever the reader is.
class SearchButton extends StatelessWidget {
  final AppState state;
  const SearchButton({super.key, required this.state});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Search the Bible',
    icon: const Icon(Icons.search),
    onPressed: () => openSearch(context, state),
  );
}

/// Full-text search over the current translation. A reference in the query jumps straight to it.
class SearchScreen extends StatefulWidget {
  final AppState state;
  const SearchScreen({super.key, required this.state});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  var _query = '';
  var _groups = const <SearchGroup>[];
  Spelling? _spelling;
  final _field = TextEditingController();
  // The empty-state line waits for a finished search, not the pause before it.
  var _searched = false;
  var _searching = false;
  var _failed = false;
  var _request = 0;
  Timer? _pending;

  @override
  void dispose() {
    _pending?.cancel();
    _field.dispose();
    super.dispose();
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
    widget.state.setReader(ref.book, ref.chapter, ref.verseStart);
    Navigator.pop(context);
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
          autofocus: true,
          controller: _field,
          onChanged: _onChanged,
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
                _GroupHeader(state: widget.state, group: g),
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

// True for search groups whose hits are Scripture rather than headings or dictionary entries.
bool _isScriptureGroup(String label) =>
    label.startsWith('Exact words') ||
    label.startsWith('Other forms') ||
    label.startsWith('All your words') ||
    RegExp(r'^\d+\s+of\s+').hasMatch(label);

/// Names how the verses below were found, and how many there are, so the order is checkable.
class _GroupHeader extends StatelessWidget {
  final AppState state;
  final SearchGroup group;
  const _GroupHeader({required this.state, required this.group});

  @override
  Widget build(BuildContext context) {
    final shown = group.verses.length;
    final count = shown < group.total
        ? '$shown of ${group.total} verses, in Bible order'
        : '${group.total} ${group.total == 1 ? 'verse' : 'verses'}, in Bible order';
    final text = Text(
      '${group.label} · $count',
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
    final canSave = _isScriptureGroup(group.label);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: canSave
          ? Row(
              children: [
                Expanded(child: text),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {
                    final refs = [
                      for (final v in group.verses)
                        Ref(v.book, v.chapter, v.verse, v.verse),
                    ];
                    state.practice.saveSet(refs);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Saved as a set.')),
                    );
                  },
                  child: const Text('Save as a set'),
                ),
              ],
            )
          : text,
    );
  }
}
