// A small notebook for the eval, built in code: pasted sermon notes (S1), a Bible passage (S2),
// a three-page PDF-like guide (S3) and a friend's note that misquotes John 3:16 (S4). The people
// and texts are invented for the eval.
import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';

const _sermon =
    'Sermon notes, 4 May. Pastor Ruth Okello preached on Acts 17. Her main point: the Bereans were '
    'noble because they tested every teaching against Scripture, even teaching from an apostle. '
    'She gave three questions to ask of any sermon: Is it in the text? Is it in its context? Does '
    'it point to Christ? She closed by urging the church to read one chapter of a Gospel each '
    'morning before work.';

const _guidePages = [
  'Small Group Guide: Studying Together. Week one. Welcome everyone and agree on a time. The '
      'group meets on Thursday evenings for ninety minutes. Bring a Bible, a notebook and a pen.',
  'Week two: Habits of a Berean. The guide names three habits: receiving the word with '
      'eagerness, examining the Scriptures daily, and comparing every claim with the written '
      'text. Discuss which habit is hardest for you.',
  'Week three: Prayer. Spend the first twenty minutes praying in pairs. The guide suggests '
      'praying through Psalm 23 one verse at a time. Close by sharing one request each.',
];

const _friend =
    'A friend wrote: John 3:16 says, "For God so loved the world that whoever believes in him '
    'will become rich and never be sick." I think that means faith brings wealth.';

/// The fixture notebook in a fresh in-memory database, with the passage read from [bible].
NotebookIndex fixtureNotebook(BibleDb bible) {
  final db = sqlite3.openInMemory()..execute(notebookSchema);
  db.execute("INSERT INTO notebooks(title, created, updated) VALUES ('Bereans', 0, 0)");
  final notebook = db.lastInsertRowId;
  final acts = RefParser.parse('Acts 17:10-12').first;
  final passage = bible.passage(acts).map((v) => '${v.verse} ${v.text}').join('\n');
  _add(db, notebook, SourceKind.text, 'Sermon notes: the noble Bereans', [_sermon]);
  _add(db, notebook, SourceKind.passage, '${acts.label} (BSB)', [
    passage,
  ], origin: '${acts.label}|BSB');
  _add(db, notebook, SourceKind.pdf, 'Small group guide.pdf', _guidePages, paged: true);
  _add(db, notebook, SourceKind.text, 'Note from a friend', [_friend]);
  return NotebookIndex(db, notebook);
}

void _add(
  Database db,
  int notebook,
  SourceKind kind,
  String title,
  List<String> sections, {
  String origin = '',
  bool paged = false,
}) {
  final chunked = chunkSections(sections, paged: paged);
  db.execute(
    'INSERT INTO notebook_sources(notebook_id, kind, title, origin, text, created) '
    'VALUES (?, ?, ?, ?, ?, 0)',
    [notebook, kind.name, title, origin, chunked.text],
  );
  final source = db.lastInsertRowId;
  for (final c in chunked.chunks) {
    db.execute(
      'INSERT INTO notebook_chunks(source_id, ordinal, start_offset, end_offset, page, text) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [source, c.ordinal, c.start, c.end, c.page, c.text],
    );
  }
}
