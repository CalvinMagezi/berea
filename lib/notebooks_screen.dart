import 'dart:async';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'brand/lamp_mark.dart';
import 'confirm.dart';
import 'keep_sheet.dart';
import 'listen_screen.dart';
import 'note_dialog.dart';
import 'notebook_store.dart';
import 'study_packet_screen.dart';
import 'study_page_screen.dart';
import 'study_store.dart';
import 'theme.dart';

export 'confirm.dart';

/// Wide enough for a paragraph of pasted text without filling a desktop window.
const _pasteDialogWidth = 520.0;
const _notePickerWidth = 480.0;
const _citedMarkWidth = 3.0;
const _citedPadding = 12.0;
const _kindLabelSize = 11.0;
const _bottomBarPadding = 12.0;
const _askMarkSize = 18.0;

/// Measured on the room the Notes place has beside the sidebar, not the window; local rather
/// than the shell's constant, so the Notes screens do not import the shell.
const notesWideBreakpoint = 760.0;
const notesWideListWidth = 400.0;
const _detailTitleSize = 26.0;
const _detailPadding = 24.0;
const _askIconSize = 32.0;

IconData kindIcon(SourceKind k) => switch (k) {
  SourceKind.text => Icons.notes,
  SourceKind.note => Icons.sticky_note_2_outlined,
  SourceKind.passage => Icons.menu_book_outlined,
  SourceKind.commentary => Icons.history_edu_outlined,
  SourceKind.pdf => Icons.picture_as_pdf_outlined,
  SourceKind.epub => Icons.auto_stories_outlined,
};

String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

void _say(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

/// Asks for a notebook's name; null when cancelled.
Future<String?> askNotebookName(BuildContext context, {required String title, String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: maxNotebookTitleChars,
        decoration: const InputDecoration(hintText: 'A passage or a topic, such as Romans 8'),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Asks for a Bible reference as typed; null when cancelled.
Future<String?> askReference(BuildContext context, String title) {
  final controller = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        void submit() {
          final text = controller.text.trim();
          if (text.isEmpty) {
            setDialogState(() => error = 'Type a passage first.');
            return;
          }
          Navigator.pop(ctx, text);
        }

        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            onChanged: (_) => setDialogState(() => error = null),
            decoration: InputDecoration(hintText: 'Romans 8:28-39', errorText: error),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: submit, child: const Text('Add')),
          ],
        );
      },
    ),
  );
}

/// Asks for a name and makes the notebook; its id, or null when cancelled or refused.
Future<int?> createNotebook(BuildContext context, NotebookStore store) async {
  final name = await askNotebookName(context, title: 'New notebook');
  if (name == null || !context.mounted) return null;
  try {
    return store.createNotebook(name);
  } on FormatException catch (e) {
    _say(context, e.message);
    return null;
  }
}

/// What a note is called in lists: its title, else its verse, else its first words.
String noteHeading(Note n) {
  if (n.title.isNotEmpty) return n.title;
  if (n.verse case final v?) return v.label;
  return firstWords(n.text);
}

/// The small capitals label over a note in a list.
String noteKind(Note n) => isKeptWord(n)
    ? 'Kept word'
    : n.verse == null
    ? 'Note'
    : 'Note on a verse';

/// The notes, kept words and study pages in notebook [id]: what its Notes view lists.
int writtenCount(StudyStore study, int id) =>
    study.notebookNotes(id).length + study.studyPages(notebookId: id).length;

/// The readings notebook [id] lists: a note linked from its own notes is listed as the note.
List<NotebookSource> listedReadings(StudyStore study, NotebookStore notebooks, int id) {
  final own = {for (final n in study.notebookNotes(id)) n.id};
  return [
    for (final r in notebooks.sources(id))
      if (r.noteId == null || !own.contains(r.noteId)) r,
  ];
}

