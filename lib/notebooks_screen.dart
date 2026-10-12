import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'notebook_store.dart';
import 'study_store.dart';
import 'theme.dart';

/// What the add-source flows read from the rest of the app, so these screens need no AppState.
class SourceLookup {
  final List<Note> Function() notes;

  /// The passage for a typed reference in the reader's translation, or null.
  final SourceRequest? Function(String reference) passage;

  /// One source per installed commentary that covers a typed reference.
  final List<SourceRequest> Function(String reference) commentary;
  final bool Function() hasCommentary;
  const SourceLookup({
    required this.notes,
    required this.passage,
    required this.commentary,
    required this.hasCommentary,
  });
}

/// Opens the conversation of notebook [notebookId].
typedef OpenNotebookChat = void Function(BuildContext context, int notebookId);

/// Wide enough for a paragraph of pasted text without filling a desktop window.
const _pasteDialogWidth = 520.0;
const _notePickerWidth = 480.0;
const _citedMarkWidth = 3.0;
const _citedPadding = 12.0;

IconData kindIcon(SourceKind k) => switch (k) {
  SourceKind.text => Icons.notes,
  SourceKind.note => Icons.sticky_note_2_outlined,
  SourceKind.passage => Icons.menu_book_outlined,
  SourceKind.commentary => Icons.history_edu_outlined,
  SourceKind.pdf => Icons.picture_as_pdf_outlined,
  SourceKind.epub => Icons.auto_stories_outlined,
};

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

void _say(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

/// Asks for a name; null when cancelled.
Future<String?> _askName(BuildContext context, {required String title, String initial = ''}) {
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

Future<bool> _confirm(BuildContext context, String title, String body, String action) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    ) ==
    true;

Future<void> _createNotebook(
  BuildContext context,
  NotebookStore store,
  SourceLookup lookup,
  OpenNotebookChat? onChat,
) async {
  final name = await _askName(context, title: 'New notebook');
  if (name == null || !context.mounted) return;
  try {
    final id = store.createNotebook(name);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            NotebookScreen(store: store, lookup: lookup, notebookId: id, onChat: onChat),
      ),
    );
  } on FormatException catch (e) {
    if (context.mounted) _say(context, e.message);
  }
}

/// Every notebook, newest first, with a clear way to start one.
class NotebooksScreen extends StatelessWidget {
  final NotebookStore store;

  final SourceLookup lookup;

  /// Null hides the way into a notebook's conversation, as in tests without an engine.
  final OpenNotebookChat? onChat;
  const NotebooksScreen({super.key, required this.store, required this.lookup, this.onChat});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notebooks',
          style: TextStyle(fontFamilyFallback: scriptureFontFallback, fontSize: 24),
        ),
        actions: [
          IconButton(
            tooltip: 'New notebook',
            icon: const Icon(Icons.add),
            onPressed: () => _createNotebook(context, store, lookup, onChat),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final notebooks = store.notebooks();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: contentMaxWidth),
              child: notebooks.isEmpty ? _emptyState(context) : _list(context, notebooks),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context) => _EmptyState(
    icon: Icons.collections_bookmark_outlined,
    title: 'No notebooks yet',
    body:
        'A notebook gathers what you read on one passage or topic: Bible passages, commentary, '
        'your notes, pasted text, PDFs and EPUB books. Everything stays on this device.',
    action: 'Create a notebook',
    onAction: () => _createNotebook(context, store, lookup, onChat),
  );

  Widget _list(BuildContext context, List<Notebook> notebooks) => ListView(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
    children: [
      for (final n in notebooks)
        ListTile(
          leading: const Icon(Icons.collections_bookmark_outlined),
          title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${_plural(n.sourceCount, 'source', 'sources')} · ${_date(n.updated)}'),
          trailing: _NotebookMenu(store: store, notebook: n),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  NotebookScreen(store: store, lookup: lookup, notebookId: n.id, onChat: onChat),
            ),
          ),
        ),
    ],
  );
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
        final name = await _askName(context, title: 'Rename notebook', initial: notebook.title);
        if (name == null || !context.mounted) return;
        try {
          store.renameNotebook(notebook.id, name);
        } on FormatException catch (e) {
          _say(context, e.message);
        }
      case _NotebookAction.delete:
        final ok = await _confirm(
          context,
          'Delete ${notebook.title}?',
          'Its ${_plural(notebook.sourceCount, 'source', 'sources')} will be removed from this '
              'device. Your notes, studies and highlights are not touched. This cannot be undone.',
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
  final String action;
  final VoidCallback onAction;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
  });

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
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: onAction, icon: const Icon(Icons.add), label: Text(action)),
        ],
      ),
    );
  }
}

