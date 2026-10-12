import 'dart:math';
import 'dart:typed_data';

import 'speech_lexicon.dart';

/// Kokoro writes 24 kHz audio, and each predicted duration frame is 600 samples (25 ms).
const kokoroSampleRate = 24000;
const kokoroSamplesPerFrame = 600;

/// The model's context is 512 tokens including the pad at each end.
const kokoroMaxTokens = 510;

/// Chunks aim well under the context: peak memory grows with chunk length, and a phone has
/// less to spare than the model allows. About 15 seconds of speech.
const kokoroChunkTokens = 200;
const kokoroStyleDim = 256;
const kokoroPadId = 0;
const _msPerSecond = 1000;

/// Kokoro v1.0's phoneme vocabulary, from hexgrad/Kokoro-82M config.json (Apache-2.0).
const kokoroVocab = <String, int>{
  ';': 1,
  ':': 2,
  ',': 3,
  '.': 4,
  '!': 5,
  '?': 6,
  '\u2014': 9,
  '…': 10,
  '"': 11,
  '(': 12,
  ')': 13,
  '“': 14,
  '”': 15,
  ' ': 16,
  '̃': 17,
  'ʣ': 18,
  'ʥ': 19,
  'ʦ': 20,
  'ʨ': 21,
  'ᵝ': 22,
  'ꭧ': 23,
  'A': 24,
  'I': 25,
  'O': 31,
  'Q': 33,
  'S': 35,
  'T': 36,
  'W': 39,
  'Y': 41,
  'ᵊ': 42,
  'a': 43,
  'b': 44,
  'c': 45,
  'd': 46,
  'e': 47,
  'f': 48,
  'h': 50,
  'i': 51,
  'j': 52,
  'k': 53,
  'l': 54,
  'm': 55,
  'n': 56,
  'o': 57,
  'p': 58,
  'q': 59,
  'r': 60,
  's': 61,
  't': 62,
  'u': 63,
  'v': 64,
  'w': 65,
  'x': 66,
  'y': 67,
  'z': 68,
  'ɑ': 69,
  'ɐ': 70,
  'ɒ': 71,
  'æ': 72,
  'β': 75,
  'ɔ': 76,
  'ɕ': 77,
  'ç': 78,
  'ɖ': 80,
  'ð': 81,
  'ʤ': 82,
  'ə': 83,
  'ɚ': 85,
  'ɛ': 86,
  'ɜ': 87,
  'ɟ': 90,
  'ɡ': 92,
  'ɥ': 99,
  'ɨ': 101,
  'ɪ': 102,
  'ʝ': 103,
  'ɯ': 110,
  'ɰ': 111,
  'ŋ': 112,
  'ɳ': 113,
  'ɲ': 114,
  'ɴ': 115,
  'ø': 116,
  'ɸ': 118,
  'θ': 119,
  'œ': 120,
  'ɹ': 123,
  'ɾ': 125,
  'ɻ': 126,
  'ʁ': 128,
  'ɽ': 129,
  'ʂ': 130,
  'ʃ': 131,
  'ʈ': 132,
  'ʧ': 133,
  'ʊ': 135,
  'ʋ': 136,
  'ʌ': 138,
  'ɣ': 139,
  'ɤ': 140,
  'χ': 142,
  'ʎ': 143,
  'ʒ': 147,
  'ʔ': 148,
  'ˈ': 156,
  'ˌ': 157,
  'ː': 158,
  'ʰ': 162,
  'ʲ': 164,
  '↓': 169,
  '→': 171,
  '↗': 172,
  '↘': 173,
  'ᵻ': 177,
};

/// ARPAbet to the misaki US phoneme set Kokoro v1.0 was trained on: diphthongs are single
/// capitals (A, I, O, W, Y), affricates are ligatures, and stress goes right before the vowel.
const _arpaConsonants = {
  'B': 'b',
  'CH': 'ʧ',
  'D': 'd',
  'DH': 'ð',
  'F': 'f',
  'G': 'ɡ',
  'HH': 'h',
  'JH': 'ʤ',
  'K': 'k',
  'L': 'l',
  'M': 'm',
  'N': 'n',
  'NG': 'ŋ',
  'P': 'p',
  'R': 'ɹ',
  'S': 's',
  'SH': 'ʃ',
  'T': 't',
  'TH': 'θ',
  'V': 'v',
  'W': 'w',
  'Y': 'j',
  'Z': 'z',
  'ZH': 'ʒ',
};
const _arpaVowels = {
  'AA': 'ɑ',
  'AE': 'æ',
  'AO': 'ɔ',
  'AW': 'W',
  'AY': 'I',
  'EH': 'ɛ',
  'EY': 'A',
  'IH': 'ɪ',
  'IY': 'i',
  'OW': 'O',
  'OY': 'Y',
  'UH': 'ʊ',
  'UW': 'u',
};
const _primary = 'ˈ';
const _secondary = 'ˌ';
final _arpaPhone = RegExp(r'^([A-Z]+)([012])?$');

