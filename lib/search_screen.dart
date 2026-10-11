import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';

const searchResultLimit = 100;

/// Full-text search over the current translation. A reference in the query jumps straight to it.
class SearchScreen extends StatefulWidget {
  final AppState state;
  const SearchScreen({super.key, required this.state});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  var _query = '';

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
    final hits = _query.length < 3
        ? const <Verse>[]
        : s.db.search(_query, translation: translation, k: searchResultLimit);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          onChanged: (v) => setState(() => _query = v.trim()),
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
              if (_query.length >= 3 && hits.isEmpty && refs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('No verses match.', style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              for (final v in hits)
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
          ),
        ),
      ),
    );
  }
}
