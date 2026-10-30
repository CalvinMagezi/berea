import 'package:berea_harness/berea_harness.dart';

import 'app_state.dart';
import 'keep_sheet.dart';
import 'notebook_store.dart';
import 'study_store.dart';

/// The notebook a section becomes, such as "Taming the Tongue (James 3:1-12)".
String sectionNotebookTitle(String heading, Ref ref) => '$heading (${ref.label})';

/// Makes notebook for the section [heading] covering [ref], ready to study: the passage, what each
/// installed commentary says on it, and its key words kept as word studies. A notebook made for
/// the same section before is opened instead, so a second tap never makes a copy; it gains the
/// commentaries installed since.
Future<int> makeSectionNotebook(AppState s, Ref ref, String heading) async {
  final title = sectionNotebookTitle(heading, ref);
  for (final n in s.notebooks.notebooks()) {
    if (n.title != title) continue;
    await _addCommentary(s, n.id, ref);
    return n.id;
  }
  final passage = passageSource(s.db, ref.label, s.settings.translation);
  if (passage == null) throw ReaderMessage('${ref.label} is not in ${s.settings.translation}.');
  final id = s.notebooks.createNotebook(title);
  await s.notebooks.addSource(id, passage);
  await _addCommentary(s, id, ref);
  for (final k in s.studyPacket(id).keyWords) {
    final e = k.entry;
    final code = strongsBase(e.key);
    s.study.addNotebookNote(
      id,
      keptWordBody(
        code: code,
        meaning: _plainMeaning(e),
        translit: e.translit,
        language: languageOf(code),
        from: k.firstUse,
        translation: packetTranslation,
      ),
      verse: k.firstUse,
      title: e.gloss.isEmpty ? e.lemma : '${e.lemma}, ${e.gloss}',
      kind: studyWordKind,
    );
  }
  s.touch();
  return id;
}

/// Adds each installed commentary on [ref] that notebook [id] does not hold yet.
Future<void> _addCommentary(AppState s, int id, Ref ref) async {
  final held = {
    for (final r in s.notebooks.sources(id)) r.title,
    for (final p in s.notebooks.pendingFor(id)) p.title,
  };
  for (final c in commentarySources(s.commentary.library, ref.label)) {
    if (!held.contains(c.title)) await s.notebooks.addSource(id, c);
  }
}

/// What a kept word says it means: the gloss and its senses in plain words, as the word study
/// shows them, not the lexicon's abbreviations.
String _plainMeaning(LexEntry e) {
  final senses = plainSenses(e.definition);
  if (senses.isEmpty) return e.gloss;
  return senses.join('; ');
}
