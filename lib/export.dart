import 'dart:convert';
import 'dart:typed_data';

import 'package:berea_harness/berea_harness.dart';
import 'package:file_picker/file_picker.dart';

import 'study_store.dart';

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One saved study as Markdown, with the verified passages it cited.
String studyMarkdown(StudyStore store, BibleDb db, int conversationId, String translation) {
  final c = store.conversations().firstWhere((c) => c.id == conversationId);
  final b = StringBuffer('# ${c.title}\n\n_Berea study, ${_date(c.updated)}_\n\n');
  final cited = <Ref>{};
  for (final m in store.messages(conversationId)) {
    if (m.isUser) {
      b.writeln('## ${m.text}\n');
    } else {
      b.writeln('${m.text}\n');
      cited.addAll(m.refs);
    }
  }
  if (cited.isNotEmpty) {
    b.writeln('## Passages ($translation)\n');
    for (final r in cited) {
      final text = db.passage(r, translation: translation).map((v) => v.text).join(' ');
      b.writeln('> **${r.label}** $text\n');
    }
  }
  return b.toString();
}

/// Every note and saved study as one Markdown document.
String allNotesMarkdown(StudyStore store, BibleDb db, String translation) {
  final b = StringBuffer('# Berea notes\n\n');
  final notes = store.notes();
  if (notes.isNotEmpty) b.writeln('## Notes\n');
  for (final n in notes) {
    final text = db.passage(n.ref, translation: translation).map((v) => v.text).join(' ');
    b.writeln('### ${n.ref.label}\n\n> $text\n\n${n.text}\n');
  }
  for (final c in store.conversations()) {
    b.writeln(studyMarkdown(store, db, c.id, translation).replaceFirst('# ', '## '));
  }
  return b.toString();
}

/// Lets the user choose where the file goes. Nothing is uploaded.
Future<bool> saveMarkdown(String fileName, String markdown) async {
  final uri = await FilePicker.saveFile(
    fileName: fileName,
    bytes: Uint8List.fromList(utf8.encode(markdown)),
    mimeType: 'text/markdown',
    type: FileType.custom,
    allowedExtensions: ['md'],
  );
  return uri != null;
}
