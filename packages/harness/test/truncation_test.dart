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

    test('nothing finished leaves nothing', () {
      expect(withoutUnfinishedSentence(''), '');
      expect(withoutUnfinishedSentence('For God so'), '');
    });
  });
}