/// Every note in every notebook with its notebook, newest first.
List<(Note, Notebook)> allNotes(StudyStore study, NotebookStore notebooks) =>
    [
      for (final nb in notebooks.notebooks())
        for (final n in study.notebookNotes(nb.id)) (n, nb),
    ]..sort((a, b) => b.$1.updated.compareTo(a.$1.updated));

const _titleWords = 8;

String firstWords(String text) {
  final words = text.trim().split(RegExp(r'\s+'));
  final head = words.take(_titleWords).join(' ');
  return words.length > _titleWords ? '$head…' : head;
}

/// One entry in a list of notes, kept words, study pages and readings: a small label over a
/// title and a line of detail.
class LabelledTile extends StatelessWidget {
  final String label;
  final String title;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Shown in the panel beside the list, on a wide screen.
  final bool selected;
  const LabelledTile({
    super.key,
    required this.label,
    required this.title,
    this.detail,
    this.trailing,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      selected: selected,
      selectedTileColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.onSurface,
      trailing: trailing,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: _kindLabelSize,
              letterSpacing: 1,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
      subtitle: detail == null
          ? null
          : Text(detail!, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}

/// What identifies a note, study page or reading across rebuilds, which make new objects.
(Type, int)? entryKey(Object? entry) => switch (entry) {
  Note n => (Note, n.id),
  StudyPageRecord p => (StudyPageRecord, p.id),
  NotebookSource r => (NotebookSource, r.id),
  _ => null,
};

/// Opens a note in the editor, or a study page or reading on its own page.
Future<void> openEntryPage(BuildContext context, AppState s, Object entry) => switch (entry) {
  Note n => showNoteEditor(context, s, note: n),
  StudyPageRecord p => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => StudyPageScreen(state: s, ref: p.ref)),
  ),
  NotebookSource r => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => SourceScreen(store: s.notebooks, source: r)),
  ),
  _ => Future.value(),
};

/// A list with the chosen entry beside it, on a wide screen.
class ListAndDetail extends StatelessWidget {
  final Widget list;
  final Widget detail;
  const ListAndDetail({super.key, required this.list, required this.detail});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(width: notesWideListWidth, child: list),
      const VerticalDivider(width: 1),
      Expanded(child: detail),
    ],
  );
}

/// The panel beside the list on a wide screen: the chosen note, study page or reading.
/// [onChanged] runs after it was edited on its own page, so the lists show the change.
class EntryDetail extends StatelessWidget {
  final AppState state;
  final Object entry;
  final VoidCallback onChanged;
  const EntryDetail({
    super.key,
    required this.state,
    required this.entry,
    required this.onChanged,
  });

  Future<void> _edit(BuildContext context) async {
    await openEntryPage(context, state, entry);
    onChanged();
  }

  @override
  Widget build(BuildContext context) => switch (entry) {
    NotebookSource r => SourceScreen(
      key: ValueKey(r.id),
      store: state.notebooks,
      source: r,
      embedded: true,
    ),
    Note n => _DetailPage(
      label: noteKind(n),
      title: noteHeading(n),
      detail: noteDate(n.updated),
      verse: n.verse,
      state: state,
      action: FilledButton.icon(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Edit'),
      ),
      children: [SelectableText(n.text, style: const TextStyle(fontSize: 17, height: 1.5))],
    ),
    StudyPageRecord p => _DetailPage(
      label: 'Study page',
      title: p.ref.label,
      detail: 'Saved ${noteDate(p.updated)}',
      verse: p.ref,
      state: state,
      action: FilledButton.icon(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Open'),
      ),
      children: [
        for (final (heading, text) in [
          ('Observation', p.observation),
          ('Interpretation', p.interpretation),
          ('Application', p.application),
        ])
          if (text.isNotEmpty) ...[
            Text(heading, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(text, style: const TextStyle(height: 1.5)),
            const SizedBox(height: 20),
          ],
      ],
    ),
    _ => const SizedBox.shrink(),
  };
}

class _DetailPage extends StatelessWidget {
  final String label;
  final String title;
  final String detail;
  final Ref? verse;
  final AppState state;
  final Widget action;
  final List<Widget> children;
  const _DetailPage({
    required this.label,
    required this.title,
    required this.detail,
    required this.verse,
    required this.state,
    required this.action,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(_detailPadding),
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: scheme.primary),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(fontFamilyFallback: scriptureFontFallback, fontSize: _detailTitleSize),
        ),
        Text(detail, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            action,
            if (verse case final v?)
              OutlinedButton.icon(
                onPressed: () => state.openInReader(v),
                icon: const Icon(Icons.menu_book_outlined),
                label: Text('Open ${v.label} in the Bible'),
              ),
          ],
        ),
        const SizedBox(height: 20),
        ...children,
      ],
    );
  }
}

