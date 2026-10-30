import 'dart:math';

import 'bible_db.dart';
import 'ref_parser.dart';

/// Word studies: from an English word the reader pressed to the Hebrew or Greek word behind it,
/// and from that word to everywhere else it is used. Everything here is keyed by the base Strong's
/// number (H8549, not H8549G), so a word's senses are counted as one word.

final _nonLetters = RegExp(r'[^a-z]');
final _token = RegExp(r'[A-Za-z]+');
final _bracketed = RegExp(r'\[[^\]]*\]|<[^>]*>');
final _strongsInText = RegExp(r'\b([HG])(\d{1,4})([A-Za-z])?\b');
final _strongsSuffix = RegExp(r'[A-Za-z]$');

/// Hebrew prefixes and suffixes (the, and, in, his) carry STEP codes from H9001 up. They are
/// grammar, not words to study.
bool isParticleCode(String code) => code.startsWith('H9');

/// H8549G and H8549 become H8549; G25 becomes G0025.
String strongsBase(String code) {
  final m = _strongsInText.firstMatch(code.trim());
  if (m == null) return code.trim().replaceAll(_strongsSuffix, '');
  return '${m[1]}${m[2]!.padLeft(4, '0')}';
}

/// The base Strong's number a word is studied by: its first code that is not a particle, or its
/// first code when it is only a particle. Null when the word has no code.
String? studyCode(WordTag w) {
  final codes = w.strongs.split(' ').where((c) => c.isNotEmpty).toList();
  if (codes.isEmpty) return null;
  return strongsBase(codes.firstWhere((c) => !isParticleCode(c), orElse: () => codes.first));
}

/// The first Strong's number written in [text], as a base code, or null.
String? strongsIn(String text) {
  final m = _strongsInText.firstMatch(text);
  return m == null ? null : '${m[1]}${m[2]!.padLeft(4, '0')}';
}

/// A light English stem, enough to match "loved", "loves" and "loving" to "love", and a verse's
/// "perfect" to a gloss's "perfected" only when they really share it. Not Porter: glosses are
/// short and a stem that over-reaches would match the wrong word in the verse.
String wordStem(String word) {
  var w = word.toLowerCase().replaceAll('\u2019', "'").replaceAll("'s", '');
  w = w.replaceAll(_nonLetters, '');
  w = _irregular[w] ?? w;
  if (w.length <= 3) return w;
  if (w.endsWith('ies') || w.endsWith('ied')) return '${w.substring(0, w.length - 3)}y';
  var cut = false;
  if (w.endsWith('sses')) {
    w = w.substring(0, w.length - 2);
  } else if (w.endsWith('es') && w.length > 4) {
    w = w.substring(0, w.length - 1);
  } else if (w.endsWith('s') && !w.endsWith('ss') && !w.endsWith('us') && !w.endsWith('is')) {
    w = w.substring(0, w.length - 1);
  }
  // The KJV's "taketh" and "didst" are "take" and "did".
  if (w.endsWith('eth') && w.length > 5) {
    w = w.substring(0, w.length - 3);
    cut = true;
  } else if (w.endsWith('est') && w.length > 6) {
    w = w.substring(0, w.length - 3);
    cut = true;
  } else if (w.endsWith('ing') && w.length > 5) {
    w = w.substring(0, w.length - 3);
    cut = true;
  } else if (w.endsWith('ed') && w.length > 4) {
    w = w.substring(0, w.length - 2);
    cut = true;
  } else if (w.endsWith('ly') && w.length > 5) {
    w = w.substring(0, w.length - 2);
  }
  // "stopped" and "running" lose the doubled letter; "called" and "blessed" keep theirs.
  if (cut && w.length > 3) {
    final a = w[w.length - 1], b = w[w.length - 2];
    if (a == b && !'lsz'.contains(a) && !'aeiou'.contains(a)) w = w.substring(0, w.length - 1);
  }
  if (w.endsWith('e') && w.length > 3) w = w.substring(0, w.length - 1);
  return w;
}

