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

/// Short book names for one-line places such as the folded card, in canon order.
const bookAbbreviations = [
  'Gen', 'Exod', 'Lev', 'Num', 'Deut', 'Josh', 'Judg', 'Ruth', '1 Sam', '2 Sam', '1 Kgs', //
  '2 Kgs', '1 Chr', '2 Chr', 'Ezra', 'Neh', 'Esth', 'Job', 'Ps', 'Prov', 'Eccl', 'Song', //
  'Isa', 'Jer', 'Lam', 'Ezek', 'Dan', 'Hos', 'Joel', 'Amos', 'Obad', 'Jonah', 'Mic', 'Nah', //
  'Hab', 'Zeph', 'Hag', 'Zech', 'Mal', 'Matt', 'Mark', 'Luke', 'John', 'Acts', 'Rom', //
  '1 Cor', '2 Cor', 'Gal', 'Eph', 'Phil', 'Col', '1 Thess', '2 Thess', '1 Tim', '2 Tim', //
  'Titus', 'Phlm', 'Heb', 'Jas', '1 Pet', '2 Pet', '1 John', '2 John', '3 John', 'Jude', 'Rev',
];

String shortBookName(Book b) => bookAbbreviations[b.id - 1];

/// "2 Cor 4:18": a reference with its book shortened.
String shortLabel(Ref r) => r.label.replaceFirst(r.book.name, shortBookName(r.book));
