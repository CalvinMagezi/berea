import 'package:berea_harness/berea_harness.dart';

import 'app_state.dart';
import 'keep_sheet.dart';
import 'notebook_store.dart';
import 'study_store.dart';

/// The notebook a section becomes, such as "Taming the Tongue (James 3:1-12)".
String sectionNotebookTitle(String heading, Ref ref) => '$heading (${ref.label})';

/// Makes notebook for the section [heading] covering [ref], ready to study: the passage, what each
/// installed commentary says on it, and its key words kept as word studies. A notebook made for
/// the same section before is opened instead, so a second tap never makes a copy.
Future<int> makeSectionNotebook(AppState s, Ref ref, String heading) async {
  final title = sectionNotebookTitle(heading, ref);
  for (final n in s.notebooks.notebooks()) {
    if (n.title == title) return n.id;
  }
  final passage = passageSource(s.db, ref.label, s.settings.translation);
  if (passage == null) throw ReaderMessage('${ref.label} is not in ${s.settings.translation}.');
  final id = s.notebooks.createNotebook(title);
  await s.notebooks.addSource(id, passage);
  for (final c in commentarySources(s.commentary.library, ref.label)) {
    await s.notebooks.addSource(id, c);
  }
  for (final k in s.studyPacket(id).keyWords) {
    final e = k.entry;
    final code = strongsBase(e.key);
    s.study.addNotebookNote(
      id,
      keptWordBody(
        code: code,
        meaning: e.definition.isEmpty ? e.gloss : e.definition,
        translit: e.translit,
        language: languageOf(code),
        from: k.firstUse,
        translation: packetTranslation,
      ),
      verse: k.firstUse,
      title: e.gloss.isEmpty ? e.lemma : '${e.lemma}, ${e.gloss}',
      kind: keptWordKind,
    );
  }
  s.touch();
  return id;
}