/// Plurals and verb forms no suffix rule reaches, common in Scripture.
const _irregular = {
  'children': 'child',
  'men': 'man',
  'women': 'woman',
  'brethren': 'brother',
  'feet': 'foot',
  'teeth': 'tooth',
  'oxen': 'ox',
  'mice': 'mouse',
  'geese': 'goose',
  'hath': 'have',
  'hast': 'have',
  'has': 'have',
  'had': 'have',
  'doth': 'do',
  'dost': 'do',
  'didst': 'did',
  'art': 'are',
  'wast': 'was',
  'shalt': 'shall',
  'wilt': 'will',
};

/// Stems of the words in a gloss. With [implied], words STEP marks as supplied by the translator
/// (`[the] land`, `<of> God`) are kept too.
Set<String> glossStems(String gloss, {bool implied = false}) {
  final text = implied ? gloss : gloss.replaceAll(_bracketed, ' ');
  return {for (final m in _token.allMatches(text)) wordStem(m[0]!)}..remove('');
}

/// A gloss as a reader would say it: no translator brackets, no leading article or trailing "of",
/// and for a Hebrew word with a prefix or suffix ("and/ upright", "god/ your") only the part that
/// is the word itself, found by lining the parts up with [strongs].
String cleanGloss(String gloss, {String strongs = ''}) {
  final parts = [
    for (final p in gloss.replaceAll(_bracketed, ' ').split('/'))
      p
          .replaceAll(RegExp(r'[^A-Za-z\s-]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .toLowerCase(),
  ];
  final codes = strongs.split(' ').where((c) => c.isNotEmpty).toList();
  final word = codes.indexWhere((c) => !isParticleCode(c));
  var part = codes.length == parts.length && word >= 0 ? parts[word] : '';
  if (part.isEmpty) {
    // Unaligned, the longest part that is not a prefix or suffix ("your", "for") is the word.
    final words = parts.where((p) => !_affixes.contains(p)).toList();
    for (final p in words.isEmpty ? parts : words) {
      if (p.length > part.length) part = p;
    }
  }
  return part.replaceFirst(RegExp(r'^(a|an|the|o) '), '').replaceFirst(RegExp(r' of$'), '');
}

/// What Hebrew prefixes and suffixes are glossed as.
const _affixes = {
  'and',
  'the',
  'in',
  'on',
  'to',
  'for',
  'from',
  'with',
  'like',
  'as',
  'of',
  'that',
  'who', //
  'my',
  'your',
  'his',
  'her',
  'its',
  'our',
  'their',
  'me',
  'you',
  'him',
  'it',
  'us',
  'them',
};

/// The original word as printed in a verse, without STEP's morpheme marks and pilcrows, and
/// without the Hebrew cantillation accents (U+0591 to U+05AF) that many fonts cannot draw. The
/// vowel points stay.
String cleanOriginal(String original) =>
    original.replaceAll(RegExp(r'[/\\¶.,;:·\u0591-\u05AF]'), '').replaceAll('־', '').trim();

/// The words of a verse, as the reader and the BSB alignment both count them: letters, with an
/// apostrophe inside a word ("king’s") but not around it.
final verseWordPattern = RegExp(r"[A-Za-zÀ-ɏ]+(?:['’][A-Za-zÀ-ɏ]+)*");

/// The word pressed at [offset] in [text]: the word, where it starts, its [index] among the
/// verse's words, and which occurrence of that word (by stem) it is, counting from 0. Null when
/// the offset is not on a word.
({String word, int start, int index, int occurrence})? wordAt(String text, int offset) {
  if (offset < 0 || offset > text.length) return null;
  final words = verseWordPattern.allMatches(text).toList();
  // A press just after a word's last letter, at its right edge, still counts as that word.
  final index = words.indexWhere((m) => m.start <= offset && offset <= m.end);
  if (index < 0) return null;
  final hit = words[index];
  if (offset == hit.end && index + 1 < words.length && words[index + 1].start == offset) {
    return null;
  }
  final stem = wordStem(hit[0]!);
  var occurrence = 0;
  for (final m in words.take(index)) {
    if (wordStem(m[0]!) == stem) occurrence++;
  }
  return (word: hit[0]!, start: hit.start, index: index, occurrence: occurrence);
}

/// One row of the BSB translation tables: the English the translators gave one original word,
/// that word's base Strong's number ('' for English they supplied), and which use of that number
/// it is in the original's word order ([repeat], from 0), to pick among a verse's repeats.
class BsbRow {
  final String english;
  final String code;
  final int repeat;
  const BsbRow(this.english, this.code, [this.repeat = 0]);
}

/// A word of a BSB verse as the tables place it. [rowStart] to [rowEnd] (exclusive) are the verse
/// word indexes of the whole table row the word belongs to: more than one word means the
/// translators gave a phrase ("and said", "Jesus replied") for one original word.
class BsbWord {
  /// Base Strong's number of the original word, '' when none stands behind the English.
  final String code;
  final int repeat;
  final int rowStart;
  final int rowEnd;
  const BsbWord(this.code, this.repeat, this.rowStart, this.rowEnd);

  bool get inPhrase => rowEnd - rowStart > 1;
}

/// The BSB words of a verse placed on the table rows. The verse's words and the rows' English are
/// aligned by content (longest common subsequence), so a row the reader's text lacks, a word the
/// tables lack, or words in a different order leave only those words unplaced and never shift a
/// neighbour. A word the tables supply no original for has the empty code.
List<BsbWord> alignBsbWords(String verse, List<BsbRow> rows) {
  String norm(String w) => w.toLowerCase().replaceAll('’', "'");
  final words = [for (final m in verseWordPattern.allMatches(verse)) norm(m[0]!)];
  final table = <String>[];
  final rowOf = <int>[];
  for (var r = 0; r < rows.length; r++) {
    for (final m in verseWordPattern.allMatches(rows[r].english)) {
      table.add(norm(m[0]!));
      rowOf.add(r);
    }
  }
  final n = words.length, m = table.length;
  final best = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      best[i][j] = words[i] == table[j]
          ? best[i + 1][j + 1] + 1
          : max(best[i + 1][j], best[i][j + 1]);
    }
  }
  final row = List.filled(n, -1);
  for (var i = 0, j = 0; i < n && j < m;) {
    if (words[i] == table[j] && best[i][j] == best[i + 1][j + 1] + 1) {
      row[i++] = rowOf[j++];
    } else if (best[i + 1][j] >= best[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  final placed = <BsbWord>[];
  for (var i = 0; i < n; i++) {
    var start = i, end = i + 1;
    if (row[i] >= 0) {
      while (start > 0 && row[start - 1] == row[i]) {
        start--;
      }
      while (end < n && row[end] == row[i]) {
        end++;
      }
    }
    final r = row[i] < 0 ? null : rows[row[i]];
    placed.add(BsbWord(r?.code ?? '', r?.repeat ?? 0, start, end));
  }
  return placed;
}

/// The BSB translation tables (bsb_tables.tsv from bereanbible.com) as rows per verse, in
/// English order. Rows the BSB leaves untranslated ("-" or blank) are dropped after they have been
/// counted in each number's [BsbRow.repeat]; a row with English and no number is a word the
/// translators supplied.
Map<Ref, List<BsbRow>> parseBsbTables(String tsv) {
  final lines = tsv.split('\n');
  final header = lines.first.split('\t').map((h) => h.trim()).toList();
  int col(String name) {
    final i = header.indexOf(name);
    if (i < 0) throw FormatException('bsb_tables has no "$name" column');
    return i;
  }

  final sortCol = col('BSB Sort'), verseCol = col('Verse'), idCol = col('VerseId');
  final hebSortCol = col('Heb Sort'), grkSortCol = col('Greek Sort');
  final hebCol = col('Str Heb'), grkCol = col('Str Grk'), englishCol = col('BSB version');
  final refs = <String, Ref>{};
  final rows = <String, List<_TableRow>>{};
  for (final line in lines.skip(1)) {
    final c = line.replaceAll('\r', '').split('\t');
    if (c.length <= englishCol) continue;
    final verse = c[verseCol];
    if (c[idCol].isNotEmpty) {
      final ref = RefParser.parse(c[idCol]).firstOrNull;
      if (ref == null) throw FormatException('bsb_tables: unknown verse "${c[idCol]}"');
      refs[verse] = ref;
    }
    final english = c[englishCol].trim();
    final hebrew = c[hebCol].isNotEmpty;
    final code = hebrew ? 'H${c[hebCol]}' : (c[grkCol].isNotEmpty ? 'G${c[grkCol]}' : '');
    // A row with no English and no number is padding; one with a number and no English is an
    // original word the BSB leaves out, and still counts as a use of that word.
    if (english.isEmpty && code.isEmpty) continue;
    rows
        .putIfAbsent(verse, () => [])
        .add(
          _TableRow(
            int.tryParse(c[sortCol]) ?? 0,
            int.tryParse(c[hebrew ? hebSortCol : grkSortCol]) ?? 0,
            english,
            code,
          ),
        );
  }
  return {
    for (final e in rows.entries)
      if (refs[e.key] case final ref?) ref: _bsbRows(e.value),
  };
}

class _TableRow {
  final int sort, original;
  final String english, code;
  _TableRow(this.sort, this.original, this.english, this.code);
}

/// The translated rows of a verse in English order, each numbered by its place among the verse's
/// rows with the same number in the original's order (untranslated rows count, as the original
/// text has the word).
List<BsbRow> _bsbRows(List<_TableRow> all) {
  final byOriginal = [...all]..sort((a, b) => a.original.compareTo(b.original));
  final seen = <String, int>{};
  final repeat = <_TableRow, int>{};
  for (final r in byOriginal) {
    if (r.code.isNotEmpty) repeat[r] = seen.update(r.code, (n) => n + 1, ifAbsent: () => 0) + 1;
  }
  return [
    for (final r in [...all]..sort((a, b) => a.sort.compareTo(b.sort)))
      if (r.english != '-' && r.english.isNotEmpty)
        BsbRow(r.english, r.code.isEmpty ? '' : strongsBase(r.code), (repeat[r] ?? 1) - 1),
  ];
}

/// How well each original word in a verse stands behind [english], best first. STEP's glosses are
/// not aligned to any one translation, so this matches on meaning: the word's own gloss, then its
/// lexicon gloss, then the opening of its lexicon definition (where KJV words such as "perfect"
/// for תָּם usually appear). [occurrence] picks among equal matches, so the second "perfect" in a
/// verse goes to the second word glossed "perfect".
List<int> matchOriginal(
  List<WordTag> words,
  String english, {
  int occurrence = 0,
  LexEntry? Function(String code)? lexicon,
}) {
  final stem = wordStem(english);
  if (stem.isEmpty) return const [];
  final scores = <int, int>{};
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    var score = 0;
    if (glossStems(w.gloss).contains(stem)) {
      score = 4;
    } else if (glossStems(w.gloss, implied: true).contains(stem)) {
      score = 3;
    } else if (lexicon != null) {
      final code = studyCode(w);
      final e = code == null ? null : lexicon(code);
      if (e != null && glossStems(e.gloss).contains(stem)) {
        score = 2;
      } else if (e != null && glossStems(_opening(e.definition)).contains(stem)) {
        score = 1;
      }
    }
    if (score > 0) scores[i] = score;
  }
  if (scores.isEmpty) return const [];
  final best = scores.values.reduce((a, b) => a > b ? a : b);
  final top = [
    for (final e in scores.entries)
      if (e.value == best) e.key,
  ];
  final pick = top[occurrence.clamp(0, top.length - 1)];
  final rest = scores.keys.where((i) => i != pick).toList()
    ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
  return [pick, ...rest];
}

/// What a press on an English word leads to.
enum PressKind {
  /// The BSB translation tables place the word on an original word.
  exact,

  /// Berea matched the word to one of the verse's original words by meaning, so the reader is
  /// asked to check it.
  byMeaning,

  /// The translators added the word; no original word stands behind it.
  supplied,

  /// Berea cannot tell which original word is meant, so the reader chooses from the verse.
  unknown,
}

/// The original word behind a pressed English word: [code] and [tag] when known, and where the
/// BSB tables put the word ([bsb]) when they were used. An [PressKind.unknown] press still names
/// the original word the tables put the English on, for the "Which word?" view.
class PressedWord {
  final PressKind kind;
  final String? code;
  final WordTag? tag;
  final BsbWord? bsb;
  const PressedWord(this.kind, {this.code, this.tag, this.bsb});
}

/// English words that stand for God where the original has none, in the BSB's "the LORD said".
const _divineTitles = {'god', 'lord'};

/// Words that are also the lexicon's names (the king "So", the city "On") but are far more often
/// plain English at the start of a sentence.
final _commonWords = {..._glue, ..._affixes, 'so', 'on', 'no', 'man'};

/// The original word behind [english], the pressed word (its [occurrence] by stem in the verse and
/// its [wordIndex] among the verse's words). In the BSB the translation tables decide, except
/// where they put a name or a title of God on a pronoun or a verb ("Jesus replied" is one Greek
/// verb): that is the BSB's supplied name, not the word, so the press falls back to a match by
/// meaning, or to [PressKind.unknown], and never opens that other word as if it were the name.
PressedWord resolvePress({
  required String english,
  required String translation,
  required List<WordTag> tags,
  required LexEntry? Function(String code) lexicon,
  required bool Function(String word) isName,
  List<BsbWord>? bsb,
  int occurrence = 0,
  int? wordIndex,
}) {
  PressedWord byMeaning(BsbWord? placed) {
    final ranked = matchOriginal(tags, english, occurrence: occurrence, lexicon: lexicon);
    if (ranked.isEmpty) return PressedWord(PressKind.unknown, bsb: placed);
    final tag = tags[ranked.first];
    return PressedWord(PressKind.byMeaning, code: studyCode(tag), tag: tag, bsb: placed);
  }

  final at = wordIndex;
  if (translation != defaultTranslation || bsb == null || at == null || at >= bsb.length) {
    return byMeaning(null);
  }
  final placed = bsb[at];
  if (placed.code.isEmpty) return PressedWord(PressKind.supplied, bsb: placed);
  if (_nameOnOtherWord(english, placed.code, lexicon, isName)) return byMeaning(placed);
  final same = [
    for (final w in tags)
      if (studyCode(w) == placed.code) w,
  ];
  final tag = same.isEmpty ? null : same[placed.repeat.clamp(0, same.length - 1)];
  return PressedWord(PressKind.exact, code: placed.code, tag: tag, bsb: placed);
}

/// True when [english] is a name or a title of God and [code] is a pronoun, verb or the like,
/// which can carry the name only because the BSB wrote it in.
bool _nameOnOtherWord(
  String english,
  String code,
  LexEntry? Function(String code) lexicon,
  bool Function(String word) isName,
) {
  final word = english.replaceFirst(RegExp(r"['’]s$"), '');
  // Names are capitalised; this keeps the lexicon query off every other word.
  if (word.isEmpty || word[0] == word[0].toLowerCase()) return false;
  if (_commonWords.contains(word.toLowerCase())) return false;
  if (!isName(word) && !_divineTitles.contains(word.toLowerCase())) return false;
  final entry = lexicon(code);
  if (entry == null) return false;
  final pos = partOfSpeech(entry.pos);
  return !(pos.startsWith('noun') || pos.startsWith('name') || pos.startsWith('adjective'));
}

/// [resolvePress] for the word pressed in [ref], reading the verse's original words (or [tags], to
/// get the caller's own word objects back), the lexicon and the BSB alignment from [db].
PressedWord pressedStudy(
  BibleDb db,
  Ref ref, {
  required String english,
  required String translation,
  List<WordTag>? tags,
  int occurrence = 0,
  int? wordIndex,
}) => resolvePress(
  english: english,
  translation: translation,
  tags: tags ?? db.words(ref),
  lexicon: db.lexicon,
  isName: db.isName,
  bsb: translation == defaultTranslation ? db.bsbWords(ref) : null,
  occurrence: occurrence,
  wordIndex: wordIndex,
);

/// The first senses of a definition, before its long tail of cross references.
String _opening(String definition) =>
    definition.length > 160 ? definition.substring(0, 160) : definition;

/// Spans of [text] whose words share a stem with [gloss], for marking the word in a verse.
List<(int, int)> glossRanges(String text, String gloss, {String strongs = ''}) {
  final stems = glossStems(cleanGloss(gloss, strongs: strongs))..removeAll(_glue);
  if (stems.isEmpty) return const [];
  return [
    for (final m in _token.allMatches(text))
      if (stems.contains(wordStem(m[0]!))) (m.start, m.end),
  ];
}

/// Small words a gloss often carries ("to perfect", "the man") that would mark half a verse.
const _glue = {'the', 'a', 'an', 'of', 'to', 'and', 'in', 'he', 'his', 'is', 'be', 'was', 'who'};

/// "Hebrew", "Aramaic" or "Greek" for a word, from its code and morphology.
String languageOf(String code, {String morph = ''}) {
  if (code.startsWith('G')) return 'Greek';
  return morph.startsWith('A') ? 'Aramaic' : 'Hebrew';
}

/// STEP's part-of-speech code ("G:A", "H:N-F", "N:N-M-P") in words.
String partOfSpeech(String pos) {
  final i = pos.indexOf(':');
  if (i < 0) return '';
  final lang = pos.substring(0, i);
  final rest = pos.substring(i + 1).split('-');
  if (lang == 'N') {
    // "N:N-M-P" is a man's name, "N:N--L" a place, "N:N--PG" a people.
    return switch (rest.last) {
      'P' => 'name of a person',
      'L' => 'name of a place',
      'PG' => 'name of a people',
      _ => 'name',
    };
  }
  const genders = {'M': ' (masculine)', 'F': ' (feminine)', 'N': ' (neuter)'};
  final gender = rest.length > 1 ? genders[rest[1]] ?? '' : '';
  return switch (rest.first.toUpperCase()) {
    'V' => 'verb',
    'N' => 'noun$gender',
    'A' => 'adjective',
    'ADV' => 'adverb',
    'PREP' => 'preposition',
    'CONJ' => 'conjunction',
    'PRT' => 'particle',
    'INTJ' => 'interjection',
    'INTG' => 'interrogative',
    'COND' => 'conditional',
    _ => '',
  };
}

/// Longest a single sense is shown, cut at a comma so it never ends mid-phrase.
const _senseLength = 140;

/// A lead-in before the first numbered sense is a sense of its own only when it is this short.
const _preambleLength = 60;

final _scriptLetters = RegExp(r'[̀-Ͽἀ-῿֐-׿יִ-ﭏ]+');
final _notes = RegExp(r'\[[^\]]*(\]|$)');
final _cutOff = RegExp(r'\([^)]*$|\.\.\.$');
final _parenthetical = RegExp(r'\([^()]*\)');
final _scriptureRef = RegExp(r'\b[1-3]?[A-Z][a-z]{1,3}\.\s?\d|\bJu\s\d');
final _senseEnd = RegExp(
  r'\s:|:\u2014|;|§|\s\.\s|\s\d+[a-z]\d*\)|\bSYN\b|\b[Cc]f\.|Also (?:means|named)|Aramaic (?:of|equivalent)',
);
final _sentenceEnd = RegExp(r'(?<=[a-z]{3}\.)\s+(?=[A-Z])');
final _leadingGrammar = RegExp(r'^(?:(?:indecl|adv|adj|prep|conj)\.[\s,]*)+');
final _dangling = RegExp(r'\s+(?:at|in|of|see|cf|and|or|from|with|also|as|the|a)$');
final _nameMeaning = RegExp(r'^[^="]{1,30}= "[^"]*"\s*');
final _clPrefix = RegExp(r'^(?:=\s*)?cl\.[\s,]*');
final _romanMarker = RegExp(r'^__[IVX]+\.\s*');

/// Marks of a numbered sense n: Abbott-Smith "__1.", BDB "1)" and Liddell-Scott "1.".
final _senseMarkers = <RegExp Function(int)>[
  (n) => RegExp('__\\s?$n\\.'),
  (n) => RegExp('(?:^|\\s)$n\\)\\s'),
  (n) => RegExp('(?:^|\\s)$n\\.\\s'),
];

/// The senses of a lexicon definition in plain words, at most [max]: no Scripture references, Greek
/// or Hebrew script, grammar notes, LXX remarks or sense markers. Abbott-Smith, BDB and Liddell-
/// Scott numbering all split into senses; a definition with no numbering is one sense. Empty when
/// nothing readable is left, so the caller can fall back to the gloss alone.
List<String> plainSenses(String definition, {int max = 4}) {
  var text = definition.replaceAll(_notes, ' ').replaceAll(_cutOff, ' ');
  for (var again = true; again;) {
    final next = text.replaceAll(_parenthetical, ' ');
    again = next != text;
    text = next;
  }
  text = text.replaceAll(_scriptLetters, ' ');
  final numbered = _splitNumbered(text);
  final parts = numbered == null
      ? [text]
      : [
          if (_sense(numbered.first, lead: true) case final lead?
              when lead.length <= _preambleLength)
            numbered.first,
          ...numbered.skip(1),
        ];
  final senses = <String>[];
  for (final part in parts) {
    final sense = _sense(part);
    if (sense != null && !senses.contains(sense)) senses.add(sense);
  }
  return senses.take(max).toList();
}

/// [text] cut at its numbered senses: the lead-in before sense 1, then each sense; null when the
/// text is not numbered.
List<String>? _splitNumbered(String text) {
  for (final marker in _senseMarkers) {
    final cuts = <RegExpMatch>[];
    for (var n = 1; ; n++) {
      final m = marker(n).allMatches(text, cuts.isEmpty ? 0 : cuts.last.end).firstOrNull;
      if (m == null) break;
      cuts.add(m);
    }
    if (cuts.isEmpty) continue;
    return [
      text.substring(0, cuts.first.start),
      for (var i = 0; i < cuts.length; i++)
        text.substring(cuts[i].end, i + 1 < cuts.length ? cuts[i + 1].start : text.length),
    ];
  }
  return null;
}

/// One sense in plain words from a piece of definition, or null when it is not readable. A
/// [lead] is the text before sense 1, which is a sense only when it is a clause that ends.
String? _sense(String part, {bool lead = false}) {
  var s = part
      .replaceAll(RegExp(r'[†*]|__\(?\w+\)?'), ' ')
      .replaceAll(_romanMarker, '')
      .replaceFirst(RegExp(r'^[\s,;:.\-]*By meton\.?'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s*,(\s*,)+'), ',')
      .replaceAll(' ,', ',')
      .replaceFirst(RegExp(r'^[\s,;:.\-]+'), '')
      .replaceFirst(_leadingGrammar, '')
      .replaceFirst(_clPrefix, '')
      .replaceFirst(_nameMeaning, '')
      .replaceFirst(RegExp(r'\s(?:adj|adv)$'), '')
      .trim();
  for (final stop in [_scriptureRef, _senseEnd]) {
    final m = stop.firstMatch(s);
    if (m != null) s = _withoutTail(s.substring(0, m.start));
  }
  if (lead && s.endsWith(',')) return null;
  s = s.split(_sentenceEnd).first.replaceFirst(RegExp(r'[\s,;:.\-]+$'), '');
  if (s.length > _senseLength) s = _withoutTail(s.substring(0, s.lastIndexOf(',', _senseLength)));
  if (s.length < 3 || s.contains(RegExp(r'\d'))) return null;
  return s[0].toUpperCase() + s.substring(1);
}

/// [s] without a clause left hanging by a cut ("only mentioned at"): its last comma clause goes
/// when it ends on a word that needs a following one.
String _withoutTail(String s) {
  final t = s.replaceFirst(RegExp(r'[\s,;:.\-]+$'), '');
  if (!_dangling.hasMatch(t)) return t;
  final comma = t.lastIndexOf(',');
  return comma < 0 ? t.replaceFirst(_dangling, '') : t.substring(0, comma);
}

/// The question a word study sends to the chat. It names the Strong's number, which the retriever
/// reads to put the lexicon entry and other uses of the word in front of the model. Without [ref]
/// it asks about the word across Scripture, as for a word reached from another word's study.
String wordStudyQuestion({
  required LexEntry entry,
  required String language,
  String? english,
  Ref? ref,
}) {
  final word =
      '$language word ${entry.lemma} (${entry.translit}, ${strongsBase(entry.key)}), '
      '"${entry.gloss}"';
  final opening = ref == null
      ? 'Word study: the $word.'
      : 'Word study: ${english == null ? 'the word' : '"$english"'} in ${ref.label} is the $word.';
  return '$opening What does it mean, how is it used ${ref == null ? 'in' : 'elsewhere in'} '
      'Scripture, and what does it teach me?';
}
