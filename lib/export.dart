import 'dart:convert';
import 'dart:typed_data';

import 'package:berea_harness/berea_harness.dart';
import 'package:file_picker/file_picker.dart';

import 'plans.dart';
import 'prayer_plan_store.dart';
import 'prayer_store.dart';
import 'provenance.dart';
import 'study_store.dart';

/// Every note, notebook by notebook, and the prayers as one Markdown document.
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
  final label = provenanceLabel(n.provenance);
  final provenance = label == null ? '' : '_${label}_\n\n';
  return '### ${heading.isEmpty ? 'Note' : heading}\n\n$quote$provenance${n.text}\n';
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
