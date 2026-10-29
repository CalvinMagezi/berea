import 'package:berea/prayer_today.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final matthew7 = Ref(bookById(40), 7);
  final matthew8 = Ref(bookById(40), 8);
  final content = PrayerContent(
    chapters: {
      PrayerContent.chapterKey(bookById(40), 7): [
        const PrayerPoint('Seven a.', 'Matthew 7:7'),
        const PrayerPoint('Seven b.', 'Matthew 7:24'),
      ],
      PrayerContent.chapterKey(bookById(40), 8): [const PrayerPoint('Eight a.', 'Matthew 8:2')],
    },
    daily: {'Isaiah 41:10': 'Hold me up.'},
  );
  final verseOfDay = Ref(bookById(23), 41, 10);

  test('a running plan offers a line from its chapters, a different one each day', () {
    final first = todaysPrayer(content, verseOfDay: verseOfDay, reading: [matthew7, matthew8]);
    final second = todaysPrayer(
      content,
      verseOfDay: verseOfDay,
      reading: [matthew7, matthew8],
      day: 1,
    );
    expect(first!.point.text, 'Seven a.');
    expect(first.source, "in today's plan");
    expect(second!.point.text, 'Seven b.');
  });

  test('with no plan, or chapters with no lines, it is the verse of the day line', () {
    final noPlan = todaysPrayer(content, verseOfDay: verseOfDay);
    expect(noPlan!.point.text, 'Hold me up.');
    expect(noPlan.point.ref, 'Isaiah 41:10');
    final unwritten = todaysPrayer(content, verseOfDay: verseOfDay, reading: [Ref(bookById(1), 1)]);
    expect(unwritten!.point.text, 'Hold me up.');
  });

  test('no line for the verse of the day means no prayer card', () {
    expect(todaysPrayer(content, verseOfDay: Ref(bookById(1), 1, 1)), isNull);
  });

  test('Pray what you read takes a line from each chapter before a second from any', () {
    final lines = prayWhatYouRead(content, [matthew7, matthew8]);
    expect([for (final l in lines) l.text], ['Seven a.', 'Eight a.', 'Seven b.']);
    expect(prayWhatYouRead(content, [matthew8]).length, 1);
    expect(prayWhatYouRead(content, [Ref(bookById(1), 1)]), isEmpty);
  });
}
