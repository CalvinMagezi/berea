import 'dart:convert';
import 'dart:typed_data';

import 'package:berea_harness/berea_harness.dart';
import 'package:test/test.dart';

/// Durations the timestamped Kokoro export (8-bit file) returned for "How could I know?"
/// (af_heart, speed 1); its waveform was 40200 samples, which is 67 rounded frames of 600.
const _howCouldIKnow = [
  15.736977,
  2.0910888,
  2.0083354,
  1.9422177,
  1.7274781,
  1.9927936,
  1.3437918,
  1.1542937,
  1.0286789,
  1.8024737,
  1.9962423,
  1.8356922,
  1.9557103,
  1.9428141,
  3.091242,
  3.6048002,
  13.493319,
  6.9805903,
  1.0035217,
];

final _lexicon = Lexicon.parseCmudict('''
;;; comment line
for F AO1 R
god G AA1 D
psalm S AA1 L M
psalm(2) S AA1 M
job JH AA1 B
three TH R IY1
sixteen S IH0 K S T IY1 N
one W AH1 N
hundred HH AH1 N D R AH0 D
forty F AO1 R T IY0
four F AO1 R
thousand TH AW1 Z AH0 N D
aalborg AO1 L B AO0 R G # place, danish
''');

Utterance _howUtterance() {
  const phonemes = 'hˌaʊ kʊd aɪ nˈoʊ?';
  const words = [
    SpeechPiece('How', 0, 3, ''),
    SpeechPiece('could', 4, 9, ''),
    SpeechPiece('I', 10, 11, ''),
    SpeechPiece('know', 12, 16, ''),
  ];
  return const Utterance(phonemes, words, [(0, 4), (5, 8), (9, 11), (12, 16)]);
}

