import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:test/test.dart';

const contentDir = '../../content/prayers';

late final Set<String> proper;
late final VerseIndex index;

/// Lines from the R10 boards, verbatim: all of them must pass.
const canvasLines = <(String, String)>[
  (
    'Father, give us today our daily bread, and teach me to trust You for tomorrow.',
    'Matthew 6:11',
  ),
  ('Let Your favour rest on me, and establish the work of my hands.', 'Psalm 90:17'),
  ('I commit my work and my plans to You. Bring them to good ends.', 'Proverbs 16:3'),
  ('Help me work with my whole heart, as for You and not only for people.', 'Colossians 3:23'),
  ('Keep my scales honest and my dealings clean, even when no one is checking.', 'Proverbs 11:1'),
  ('Teach me to be content, in a month of plenty and in a month of little.', 'Philippians 4:11-12'),
  ('Make me strong in You and in Your mighty power, not in my own.', 'Ephesians 6:10'),
  ('Clothe me in Your full armour, so that I can stand.', 'Ephesians 6:11'),
  (
    // The board's line has 21 words; a second "my" is dropped to meet the limit.
    'Remind me that my struggle is not against people, not my relatives or neighbours, '
        'but against the powers of darkness.',
    'Ephesians 6:12',
  ),
  ('I submit to You. Help me resist the devil, and he will flee.', 'James 4:7'),
  (
    'Thank You that the One who is in me is greater than the one who is in the world.',
    '1 John 4:4',
  ),
  ('I bring this to You now, instead of carrying it alone.', 'Philippians 4:6'),
  ('Thank You for what You have already done, before I see the answer.', 'Philippians 4:6'),
  ('Guard my heart and my mind with Your peace, the peace I cannot explain.', 'Philippians 4:7'),
  ('Teach me to keep asking, seeking and knocking, and to trust You to answer.', 'Matthew 7:7'),
  ('Lord, if You are willing, touch what I cannot fix.', 'Matthew 8:2-3'),
  ('Lord of the harvest, send out workers into Your harvest, and send me.', 'Matthew 9:38'),
  ('Lord, lift my eyes from what I can see today to what lasts forever.', '2 Corinthians 4:18'),
  ('Give me wisdom for the choices in front of me this week.', 'James 1:5'),
  ('Lord, send rain on our land in its season, the early rains and the late.', 'Deuteronomy 11:14'),
  ('Bless the seed in the ground and the work of our hands.', 'Deuteronomy 28:12'),
  ('Soak the furrows, soften the soil, and crown this year with Your goodness.', 'Psalm 65:10-11'),
  ('Give me patience while the crop grows, like the farmer who waits for the rains.', 'James 5:7'),
  ('Keep me from growing weary of planting and weeding. Let us reap in due time.', 'Galatians 6:9'),
  ('Help me know the state of my animals and care for them well.', 'Proverbs 27:23'),
  ('Thank You that seedtime and harvest will not stop while the earth remains.', 'Genesis 8:22'),
];

