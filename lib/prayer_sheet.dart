import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'prayer_store.dart';
import 'theme.dart';

/// The verses of [ref] in the reader's translation.
typedef PassageLookup = List<Verse> Function(Ref ref);

/// Opens the OS share sheet with plain text, pointing from [origin]. The app itself sends nothing.
typedef ShareText = Future<void> Function(String text, Rect? origin);

Future<void> shareText(String text, Rect? origin) =>
    SharePlus.instance.share(ShareParams(text: text, sharePositionOrigin: origin));

/// The tapped control's rectangle. iPad needs one to anchor the share popover; macOS
/// otherwise opens it from the window's corner.
Rect? shareOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Reads passages from [db] in whatever translation the reader is on when asked.
PassageLookup passageLookupFor(BibleDb db, String Function() translation) =>
    (ref) => db.passage(ref, translation: translation());

String passageText(List<Verse> verses) => verses.map((v) => v.text).join(' ');

const prayerTitleMaxChars = 120;
const prayerForWhomMaxChars = 80;
const _sheetPadding = 20.0;
const _versePreviewLines = 3;

void sayPrayer(BuildContext context, String message, {SnackBarAction? action}) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), action: action));

/// A small label such as "PRAYING · 5" or "ISAIAH 41:10 · BSB".
class PrayerLabel extends StatelessWidget {
  final String text;
  const PrayerLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Theme.of(context).colorScheme.primary, letterSpacing: 1.2),
  );
}

/// A verse reference shown as a small tinted chip.
class VerseChip extends StatelessWidget {
  final String label;
  final VoidCallback? onDeleted;
  const VerseChip(this.label, {super.key, this.onDeleted});

  @override
  Widget build(BuildContext context) => Chip(
    avatar: const Icon(Icons.menu_book_outlined, size: 14),
    label: Text(label),
    labelStyle: Theme.of(context).textTheme.labelMedium,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    onDeleted: onDeleted,
  );
}

/// The new prayer sheet, or the edit sheet when [editing] is given. [verse] prefills the verse,
/// for adding a prayer from a selection in the Bible; [title] prefills what is prayed for, as
/// from a note. Returns the prayer id when saved.
Future<int?> showPrayerSheet(
  BuildContext context,
  PrayerStore store, {
  Prayer? editing,
  String? verse,
  String? title,
  PassageLookup? passage,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) =>
      _PrayerSheet(store: store, editing: editing, verse: verse, title: title, passage: passage),
);

class _PrayerSheet extends StatefulWidget {
  final PrayerStore store;
  final Prayer? editing;
  final String? verse;
  final String? title;
  final PassageLookup? passage;
  const _PrayerSheet({required this.store, this.editing, this.verse, this.title, this.passage});

  @override
  State<_PrayerSheet> createState() => _PrayerSheetState();
}

class _PrayerSheetState extends State<_PrayerSheet> {
  late final _title = TextEditingController(text: widget.editing?.title ?? widget.title);
  late final _forWhom = TextEditingController(text: widget.editing?.forWhom);
  late final _note = TextEditingController(text: widget.editing?.note);
  late final _verse = TextEditingController(text: widget.editing?.verse ?? widget.verse);
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _forWhom, _note, _verse]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final typedVerse = _verse.text.trim();
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Write what you are praying for first.');
      return;
    }
    final ref = RefParser.parse(typedVerse).firstOrNull;
    if (typedVerse.isNotEmpty && ref == null) {
      setState(() => _error = 'That verse was not recognised. Try one like Philippians 4:6-7.');
      return;
    }
    if (ref != null && ref.verseStart == null) {
      setState(() => _error = 'Choose a verse or a few verses, such as Psalm 23:1-4.');
      return;
    }
    final s = widget.store;
    final editing = widget.editing;
    if (editing == null) {
      final id = s.add(
        title: _title.text,
        forWhom: _forWhom.text,
        verse: typedVerse,
        note: _note.text,
      );
      Navigator.pop(context, id);
      return;
    }
    s.edit(
      editing.id,
      title: _title.text,
      forWhom: _forWhom.text,
      verse: typedVerse,
      note: _note.text,
    );
    Navigator.pop(context, editing.id);
  }

  void _stopPraying() {
    widget.store.setArchived(widget.editing!.id, true);
    Navigator.pop(context);
  }

  void _delete() {
    widget.store.delete(widget.editing!.id);
    Navigator.pop(context);
  }

  Widget _versePreview(BuildContext context) {
    final ref = RefParser.parse(_verse.text).firstOrNull;
    final passage = widget.passage;
    if (ref == null || passage == null) return const SizedBox.shrink();
    final text = passageText(passage(ref));
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        maxLines: _versePreviewLines,
        overflow: TextOverflow.ellipsis,
        style: scriptureStyle(context).copyWith(
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _sheetPadding,
        0,
        _sheetPadding,
        _sheetPadding + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              editing == null ? 'New prayer' : 'Edit prayer',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: editing == null,
              maxLength: prayerTitleMaxChars,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What are you praying for?',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _forWhom,
              maxLength: prayerForWhomMaxChars,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'For whom (optional)', counterText: ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _verse,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'A verse to pray (optional)',
                hintText: 'Philippians 4:6-7',
                prefixIcon: Icon(Icons.menu_book_outlined),
              ),
            ),
            _versePreview(context),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'A note (optional)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Prayers stay on this device. Nothing is sent.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (editing != null) ...[
                  TextButton(onPressed: _delete, child: const Text('Delete')),
                  TextButton(onPressed: _stopPraying, child: const Text('Stop praying')),
                ],
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for the person's own line about how a prayer was answered. Null when cancelled; the
/// line may be empty.
Future<String?> askAnswerLine(BuildContext context, Prayer p) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Answered'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.title),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'How was it answered? (optional)'),
          ),
        ],
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

/// Marks [p] answered with the person's line, then offers Undo.
Future<bool> answerPrayer(BuildContext context, PrayerStore store, Prayer p) async {
  final line = await askAnswerLine(context, p);
  if (line == null || !context.mounted) return false;
  store.markAnswered(p.id, line);
  sayPrayer(
    context,
    'Moved to Answered',
    action: SnackBarAction(label: 'Undo', onPressed: () => store.unanswer(p.id)),
  );
  return true;
}

/// Asks for a line to add to a prayer's note. Null when cancelled.
Future<String?> askExtraLine(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add a line'),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 1,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
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
