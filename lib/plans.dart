import 'package:berea_harness/berea_harness.dart';

import 'today.dart';

/// A reading plan: whole chapters spread evenly over its days, computed from chapter counts.
class ReadingPlan {
  final String id;
  final String name;
  final String description;
  final int days;
  final List<Book> books;
  const ReadingPlan(this.id, this.name, this.description, this.days, this.books);

  /// Chapters for each day, index 0 is day 1.
  List<List<Ref>> schedule() {
    final chapters = [
      for (final b in books)
        for (var c = 1; c <= chapterCount(b); c++) Ref(b, c),
    ];
    final out = List.generate(days, (_) => <Ref>[]);
    for (var i = 0; i < chapters.length; i++) {
      out[i * days ~/ chapters.length].add(chapters[i]);
    }
    return out;
  }

  int get chapters => books.fold(0, (n, b) => n + chapterCount(b));

  /// Chapters a day, rounded to the nearest whole chapter.
  int get dailyLoad => (chapters / days).round();
}

/// Chapters in each of the 66 books, in canon order. Fixed, so a schedule (and the chapter
/// ticks carried over from day ticks) never depends on which Bible file is installed.
const bookChapters = [
  50, 40, 27, 36, 34, 24, 21, 4, 31, 24, 22, 25, 29, 36, 10, 13, 10, 42, 150, 31, 12, 8, //
  66, 52, 5, 48, 12, 14, 3, 9, 1, 4, 7, 3, 3, 3, 2, 14, 4, 28, 16, 24, 21, 28, 16, 16, 13, //
  6, 6, 4, 4, 5, 3, 6, 4, 3, 1, 13, 5, 5, 3, 5, 1, 1, 1, 22,
];

int chapterCount(Book b) => bookChapters[b.id - 1];

const _nt = 40;
const _gospelsEnd = 43;

final readingPlans = <ReadingPlan>[
  ReadingPlan(
    'bible-year',
    'The Bible in a year',
    'Every chapter, Genesis to Revelation.',
    365,
    books,
  ),
  ReadingPlan(
    'nt-90',
    'New Testament in 90 days',
    'Matthew to Revelation, about three chapters a day.',
    90,
    books.where((b) => b.id >= _nt).toList(),
  ),
  ReadingPlan(
    'gospels-30',
    'The Gospels in 30 days',
    'Matthew, Mark, Luke and John.',
    30,
    books.where((b) => b.id >= _nt && b.id <= _gospelsEnd).toList(),
  ),
  ReadingPlan(
    'wisdom-60',
    'Psalms and Proverbs in 60 days',
    'Prayer and wisdom, a few psalms and a proverb a day.',
    60,
    [bookFor('Psalms')!, bookFor('Proverbs')!],
  ),
];

ReadingPlan? planById(String? id) => readingPlans.where((p) => p.id == id).firstOrNull;

/// Groups consecutive chapters of one book: "Genesis 1-3", "Exodus 1". [short] gives "Gen 1-3".
String readingLabel(List<Ref> refs, {bool short = false}) {
  String name(Book b) => short ? shortBookName(b) : b.name;
  final parts = <String>[];
  var i = 0;
  while (i < refs.length) {
    var j = i;
    while (j + 1 < refs.length &&
        refs[j + 1].book.id == refs[i].book.id &&
        refs[j + 1].chapter == refs[j].chapter + 1) {
      j++;
    }
    parts.add(
      j == i
          ? '${name(refs[i].book)} ${refs[i].chapter}'
          : '${name(refs[i].book)} ${refs[i].chapter}-${refs[j].chapter}',
    );
    i = j + 1;
  }
  return parts.join(', ');
}

/// Where a running plan stands, worked out from the chapters ticked. Counts chapters, never
/// days in a row: a missed day is offered as catching up, not as a streak lost.
class PlanProgress {
  final ReadingPlan plan;
  final List<List<Ref>> days;
  final Set<Ref> done;

  /// Today's day of the plan, from 1.
  final int today;
  PlanProgress(this.plan, this.done, this.today) : days = plan.schedule();

  bool dayDone(int day) => days[day - 1].every(done.contains);

  List<Ref> get portion => days[today - 1];

  /// The first unread chapter of today's portion; null once today is read.
  Ref? get next => portion.where((r) => !done.contains(r)).firstOrNull;

  /// Earlier days with a chapter still unread.
  List<int> get missed => [
    for (var d = 1; d < today; d++)
      if (!dayDone(d)) d,
  ];

  /// The unread chapters of the missed days, in order.
  List<Ref> get catchUp => [for (final d in missed) ...days[d - 1].where((r) => !done.contains(r))];

  int get chaptersDone => days.expand((d) => d).where(done.contains).length;
}