enum _NotebookAction { rename, delete }

class _NotebookMenu extends StatelessWidget {
  final NotebookStore store;
  final Notebook notebook;
  final VoidCallback? onDeleted;
  const _NotebookMenu({required this.store, required this.notebook, this.onDeleted});

  Future<void> _act(BuildContext context, _NotebookAction a) async {
    switch (a) {
      case _NotebookAction.rename:
        final name = await askNotebookName(
          context,
          title: 'Rename notebook',
          initial: notebook.title,
        );
        if (name == null || !context.mounted) return;
        try {
          store.renameNotebook(notebook.id, name);
        } on FormatException catch (e) {
          _say(context, e.message);
        }
      case _NotebookAction.delete:
        final added = store.addedWords(notebook.id);
        final ok = await confirmAction(
          context,
          'Delete ${notebook.title}?',
          'Its ${plural(notebook.sourceCount, 'reading', 'readings')}'
              '${added == 0 ? '' : ' and the ${plural(added, 'word study', 'word studies')} Study notebook added'}'
              ' will be removed from this device. Notes and study pages you wrote in it move to '
              '$notesOnVersesTitle. This cannot be undone.',
          'Delete',
        );
        if (!ok || !context.mounted) return;
        store.deleteNotebook(notebook.id);
        onDeleted?.call();
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<_NotebookAction>(
    tooltip: 'Notebook options',
    onSelected: (a) => _act(context, a),
    itemBuilder: (_) => const [
      PopupMenuItem(value: _NotebookAction.rename, child: Text('Rename')),
      PopupMenuItem(value: _NotebookAction.delete, child: Text('Delete')),
    ],
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _EmptyState({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}

enum _View { everything, notes, readings }

/// The Add sheet's choice for writing a note; its other choices are reading kinds.
const _writeNote = 'note';

/// One notebook: its notes, kept words and study pages, the readings it holds, a way to add
/// either, and Ask about this notebook, which opens Study scoped to it.
class NotebookScreen extends StatefulWidget {
  final AppState state;
  final int notebookId;
  const NotebookScreen({super.key, required this.state, required this.notebookId});

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen> {
  var _view = _View.everything;

  /// The entry shown beside the list on a wide screen.
  (Type, int)? _selected;
  var _wide = false;

  AppState get _s => widget.state;
  NotebookStore get store => _s.notebooks;
  int get notebookId => widget.notebookId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final notebook = store.notebook(notebookId);
      if (notebook == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('This notebook has been deleted.')),
        );
      }
      final notes = _s.study.notebookNotes(notebookId);
      final pages = _s.study.studyPages(notebookId: notebookId);
      final readings = listedReadings(_s.study, store, notebookId);
      final pending = store.pendingFor(notebookId);
      final written = notes.length + pages.length;
      return Scaffold(
        appBar: AppBar(
          title: Text(notebook.title),
          actions: [
            IconButton(
              tooltip: 'Synthesize',
              icon: const Icon(Icons.auto_stories_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => StudyPacketScreen(state: _s, notebookId: notebookId),
                ),
              ),
            ),
            ListenButton(state: _s, notebookId: notebookId, title: notebook.title),
            _NotebookMenu(
              store: store,
              notebook: notebook,
              onDeleted: () => Navigator.maybePop(context),
            ),
          ],
        ),
        bottomNavigationBar: _bottomBar(context),
        body: LayoutBuilder(
          builder: (context, c) {
            _wide = c.maxWidth >= notesWideBreakpoint;
            final list = _views(context, notes, pages, readings, pending, written);
            if (!_wide) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                  child: list,
                ),
              );
            }
            // Only what the current view lists; a hidden entry leaves the panel.
            final chosen = [
              if (_view != _View.readings) ...[...notes, ...pages],
              if (_view != _View.notes) ...readings,
            ].where((e) => entryKey(e) == _selected).firstOrNull;
            return ListAndDetail(
              list: list,
              detail: chosen == null
                  ? const _AskPanel()
                  : EntryDetail(state: _s, entry: chosen, onChanged: () => setState(() {})),
            );
          },
        ),
      );
    },
  );

  /// The counts, the Everything, Notes and Readings views, and the list under them.
  Widget _views(
    BuildContext context,
    List<Note> notes,
    List<StudyPageRecord> pages,
    List<NotebookSource> readings,
    List<PendingSource> pending,
    int written,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(
          '${plural(written, 'note', 'notes')} · '
          '${plural(readings.length, 'reading', 'readings')}',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<_View>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(value: _View.everything, label: Text('Everything')),
              ButtonSegment(value: _View.notes, label: Text('Notes $written')),
              ButtonSegment(
                value: _View.readings,
                label: Text('Readings ${readings.length}'),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (v) => setState(() => _view = v.single),
          ),
        ),
      ),
      Expanded(child: _list(context, notes, pages, readings, pending)),
    ],
  );

  Widget _bottomBar(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(_bottomBarPadding),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _add(context),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
              const SizedBox(width: _bottomBarPadding),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _s.askAboutNotebook(notebookId),
                  icon: Builder(
                    builder: (context) {
                      final on = Theme.of(context).colorScheme.onPrimary;
                      return LampMark(size: _askMarkSize, ink: on, flame: on);
                    },
                  ),
                  label: const Text('Ask about this notebook'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _list(
    BuildContext context,
    List<Note> notes,
    List<StudyPageRecord> pages,
    List<NotebookSource> readings,
    List<PendingSource> pending,
  ) {
    final showWritten = _view != _View.readings;
    final showReadings = _view != _View.notes;
    final written = [
      if (showWritten) ...[
        for (final n in notes) (n.updated, _noteTile(context, n)),
        for (final p in pages) (p.updated, _pageTile(context, p)),
      ],
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    final tiles = [
      for (final (_, tile) in written) tile,
      if (showReadings) ...[
        for (final r in readings) _readingTile(context, r),
        for (final p in pending) _pendingTile(p),
      ],
    ];
    if (tiles.isEmpty) {
      return _EmptyState(
        icon: Icons.library_add_outlined,
        title: switch (_view) {
          _View.readings => 'No readings yet',
          _View.notes => 'No notes yet',
          _View.everything => 'Nothing here yet',
        },
        body:
            'Write a note, or bring in a reading: a Bible passage, commentary on it, pasted '
            'text, a PDF or an EPUB book. Everything stays on this device.',
      );
    }
    return ListView(padding: const EdgeInsets.fromLTRB(8, 8, 8, 24), children: tiles);
  }

  /// A wide screen shows the entry beside the list; otherwise it opens on its own.
  void _open(BuildContext context, Object entry) => _wide
      ? setState(() => _selected = entryKey(entry))
      : openEntryPage(context, _s, entry);

  bool _isSelected(Object entry) => _wide && entryKey(entry) == _selected;

  Widget _noteTile(BuildContext context, Note n) => LabelledTile(
    label: noteKind(n),
    title: noteHeading(n),
    detail: n.text.isEmpty ? null : n.text,
    selected: _isSelected(n),
    onTap: () => _open(context, n),
  );

  Widget _pageTile(BuildContext context, StudyPageRecord p) => LabelledTile(
    label: 'Study page',
    title: p.ref.label,
    detail: p.observation.isEmpty ? 'Observation, interpretation, application' : p.observation,
    trailing: IconButton(
      tooltip: 'Delete study page',
      icon: const Icon(Icons.delete_outline),
      onPressed: () async {
        final ok = await confirmAction(
          context,
          'Delete the study page on ${p.ref.label}?',
          'It will be removed from this device. This cannot be undone.',
          'Delete',
        );
        if (!ok) return;
        _s.study.deleteStudyPage(p.id);
        _s.touch();
      },
    ),
    selected: _isSelected(p),
    onTap: () => _open(context, p),
  );

  /// A passage reading's verses, from its origin "Romans 8:18-39|BSB" (see passageSource).
  (Ref, String)? _passage(NotebookSource r) {
    final parts = r.origin.split('|');
    if (r.kind != SourceKind.passage || parts.length != 2) return null;
    final ref = RefParser.parse(parts.first).firstOrNull;
    return ref == null ? null : (ref, parts.last);
  }

  /// As the notebook board draws a reading: a passage by its translation and verses, a
  /// commentary by where it came from, the rest by sections.
  String _readingDetail(NotebookSource r) {
    if (_passage(r) case (final ref, final translation)) {
      final verses = _s.db.verses(ref, translation: translation).length;
      return '$translation · ${plural(verses, 'verse', 'verses')}';
    }
    if (r.kind == SourceKind.commentary) return 'From the installed commentaries';
    return plural(r.chunkCount, 'section', 'sections');
  }

  Widget _readingTile(BuildContext context, NotebookSource r) => LabelledTile(
    label: 'Reading · ${r.kind.label}',
    title: _passage(r)?.$1.label ?? r.title,
    detail: [_readingDetail(r), if (r.pinned) 'Always included'].join(' · '),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: r.pinned ? 'Always included. Tap to stop' : 'Include in every answer',
          icon: Icon(r.pinned ? Icons.push_pin : Icons.push_pin_outlined),
          onPressed: () => store.setPinned(r.id, !r.pinned),
        ),
        IconButton(
          tooltip: 'Remove reading',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final ok = await confirmAction(
              context,
              'Remove ${r.title}?',
              'It will be removed from this notebook. This cannot be undone.',
              'Remove',
            );
            if (ok) store.removeSource(r.id);
          },
        ),
      ],
    ),
    selected: _isSelected(r),
    onTap: () => _open(context, r),
  );

  Widget _pendingTile(PendingSource p) => ListTile(
    leading: Icon(kindIcon(p.kind)),
    title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 8),
      child: LinearProgressIndicator(semanticsLabel: 'Reading ${p.title}'),
    ),
    trailing: const Text('Reading'),
  );

  Future<void> _add(BuildContext context) async {
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Write a note'),
              subtitle: const Text('On a verse or on its own'),
              onTap: () => Navigator.pop(ctx, _writeNote),
            ),
            for (final (kind, hint) in _kindHints)
              ListTile(
                leading: Icon(kindIcon(kind)),
                title: Text(kind.label),
                subtitle: Text(hint),
                onTap: () => Navigator.pop(ctx, kind),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice is! SourceKind) {
      await showNoteEditor(context, _s, notebookId: notebookId);
      return;
    }
    final requests = await _requestsFor(context, choice);
    if (!context.mounted) return;
    for (final r in requests) {
      unawaited(_ingest(context, r));
    }
  }

  static const _kindHints = [
    (SourceKind.passage, 'Verses in your reading translation'),
    (SourceKind.commentary, 'What the installed commentaries say on a passage'),
    (SourceKind.note, 'A note from another notebook, kept in step as you edit it'),
    (SourceKind.text, 'Anything you copied from elsewhere'),
    (SourceKind.pdf, 'Text from a PDF, with page numbers'),
    (SourceKind.epub, 'Text from an EPUB book'),
  ];

  Future<List<SourceRequest>> _requestsFor(BuildContext context, SourceKind kind) async {
    switch (kind) {
      case SourceKind.text:
        return [?await _pasteDialog(context)];
      case SourceKind.note:
        return _pickNotes(context);
      case SourceKind.passage:
        final ref = await askReference(context, 'Add a Bible passage');
        if (ref == null || !context.mounted) return const [];
        final r = passageSource(_s.db, ref, _s.settings.translation);
        if (r == null) _say(context, 'Berea could not find "$ref". Try a form like John 3:16-21.');
        return [?r];
      case SourceKind.commentary:
        return _commentary(context);
      case SourceKind.pdf || SourceKind.epub:
        return [?await _pickFile(context, kind)];
    }
  }

  Future<List<SourceRequest>> _commentary(BuildContext context) async {
    final library = _s.commentary.library;
    if (library.isEmpty) {
      _say(context, 'No commentaries are installed. Add them in Settings, under Commentaries.');
      return const [];
    }
    final ref = await askReference(context, 'Add commentary on a passage');
    if (ref == null || !context.mounted) return const [];
    final found = commentarySources(library, ref);
    if (found.isEmpty) _say(context, 'The installed commentaries have nothing on "$ref".');
    return found;
  }

  Future<SourceRequest?> _pasteDialog(BuildContext context) {
    final title = TextEditingController();
    final body = TextEditingController();
    String? error;
    return showDialog<SourceRequest>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Paste text'),
          content: SizedBox(
            width: _pasteDialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(hintText: 'Title (optional)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: body,
                  autofocus: true,
                  minLines: 6,
                  maxLines: 14,
                  onChanged: (_) => setDialogState(() => error = null),
                  decoration: InputDecoration(
                    hintText: 'Paste or type the text here',
                    errorText: error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final text = body.text.trim();
                if (text.isEmpty) {
                  setDialogState(() => error = 'Paste some text first.');
                  return;
                }
                final name = title.text.trim();
                Navigator.pop(
                  ctx,
                  SourceRequest(
                    SourceKind.text,
                    name.isEmpty ? firstWords(text) : name,
                    text: text,
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<SourceRequest>> _pickNotes(BuildContext context) async {
    final notes = [
      for (final (n, nb) in allNotes(_s.study, store))
        if (nb.id != notebookId && n.text.trim().isNotEmpty) n,
    ];
    if (notes.isEmpty) {
      _say(context, 'Other notebooks have no notes yet.');
      return const [];
    }
    final chosen = await showDialog<List<Note>>(
      context: context,
      builder: (ctx) => _NotePicker(notes: notes),
    );
    return [for (final n in chosen ?? const <Note>[]) noteSource(n)];
  }

  Future<SourceRequest?> _pickFile(BuildContext context, SourceKind kind) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [kind == SourceKind.pdf ? 'pdf' : 'epub'],
    );
    if (picked.isEmpty || !context.mounted) return null;
    final file = picked.single;
    if (file.path == null) {
      _say(context, 'That file is not on this device.');
      return null;
    }
    return SourceRequest(kind, file.name, origin: file.name, path: file.path);
  }

  Future<void> _ingest(BuildContext context, SourceRequest r) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await store.addSource(notebookId, r);
      if (id != null) messenger.showSnackBar(SnackBar(content: Text('Added ${r.title}.')));
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${r.title}: ${e.message}')));
    } catch (e) {
      debugPrint('Notebook source failed: $e');
      messenger.showSnackBar(SnackBar(content: Text('${r.title} could not be read.')));
    } finally {
      if (r.path case final path?) unawaited(_deletePickedCopy(path));
    }
  }

  /// The picker copies files into a temporary folder on phones; delete only such a copy.
  static Future<void> _deletePickedCopy(String path) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    // iOS copies into NSTemporaryDirectory (systemTemp); Android into the cache directory.
    final roots = [
      Directory.systemTemp.absolute.path,
      (await getTemporaryDirectory()).absolute.path,
    ];
    final file = File(path).absolute;
    if (!roots.any((r) => file.path.startsWith('$r/')) || !file.existsSync()) return;
    file.deleteSync();
  }
}

