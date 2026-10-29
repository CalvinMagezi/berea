// Compiles content/prayers into assets/prayers.json and fails on any line that breaks the writing
// rules. CI runs it with --check; a release runs it with --release, which also refuses unreviewed
// content. --refresh-indexes rewrites the verse tables from the built Bible, which CI does not have.
// Usage: dart run bin/build_prayers.dart [--check] [--release] [--refresh-indexes]
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:berea_harness/src/prayer_source.dart';

const contentDir = '../../content/prayers';
const compiledFile = '../../assets/prayers.json';
const dbFile = '../../assets/berea.sqlite';
const maxCompiledBytes = 1000 * 1000;

Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  final release = args.contains('--release');
  if (args.contains('--refresh-indexes')) return refreshIndexes();

  final dir = Directory(contentDir);
  final problems = <PrayerProblem>[];
  final source = loadPrayerSource(dir);
  final proper = parseProperWords(File('$contentDir/proper-words.txt').readAsStringSync());
  final index = VerseIndex.parse(File('$contentDir/verse-counts.txt').readAsStringSync());
  final daily = File('$contentDir/daily-verses.txt').readAsLinesSync().where((l) => l.isNotEmpty);
  problems.addAll(checkPrayerContent(source.content, proper, index, dailyList: daily.toList()));

  final compiled = compilePrayerContent(source.content);
  if (compiled.length > maxCompiledBytes) {
    problems.add(PrayerProblem('prayers.json', 'is ${compiled.length} bytes, over the 1 MB limit'));
  }
  if (File(dbFile).existsSync()) problems.addAll(_againstBible(index, daily.toList()));

  if (problems.isNotEmpty) {
    for (final p in problems.take(200)) {
      stderr.writeln(p);
    }
    stderr.writeln('${problems.length} problems in the prayer content.');
    exit(1);
  }
  final out = File(compiledFile);
  if (check) {
    if (!out.existsSync() || out.readAsStringSync() != compiled) {
      stderr.writeln('assets/prayers.json is out of date. Run: dart run bin/build_prayers.dart');
      exit(1);
    }
  } else {
    out.writeAsStringSync(compiled);
  }
  stdout.writeln(
    'prayer content ok: ${source.content.topics.length} topics, '
    '${source.content.chapters.length} chapters, ${source.content.daily.length} daily lines, '
    '${source.content.plans.length} plans, ${compiled.length} bytes',
  );
  if (release && source.unreviewed.isNotEmpty) {
    stderr.writeln('Not reviewed yet (${source.unreviewed.length}):');
    for (final u in source.unreviewed) {
      stderr.writeln('  $u');
    }
    exit(1);
  }
}

/// With a built Bible at hand, the committed tables must still describe it.
List<PrayerProblem> _againstBible(VerseIndex index, List<String> daily) {
  final bible = BibleDb.open(dbFile);
  final out = <PrayerProblem>[];
  for (final b in books) {
    final chapters = bible.chapterCount(b);
    if (chapters != index.chapters(b)) {
      out.add(PrayerProblem('verse-counts.txt', '${b.name} has $chapters chapters in the Bible'));
    }
  }
  final built = _builtDaily(bible);
  if (built.toSet().difference(daily.toSet()).isNotEmpty) {
    out.add(
      const PrayerProblem('daily-verses.txt', 'is behind the Bible\'s verse of the day list'),
    );
  }
  bible.close();
  return out;
}

List<String> _builtDaily(BibleDb bible) => [
  for (final r in bible.db.select('SELECT book, chapter, verse FROM daily_verses ORDER BY day'))
    Ref(bookById(r['book'] as int), r['chapter'] as int, r['verse'] as int).label,
];

void refreshIndexes() {
  final bible = BibleDb.open(dbFile);
  final counts = <String, List<int>>{};
  for (final b in books) {
    counts[b.name] = [
      for (final r in bible.db.select(
        'SELECT MAX(verse) AS n FROM verses WHERE translation = ? AND book = ? GROUP BY chapter '
        'ORDER BY chapter',
        [defaultTranslation, b.id],
      ))
        r['n'] as int,
    ];
  }
  File('$contentDir/verse-counts.txt').writeAsStringSync(VerseIndex.render(counts));
  File('$contentDir/daily-verses.txt').writeAsStringSync('${_builtDaily(bible).join('\n')}\n');
  bible.close();
  stdout.writeln('verse-counts.txt and daily-verses.txt rewritten from the Bible');
}