/// One notebook: its sources, any being read, and the ways to add more.
class NotebookScreen extends StatelessWidget {
  final NotebookStore store;
  final SourceLookup lookup;
  final int notebookId;
  final OpenNotebookChat? onChat;
  const NotebookScreen({
    super.key,
    required this.store,
    required this.lookup,
    required this.notebookId,
    this.onChat,
  });

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
      final sources = store.sources(notebookId);
      final pending = store.pendingFor(notebookId);
      return Scaffold(
        appBar: AppBar(
          title: Text(notebook.title),
          actions: [
            if (onChat != null)
              IconButton(
                tooltip: 'Ask about this notebook',
                icon: const Icon(Icons.forum_outlined),
                onPressed: () => onChat!(context, notebookId),
              ),
            _NotebookMenu(
              store: store,
              notebook: notebook,
              onDeleted: () => Navigator.maybePop(context),
            ),
          ],
        ),
        floatingActionButton: sources.isEmpty && pending.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _addSource(context),
                icon: const Icon(Icons.add),
                label: const Text('Add source'),
              ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: contentMaxWidth),
            child: sources.isEmpty && pending.isEmpty
                ? _EmptyState(
                    icon: Icons.library_add_outlined,
                    title: 'Add your first source',
                    body:
                        'Bring in a Bible passage, commentary on it, your notes, pasted text, '
                        'a PDF or an EPUB book. Berea reads it on this device and keeps it here.',
                    action: 'Add a source',
                    onAction: () => _addSource(context),
                  )
                : _sourceList(context, sources, pending),
          ),
        ),
      );
    },
  );

  Widget _sourceList(
    BuildContext context,
    List<NotebookSource> sources,
    List<PendingSource> pending,
  ) => ListView(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
    children: [
      if (onChat != null && sources.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () => onChat!(context, notebookId),
              icon: const Icon(Icons.forum_outlined),
              label: const Text('Ask about these sources'),
            ),
          ),
        ),
      for (final s in sources)
        ListTile(
          leading: Icon(kindIcon(s.kind)),
          title: Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${s.kind.label} · ${_plural(s.chunkCount, 'section', 'sections')}'
            '${s.pinned ? ' · Pinned' : ''}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: s.pinned ? 'Unpin' : 'Pin to every answer',
                icon: Icon(s.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                onPressed: () => store.setPinned(s.id, !s.pinned),
              ),
              IconButton(
                tooltip: 'Remove source',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await _confirm(
                    context,
                    'Remove ${s.title}?',
                    'It will be removed from this notebook. This cannot be undone.',
                    'Remove',
                  );
                  if (ok) store.removeSource(s.id);
                },
              ),
            ],
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => SourceScreen(store: store, source: s),
            ),
          ),
        ),
      for (final p in pending)
        ListTile(
          leading: Icon(kindIcon(p.kind)),
          title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(semanticsLabel: 'Reading ${p.title}'),
          ),
          trailing: const Text('Reading'),
        ),
    ],
  );

  Future<void> _addSource(BuildContext context) async {
    final kind = await showModalBottomSheet<SourceKind>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
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
    if (kind == null || !context.mounted) return;
    final requests = await _requestsFor(context, kind);
    if (!context.mounted) return;
    for (final r in requests) {
      unawaited(_ingest(context, r));
    }
  }

  static const _kindHints = [
    (SourceKind.passage, 'Verses in your reading translation'),
    (SourceKind.commentary, 'What the installed commentaries say on a passage'),
    (SourceKind.note, 'Notes you wrote in the Bible tab'),
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
        final ref = await _askReference(context, 'Add a Bible passage');
        if (ref == null || !context.mounted) return const [];
        final r = lookup.passage(ref);
        if (r == null) _say(context, 'Berea could not find "$ref". Try a form like John 3:16-21.');
        return [?r];
      case SourceKind.commentary:
        return _commentary(context);
      case SourceKind.pdf || SourceKind.epub:
        return [?await _pickFile(context, kind)];
    }
  }

  Future<List<SourceRequest>> _commentary(BuildContext context) async {
    if (!lookup.hasCommentary()) {
      _say(context, 'No commentaries are installed. Add them in Settings, under Commentaries.');
      return const [];
    }
    final ref = await _askReference(context, 'Add commentary on a passage');
    if (ref == null || !context.mounted) return const [];
    final found = lookup.commentary(ref);
    if (found.isEmpty) _say(context, 'The installed commentaries have nothing on "$ref".');
    return found;
  }

  Future<String?> _askReference(BuildContext context, String title) {
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
                    name.isEmpty ? _firstWords(text) : name,
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

  static const _titleWords = 8;

  static String _firstWords(String text) {
    final words = text.split(RegExp(r'\s+'));
    final head = words.take(_titleWords).join(' ');
    return words.length > _titleWords ? '$head…' : head;
  }

  Future<List<SourceRequest>> _pickNotes(BuildContext context) async {
    final notes = lookup.notes();
    if (notes.isEmpty) {
      _say(context, 'You have no notes yet. Select a verse in the Bible tab and tap Note.');
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
              title: Text(n.ref.label),
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
  const SourceScreen({super.key, required this.store, required this.source, this.focusOrdinal});

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
      appBar: AppBar(title: Text(source.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
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
