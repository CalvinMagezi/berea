import 'package:berea_harness/berea_harness.dart';

/// A reading plan: whole chapters spread evenly over its days, computed from chapter counts.
class ReadingPlan {
  final String id;
  final String name;
  final String description;
  final int days;
  final List<Book> books;
  const ReadingPlan(this.id, this.name, this.description, this.days, this.books);

  /// Chapters for each day, index 0 is day 1.
  List<List<Ref>> schedule(int Function(Book) chapterCount) {
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
}

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

/// Groups consecutive chapters of one book: "Genesis 1-3", "Exodus 1".
String readingLabel(List<Ref> refs) {
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
          ? '${refs[i].book.name} ${refs[i].chapter}'
          : '${refs[i].book.name} ${refs[i].chapter}-${refs[j].chapter}',
    );
    i = j + 1;
  }
  return parts.join(', ');
}
