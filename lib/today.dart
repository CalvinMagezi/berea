import 'package:berea_harness/berea_harness.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Shown when the Bible was built before it had a daily list.
const _fallbackDailyVerse = 'Acts 17:11';

/// The local calendar day, for remembering what was done today.
String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// "Wed 28 Oct".
String shortDate(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

String weekdayName(DateTime d) => _weekdays[d.weekday - 1];

Ref verseOfTheDay(BibleDb db, DateTime day) =>
    db.dailyVerse(day) ?? RefParser.parse(_fallbackDailyVerse).first;

/// Whole days from [from] to [to], by the calendar rather than by hours.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
