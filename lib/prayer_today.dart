import 'package:berea_harness/berea_harness.dart';

/// The line offered as today's prayer, and where it came from.
class TodayPrayer {
  final PrayerPoint point;

  /// Where the line comes from: "in today's plan".
  final String source;
  const TodayPrayer(this.point, this.source);
}

/// Today's prayer: a line from the chapters of today's plan, a different one each day. Chosen on
/// the device; null when the plan's chapters have no line.
TodayPrayer? todaysPrayer(PrayerContent content, {List<Ref>? reading, int day = 0}) {
  final fromPlan = [
    for (final chapter in reading ?? const <Ref>[]) ...content.chapterPoints(chapter),
  ];
  if (fromPlan.isEmpty) return null;
  return TodayPrayer(fromPlan[day % fromPlan.length], "in today's plan");
}

/// The lines to pray after the day's chapters: the first of each chapter, then more, up to
/// [count]. Short days stay short, and a catch-up day gets one line a chapter.
List<PrayerPoint> prayWhatYouRead(PrayerContent content, List<Ref> chapters, {int count = 3}) {
  final lists = [for (final c in chapters) content.chapterPoints(c)];
  final out = <PrayerPoint>[];
  for (var round = 0; out.length < count; round++) {
    var added = false;
    for (final list in lists) {
      if (round < list.length && out.length < count) {
        out.add(list[round]);
        added = true;
      }
    }
    if (!added) break;
  }
  return out;
}