/// Kokoro phonemes for one ARPAbet pronunciation such as `HH AH0 L OW1`.
String arpabetToKokoro(String arpabet) {
  final out = StringBuffer();
  for (final phone in arpabet.trim().split(RegExp(r'\s+'))) {
    final m = _arpaPhone.firstMatch(phone);
    if (m == null) throw FormatException('Not an ARPAbet phone: "$phone"');
    final base = m[1]!;
    final consonant = _arpaConsonants[base];
    if (consonant != null) {
      out.write(consonant);
      continue;
    }
    final stressed = m[2] == '1' || m[2] == '2';
    final vowel = switch (base) {
      'AH' => stressed ? 'ʌ' : 'ə',
      'ER' => stressed ? 'ɜɹ' : 'əɹ',
      _ => _arpaVowels[base],
    };
    if (vowel == null) throw FormatException('Not an ARPAbet phone: "$phone"');
    if (m[2] == '1') out.write(_primary);
    if (m[2] == '2') out.write(_secondary);
    out.write(vowel);
  }
  return out.toString();
}

/// Pronunciations by lower-case word, in ARPAbet, from CMUdict (BSD-style licence).
class Lexicon {
  final Map<String, String> arpabet;
  const Lexicon(this.arpabet);

  /// Parses `cmudict.dict`: `word PH ON ES # comment`, alternates as `word(2)`. The first
  /// pronunciation of each word wins.
  static Lexicon parseCmudict(String text) {
    final out = <String, String>{};
    for (final line in text.split('\n')) {
      final hash = line.indexOf('#');
      final body = (hash < 0 ? line : line.substring(0, hash)).trim();
      final space = body.indexOf(' ');
      if (space <= 0 || body.startsWith(';;;')) continue;
      final key = body.substring(0, space);
      if (key.contains('(')) continue;
      out.putIfAbsent(key, () => body.substring(space + 1).trim());
    }
    return Lexicon(out);
  }
}

/// A word, number or punctuation mark of the source text and the phonemes it is spoken as.
/// [start] and [end] are offsets into the source text; punctuation has [isWord] false.
class SpeechPiece {
  final String text;
  final int start;
  final int end;
  final String phonemes;
  final bool isWord;
  const SpeechPiece(this.text, this.start, this.end, this.phonemes, {this.isWord = true});
}

/// One chunk's phoneme string and where each word's phonemes sit in it. Every character of
/// [phonemes] is one Kokoro token, so string offsets are token offsets.
class Utterance {
  final String phonemes;
  final List<SpeechPiece> words;
  final List<(int, int)> tokenSpans;
  const Utterance(this.phonemes, this.words, this.tokenSpans);

  /// Token ids with the pad at each end, ready for the model's `input_ids`.
  Int64List get inputIds => Int64List.fromList([
    kokoroPadId,
    for (final c in phonemes.split('')) kokoroVocab[c]!,
    kokoroPadId,
  ]);
}

const _openingMarks = {'“', '(', '"'};
const _breakMarks = {'.', '!', '?', ';', ':', '\u2014', '…', ','};
final _tokenPattern = RegExp(
  r"(\d{1,3}(?:,\d{3})+|\d+)|([A-Za-z]+(?:['’][A-Za-z]+)*)|([;:,.!?\u2014\u2013…"
  '"()“”])',
);

/// Text to Kokoro phonemes without espeak-ng. Words go through the biblical name lexicon, then
/// CMUdict, then simple letter rules; numbers are spelled out first.
class Phonemizer {
  final Lexicon lexicon;
  final Map<String, String> overrides;
  Phonemizer(this.lexicon, {this.overrides = biblicalPronunciations});

