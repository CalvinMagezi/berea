import 'dart:async';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'brand/prayer_icon.dart';
import 'keep_sheet.dart';
import 'notebooks_screen.dart';
import 'prayer_screen.dart';
import 'settings_sheet.dart';
import 'study_store.dart';
import 'theme.dart';
import 'voice.dart';
import 'voice_composer.dart';

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _shortName = 3;
const _previewLines = 4;
const _bodyMinLines = 8;
const _titleSize = 26.0;

/// "Sunday 26 October", or "Sun 26 Oct" when [short].
String noteDate(DateTime d, {bool short = false}) {
  String cut(String s) => short ? s.substring(0, _shortName) : s;
  return '${cut(_weekdays[d.weekday - 1])} ${d.day} ${cut(_months[d.month - 1])}';
}

/// Shows the Bible references typed in the text as links while it is edited.
class RefLinkController extends TextEditingController {
  /// Set from the theme as the editor builds.
  Color linkColor = BereaColors.gold;
  RefLinkController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final matches = RefParser.matches(text);
    if (matches.isEmpty) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final link = TextStyle(
      color: linkColor,
      decoration: TextDecoration.underline,
      decorationColor: linkColor,
    );
    var at = 0;
    final spans = <TextSpan>[];
    for (final m in matches) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      spans.add(TextSpan(text: text.substring(m.start, m.end), style: link));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: spans);
  }
}

/// Dictation transcribes with the on-device model, so the editor's microphone shows only when
/// that model is loaded and hears audio; with Ollama or no model it is hidden.
bool canDictate(AppState s) =>
    voiceSupport(s.settings, s.deviceState, hearsAudio: s.deviceHearsAudio) == VoiceSupport.ready;

/// [value] with [heard] put in at the cursor, or at the end when there is none.
TextEditingValue withDictation(TextEditingValue value, String heard) {
  final text = value.text;
  final at = value.selection.isValid ? value.selection.start : text.length;
  final before = text.substring(0, at);
  final gap = before.isEmpty || before.endsWith(' ') || before.endsWith('\n') ? '' : ' ';
  return TextEditingValue(
    text: '$before$gap$heard${text.substring(at)}',
    selection: TextSelection.collapsed(offset: at + gap.length + heard.length),
  );
}

/// Opens the note editor on [ref], editing [note] when given. Kept for the reader's Note action.
Future<void> showNoteDialog(BuildContext context, AppState s, {Ref? ref, Note? note}) =>
    showNoteEditor(context, s, note: note, verse: ref);

/// The full-screen note editor: a new note, on [verse] or in [notebookId] when given, or [note].
Future<void> showNoteEditor(
  BuildContext context,
  AppState s, {
  Note? note,
  Ref? verse,
  int? notebookId,
}) => Navigator.of(context, rootNavigator: true).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => NoteEditor(state: s, note: note, verse: verse, notebookId: notebookId),
  ),
);

class NoteEditor extends StatefulWidget {
  final AppState state;
  final Note? note;
  final Ref? verse;
  final int? notebookId;

  /// Whether the microphone shows; tests stand in for a loaded device model.
  final bool Function(AppState) dictates;
  const NoteEditor({
    super.key,
    required this.state,
    this.note,
    this.verse,
    this.notebookId,
    this.dictates = canDictate,
  });

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

/// The New notebook item of the notebook menu.
const _newNotebook = -2;

class _NoteEditorState extends State<NoteEditor> {
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final _body = RefLinkController(text: widget.note?.text ?? '')
    ..addListener(() => setState(() {}));
  late Ref? _verse = widget.note?.verse ?? widget.verse;
  late int _notebook = _initialNotebook();
  var _dirty = false;
  late final VoiceInput _voice = widget.state.voice;
  var _voicePhase = VoicePhase.idle;

  AppState get _s => widget.state;

  @override
  void initState() {
    super.initState();
    _voice.addListener(_onVoice);
  }

