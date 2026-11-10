import 'dart:async';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';

const searchResultLimit = 100;
const _minQueryLength = 2;
// Long enough that typing a word does not search each letter, short enough to feel immediate.
const _searchDelay = Duration(milliseconds: 300);

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
  Timer? _pending;

  @override
  void dispose() {
    _pending?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    final query = value.trim();
    setState(() => _query = query);
    _pending?.cancel();
    if (query.length < _minQueryLength) {
      setState(() => _groups = const []);
      return;
    }
    _pending = Timer(_searchDelay, () {
      final translation = widget.state.settings.translation;
      final found = widget.state.db.searchVerses(
        query,
        translation: translation,
        perGroup: searchResultLimit,
      );
      if (mounted) setState(() => _groups = found);
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
              for (final r in refs)
                ListTile(
                  leading: Icon(Icons.arrow_forward, color: scheme.primary),
                  title: Text('Go to ${r.label}'),
                  onTap: () => _open(r),
                ),
              if (_query.length >= _minQueryLength && _groups.isEmpty && refs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No verse in the $translation has those words.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
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