  /// The pieces of [text] in reading order; anything that is not a word, number or
  /// Kokoro punctuation is dropped.
  List<SpeechPiece> pieces(String text) => [
    for (final m in _tokenPattern.allMatches(text))
      if (m[1] != null)
        SpeechPiece(m[0]!, m.start, m.end, _numberPhonemes(m[1]!))
      else if (m[2] != null)
        SpeechPiece(m[0]!, m.start, m.end, word(m[2]!))
      else
        SpeechPiece(m[0]!, m.start, m.end, m[0] == '\u2013' ? '\u2014' : m[0]!, isWord: false),
  ];

  /// Phonemes for one word, keeping only characters Kokoro knows.
  String word(String raw) {
    final w = raw.replaceAll('’', "'");
    final found = _lookup(w);
    if (found != null) return found;
    final possessive = RegExp(r"^(.+)'s$", caseSensitive: false).firstMatch(w);
    if (possessive != null) {
      final base = _lookup(possessive[1]!) ?? letterRulePhonemes(possessive[1]!);
      return base + _sSuffix(base);
    }
    return letterRulePhonemes(w);
  }

  /// A capitalised override ("Job") applies only to that spelling, so the noun "job" keeps
  /// its own pronunciation.
  String? _lookup(String w) {
    final arpa = overrides[w] ?? overrides[w.toLowerCase()] ?? lexicon.arpabet[w.toLowerCase()];
    return arpa == null ? null : arpabetToKokoro(arpa);
  }

  /// Whole numbers are read as numbers; a run of digits longer than that is read digit by digit.
  String _numberPhonemes(String raw) {
    final digits = raw.replaceAll(',', '');
    final words = digits.length > _maxNumberDigits
        ? digits.split('').map((d) => numberToWords(int.parse(d))).join(' ')
        : numberToWords(int.parse(digits));
    return words.split(' ').map(word).join(' ');
  }

  /// Joins [pieces] into one utterance: a space between words, punctuation against the word
  /// it follows, opening quotes against the word after them.
  Utterance assemble(List<SpeechPiece> pieces) {
    final out = StringBuffer();
    final words = <SpeechPiece>[];
    final spans = <(int, int)>[];
    var glue = false;
    var inQuote = false;
    for (final p in pieces) {
      // A straight quote opens and closes in turn; curly ones say which they are.
      final straight = p.text == '"';
      final opening = !p.isWord && _openingMarks.contains(p.text) && !(straight && inQuote);
      if (straight) inQuote = !inQuote;
      final attaches = !p.isWord && !opening;
      if (out.isNotEmpty && !attaches && !glue) out.write(' ');
      final start = out.length;
      out.write(p.phonemes.split('').where(kokoroVocab.containsKey).join());
      if (p.isWord) {
        words.add(p);
        spans.add((start, out.length));
      }
      glue = opening;
    }
    return Utterance(out.toString(), words, spans);
  }

  /// Splits [text] into utterances that each fit the model's context, breaking after
  /// punctuation where it can and between words where it must.
  List<Utterance> utterances(String text, {int maxTokens = kokoroChunkTokens}) {
    final all = pieces(text);
    final chunks = <List<SpeechPiece>>[];
    var current = <SpeechPiece>[];
    for (final p in all) {
      current.add(p);
      if (assemble(current).phonemes.length <= maxTokens || current.length == 1) continue;
      // Break after punctuation only if what follows still fits; the chunk without the new
      // piece always does.
      final lastBreak = current.lastIndexWhere((q) => !q.isWord && _breakMarks.contains(q.text));
      final tailFits =
          lastBreak >= 0 &&
          lastBreak < current.length - 1 &&
          assemble(current.sublist(lastBreak + 1)).phonemes.length <= maxTokens;
      final cut = tailFits ? lastBreak + 1 : current.length - 1;
      chunks.add(current.sublist(0, cut));
      current = current.sublist(cut);
    }
    if (current.isNotEmpty) chunks.add(current);
    return [
      for (final c in chunks)
        if (c.any((p) => p.isWord)) _truncated(assemble(c), maxTokens),
    ];
  }

