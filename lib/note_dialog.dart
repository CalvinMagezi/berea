import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'study_store.dart';
import 'theme.dart';

/// Create or edit a note on [ref]. Pass [note] to edit.
Future<void> showNoteDialog(BuildContext context, AppState s, {required Ref ref, Note? note}) {
  final controller = TextEditingController(text: note?.text ?? '');
  final verses = s.db.passage(ref, translation: s.settings.translation);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ref.label, style: TextStyle(fontFamilyFallback: scriptureFontFallback)),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (verses.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: SingleChildScrollView(
                  child: Text(
                    verses.map((v) => '${v.verse} ${v.text}').join(' '),
                    style: scriptureStyle(ctx)
                        .copyWith(fontSize: 14, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 4,
              maxLines: 12,
              decoration: const InputDecoration(hintText: 'Your note'),
            ),
          ],
        ),
      ),
      actions: [
        if (note != null)
          TextButton(
            onPressed: () {
              s.study.deleteNote(note.id);
              s.touch();
              Navigator.pop(ctx);
            },
            child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final text = controller.text.trim();
            if (text.isNotEmpty) {
              note == null ? s.study.addNote(ref, text) : s.study.updateNote(note.id, text);
              s.touch();
            }
            Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
