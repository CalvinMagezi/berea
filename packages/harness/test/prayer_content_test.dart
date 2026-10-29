import 'dart:convert';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:berea_harness/src/prayer_source.dart';
import 'package:test/test.dart';

const contentDir = '../../content/prayers';
const compiledFile = '../../assets/prayers.json';

late final PrayerSource source;
late final PrayerContent content;

/// The topics as the library board draws them: group, then title.
const library = <String, List<String>>{
  'Every day': ['Praise', 'Confession', 'Thanksgiving', 'For others'],
  'Daily life': [
    'Work and daily bread',
    'Looking for work',
    'Business and trade',
    'Farming, rain and harvest',
    'Money and debts',
    'Exams and study',
    'Justice and fairness',
  ],
  'Home and health': [
    'Sickness and healing',
    'Hoping for a child',
    'Raising children',
    'Marriage',
    'Waiting for a spouse',
    'Peace at home',
  ],
  'The heart': ['Fear and worry', 'Grief', 'Guidance', 'New beginnings', 'Protection'],
  'Faith': ['Growing in faith', 'Standing firm against evil'],
};

const planDays = {
  'work-7': 7,
  'exam-5': 5,
  'family-21': 21,
  'psalms-40': 40,
  'paul-7': 7,
  'country-7': 7,
};

/// Matthew to Revelation, Psalms and Proverbs: where chapter prayers are written first.
Iterable<Book> get prayedBooks =>
    books.where((b) => b.id >= 40 || b.name == 'Psalms' || b.name == 'Proverbs');

void main() {
  setUpAll(() {
    source = loadPrayerSource(Directory(contentDir));
    content = source.content;
  });

  test('every line passes the writing rules, and every verse of the day has its line', () {
    final proper = parseProperWords(File('$contentDir/proper-words.txt').readAsStringSync());
    final index = VerseIndex.parse(File('$contentDir/verse-counts.txt').readAsStringSync());
    final daily = File('$contentDir/daily-verses.txt').readAsLinesSync().where((l) => l.isNotEmpty);
    final problems = checkPrayerContent(content, proper, index, dailyList: daily.toList());
    expect(problems, isEmpty, reason: problems.take(30).join('\n'));
  });

  test('the 24 topics are the ones on the library board, in its groups', () {
    final byGroup = <String, List<String>>{};
    for (final t in content.topics) {
      (byGroup[t.group] ??= []).add(t.title);
    }
    expect(byGroup, library);
    for (final t in content.topics) {
      expect(t.points.length, inInclusiveRange(5, 8), reason: t.title);
      expect(t.words, isNotEmpty, reason: t.title);
    }
    final lines = content.topics.fold(0, (n, t) => n + t.points.length);
    expect(lines, inInclusiveRange(150, 190));
  });

  test('ten prayers of the Bible, as references only', () {
    expect(
      [for (final p in content.biblePrayers) p.passage.label],
      [
        'Matthew 6:9-13',
        'Psalms 23',
        'Psalms 51',
        'Psalms 91',
        'Numbers 6:24-26',
        '1 Samuel 2:1-10',
        'Ephesians 1:17-19',
        'Ephesians 3:14-21',
        'Philippians 1:9-11',
        'Colossians 1:9-12',
      ],
    );
  });

  test('every chapter of the New Testament, Psalms and Proverbs has two or three lines', () {
    final index = VerseIndex.parse(File('$contentDir/verse-counts.txt').readAsStringSync());
    var expected = 0;
    for (final b in prayedBooks) {
      final chapters = index.chapters(b);
      for (var c = 1; c <= chapters; c++) {
        expected++;
        final n = content.chapterPoints(Ref(b, c)).length;
        expect(n, inInclusiveRange(2, 3), reason: '${b.name} $c has $n lines');
      }
    }
    expect(expected, 441);
    expect(content.chapters.length, expected);
  });

  test('a verse of the day line for each of the 366 verses', () {
    expect(content.daily.length, 366);
  });

  test('six prayer plans with the days the board promises', () {
    expect({for (final p in content.plans) p.id: p.days.length}, planDays);
    expect([for (final p in content.plans) p.id], planDays.keys.toList());
    for (final p in content.plans) {
      for (final d in p.days) {
        if (p.id == 'psalms-40') {
          expect(d.points, isEmpty, reason: d.title);
          expect(d.passage.book.name, 'Psalms');
          // A passage is prayed word for word, so none may include a verse that calls down harm.
          expect(d.ref, isNot(anyOf("Psalms 3", "Psalms 5", "Psalms 40", "Psalms 63")));
          expect(d.ref, isNot(anyOf('Psalms 139', 'Psalms 143', 'Psalms 149', 'Psalms 86')));
        } else {
          expect(d.points.length, inInclusiveRange(2, 3), reason: '${p.id} ${d.title}');
        }
      }
    }
    expect(content.plan('exam-5')!.fasting, isFalse);
    expect(content.plan('work-7')!.fasting, isTrue);
  });

  test('work-7 day 3 keeps the board\'s two lines', () {
    final day = content.plan('work-7')!.days[2];
    expect(day.title, 'Ask for wisdom');
    expect(day.points[0].text, 'Give me wisdom for the choices in front of me this week.');
    expect(day.points[1].text, 'I commit my plans to You. Make them firm.');
  });

  test('the bundled file is the compiled source, and under 1 MB', () {
    final compiled = compilePrayerContent(content);
    expect(File(compiledFile).readAsStringSync(), compiled, reason: 'run bin/build_prayers.dart');
    expect(compiled.length, lessThan(1000 * 1000));
    final back = PrayerContent.fromJson(
      (File(compiledFile).readAsStringSync().isEmpty ? {} : _decode(compiled)),
    );
    expect(back.topics.length, 24);
  });

  test('topic and plan ids are unique and stable in form', () {
    final ids = [for (final t in content.topics) t.id, for (final p in content.plans) p.id];
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')));
    }
  });
}

Map<String, Object?> _decode(String json) => (jsonDecode(json) as Map).cast();
