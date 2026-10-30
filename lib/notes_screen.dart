import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'export.dart';
import 'note_dialog.dart';
import 'notebook_store.dart';
import 'notebooks_screen.dart';
import 'study_store.dart';
import 'settings_sheet.dart';
import 'theme.dart';

/// Recent shows this many entries; older ones are in their notebooks.
const recentLimit = 50;
const _cardWidth = 140.0;
const _cardHeight = 116.0;
const _cardRadius = 14.0;
const _refsShown = 2;

/// Notebook [id]'s page, carrying its id so the sidebar can tell which notebook is open.
Route<void> notebookRoute(AppState s, int id) => MaterialPageRoute<void>(
  settings: RouteSettings(name: notebookRouteName, arguments: id),
  builder: (_) => NotebookScreen(state: s, notebookId: id),
);

const notebookRouteName = 'notebook';

/// Opens notebook [id] where the Notes place keeps its pages.
void openNotebook(BuildContext context, AppState s, int id) =>
    Navigator.push(context, notebookRoute(s, id));

/// Follows the Notes place's pages and tells which notebook is open under whatever is on top.
class OpenNotebookObserver extends NavigatorObserver {
  final open = ValueNotifier<int?>(null);
  final _stack = <Route<dynamic>>[];

  void _sync() => open.value =
      _stack.reversed
              .where((r) => r.settings.name == notebookRouteName)
              .firstOrNull
              ?.settings
              .arguments
          as int?;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final at = _stack.indexOf(oldRoute!);
    if (at < 0 || newRoute == null) return;
    _stack[at] = newRoute;
    _sync();
  }
}

/// Notes: the notebooks in a row, with New, and Recent: notes, kept words, study pages and
/// readings, newest first, each labelled with its notebook.
class NotesScreen extends StatefulWidget {
  final AppState state;
  const NotesScreen({super.key, required this.state});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  var _searching = false;
  var _filter = '';

  /// The entry shown beside the list on a wide screen.
  (Type, int)? _selected;
  var _wide = false;

  AppState get _s => widget.state;