void main() {
  setUpAll(() {
    proper = parseProperWords(File('$contentDir/proper-words.txt').readAsStringSync());
    index = VerseIndex.parse(File('$contentDir/verse-counts.txt').readAsStringSync());
  });

  List<PrayerProblem> check(String text, [String ref = 'Psalm 23:1']) =>
      pointProblems('t', PrayerPoint(text, ref), proper, index);

  test('every line on the R10 boards passes', () {
    for (final (text, ref) in canvasLines) {
      expect(check(text, ref), isEmpty, reason: text);
    }
  });

  test('the fasting note passes, and says never water', () {
    expect(lineProblems(prayerFastingNote, proper), isEmpty);
    expect(prayerFastingNote, contains('never water'));
    expect(prayerFastingNote, contains('health worker'));
  });

  test('a line over 20 words fails', () {
    final long = 'Lord ${List.filled(20, 'give').join(' ')} me peace.';
    expect(check(long).single.message, contains('words'));
    expect(check('Lord ${List.filled(19, 'give').join(' ')}.'), isEmpty);
  });

  test('em and en dashes and emoji fail', () {
    expect(check('Lord, hear me — I am here.').single.message, contains('dash'));
    expect(check('Lord, hear me – I am here.').single.message, contains('dash'));
    expect(check('Lord, hear me \u{1F64F}.').single.message, contains('emoji'));
  });

  test('sentence case: names and titles of God are fine, other capitals are not', () {
    expect(lineProblems('Pray For Our Country.', proper), isNotEmpty);
    expect(lineProblems('PRAY for our country.', proper), isNotEmpty);
    expect(lineProblems('pray for our country.', proper), isNotEmpty);
    expect(lineProblems('Thank You, Lord, for Your Word and Your Spirit.', proper), isEmpty);
    expect(lineProblems('7 days for your work', proper), isEmpty);
    expect(lineProblems('Hear me. Then answer me.', proper), isEmpty);
  });

  test('a line may not turn on a relative, a neighbour or a village', () {
    for (final line in [
      'Lord, scatter the enemies in my village.',
      'Let my relatives fall before me.',
      'Curse my neighbours who laughed at me.',
      'Fight against my uncle and defeat him.',
    ]) {
      expect(lineProblems(line, proper).join(), contains('relative'), reason: line);
    }
    expect(lineProblems('Help me forgive my neighbour who wronged me.', proper), isEmpty);
    expect(lineProblems('Bless my relatives and bring us together.', proper), isEmpty);
  });

  test('a line may not tell anyone to stop treatment or ignore a report', () {
    for (final line in [
      'I stop my medicine and trust You to heal me.',
      'I reject the doctor\'s report.',
      'Help me ignore the diagnosis and believe.',
      'I refuse the treatment.',
    ]) {
      expect(lineProblems(line, proper).join(), contains('stop treatment'), reason: line);
    }
    expect(
      lineProblems(
        'Thank You for doctors, nurses and health workers who care for the sick.',
        proper,
      ),
      isEmpty,
    );
    expect(lineProblems('Heal me, and guide the hands of those who treat me.', proper), isEmpty);
  });

  test('a fast is never without water', () {
    expect(lineProblems('Today I fast with no water.', proper).join(), contains('without water'));
    expect(lineProblems('A dry fast for three days.', proper).join(), contains('without water'));
    expect(lineProblems('I fast today.', proper).join(), contains('never water'));
    expect(lineProblems('If you fast, skip food, never water.', proper), isEmpty);
    expect(lineProblems('Thank You for the water in our well.', proper), isEmpty);
    expect(lineProblems('When there is no water, You provide.', proper), isEmpty);
  });

  test('a reference must be one reference that is in the BSB', () {
    expect(check('Lord, hear me.', 'John 3:99').single.message, contains('not in the BSB'));
    expect(check('Lord, hear me.', 'Hezekiah 4:1').single.message, contains('not one reference'));
    expect(check('Lord, hear me.', 'John 3:16 and John 3:17').single.message, contains('not one'));
    expect(check('Lord, hear me.', 'Psalm 23').single.message, contains('needs a verse'));
    expect(check('Lord, hear me.', 'Psalm 151:1').single.message, contains('no such chapter'));
    expect(check('Lord, hear me.', '3 John 1:14'), isEmpty);
    expect(check('Lord, hear me.', '3 John 1:15').single.message, contains('not in the BSB'));
  });

  test('a chapter prayer must stand on a verse of its own chapter', () {
    final matthew7 = Ref(bookById(40), 7);
    expect(
      pointProblems(
        'm',
        const PrayerPoint('Lord, hear me.', 'Matthew 8:2'),
        proper,
        index,
        mustBeIn: matthew7,
      ).single.message,
      contains('outside Matthew 7'),
    );
    expect(
      pointProblems(
        'm',
        const PrayerPoint('Lord, hear me.', 'Matthew 7:7'),
        proper,
        index,
        mustBeIn: matthew7,
      ),
      isEmpty,
    );
  });

  test('the verse of the day list needs a line for every verse', () {
    final content = PrayerContent(daily: {'Isaiah 41:10': 'Lord, hold me up.'});
    final problems = checkPrayerContent(
      content,
      proper,
      index,
      dailyList: ['Isaiah 41:10', 'Romans 8:31'],
    );
    expect(problems.map((p) => p.where), ['daily Romans 8:31']);
  });

  test('content round trips through the compiled JSON', () {
    final content = PrayerContent(
      topics: [
        const PrayerTopic(
          'work',
          'Daily life',
          'Work and daily bread',
          ['job'],
          [PrayerPoint('Lord, hear me.', 'Matthew 6:11')],
        ),
      ],
      chapters: {
        '40.7': [const PrayerPoint('Lord, hear me.', 'Matthew 7:7')],
      },
      daily: {'Isaiah 41:10': 'Lord, hold me up.'},
    );
    final back = PrayerContent.fromJson(content.toJson());
    expect(back.toJson(), content.toJson());
    expect(back.pointsForVerse(Ref(bookById(40), 7, 7)).single.text, 'Lord, hear me.');
    expect(back.pointsForVerse(Ref(bookById(40), 7, 8)), isEmpty);
    expect(back.dailyLine(Ref(bookById(23), 41, 10)), 'Lord, hold me up.');
  });

  test('a canonical label parses the same as a typed reference', () {
    for (final label in [
      'Psalms 37:5',
      'Psalms 23',
      '1 John 4:4-6',
      'Song of Solomon 2:4',
      'Matthew 6:9-13',
      '3 John 1:14',
    ]) {
      expect(parseLabel(label), RefParser.parse(label).first, reason: label);
    }
    expect(parseLabel('Psalm 23:1'), RefParser.parse('Psalm 23:1').first);
  });

  test('topics are found by the words people type', () {
    final content = PrayerContent(
      topics: [
        const PrayerTopic('farm', 'Daily life', 'Farming, rain and harvest', [
          'crops',
          'garden',
        ], []),
        const PrayerTopic('exam', 'Daily life', 'Exams and study', ['school', 'test'], []),
      ],
    );
    expect(content.topicsFor('rain for my crops').map((t) => t.id), ['farm']);
    expect(content.topicsFor('Brian is sitting an exam').map((t) => t.id), ['exam']);
    expect(content.topicsFor('hello'), isEmpty);
  });
}