  /// A finished dictation goes in at the cursor, for the writer to check like anything typed.
  void _onVoice() {
    if (_voice.phase == _voicePhase) return;
    _voicePhase = _voice.phase;
    if (_voice.phase != VoicePhase.confirm || !_voice.ownedBy(this)) return;
    final heard = _voice.transcript.trim();
    _voice.accept();
    if (heard.isEmpty) return;
    _body.value = withDictation(_body.value, heard);
    _changed();
  }

  int _initialNotebook() {
    if (widget.note?.notebookId ?? widget.notebookId case final id?) return id;
    final notebooks = _s.notebooks.notebooks();
    if (_verse != null) {
      return notebooks.where((n) => n.title == notesOnVersesTitle).firstOrNull?.id ??
          notesOnVersesChoice;
    }
    return notebooks.firstOrNull?.id ?? notesOnVersesChoice;
  }

  @override
  void dispose() {
    _voice.removeListener(_onVoice);
    unawaited(_voice.release(this));
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _changed() => _dirty = true;

  void _save() {
    final text = _body.text.trim();
    final title = _title.text.trim();
    if (text.isEmpty && title.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final notebook = chosenNotebook(_s.study, _notebook);
    final note = widget.note;
    if (note == null) {
      _s.study.addNotebookNote(notebook, text, verse: _verse, title: title);
    } else {
      _s.study.saveNote(note.id, notebookId: notebook, text: text, title: title, verse: _verse);
    }
    _s.touch();
    _dirty = false;
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final note = widget.note;
    if (note == null) return;
    final ok = await confirmAction(
      context,
      'Delete this note?',
      'It will be removed from this device. A notebook that reads it keeps a copy.',
      'Delete',
    );
    if (!ok || !mounted) return;
    _s.study.deleteNote(note.id);
    _s.touch();
    _dirty = false;
    Navigator.pop(context);
  }

  Future<void> _pickNotebook(int value) async {
    if (value != _newNotebook) {
      setState(() => _notebook = value);
      _changed();
      return;
    }
    final name = await askNotebookName(context, title: 'New notebook');
    if (name == null || !mounted) return;
    try {
      final id = _s.notebooks.createNotebook(name);
      setState(() => _notebook = id);
      _changed();
    } on FormatException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _addVerse() async {
    final typed = await askReference(context, 'Add a verse');
    if (typed == null || !mounted) return;
    final ref = RefParser.parse(typed).firstOrNull;
    if (ref == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Berea could not find "$typed". Try a form like John 3:16.')),
      );
      return;
    }
    setState(() => _verse = ref);
    _changed();
  }

  /// Opens the new prayer sheet with the note's verse; a chapter alone is not a prayer's verse.
  Future<void> _prayThis() {
    final verse = _verse;
    return showPrayerSheet(
      context,
      _s.prayers,
      verse: verse?.verseStart == null ? null : verse!.label,
      passage: passageLookupFor(_s.db, () => _s.settings.translation),
    );
  }

  /// The reference under the cursor, else the first one typed, else the note's verse.
  Ref? get _previewRef {
    final matches = RefParser.matches(_body.text);
    final at = _body.selection.baseOffset;
    final under = matches.where((m) => m.start <= at && at <= m.end).firstOrNull;
    return (under ?? matches.firstOrNull)?.ref ?? _verse;
  }

  void _open(Ref ref) {
    Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
    _s.openInReader(ref);
  }

  Future<void> _close() async {
    if (_unsaved) {
      final discard = await confirmAction(
        context,
        'Discard this note?',
        'What you wrote here has not been saved.',
        'Discard',
      );
      if (!discard || !mounted) return;
    }
    _dirty = false;
    Navigator.pop(context);
  }

  bool get _unsaved => _dirty || _body.text.trim() != (widget.note?.text ?? '').trim();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = _previewRef;
    _body.linkColor = scheme.primary;
    return PopScope(
      canPop: !_unsaved,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: _close,
          ),
          actions: [
            if (widget.note != null)
              IconButton(
                tooltip: 'Delete note',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
            TextButton(onPressed: _save, child: const Text('Done')),
            const SizedBox(width: 8),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VoiceStatusLine(_voice, owner: this),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _addVerse,
                      icon: const Icon(Icons.menu_book_outlined),
                      label: Text(_verse == null ? 'Add a verse' : 'Change the verse'),
                    ),
                    TextButton.icon(
                      onPressed: _prayThis,
                      icon: const PrayerIcon(),
                      label: const Text('Pray this'),
                    ),
                    const Spacer(),
                    ListenableBuilder(
                      listenable: _s,
                      builder: (context, _) => widget.dictates(_s)
                          ? VoiceMicButton(
                              voice: _voice,
                              owner: this,
                              support: VoiceSupport.ready,
                              modelFree: _s.ready,
                              onOpenSettings: () => showSettingsSheet(context, _s),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: contentMaxWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Align(alignment: Alignment.centerLeft, child: _notebookMenu(scheme)),
                const SizedBox(height: 8),
                TextField(
                  controller: _title,
                  onChanged: (_) => _changed(),
                  style: TextStyle(
                    fontFamilyFallback: scriptureFontFallback,
                    fontSize: _titleSize,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    filled: false,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                Text(
                  noteDate(widget.note?.updated ?? DateTime.now()),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
                if (_verse case final v?) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      avatar: const Icon(Icons.menu_book_outlined),
                      label: Text('On ${v.label}'),
                      onDeleted: () => setState(() {
                        _verse = null;
                        _changed();
                      }),
                      deleteButtonTooltipMessage: 'Take the note off ${v.label}',
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: _body,
                  autofocus: widget.note == null,
                  minLines: _bodyMinLines,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontSize: 17, height: 1.5),
                  decoration: const InputDecoration(
                    hintText: 'Write your note. Verses you type, such as Romans 8:28, become links.',
                    filled: false,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (preview != null) ...[
                  const SizedBox(height: 12),
                  _VersePreview(state: _s, ref: preview, onOpen: () => _open(preview)),
                ],
                const SizedBox(height: 12),
                Text(
                  'A note can stand on its own or sit on a verse. Berea can quote it when you '
                  'ask about this notebook.',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _notebookMenu(ColorScheme scheme) {
    final notebooks = _s.notebooks.notebooks();
    final name = _notebook == notesOnVersesChoice
        ? notesOnVersesTitle
        : notebooks.where((n) => n.id == _notebook).firstOrNull?.title ?? notesOnVersesTitle;
    return PopupMenuButton<int>(
      tooltip: 'Choose a notebook',
      onSelected: _pickNotebook,
      itemBuilder: (_) => [
        for (final n in notebooks) PopupMenuItem(value: n.id, child: Text(n.title)),
        if (!notebooks.any((n) => n.title == notesOnVersesTitle))
          const PopupMenuItem(value: notesOnVersesChoice, child: Text(notesOnVersesTitle)),
        const PopupMenuItem(value: _newNotebook, child: Text('New notebook')),
      ],
      child: Chip(
        avatar: const Icon(Icons.class_outlined),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                text: 'In ',
                children: [
                  TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }
}

/// The verse a reference in the note points to, in the reading translation; tap to open it.
class _VersePreview extends StatelessWidget {
  final AppState state;
  final Ref ref;
  final VoidCallback onOpen;
  const _VersePreview({required this.state, required this.ref, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final verses = state.db.passage(ref, translation: state.settings.translation);
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.menu_book_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(ref.label)),
                  Text(
                    'tap to open',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
              if (verses.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  verses.map((v) => v.text).join(' '),
                  maxLines: _previewLines,
                  overflow: TextOverflow.ellipsis,
                  style: scriptureStyle(context).copyWith(
                    fontStyle: FontStyle.italic,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