void main() {
  group('ARPAbet to Kokoro phonemes', () {
    test('uses the misaki US set with stress before the vowel', () {
      expect(arpabetToKokoro('HH AH0 L OW1'), 'həlˈO');
      expect(arpabetToKokoro('B ER1 D'), 'bˈɜɹd');
      expect(arpabetToKokoro('B AH1 T ER0'), 'bˈʌtəɹ');
      expect(arpabetToKokoro('JH AH1 JH'), 'ʤˈʌʤ');
      expect(arpabetToKokoro('G AA1 D'), 'ɡˈɑd');
      expect(arpabetToKokoro('S IH2 K S T IY1 N'), 'sˌɪkstˈin');
    });

    test('every phone maps to characters in the Kokoro vocabulary', () {
      const phones =
          'AA AE AH AO AW AY EH ER EY IH IY OW OY UH UW B CH D DH F G HH JH K L M N NG P R S SH '
          'T TH V W Y Z ZH';
      for (final p in phones.split(' ')) {
        for (final stress in ['', '0', '1', '2']) {
          final out = arpabetToKokoro('$p$stress');
          expect(out.split('').every(kokoroVocab.containsKey), isTrue, reason: '$p$stress');
        }
      }
    });

    test('rejects anything that is not ARPAbet', () {
      expect(() => arpabetToKokoro('HH XX1'), throwsFormatException);
      expect(() => arpabetToKokoro('hh ah0'), throwsFormatException);
    });
  });

  group('CMUdict', () {
    test('keeps the first pronunciation and skips comments', () {
      expect(_lexicon.arpabet['psalm'], 'S AA1 L M');
      expect(_lexicon.arpabet['aalborg'], 'AO1 L B AO0 R G');
      expect(_lexicon.arpabet.containsKey(';;;'), isFalse);
      expect(_lexicon.arpabet.keys.any((k) => k.contains('(')), isFalse);
    });
  });

  group('Phonemizer', () {
    final p = Phonemizer(_lexicon);

    test('the biblical lexicon wins over CMUdict', () {
      expect(p.word('Psalm'), 'sˈɑm');
      expect(p.word('Melchizedek'), arpabetToKokoro(biblicalPronunciations['melchizedek']!));
      expect(p.word('NEBUCHADNEZZAR'), arpabetToKokoro(biblicalPronunciations['nebuchadnezzar']!));
      expect(p.word('Habakkuk'), 'həbˈækək');
    });

    test('a capitalised override applies only to that spelling', () {
      expect(p.word('Job'), 'ʤˈOb');
      expect(p.word('job'), 'ʤˈɑb');
    });

    test('possessives add the right ending to the base word', () {
      final base = p.word('Nebuchadnezzar');
      expect(p.word('Nebuchadnezzar’s'), '${base}z');
      expect(p.word("God's"), 'ɡˈɑdz');
    });

    test('a caller can extend the lexicon', () {
      final extended = Phonemizer(
        _lexicon,
        overrides: {...biblicalPronunciations, 'zoar': 'Z OW1 ER0'},
      );
      expect(extended.word('Zoar'), 'zˈOəɹ');
    });

    test('unknown words fall back to letter rules with one primary stress', () {
      final out = p.word('Zaphnath');
      expect(out, isNotEmpty);
      expect('ˈ'.allMatches(out).length, 1);
      expect(out.split('').every(kokoroVocab.containsKey), isTrue);
    });

    test('numbers are spelled out and keep their source text', () {
      final pieces = p.pieces('Psalm 144,000 and 3:16');
      expect(pieces.map((x) => x.text).toList(), ['Psalm', '144,000', 'and', '3', ':', '16']);
      expect(
        pieces[1].phonemes,
        [
          'one',
          'hundred',
          'forty',
          'four',
          'thousand',
        ].map((w) => arpabetToKokoro(_lexicon.arpabet[w]!)).join(' '),
      );
      expect(pieces[5].phonemes, arpabetToKokoro('S IH0 K S T IY1 N'));
    });

    test('assembles punctuation against words and maps word spans to tokens', () {
      final u = p.assemble(p.pieces('“For God,” three.'));
      expect(u.phonemes, '“fˈɔɹ ɡˈɑd,” θɹˈi.');
      expect(u.words.map((w) => w.text), ['For', 'God', 'three']);
      for (var i = 0; i < u.words.length; i++) {
        final (a, b) = u.tokenSpans[i];
        expect(u.phonemes.substring(a, b), p.word(u.words[i].text));
      }
      final ids = u.inputIds;
      expect(ids.first, kokoroPadId);
      expect(ids.last, kokoroPadId);
      expect(ids.length, u.phonemes.length + 2);
    });

    test('a long run without punctuation never cuts a word to fit', () {
      final text = 'For God, ${List.filled(60, 'so').join(' ')} Nebuchadnezzar three.';
      const max = 40;
      for (final c in p.utterances(text, maxTokens: max)) {
        expect(c.phonemes.length, lessThanOrEqualTo(max));
        for (var i = 0; i < c.words.length; i++) {
          final (a, b) = c.tokenSpans[i];
          expect(c.phonemes.substring(a, b), p.word(c.words[i].text), reason: c.words[i].text);
        }
      }
    });

    test('straight quotes open and close in turn', () {
      final u = p.assemble(p.pieces('God said, "So." Three'));
      expect(u.phonemes, endsWith('${p.word('So')}." ${p.word('three')}'));
    });

    test('a lone q and very long numbers do not stop speech', () {
      expect(p.word('Qoph'), isNotEmpty);
      final digits = p.pieces('123456789012345678901234').single;
      expect(digits.phonemes.split(' ').length, 24);
    });

    test('long text splits after punctuation and every chunk fits', () {
      final text = List.filled(12, 'For God so loved, the world.').join(' ');
      const max = 40;
      final chunks = p.utterances(text, maxTokens: max);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.phonemes.length, lessThanOrEqualTo(max));
      }
      final spoken = chunks.expand((c) => c.words.map((w) => w.text)).toList();
      expect(spoken, p.pieces(text).where((x) => x.isWord).map((x) => x.text).toList());
    });
  });

  group('number words', () {
    test('spells whole numbers', () {
      expect(numberToWords(0), 'zero');
      expect(numberToWords(13), 'thirteen');
      expect(numberToWords(40), 'forty');
      expect(numberToWords(153), 'one hundred fifty three');
      expect(numberToWords(1611), 'one thousand six hundred eleven');
      expect(numberToWords(144000), 'one hundred forty four thousand');
      expect(numberToWords(2000000), 'two million');
    });
  });

  group('word timings', () {
    test('rounded frames times 600 match the waveform the model returned', () {
      expect(expectedSamples(_howCouldIKnow), 40200);
    });

    test('each word spans the frames of its own phonemes', () {
      final t = wordTimings(_howUtterance(), _howCouldIKnow);
      expect(
        [for (final w in t) w.toJson()],
        [
          {'word': 'How', 'startMs': 400, 'endMs': 600},
          {'word': 'could', 'startMs': 650, 'endMs': 725},
          {'word': 'I', 'startMs': 775, 'endMs': 875},
          {'word': 'know', 'startMs': 925, 'endMs': 1475},
        ],
      );
      expect(t[1].sourceStart, 4);
      expect(t[1].sourceEnd, 9);
    });

    test('a later chunk is offset and ends stay inside the audio', () {
      final t = wordTimings(
        _howUtterance(),
        _howCouldIKnow,
        offsetSamples: 24000,
        totalSamples: 30000,
      );
      expect(t.first.startMs, 1400);
      expect(t.last.endMs, 2250);
    });

    test('refuses durations that do not belong to the utterance', () {
      expect(() => wordTimings(_howUtterance(), _howCouldIKnow.sublist(1)), throwsArgumentError);
    });
  });

  group('voice styles and audio', () {
    test('the style row follows the token count and stops at the last row', () {
      final voice = Float32List(kokoroStyleDim * 3);
      for (var i = 0; i < voice.length; i++) {
        voice[i] = (i ~/ kokoroStyleDim).toDouble();
      }
      expect(styleFor(voice, 1).first, 1);
      expect(styleFor(voice, 99).first, 2);
      expect(styleFor(voice, 1).length, kokoroStyleDim);
      expect(() => styleFor(Float32List(10), 1), throwsFormatException);
    });

    test('writes a mono 16-bit WAV header', () {
      final wav = wavBytes(Float32List.fromList([0, 1, -1, 2]));
      final b = ByteData.sublistView(wav);
      expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
      expect(b.getUint32(24, Endian.little), kokoroSampleRate);
      expect(wav.length, 44 + 8);
      expect(b.getInt16(46, Endian.little), 32767);
      expect(b.getInt16(50, Endian.little), 32767);
    });
  });

  group('voice pack manifest', () {
    test('round-trips the pinned files', () {
      final parsed = parseVoicePackManifest(voicePackManifestJson());
      expect(
        parsed.map((f) => f.toJson()).toList(),
        voicePackFiles.map((f) => f.toJson()).toList(),
      );
    });

    test('pins are well formed and names unique', () {
      expect(voicePackFiles.map((f) => f.name).toSet().length, voicePackFiles.length);
      for (final f in voicePackFiles) {
        expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(f.bytes, greaterThan(0));
        expect(f.upstream, startsWith('https://'));
      }
      for (final s in kokoroSpeakers) {
        expect(voicePackDeviceFiles.map((f) => f.name), contains(s.fileName));
      }
      expect(voicePackDeviceFiles.any((f) => f.role == VoiceFileRole.licence), isFalse);
      expect(voicePackDownloadBytes, greaterThan(90 * 1000 * 1000));
    });

    test('refuses malformed manifests', () {
      Map<String, Object> entry(Map<String, Object> change) => {
        ...voicePackFiles.first.toJson(),
        ...change,
      };
      String manifest(Object files, {int format = voicePackFormat}) =>
          jsonEncode({'format': format, 'files': files});
      expect(() => parseVoicePackManifest(manifest([], format: 99)), throwsFormatException);
      expect(() => parseVoicePackManifest('{"format": 1}'), throwsFormatException);
      for (final bad in [
        {'sha256': 'abc'},
        {'name': '../evil.onnx'},
        {'bytes': 0},
        {'role': 'binary'},
      ]) {
        expect(() => parseVoicePackManifest(manifest([entry(bad)])), throwsFormatException);
      }
    });
  });
}
