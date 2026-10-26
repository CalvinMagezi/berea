import 'package:berea_harness/berea_harness.dart';
import 'package:test/test.dart';

void main() {
  group('withoutUnfinishedSentence', () {
    test('keeps a text that already ends a sentence', () {
      expect(withoutUnfinishedSentence('All done.'), 'All done.');
      expect(withoutUnfinishedSentence('See (John 3:16).'), 'See (John 3:16).');
      expect(withoutUnfinishedSentence('He said "Peace." '), 'He said "Peace."');
      expect(withoutUnfinishedSentence('**Peace.**'), '**Peace.**');
    });

    test('drops the sentence that was cut off', () {
      expect(withoutUnfinishedSentence('For God so loved. He gave his'), 'For God so loved.');
    });

    test('a reference cut short cannot pass as a different verse', () {
      expect(
        withoutUnfinishedSentence('Romans 8:28 says it. See also Romans 8:2'),
        'Romans 8:28 says it.',
      );
    });

    test('a quotation left open is removed with what follows it', () {
      expect(
        withoutUnfinishedSentence('It is written. He said “For God so loved the world. He gave'),
        'It is written.',
      );
      expect(withoutUnfinishedSentence('It is written. He said "For God so'), 'It is written.');
    });

    test('a number with a point inside is not a sentence end', () {
      expect(withoutUnfinishedSentence('Read 3.16 aloud'), '');
    });

    test('a quotation does not run past the end of its line', () {
      expect(
        withoutUnfinishedSentence(
          'He said "Peace be with you.\n\nGrace is a gift (John 3:16).\n\nAnd more',
        ),
        'He said "Peace be with you.\n\nGrace is a gift (John 3:16).',
      );
    });

    test('a list number is not the end of a sentence', () {
      expect(
        withoutUnfinishedSentence('Three things.\n1. Faith.\n2. Hope.\n3. Lov'),
        'Three things.\n1. Faith.\n2. Hope.',
      );
    });

    test('typographic closers and the ellipsis end a sentence too', () {
      expect(withoutUnfinishedSentence('He said ‘Peace.’ And then'), 'He said ‘Peace.’');
      expect(withoutUnfinishedSentence('It trails off… and then'), 'It trails off…');
    });

    test('nothing finished leaves nothing', () {
      expect(withoutUnfinishedSentence(''), '');
      expect(withoutUnfinishedSentence('For God so'), '');
    });
  });
}
