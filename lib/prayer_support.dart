import 'prayer_store.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

String monthName(DateTime d) => _monthNames[d.month - 1];

String dayMonth(DateTime d) => '${d.day} ${monthName(d)}';

String prayedSummary(Prayer p) => p.daysPrayed == 0
    ? 'Not prayed yet'
    : 'Prayed on ${p.daysPrayed} ${p.daysPrayed == 1 ? 'day' : 'days'} '
          'since ${dayMonth(p.firstPrayed!)}';

/// An answered prayer shared as a testimony: the request, who it was for unless left out, the
/// person's own line, the day, and the verse they stood on with its words when asked.
String testimonyShareText(
  Prayer p, {
  String? verseText,
  bool includeVerse = true,
  bool includeWho = false,
}) {
  final b = StringBuffer('Answered prayer: ${p.title}');
  if (includeWho && p.forWhom.isNotEmpty) b.write('\nFor ${p.forWhom}');
  if (p.answer != null) b.write('\n${p.answer}');
  if (includeVerse && p.verse != null) {
    b.write('\nI stood on ${p.verse}');
    if (verseText != null && verseText.isNotEmpty) b.write(': “$verseText”');
  }
  return b.toString();
}