  /// A single word longer than the context is cut rather than sent past the model's limit.
  Utterance _truncated(Utterance u, int maxTokens) {
    if (u.phonemes.length <= maxTokens) return u;
    return Utterance(u.phonemes.substring(0, maxTokens), u.words, [
      for (final (a, b) in u.tokenSpans) (min(a, maxTokens), min(b, maxTokens)),
    ]);
  }
}

/// `s` after a voiceless sound, `ɪz` after a hissing one, `z` otherwise.
String _sSuffix(String phonemes) {
  if (phonemes.isEmpty) return 'z';
  final last = phonemes[phonemes.length - 1];
  if ('szʃʒʧʤ'.contains(last)) return 'ɪz';
  if ('ptkfθ'.contains(last)) return 's';
  return 'z';
}

const _ones = [
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];
const _tens = [
  '',
  '',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
];
const _scales = [(1000000000, 'billion'), (1000000, 'million'), (1000, 'thousand')];
const _hundred = 100;
const _ten = 10;
const _teens = 20;

/// Up to hundreds of billions; longer runs are serial numbers, not quantities.
const _maxNumberDigits = 12;

/// English words for a whole number: 144000 is "one hundred forty four thousand".
String numberToWords(int n) {
  if (n < 0) return 'minus ${numberToWords(-n)}';
  if (n < _teens) return _ones[n];
  if (n < _hundred) {
    final rest = n % _ten;
    return rest == 0 ? _tens[n ~/ _ten] : '${_tens[n ~/ _ten]} ${_ones[rest]}';
  }
  for (final (size, name) in [..._scales, (_hundred, 'hundred')]) {
    if (n < size) continue;
    final rest = n % size;
    final head = '${numberToWords(n ~/ size)} $name';
    return rest == 0 ? head : '$head ${numberToWords(rest)}';
  }
  throw StateError('unreachable');
}

/// Letter groups to ARPAbet, longest first. A last resort for words in neither lexicon.
const _letterRules = [
  ('tch', 'CH'),
  ('sch', 'S K'),
  ('igh', 'AY'),
  ('ch', 'CH'),
  ('ph', 'F'),
  ('sh', 'SH'),
  ('th', 'TH'),
  ('ng', 'NG'),
  ('ck', 'K'),
  ('qu', 'K W'),
  ('wh', 'W'),
  ('gh', 'G'),
  ('ee', 'IY'),
  ('ea', 'IY'),
  ('oo', 'UW'),
  ('ai', 'EY'),
  ('ay', 'EY'),
  ('oa', 'OW'),
  ('ou', 'AW'),
  ('ow', 'OW'),
  ('oi', 'OY'),
  ('oy', 'OY'),
  ('au', 'AO'),
  ('aw', 'AO'),
  ('ei', 'EY'),
  ('ie', 'IY'),
  ('a', 'AE'),
  ('e', 'EH'),
  ('i', 'IH'),
  ('o', 'AA'),
  ('u', 'AH'),
  ('y', 'IY'),
  ('b', 'B'),
  ('c', 'K'),
  ('d', 'D'),
  ('f', 'F'),
  ('g', 'G'),
  ('h', 'HH'),
  ('j', 'JH'),
  ('k', 'K'),
  ('l', 'L'),
  ('m', 'M'),
  ('n', 'N'),
  ('p', 'P'),
  ('q', 'K'),
  ('r', 'R'),
  ('s', 'S'),
  ('t', 'T'),
  ('v', 'V'),
  ('w', 'W'),
  ('x', 'K S'),
  ('z', 'Z'),
];
const _vowelPhones = {'AE', 'EH', 'IH', 'AA', 'AH', 'IY', 'EY', 'UW', 'OW', 'AW', 'OY', 'AO', 'AY'};

/// Spelling-based phonemes with stress on the first vowel.
// ponytail: naive letter rules; a trained grapheme-to-phoneme model if names outside both
// lexicons turn out to be common.
String letterRulePhonemes(String raw) {
  var w = raw.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  if (w.length > 2 && w.endsWith('e') && !w.endsWith('ee')) w = w.substring(0, w.length - 1);
  final phones = <String>[];
  var i = 0;
  while (i < w.length) {
    final (letters, arpa) = _letterRules.firstWhere((r) => w.startsWith(r.$1, i));
    final doubled =
        letters.length == 1 && i > 0 && w[i - 1] == letters && !'aeiou'.contains(letters);
    if (!doubled) phones.addAll(arpa.split(' '));
    i += letters.length;
  }
  final marked = <String>[];
  var stressed = false;
  for (final p in phones) {
    if (!_vowelPhones.contains(p)) {
      marked.add(p);
      continue;
    }
    marked.add('$p${stressed ? 0 : 1}');
    stressed = true;
  }
  return marked.isEmpty ? '' : arpabetToKokoro(marked.join(' '));
}

