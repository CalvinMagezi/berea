// Retrieval-only check for topical questions: does BM25 put a well-known passage on the topic in
// front of the model? No model needed. Usage: dart run bin/retrieval_check.dart
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';

const _cases = {
  'What does the Bible say about caring for widows?': [
    'James 1:27',
    '1 Timothy 5:3-16',
    'Deuteronomy 10:18',
    'Acts 6:1',
  ],
  'How should a Christian think about humility?': [
    'Philippians 2:3-8',
    'James 4:6-10',
    '1 Peter 5:5-6',
    'Micah 6:8',
    'Proverbs 3:34',
  ],
  'What does Scripture teach about parenting children?': [
    'Ephesians 6:1-4',
    'Proverbs 22:6',
    'Deuteronomy 6:6-7',
    'Colossians 3:20-21',
  ],
  'Is it wrong to be angry?': ['Ephesians 4:26', 'James 1:19-20', 'Proverbs 15:1', 'Matthew 5:22'],
  'What does the Bible say about money and contentment?': [
    '1 Timothy 6:6-10',
    'Hebrews 13:5',
    'Philippians 4:11-12',
    'Matthew 6:24',
  ],
  'What does the Bible say about forgiveness?': [
    'Matthew 6:14-15',
    'Ephesians 4:32',
    'Colossians 3:13',
    'Matthew 18:21-22',
  ],
  'How do I deal with anxiety and worry?': ['Philippians 4:6-7', 'Matthew 6:25-34', '1 Peter 5:7'],
  'What does the Bible teach about pride?': ['Proverbs 16:18', 'James 4:6', 'Proverbs 11:2'],
};

void main(List<String> args) {
  final db = BibleDb.open('../../assets/berea.sqlite');
  final r = Retriever(db);
  var hits = 0;
  for (final e in _cases.entries) {
    final ctx = r.retrieve(e.key, Tier.mid);
    final shown = ctx.allVerses.map((v) => Ref(v.book, v.chapter, v.verse, v.verse)).toList();
    final want = [for (final s in e.value) ...RefParser.parse(s)];
    final found = want.where((w) => shown.any(w.overlaps)).toList();
    if (found.isNotEmpty) hits++;
    stdout.writeln(
      '${found.isEmpty ? 'MISS' : 'ok  '} ${e.key}\n'
      '     found ${found.length}/${want.length}: ${found.join(', ')}\n'
      '     shown: ${ctx.searchHits.map((v) => v.label).join(', ')}',
    );
  }
  stdout.writeln('\n$hits/${_cases.length} topical questions retrieved at least one key passage');
  db.close();
}
