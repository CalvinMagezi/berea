import 'package:flutter/material.dart';

import 'app_state.dart';
import 'export.dart';
import 'note_dialog.dart';
import 'study_page_screen.dart';
import 'theme.dart';

class NotesScreen extends StatefulWidget {
  final AppState state;
  final VoidCallback onOpenStudy;
  const NotesScreen({super.key, required this.state, required this.onOpenStudy});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  var _filter = '';

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.state.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final scheme = Theme.of(context).colorScheme;
    final q = _filter.toLowerCase();
    final studies = s.study
        .conversations()
        .where((c) => c.title.toLowerCase().contains(q))
        .toList();
    final pages = s.study
        .studyPages()
        .where(
          (p) => p.ref.label.toLowerCase().contains(q) || p.observation.toLowerCase().contains(q),
        )
        .toList();
    final notes = s.study
        .notes()
        .where((n) => n.text.toLowerCase().contains(q) || n.ref.label.toLowerCase().contains(q))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notes',
          style: TextStyle(fontFamilyFallback: scriptureFontFallback, fontSize: 24),
        ),
        actions: [
          IconButton(
            tooltip: 'Export all as Markdown',
            icon: const Icon(Icons.ios_share),
            onPressed: () => saveMarkdown(
              'berea-notes.md',
              allNotesMarkdown(s.study, s.db, s.settings.translation),
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              onChanged: (v) => setState(() => _filter = v.trim()),
              decoration: const InputDecoration(
                hintText: 'Search notes and studies',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: studies.isEmpty && notes.isEmpty && pages.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Studies you have with Berea and notes you add in the Bible tab appear here. '
                    'Everything stays on this device.',
                    style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                  children: [
                    if (studies.isNotEmpty) _Header('Saved studies'),
                    for (final c in studies)
                      ListTile(
                        leading: const Icon(Icons.auto_stories_outlined),
                        title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${c.messageCount ~/ 2} turns · ${_date(c.updated)}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => s.deleteConversation(c.id),
                        ),
                        onTap: () {
                          s.openConversation(c.id);
                          widget.onOpenStudy();
                        },
                      ),
                    if (pages.isNotEmpty) _Header('Study pages'),
                    for (final p in pages)
                      ListTile(
                        leading: const Icon(Icons.article_outlined),
                        title: Text(
                          p.ref.label,
                          style: TextStyle(fontFamilyFallback: scriptureFontFallback),
                        ),
                        subtitle: Text(p.observation, maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            s.study.deleteStudyPage(p.id);
                            s.touch();
                          },
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => StudyPageScreen(state: s, ref: p.ref),
                          ),
                        ),
                      ),
                    if (notes.isNotEmpty) _Header('Notes'),
                    for (final n in notes)
                      ListTile(
                        leading: const Icon(Icons.sticky_note_2_outlined),
                        title: Text(
                          n.ref.label,
                          style: TextStyle(fontFamilyFallback: scriptureFontFallback),
                        ),
                        subtitle: Text(n.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: Text(
                          _date(n.updated),
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                        onTap: () => showNoteDialog(context, s, ref: n.ref, note: n),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
