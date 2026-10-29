import 'dart:convert';
import 'dart:typed_data';

import 'package:berea_harness/berea_harness.dart';
import 'package:file_picker/file_picker.dart';

import 'plans.dart';
import 'prayer_plan_store.dart';
import 'prayer_store.dart';
import 'study_store.dart';

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One saved study as Markdown, with the verified passages it cited.
String studyMarkdown(StudyStore store, BibleDb db, int conversationId, String translation) {
  final c = store.conversation(conversationId)!;
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
      final text = db.verses(r, translation: translation).map((v) => v.text).join(' ');
      b.writeln('> **${r.label}** $text\n');
    }
  }
  return b.toString();
}

/// Every note, notebook by notebook, and every saved study as one Markdown document.
String allNotesMarkdown(
  StudyStore store,
  BibleDb db,
  String translation, {
  PrayerContent? content,
}) {
  final b = StringBuffer('# Berea notes\n\n');
  final notebooks = store.db.select('SELECT id, title FROM notebooks ORDER BY id');
  for (final nb in notebooks) {
    final notes = store.notebookNotes(nb['id'] as int);
    if (notes.isEmpty) continue;
    b.writeln('## ${nb['title']}\n');
    for (final n in notes) {
      b.writeln(_noteMarkdown(n, db, translation));
    }
  }
  final studies = [
    ...store.conversations(),
    for (final nb in notebooks) ...store.conversations(notebookId: nb['id'] as int),
  ];
  for (final c in studies) {
    b.writeln(studyMarkdown(store, db, c.id, translation).replaceFirst('# ', '## '));
  }
  if (store.db.select('SELECT 1 FROM prayers LIMIT 1').isNotEmpty) {
    // One level down, so Prayer sits beside the notebooks under the document title.
    final prayers = prayersMarkdown(
      PrayerStore(store.db),
      plans: PrayerPlanStore(store.db),
      planTitles: {
        for (final p in readingPlans) p.id: p.name,
        for (final p in content?.plans ?? const <PrayerPlan>[]) p.id: p.title,
      },
    );
    b.write(prayers.replaceAllMapped(RegExp('^#', multiLine: true), (_) => '##'));
  }
  return b.toString();
}

String _noteMarkdown(Note n, BibleDb db, String translation) {
  final verse = n.verse;
  final heading = [?verse?.label, if (n.title.isNotEmpty) n.title].join(', ');
  final quote = verse == null
      ? ''
      : '> ${db.verses(verse, translation: translation).map((v) => v.text).join(' ')}\n\n';
  return '### ${heading.isEmpty ? 'Note' : heading}\n\n$quote${n.text}\n';
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
