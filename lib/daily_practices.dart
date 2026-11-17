import 'package:berea_harness/berea_harness.dart';

import 'daily_reminder.dart' show ReminderMessage, reminderDaysAhead, reminderId;

/// The two daily practices Berea carries. Their words are the maintainer's, condensed from
/// his two longer writings (*Building the Inner City of God* and *Three Ways We Fall*). Berea
/// adds only the labels and the order. Scripture is never typed here: a verse is a reference,
/// and its words are read from the translation the person has chosen.
enum Practice {
  /// One stone of the inner city a day, to build a place where God can live.
  building,

  /// Sin, iniquity and transgression, asked of the day that is ending.
  reflection,
}

const _minutesPerHour = 60;

extension PracticeInfo on Practice {
  String get title => switch (this) {
    Practice.building => 'Daily inner building',
    Practice.reflection => 'Daily reflection',
  };

  /// One line under the title, wherever the practice is listed.
  String get blurb => switch (this) {
    Practice.building => 'One stone a day, to build a city where God can live.',
    Practice.reflection => 'Sin, iniquity and transgression: a quiet look at the day.',
  };

  /// The preferences keys, so the two practices keep separate choices.
  String get onKey => switch (this) {
    Practice.building => 'buildingReminderOn',
    Practice.reflection => 'reflectionReminderOn',
  };

  String get minutesKey => switch (this) {
    Practice.building => 'buildingReminderMinutes',
    Practice.reflection => 'reflectionReminderMinutes',
  };

  /// Morning for building; evening for looking back over the day.
  int get defaultMinutes => switch (this) {
    Practice.building => 7 * _minutesPerHour,
    Practice.reflection => 21 * _minutesPerHour,
  };

  /// The times offered in the sheet, in minutes after midnight.
  List<int> get times => switch (this) {
    Practice.building => const [6 * 60, 6 * 60 + 30, 7 * 60, 8 * 60],
    Practice.reflection => const [20 * 60, 21 * 60, 21 * 60 + 30, 22 * 60],
  };

  /// Notification ids start here, so the practices never share one with each other or with the
  /// reading reminder (which uses the date alone, about 20 million).
  int get idBase => switch (this) {
    Practice.building => 1000000000,
    Practice.reflection => 1100000000,
  };
}

/// One stone of the inner city: what it looks like, and the one thing to do today.
class Stone {
  final String name;
  final String picture;
  final String practice;

  /// A line to say quietly, when the stone has one.
  final String? say;
  const Stone(this.name, this.picture, this.practice, {this.say});
}

/// The stones, from the ground up. One is shown each day, round and round: building is not
/// finished, only kept.
const stones = [
  Stone(
    'The Ground',
    'Clearing surface debris and digging down to solid bedrock.',
    'Acknowledge your limitations honestly. Accept correction without defending yourself.',
    say: 'God, You are everything and need nothing; I am dust held in existence by Your love.',
  ),
  Stone(
    'The First Brick',
    'A square cornerstone, set true against a golden measuring reed.',
    'Do what God has commanded and what your own duties ask, before the extra things you chose.',
  ),
  Stone(
    'The Foundation Stones',
    'Twelve precious stones, from jasper to amethyst, holding up the walls.',
    'Grow in courage, inner calm, and pure faith, hope and charity.',
  ),
  Stone(
    'The Jasper Walls',
    'Thick, smooth walls that keep the noise out of the inner rooms.',
    'Limit digital distraction, vanity, and too much attention to the world.',
  ),
  Stone(
    'The Pearl Gates',
    'Gates that open to truth and close to sin.',
    'Pause before looking, listening or speaking, and ask if it serves love.',
    say: 'Does this promote love of God and neighbor, or does it invite anger, vanity, or anxiety?',
  ),
  Stone(
    'The Golden Streets',
    'Clear golden avenues that reflect light and hold no dark corners.',
    'When a good thought comes in prayer, act on it today with a concrete kindness.',
  ),
  Stone(
    'The Central Temple',
    'A radiant Presence living at the heart of the soul.',
    'Stop for a few seconds during the day and adore Christ within.',
    say: 'Lord, You dwell within me; rule my heart in this moment.',
  ),
  Stone(
    'The Finishing Polish',
    'Rough stones made smooth by patient, quiet love.',
    'Take everyday inconveniences and hidden tasks cheerfully, and do one unnoticed thing well.',
  ),
  Stone(
    'The Perpetual Light',
    'A warm, steady light across the whole city.',
    'Keep your mind and your intentions anchored in Christ, whatever the day brings.',
  ),
  Stone(
    'The Watch',
    'Tending the sanctuary fire, pulling weeds, keeping the walls.',
    'Deal with small faults early. Do not despair after a failure; begin again in peace.',
  ),
];

