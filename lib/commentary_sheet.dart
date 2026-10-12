import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';

/// Longer comments show this much, with the rest a tap away, so a whole-book preface never
/// has to lay out inside the sheet.
const commentaryPreviewChars = 1200;
const _sheetHeight = 0.85;

/// What the installed public domain commentaries say on [ref], each under its title, author
/// and licence. Book and chapter introductions are folded away at the end.
Future<void> showCommentary(BuildContext context, AppState s, Ref ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => FractionallySizedBox(
      heightFactor: _sheetHeight,
      child: CommentaryPanel(library: s.commentary.library, passage: ref),
    ),
  );
}

class CommentaryPanel extends StatelessWidget {
  final CommentaryLibrary library;
  final Ref passage;
  const CommentaryPanel({super.key, required this.library, required this.passage});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = passage.verseStart ?? 1;
    final entries = library.forRange(
      passage.book.id,
      passage.chapter,
      first,
      passage.verseEnd ?? first,
    );
    final intros = library.introductions(passage.book.id, passage.chapter);
    final modules = {for (final m in library.modules()) m.id: m};
    final byModule = <String, List<CommentaryEntry>>{};
    for (final e in entries) {
      byModule.putIfAbsent(e.module, () => []).add(e);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            passage.label,
            style: TextStyle(fontFamilyFallback: scriptureFontFallback, fontSize: 22),
          ),
          Text(
            'Commentary, public domain, on this device',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                if (library.isEmpty)
                  _Muted(
                    'No commentaries are installed. They are optional: open Settings and '
                    'download them under Commentaries.',
                  )
                else if (entries.isEmpty && intros.isEmpty)
                  _Muted('The installed commentaries have nothing on this passage.'),
                for (final e in byModule.entries)
                  _ModuleComments(module: modules[e.key], moduleId: e.key, entries: e.value),
                if (intros.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Introductions'),
                    children: [
                      for (final e in intros) ...[
                        _Label(_introLabel(modules[e.module], e)),
                        _CommentText(text: e.text, title: _introLabel(modules[e.module], e)),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _introLabel(CommentaryModule? m, CommentaryEntry e) {
    final where = e.chapter == 0 ? passage.book.name : '${passage.book.name} ${e.chapter}';
    return '${m?.title ?? e.module}, on $where';
  }
}

class _ModuleComments extends StatelessWidget {
  final CommentaryModule? module;
  final String moduleId;
  final List<CommentaryEntry> entries;
  const _ModuleComments({required this.module, required this.moduleId, required this.entries});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = module;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(m?.title ?? moduleId, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (m != null)
            Text(
              '${m.author} · ${m.licence}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          const SizedBox(height: 6),
          for (final e in entries) ...[
            _Label(_rangeLabel(e)),
            _CommentText(text: e.text, title: '${m?.title ?? moduleId}, ${_rangeLabel(e)}'),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  String _rangeLabel(CommentaryEntry e) =>
      Ref(bookById(e.book), e.chapter, e.verseStart, e.verseEnd).label;
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary));
}

class _Muted extends StatelessWidget {
  final String text;
  const _Muted(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
}

/// A comment, cut to a preview when long; the whole text opens on its own page.
class _CommentText extends StatelessWidget {
  final String text;
  final String title;
  const _CommentText({required this.text, required this.title});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(height: 1.5);
    if (text.length <= commentaryPreviewChars) return SelectableText(text, style: style);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${text.substring(0, commentaryPreviewChars).trimRight()}…', style: style),
        TextButton(
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => _FullComment(title: title, text: text),
            ),
          ),
          child: const Text('Read all'),
        ),
      ],
    );
  }
}

class _FullComment extends StatelessWidget {
  final String title;
  final String text;
  const _FullComment({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final paragraphs = text.split('\n');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            itemCount: paragraphs.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SelectableText(paragraphs[i], style: const TextStyle(height: 1.5)),
            ),
          ),
        ),
      ),
    );
  }
}