/// When each word is spoken, in milliseconds from the start of the audio.
class WordTiming {
  final String word;
  final int startMs;
  final int endMs;

  /// Offsets of the word in the source text, for highlighting it.
  final int sourceStart;
  final int sourceEnd;
  const WordTiming(this.word, this.startMs, this.endMs, this.sourceStart, this.sourceEnd);

  Map<String, Object> toJson() => {'word': word, 'startMs': startMs, 'endMs': endMs};
}

/// Kokoro predicts a duration per input token, pads included. Each is rounded on its own and
/// held to at least one frame, which is how the model sizes its audio: the frame sum times 600
/// equals the waveform length. Words are timed from the frames of their own phonemes, so the
/// pauses between words belong to no word. [offsetSamples] places a later chunk after the ones
/// before it, and ends are held inside [totalSamples] when given.
List<WordTiming> wordTimings(
  Utterance u,
  List<double> durations, {
  int offsetSamples = 0,
  int? totalSamples,
}) {
  final expected = u.phonemes.length + 2;
  if (durations.length != expected) {
    throw ArgumentError('Expected $expected durations, got ${durations.length}.');
  }
  final before = List<int>.filled(durations.length + 1, 0);
  for (var i = 0; i < durations.length; i++) {
    before[i + 1] = before[i] + max(1, durations[i].round());
  }
  int ms(int frame) {
    var samples = offsetSamples + frame * kokoroSamplesPerFrame;
    if (totalSamples != null) samples = min(samples, offsetSamples + totalSamples);
    return samples * _msPerSecond ~/ kokoroSampleRate;
  }

  return [
    for (var w = 0; w < u.words.length; w++)
      WordTiming(
        u.words[w].text,
        ms(before[u.tokenSpans[w].$1 + 1]),
        ms(before[u.tokenSpans[w].$2 + 1]),
        u.words[w].start,
        u.words[w].end,
      ),
  ];
}

/// Samples the model will produce for [durations]: the rounded frame sum times 600.
int expectedSamples(List<double> durations) =>
    durations.fold<int>(0, (sum, d) => sum + max(1, d.round())) * kokoroSamplesPerFrame;

/// The style row for an utterance of [tokenCount] tokens, pads excluded. A voice file holds
/// one 256-float row per length.
Float32List styleFor(Float32List voice, int tokenCount) {
  final rows = voice.length ~/ kokoroStyleDim;
  if (rows == 0 || voice.length % kokoroStyleDim != 0) {
    throw const FormatException('That is not a Kokoro voice file.');
  }
  final row = tokenCount.clamp(0, rows - 1);
  return Float32List.sublistView(voice, row * kokoroStyleDim, (row + 1) * kokoroStyleDim);
}

const _wavHeaderBytes = 44;
const _pcmMax = 32767;
const _bitsPerSample = 16;
const _bytesPerSample = 2;
const _fmtChunkBytes = 16;
const _pcmFormat = 1;
const _monoChannels = 1;

/// Mono 16-bit PCM WAV bytes for [samples] in -1..1.
Uint8List wavBytes(Float32List samples, {int sampleRate = kokoroSampleRate}) {
  final dataBytes = samples.length * _bytesPerSample;
  final b = ByteData(_wavHeaderBytes + dataBytes);
  void tag(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, _wavHeaderBytes - 8 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, _fmtChunkBytes, Endian.little);
  b.setUint16(20, _pcmFormat, Endian.little);
  b.setUint16(22, _monoChannels, Endian.little);
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * _bytesPerSample, Endian.little);
  b.setUint16(32, _bytesPerSample, Endian.little);
  b.setUint16(34, _bitsPerSample, Endian.little);
  tag(36, 'data');
  b.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final x = samples[i];
    final v = x.isNaN ? 0 : (x.clamp(-1.0, 1.0) * _pcmMax).round();
    b.setInt16(_wavHeaderBytes + i * _bytesPerSample, v, Endian.little);
  }
  return b.buffer.asUint8List();
}
