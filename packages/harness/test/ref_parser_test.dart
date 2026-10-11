import 'package:berea_harness/berea_harness.dart';
import 'package:test/test.dart';

void main() {
  test('parses common reference forms', () {
    final refs = RefParser.parse(
      'Compare John 3:16, Jn 3.16-18, 1 Cor 13, Psalm 23:1 and Song of Solomon 2:1. '
      'Chapter 3 and verse 16 are not refs, nor is 2 days.',
    );
    expect(refs.map((r) => r.label), [
      'John 3:16',
      'John 3:16-18',
      '1 Corinthians 13',
      'Psalms 23:1',
      'Song of Solomon 2:1',
    ]);
  });

  test('a stray number before a numbered book does not swallow it', () {
    expect(RefParser.parse('love in 1 Corinthians 13:4?').map((r) => r.label), [
      '1 Corinthians 13:4',
    ]);
    expect(RefParser.parse('Messiah 3 and jobs 4 are not refs').isEmpty, isTrue);
    expect(RefParser.parse('see 1 Cor. 13:4 and II Timothy 3:16').map((r) => r.label), [
      '1 Corinthians 13:4',
      '2 Timothy 3:16',
    ]);
  });

  test('match offsets map onto the original text', () {
    const text = 'See Song of Songs 4:7 and Rev 21:4.';
    final ms = RefParser.matches(text);
    expect(text.substring(ms[1].start, ms[1].end), 'Rev 21:4');
    expect(ms[0].start, 4);
  });
}
