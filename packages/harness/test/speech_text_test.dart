import 'package:berea_harness/berea_harness.dart';
import 'package:test/test.dart';

void main() {
  group('failed claims', () {
    test('drops a sentence holding an unverified marker', () {
      expect(
        speakable('Love wins. Jesus said so [unverified: John 99:1]. Grace abounds.'),
        'Love wins. Grace abounds.',
      );
    });

    test('drops unverified quotes and differs-from-Scripture sentences', () {
      expect(
        speakable('One. Two [unverified quote]. Three [differs from Scripture]. Four.'),
        'One. Four.',
      );
    });

    test('keeps a corrected quote without its marker', () {
      expect(speakable('He said it [quote corrected]. Done.'), 'He said it. Done.');
    });

    test('does not split inside a reference or after v.', () {
      expect(speakable('See v. 3 and John 3:16 [unverified: John 99:1]. Next one.'), 'Next one.');
    });
  });

  group('source tags', () {
    test('removes notebook and pack tags and tidies the gap', () {
      expect(
        speakable('Grace [N12 §3] is free [S4 p.14], truly [S4 pp. 14-15] [C1234]. Yes [x y] ok.'),
        'Grace is free, truly. Yes ok.',
      );
    });
  });

  group('markdown', () {
    test('strips markers, emphasis, code and links', () {
      expect(
        speakable('## Title\n- **bold** and *it* and _it2_ `code`\n1. [link](http://x.y) text'),
        'Title. bold and it and it2 code. link text.',
      );
    });
  });

  group('spoken references', () {
    test('verse, range and chapter forms', () {
      expect(speakable('John 3:16'), 'John chapter 3, verse 16');
      expect(speakable('John 3:16-18'), 'John chapter 3, verses 16 to 18');
      expect(speakable('John 3'), 'John chapter 3');
    });

    test('Psalms say Psalm', () {
      expect(speakable('Psalm 23:1'), 'Psalm 23, verse 1');
      expect(speakable('Psalms 23'), 'Psalm 23');
    });

    test('numbered books use ordinals', () {
      expect(speakable('1 John 4:8'), 'First John chapter 4, verse 8');
      expect(speakable('2 Samuel 7:12'), 'Second Samuel chapter 7, verse 12');
      expect(speakable('3 John 1:2'), 'Third John chapter 1, verse 2');
    });

    test('parenthesised citations lose parentheses and translation code', () {
      expect(
        speakable('God loved the world (John 3:16, BSB).'),
        'God loved the world, John chapter 3, verse 16.',
      );
      expect(speakable('Faith (Romans 10:17) comes.'), 'Faith, Romans chapter 10, verse 17 comes.');
      expect(
        speakable('We start with Philippians 4:4, BSB, which commands joy.'),
        'We start with Philippians chapter 4, verse 4, which commands joy.',
      );
    });
  });

  group('original languages', () {
    test('drops Greek, Hebrew and Strong\'s codes and empty parentheses', () {
      expect(
        speakable('Love ἀγάπη (G26) and שָׁלוֹם (H7965a) and (ἀγάπη, G26) matter.'),
        'Love and and matter.',
      );
    });
  });

  group('divine name', () {
    test('LORD and GOD lose their capitals', () {
      expect(
        speakable('The LORD is God; the Lord GOD reigns.'),
        'The Lord is God; the Lord God reigns.',
      );
    });
  });

  group('paragraphs', () {
    const script = '''
# The Shepherd

The LORD is my shepherd (Psalm 23:1, BSB) [S4 p.14]. This was never said [unverified: Hezekiah 2:1].

- The Greek ποιμήν (G4166) means *shepherd*.
- See **John 10:11-14** [N2 §1].


   ''';

    test('speechParagraphs splits on blank lines and drops empties', () {
      expect(speechParagraphs(script), [
        'The Shepherd.',
        'The Lord is my shepherd, Psalm 23, verse 1.',
        'The Greek means shepherd. See John chapter 10, verses 11 to 14.',
      ]);
    });

    test('speakable joins them with a blank line', () {
      expect(speakable(script), speechParagraphs(script).join('\n\n'));
    });

    test('empty script gives nothing', () {
      expect(speechParagraphs(''), isEmpty);
    });
  });
}
