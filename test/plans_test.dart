import 'package:berea/plans.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real chapter counts for the 66 books.
const _counts = [
  50,
  40,
  27,
  36,
  34,
  24,
  21,
  4,
  31,
  24,
  22,
  25,
  29,
  36,
  10,
  13,
  10,
  42,
  150,
  31,
  12,
  8,
  66,
  52,
  5,
  48,
  12,
  14,
  3,
  9,
  1,
  4,
  7,
  3,
  3,
  3,
  2,
  14,
  4,
  28,
  16,
  24,
  21,
  28,
  16,
  16,
  13,
  6,
  6,
  4,
  4,
  5,
  3,
  6,
  4,
  3,
  1,
  13,
  5,
  5,
  3,
  5,
  1,
  1,
  1,
  22,
];

int _count(Book b) => _counts[b.id - 1];

void main() {
  test('every plan covers each chapter exactly once with no empty days', () {
    for (final p in readingPlans) {
      final days = p.schedule(_count);
      expect(days.length, p.days, reason: p.id);
      expect(days.every((d) => d.isNotEmpty), isTrue, reason: p.id);
      final all = days.expand((d) => d).toList();
      expect(all.length, p.books.fold(0, (n, b) => n + _count(b)), reason: p.id);
      expect(all.toSet().length, all.length, reason: p.id);
    }
    expect(planById('bible-year')!.schedule(_count).expand((d) => d).length, 1189);
  });

  test('reading labels group consecutive chapters', () {
    final refs = [
      ...RefParser.parse('Genesis 1, Genesis 2, Genesis 3'),
      ...RefParser.parse('Exodus 1'),
    ];
    expect(readingLabel(refs), 'Genesis 1-3, Exodus 1');
  });
}