/// The stone for [day]. It depends on the calendar date alone, so the app and the notification
/// for that date always agree, and a daylight saving change cannot skip or repeat one.
Stone stoneFor(DateTime day) {
  final days = DateTime.utc(day.year, day.month, day.day).difference(DateTime.utc(2000)).inDays;
  return stones[days % stones.length];
}

/// One way of falling, with the three questions that bring it to light.
class Lens {
  final String name;

  /// The Hebrew word it translates, in letters a reader can say.
  final String hebrew;
  final String picture;
  final String question;
  final List<String> prompts;
  const Lens(this.name, this.hebrew, this.picture, this.question, this.prompts);
}

const lenses = [
  Lens(
    'Sin',
    'chata’ah',
    'Missing the mark.',
    'Where did I miss the mark today?',
    [
      'Where did haste or distraction make me miss what God was asking of me?',
      'Who needed my prayer, encouragement or presence, and received silence instead?',
      'Did I give my best to my work and only my leftovers to those closest to me?',
    ],
  ),
  Lens(
    'Iniquity',
    'avon',
    'Bent and twisted.',
    'Where was my heart bent or crooked?',
    [
      'Where did I lead or decide today without asking for God’s wisdom?',
      'Did I bend the truth, or use sharp words to win?',
      'What crooked desire, whether lust, envy, anger, pride or escapism, did I entertain instead of ruling over it?',
    ],
  ),
  Lens(
    'Transgression',
    'pesha',
    'Crossing the line.',
    'Where did I willfully cross a known line?',
    [
      'Did I break trust with someone who relies on me?',
      'Did I ask of others what I would not ask of myself?',
      'Did I knowingly walk past someone vulnerable whom I had the power to help?',
    ],
  ),
];

/// Said at the start: the reason for looking is mercy.
const reflectionStill =
    'God already sees the whole day. He calls you into the light to cleanse you, not to crush you.';

/// Said at the end, and taken word for word from the maintainer's Prayer of Confession.
const reflectionPrayer =
    'I do not bring you my righteousness. I bring your great mercies. Have mercy on me, O God, '
    'according to your lovingkindness. Blot out my transgressions. Wash me thoroughly from my '
    'iniquity. Cleanse me from my sin.';

const reflectionRepair =
    'Pardon is not the whole of repentance. If you broke trust with someone, choose one apology '
    'or repair and begin it within 24 hours.';

/// Psalm 139:23-24, the verse to carry. Its words come from the person's translation.
Ref get reflectionVerse => Ref(bookById(19), 139, 23, 24);

/// The picture the inner city is drawn from: God himself is its temple. Read from the translation.
Ref get buildingVerse => Ref(bookById(66), 21, 22);

/// The notification for [practice] on [day]: building names that day's stone, reflection asks the
/// same plain question each evening. Nothing from the person's own writing is ever in it.
({String title, String body}) practiceMessage(Practice practice, DateTime day) {
  if (practice == Practice.reflection) {
    return (
      title: practice.title,
      body: 'Where did I miss, bend, or cross a line today? Take a few quiet minutes.',
    );
  }
  final stone = stoneFor(day);
  return (title: practice.title, body: '${stone.name}: ${stone.practice}');
}

/// The notifications for [practice] over the next [days] days from [now], at [minutes] after
/// midnight, local time. A time already past today starts tomorrow.
List<ReminderMessage> buildPracticeReminders({
  required Practice practice,
  required DateTime now,
  required int minutes,
  int days = reminderDaysAhead,
  DateTime Function(int year, int month, int day, int hour, int minute) clockTime = _local,
}) {
  final out = <ReminderMessage>[];
  for (var i = 0; out.length < days; i++) {
    final day = DateTime(now.year, now.month, now.day + i);
    // Clock time, so a daylight saving change does not move it an hour.
    final at = clockTime(
      day.year,
      day.month,
      day.day,
      minutes ~/ _minutesPerHour,
      minutes % _minutesPerHour,
    );
    if (!at.isAfter(now)) continue;
    final m = practiceMessage(practice, day);
    out.add(ReminderMessage(practice.idBase + reminderId(day), at, m.title, m.body));
  }
  return out;
}

DateTime _local(int year, int month, int day, int hour, int minute) =>
    DateTime(year, month, day, hour, minute);

/// What the person chose for one practice's reminder. Off until they turn it on.
class PracticeReminder {
  final bool on;
  final int minutes;
  const PracticeReminder({required this.on, required this.minutes});
}