  Future<void> _newNotebook() async {
    final id = await createNotebook(context, _s.notebooks);
    if (id != null && mounted) openNotebook(context, _s, id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
                decoration: const InputDecoration(
                  hintText: 'Search notes and readings',
                  isDense: true,
                ),
              )
            : Text(
                'Notes',
                style: TextStyle(fontFamilyFallback: scriptureFontFallback, fontSize: 24),
              ),
        actions: [
          IconButton(
            tooltip: _searching ? 'Stop searching' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _filter = '';
            }),
          ),
          SettingsButton(state: _s),
          IconButton(
            tooltip: 'Export all as Markdown',
            icon: const Icon(Icons.ios_share),
            onPressed: () => saveMarkdown(
              'berea-notes.md',
              allNotesMarkdown(_s.study, _s.db, _s.settings.translation, content: _s.prayerContent),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showNoteEditor(context, _s),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Write'),
      ),
      body: ListenableBuilder(
        listenable: _s.notebooks,
        builder: (context, _) => LayoutBuilder(
          builder: (context, c) {
            _wide = c.maxWidth >= notesWideBreakpoint;
            final notebooks = _s.notebooks.notebooks();
            final recent = _recent(notebooks);
            final list = _list(notebooks, [for (final (_, tile) in recent) tile]);
            if (!_wide) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                  child: list,
                ),
              );
            }
            final chosen = recent
                .map((r) => r.$1)
                .where((e) => entryKey(e) == _selected)
                .firstOrNull;
            return ListAndDetail(
              list: list,
              detail: chosen == null
                  ? Center(
                      child: Text(
                        'Choose a note to read it here.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : EntryDetail(state: _s, entry: chosen, onChanged: () => setState(() {})),
            );
          },
        ),
      ),
    );
  }

  Widget _list(List<Notebook> notebooks, List<Widget> recent) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
      children: [
        if (!_searching) ...[
          const _Header('Notebooks'),
          _NotebookRow(
            state: _s,
            notebooks: notebooks,
            onOpen: (id) => openNotebook(context, _s, id),
            onNew: _newNotebook,
          ),
        ],
        const _Header('Recent'),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _filter.isEmpty
                  ? 'Notes you write, words you keep, study pages and readings appear '
                        'here. Everything stays on this device.'
                  : 'Nothing matches "$_filter".',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
            ),
          ),
        ...recent,
      ],
    );
  }

  bool _matches(Iterable<String> fields) =>
      _filter.isEmpty || fields.any((f) => f.toLowerCase().contains(_filter));

  /// Notes and study pages by when they changed; readings carry no date of their own, so they
  /// sort by their notebook's.
  List<(Object, Widget)> _recent(List<Notebook> notebooks) {
    final byId = {for (final n in notebooks) n.id: n};
    final dated = <(DateTime, Object, Widget)>[
      for (final (n, nb) in allNotes(_s.study, _s.notebooks))
        if (_matches([n.title, n.text, n.verse?.label ?? '', nb.title]))
          (n.updated, n, _noteTile(n, nb)),
      for (final p in _s.study.studyPages())
        if (byId[p.notebookId] case final nb?)
          if (_matches([p.ref.label, p.observation, nb.title])) (p.updated, p, _pageTile(p, nb)),
      for (final nb in notebooks)
        for (final r in _s.notebooks.sources(nb.id))
          if (r.kind != SourceKind.note && _matches([r.title, nb.title]))
            (nb.updated, r, _readingTile(r, nb)),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final (_, entry, tile) in dated.take(recentLimit)) (entry, tile)];
  }

  /// A wide screen shows the entry beside the list; otherwise it opens on its own.
  void _open(Object entry) =>
      _wide ? setState(() => _selected = entryKey(entry)) : openEntryPage(context, _s, entry);

  bool _isSelected(Object entry) => _wide && entryKey(entry) == _selected;

  Widget _noteTile(Note n, Notebook nb) {
    final where = switch (n.verse) {
      final v? => [v.label],
      null => RefParser.parse(n.text).take(_refsShown).map((r) => r.label),
    };
    final detail = n.title.isEmpty
        ? n.text
        : [...where, noteDate(n.updated, short: true)].join(' · ');
    return LabelledTile(
      label: '${noteKind(n)} · ${nb.title}',
      title: noteHeading(n),
      detail: detail,
      selected: _isSelected(n),
      onTap: () => _open(n),
    );
  }

  Widget _pageTile(StudyPageRecord p, Notebook nb) => LabelledTile(
    label: 'Study page · ${nb.title}',
    title: p.ref.label,
    detail: p.observation.isEmpty ? null : 'Observation: ${p.observation}',
    selected: _isSelected(p),
    onTap: () => _open(p),
  );

  Widget _readingTile(NotebookSource r, Notebook nb) => LabelledTile(
    label: 'Reading · ${nb.title}',
    title: r.title,
    detail: [r.kind.label, if (r.pinned) 'Always included'].join(' · '),
    selected: _isSelected(r),
    onTap: () => _open(r),
  );
}

/// The notebooks as cards in one scrolling row, newest first, then New.
class _NotebookRow extends StatelessWidget {
  final AppState state;
  final List<Notebook> notebooks;
  final ValueChanged<int> onOpen;
  final VoidCallback onNew;
  const _NotebookRow({
    required this.state,
    required this.notebooks,
    required this.onOpen,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _cardHeight,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final n in notebooks)
          _Card(
            icon: Icons.class_outlined,
            title: n.title,
            detail: _counts(n),
            onTap: () => onOpen(n.id),
          ),
        _Card(icon: Icons.add, title: 'New notebook', onTap: onNew),
      ],
    ),
  );

  String _counts(Notebook n) {
    return [
      plural(writtenCount(state.study, n.id), 'note', 'notes'),
      if (n.sourceCount > 0) plural(n.sourceCount, 'reading', 'readings'),
    ].join(' · ');
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback onTap;
  const _Card({required this.icon, required this.title, required this.onTap, this.detail});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_cardRadius),
          onTap: onTap,
          child: SizedBox(
            width: _cardWidth,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (detail case final d?)
                    Text(
                      d,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
