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
  'and', 'the', 'in', 'on', 'to', 'for', 'from', 'with', 'like', 'as', 'of', 'that', 'who', //
  'my', 'your', 'his', 'her', 'its', 'our', 'their', 'me', 'you', 'him', 'it', 'us', 'them',
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

/// Base Strong's numbers for each word of a BSB verse, from the BSB translation tables, in the
/// order of [verseWordPattern]: '' for a word the translators supplied with no original behind
/// it. [phrases] are the table's (English, Strong's) rows for the verse in English order. Words
/// are matched in order within a short window, so a phrase the table words a little differently
/// from the verse text leaves only its own words empty.
List<String> alignBsbWords(String verse, List<(String, String)> phrases) {
  String norm(String w) => w.toLowerCase().replaceAll('’', "'");
  final words = [for (final m in verseWordPattern.allMatches(verse)) norm(m[0]!)];
  final codes = List.filled(words.length, '');
  var next = 0;
  for (final (english, code) in phrases) {
    final base = code.isEmpty ? '' : strongsBase(code);
    for (final m in verseWordPattern.allMatches(english)) {
      final w = norm(m[0]!);
      for (var j = next; j < words.length && j < next + _alignWindow; j++) {
        if (words[j] == w) {
          codes[j] = base;
          next = j + 1;
          break;
        }
      }
    }
  }
  return codes;
}

/// The BSB translation tables (bsb_tables.tsv from bereanbible.com) as (English, Strong's) rows
/// per verse, in English order. Rows the BSB leaves untranslated ("-") are dropped; a row with
/// English and no number is a word the translators supplied.
Map<Ref, List<(String, String)>> parseBsbTables(String tsv) {
  final lines = tsv.split('\n');
  final header = lines.first.split('\t').map((h) => h.trim()).toList();
  int col(String name) {
    final i = header.indexOf(name);
    if (i < 0) throw FormatException('bsb_tables has no "$name" column');
    return i;
  }

  final sortCol = col('BSB Sort'), verseCol = col('Verse'), idCol = col('VerseId');
  final hebCol = col('Str Heb'), grkCol = col('Str Grk'), englishCol = col('BSB version');
  final refs = <String, Ref>{};
  final rows = <String, List<(int, String, String)>>{};
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
    if (english.isEmpty || english == '-') continue;
    final code = c[hebCol].isNotEmpty
        ? 'H${c[hebCol]}'
        : (c[grkCol].isNotEmpty ? 'G${c[grkCol]}' : '');
    rows.putIfAbsent(verse, () => []).add((int.tryParse(c[sortCol]) ?? 0, english, code));
  }
  return {
    for (final e in rows.entries)
      if (refs[e.key] case final ref?)
        ref: [for (final r in e.value..sort((a, b) => a.$1.compareTo(b.$1))) (r.$2, r.$3)],
  };
}

/// How far ahead of the last matched word the next table word is looked for.
const _alignWindow = 4;

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
