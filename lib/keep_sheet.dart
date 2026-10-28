import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'notebook_store.dart';
import 'notebooks_screen.dart';
import 'study_store.dart';
import 'theme.dart';

/// A kept word's body names its Strong's number on a line of its own; this is how Notes tells a
/// kept word from a note, since both are notes.
const keptWordMarker = "Strong's";

final _keptWord = RegExp('^$keptWordMarker [GH]\\d+', multiLine: true);

bool isKeptWord(Note n) => _keptWord.hasMatch(n.text);

/// The notebook something was last kept in, offered first the next time.
const lastKeptNotebookKey = 'lastKeptNotebook';

/// The body of a kept word: what it means, its number and language, and where it was found.
String keptWordBody({
  required String code,
  required String meaning,
  String translit = '',
  String language = '',
  Ref? from,
  String translation = '',
}) => [
  if (meaning.isNotEmpty) meaning,
  [
    '$keptWordMarker $code',
    if (translit.isNotEmpty) translit,
    if (language.isNotEmpty) language,
  ].join(' · '),
  if (from != null) 'From ${from.label}${translation.isEmpty ? '' : ', $translation'}',
].join('\n');

/// Keep in a notebook: files [body] as a note titled [title] in a notebook the reader picks, on
/// [verse] when they leave it beside the verse. Returns the new note's id, or null if cancelled.
/// Word study, commentary and Study answers all keep through here.
Future<int?> showKeepSheet(
  BuildContext context,
  AppState s, {
  required String title,
  required String body,
  Ref? verse,
  String? subtitle,
}) async {
  final id = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => KeepSheet(
      study: s.study,
      notebooks: s.notebooks,
      title: title,
      body: body,
      verse: verse,
      subtitle: subtitle,
      lastUsed: s.prefs.getInt(lastKeptNotebookKey),
    ),
  );
  if (id == null) return null;
  // Read back from the note, so the notes on verses notebook made by this keep counts too.
  if (s.study.note(id)?.notebookId case final nb?) await s.prefs.setInt(lastKeptNotebookKey, nb);
  s.touch();
  return id;
}

class KeepSheet extends StatefulWidget {
  final StudyStore study;
  final NotebookStore notebooks;
  final String title;
  final String body;
  final Ref? verse;
  final String? subtitle;

  /// The notebook last kept in, listed first; ignored when it no longer exists.
  final int? lastUsed;
  const KeepSheet({
    super.key,
    required this.study,
    required this.notebooks,
    required this.title,
    required this.body,
    this.verse,
    this.subtitle,
    this.lastUsed,
  });

  @override
  State<KeepSheet> createState() => _KeepSheetState();
}

/// Stands for the notes on verses notebook before it exists; it is made when something is kept.
const notesOnVersesChoice = -1;

/// The notebook id for a choice that may be [notesOnVersesChoice].
int chosenNotebook(StudyStore study, int choice) =>
    choice == notesOnVersesChoice ? StudyStore.notesOnVersesNotebook(study.db) : choice;

class _KeepSheetState extends State<KeepSheet> {
  late int _chosen = _initial();
  var _beside = true;

  /// The notebook kept for the passage first, then the one last used, then the newest.
  int _initial() {
    final verse = widget.verse;
    final held = verse == null ? null : widget.study.notebookForPassage(verse);
    return held ??
        _lastUsed?.id ??
        widget.notebooks.notebooks().firstOrNull?.id ??
        notesOnVersesChoice;
  }

  Notebook? get _lastUsed =>
      widget.notebooks.notebooks().where((n) => n.id == widget.lastUsed).firstOrNull;

  Future<void> _newNotebook() async {
    final name = await askNotebookName(
      context,
      title: 'New notebook',
      initial: widget.verse?.label ?? '',
    );
    if (name == null || !mounted) return;
    try {
      final id = widget.notebooks.createNotebook(name);
      setState(() => _chosen = id);
    } on FormatException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _keep() {
    final id = widget.study.addNotebookNote(
      chosenNotebook(widget.study, _chosen),
      widget.body,
      title: widget.title,
      verse: _beside ? widget.verse : null,
    );
    Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = _lastUsed;
    final notebooks = [?last, ...widget.notebooks.notebooks().where((n) => n.id != last?.id)];
    final verse = widget.verse;
    final label = TextStyle(fontSize: 12, letterSpacing: 1.2, color: scheme.primary);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Keep ${widget.title}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamilyFallback: scriptureFontFallback, fontSize: 22),
            ),
            if (widget.subtitle case final sub?)
              Text(sub, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 16),
            Text('IN A NOTEBOOK', style: label),
            RadioGroup<int>(
              groupValue: _chosen,
              onChanged: (v) => setState(() => _chosen = v ?? _chosen),
              child: Column(
                children: [
                  for (final n in notebooks)
                    RadioListTile<int>(
                      value: n.id,
                      contentPadding: EdgeInsets.zero,
                      title: Text(n.title),
                      subtitle: Text(n.id == last?.id ? 'Last used · ${_counts(n)}' : _counts(n)),
                    ),
                  if (!notebooks.any((n) => n.title == notesOnVersesTitle))
                    const RadioListTile<int>(
                      value: notesOnVersesChoice,
                      contentPadding: EdgeInsets.zero,
                      title: Text(notesOnVersesTitle),
                      subtitle: Text('Beside the verse in the reader'),
                    ),
                ],
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.add, color: scheme.primary),
              title: Text('New notebook', style: TextStyle(color: scheme.primary)),
              onTap: _newNotebook,
            ),
            if (verse != null) ...[
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _beside,
                onChanged: (v) => setState(() => _beside = v),
                secondary: const Icon(Icons.menu_book_outlined),
                title: Text('Show it beside ${verse.label}'),
                subtitle: const Text("A mark in the reader's margin"),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(onPressed: _keep, child: const Text('Keep')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _counts(Notebook n) {
    final notes = writtenCount(widget.study, n.id);
    return '${plural(notes, 'note', 'notes')} · ${plural(n.sourceCount, 'reading', 'readings')}';
  }
}