/// Beside the list on a wide screen until an entry is chosen: what asking about it draws on.
class _AskPanel extends StatelessWidget {
  const _AskPanel();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(_detailPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: _askIconSize, color: scheme.primary),
            const SizedBox(height: 12),
            Text('Ask about this notebook', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              "Answers draw on this notebook's notes and readings, and on Scripture. Pin a "
              'reading to include it in every answer. Choose a note or reading to see it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotePicker extends StatefulWidget {
  final List<Note> notes;
  const _NotePicker({required this.notes});

  @override
  State<_NotePicker> createState() => _NotePickerState();
}

class _NotePickerState extends State<_NotePicker> {
  final _chosen = <int>{};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add your notes'),
    content: SizedBox(
      width: _notePickerWidth,
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final n in widget.notes)
            CheckboxListTile(
              value: _chosen.contains(n.id),
              onChanged: (on) =>
                  setState(() => on == true ? _chosen.add(n.id) : _chosen.remove(n.id)),
              title: Text(noteHeading(n)),
              subtitle: Text(n.text, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: _chosen.isEmpty
            ? null
            : () => Navigator.pop(context, [
                for (final n in widget.notes)
                  if (_chosen.contains(n.id)) n,
              ]),
        child: Text(_chosen.length > 1 ? 'Add ${_chosen.length}' : 'Add'),
      ),
    ],
  );
}

/// A source's text as Berea stored it, section by section, with PDF page numbers.
class SourceScreen extends StatelessWidget {
  final NotebookStore store;
  final NotebookSource source;

  /// The section to open at and mark, where an answer cited it; null opens at the start.
  final int? focusOrdinal;

  /// Shown beside a list rather than as a page of its own, so it has no way back.
  final bool embedded;
  const SourceScreen({
    super.key,
    required this.store,
    required this.source,
    this.focusOrdinal,
    this.embedded = false,
  });

  static const _focusKey = ValueKey('focus');

  @override
  Widget build(BuildContext context) {
    final chunks = store.sourceChunks(source.id);
    final at = chunks.indexWhere((c) => c.ordinal == focusOrdinal);
    final focus = at < 0 ? 0 : at;
    Widget item(int i) => _SectionView(
      chunk: chunks[i],
      showPage:
          chunks[i].page != null && (i == focus || i == 0 || chunks[i - 1].page != chunks[i].page),
      marked: at >= 0 && i == focus,
    );
    // The cited section is the scroll origin, so a section deep in a long book opens at once and
    // the sections before it build lazily as the reader scrolls up.
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !embedded,
        title: Text(source.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: CustomScrollView(
            center: _focusKey,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => item(focus - 1 - i),
                    childCount: focus,
                  ),
                ),
              ),
              SliverPadding(
                key: _focusKey,
                padding: EdgeInsets.fromLTRB(20, focus == 0 ? 12 : 0, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => item(focus + i),
                    childCount: chunks.length - focus,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionView extends StatelessWidget {
  final NotebookChunk chunk;
  final bool showPage;

  /// The section an answer cited.
  final bool marked;
  const _SectionView({required this.chunk, required this.showPage, required this.marked});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = SelectableText(chunk.text, style: const TextStyle(height: 1.5));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPage)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              'PAGE ${chunk.page}',
              style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: scheme.primary),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: marked
              ? Container(
                  key: const ValueKey('cited-section'),
                  padding: const EdgeInsets.all(_citedPadding),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    border: Border(
                      left: BorderSide(color: scheme.primary, width: _citedMarkWidth),
                    ),
                  ),
                  child: text,
                )
              : text,
        ),
      ],
    );
  }
}
