import 'books.dart';
import 'prayer_content.dart';
import 'ref_parser.dart';

/// The longest a prayer point may be, so a group can pray it in one breath.
const maxPrayerWords = 20;

/// Verses in each chapter of the BSB, from content/prayers/verse-counts.txt. The BSB is not
/// available to CI, so references are checked against this table instead of the database.
class VerseIndex {
  final Map<String, List<int>> _counts;
  const VerseIndex._(this._counts);

  /// One line per book: its name, then the verse count of each chapter in order.
  factory VerseIndex.parse(String text) {
    final counts = <String, List<int>>{};
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final cut = trimmed.lastIndexOf(RegExp(r'[A-Za-z]')) + 1;
      final name = trimmed.substring(0, cut).trim();
      counts[name] = [for (final n in trimmed.substring(cut).trim().split(' ')) int.parse(n)];
    }
    return VerseIndex._(counts);
  }

  static String render(Map<String, List<int>> counts) =>
      '${[for (final e in counts.entries) '${e.key} ${e.value.join(' ')}'].join('\n')}\n';

  int chapters(Book b) => _counts[b.name]?.length ?? 0;

  /// Why [r] is not in the BSB, or null when it is.
  String? problemWith(Ref r) {
    final counts = _counts[r.book.name];
    if (counts == null || r.chapter < 1 || r.chapter > counts.length) {
      return '${r.label} has no such chapter in the BSB';
    }
    final last = counts[r.chapter - 1];
    final start = r.verseStart;
    if (start == null) return null;
    final end = r.verseEnd ?? start;
    if (start < 1 || end < start || end > last) {
      return '${r.label} is not in the BSB (the chapter has $last verses)';
    }
    return null;
  }
}

/// A rule a line broke. [where] names the file entry so an author can find it.
class PrayerProblem {
  final String where;
  final String message;
  const PrayerProblem(this.where, this.message);

  @override
  String toString() => '$where: $message';
}

/// Parses [label] as exactly one reference with nothing else in it, or returns null.
Ref? parseSingleRef(String label) {
  final matches = RefParser.matches(label.trim());
  if (matches.length != 1) return null;
  final m = matches.first;
  return m.start == 0 && m.end == label.trim().length ? m.ref : null;
}

final _dash = RegExp('[‒-―−]| -- ');
final _emoji = RegExp(
  '[\u{1F000}-\u{1FAFF}\u{2190}-\u{21FF}\u{2300}-\u{23FF}\u{2600}-\u{27BF}'
  '\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]',
  unicode: true,
);

const _relation =
    r'relatives?|neighbou?rs?|villages?|villagers?|uncles?|aunts?|in-laws?|'
    r'kinsm[ae]n|clans?|tribe';
const _hostile =
    r'enem(?:y|ies)|curse[sd]?|destroy|scatter|smite|strike|punish|avenge|'
    r'vengeance|overthrow|perish|die|death|fall|fight|war|against|bind|witch\w*|sorcer\w*';
final _relationRe = RegExp('\\b(?:$_relation)\\b', caseSensitive: false);
final _hostileRe = RegExp('\\b(?:$_hostile)\\b', caseSensitive: false);
final _negatedRelationRe = RegExp(
  '\\b(?:not|never|no)\\b[^.;!?]*\\b(?:$_relation)\\b',
  caseSensitive: false,
);

const _stopVerbs =
    r'stop|stopping|refuse|reject|ignore|skip|abandon|quit|discard|cancel|'
    r'deny|dismiss|disregard|throw away|do not need|no need for|no longer take|do not take';
const _careNouns =
    r'treatment|medicine|medicines|medication|drugs|doctors?|hospital|clinic|'
    r'diagnosis|reports?|test results|scan|surgery|operation|prescription|nurses?';
final _stopCareRe = RegExp(
  '\\b(?:$_stopVerbs)\\b[^.;!?]*\\b(?:$_careNouns)\\b',
  caseSensitive: false,
);

final _fastRe = RegExp(r'\bfast(?:s|ing|ed)?\b', caseSensitive: false);
final _dryFastRe = RegExp(
  r'without water|no water|not even water|nor water|dry fast|neither food nor drink|'
  r'without food or water',
  caseSensitive: false,
);

/// Words that stay capitalised inside a sentence, from content/prayers/proper-words.txt.
Set<String> parseProperWords(String text) => {
  for (final line in text.split('\n'))
    if (line.trim().isNotEmpty && !line.startsWith('#')) line.trim(),
};

final _edgePunctuation = RegExp('^[\\s“”"\'‘’(),.;:!?]+|[\\s“”"\'‘’(),.;:!?]+\$');
final _possessive = RegExp("[’']s\$");

/// The one title with a second capital, which a Bible prayer is called.
final _properPhrase = RegExp("Lord[’']s Prayer");

/// Problems with the case of [text]: a capital inside a sentence on a word that is not a name or
/// a divine title, or a word in capitals.
List<String> caseProblems(String text, Set<String> proper) {
  final out = <String>[];
  var sentenceStart = true;
  for (final raw in text.replaceAll(_properPhrase, 'Lord\'s').split(RegExp(r'\s+'))) {
    final word = raw.replaceAll(_edgePunctuation, '');
    if (word.isNotEmpty) {
      final bare = word.replaceFirst(_possessive, '').split('-').first;
      final capital = RegExp(r'^[A-Z]').hasMatch(bare);
      final shouting = RegExp(r'^[A-Z]{2,}$').hasMatch(bare) && !proper.contains(bare);
      if (sentenceStart && RegExp(r'^[a-z]').hasMatch(bare)) {
        out.add('"$word" should start the sentence with a capital');
      }
      if (shouting) out.add('"$word" is in capitals');
      if (!sentenceStart && capital && !shouting && !proper.contains(bare)) {
        out.add('"$word" is capitalised mid-sentence; add it to proper-words.txt if it is a name');
      }
    }
    sentenceStart = RegExp(r'[.!?]["”’\)]*$').hasMatch(raw);
  }
  return out;
}

/// The mechanical rules every authored line must pass. Meaning is checked by people.
List<String> lineProblems(String text, Set<String> proper, {bool prayer = true}) {
  final out = <String>[];
  if (text.trim().isEmpty) return ['is empty'];
  final words = RegExp(r'\S+').allMatches(text).length;
  if (prayer && words > maxPrayerWords) out.add('has $words words, the limit is $maxPrayerWords');
  if (_dash.hasMatch(text)) out.add('has an em or en dash');
  if (_emoji.hasMatch(text)) out.add('has an emoji or symbol');
  out.addAll(caseProblems(text, proper));
  if (_relationRe.hasMatch(text) &&
      _hostileRe.hasMatch(text) &&
      !_negatedRelationRe.hasMatch(text)) {
    out.add('turns on a relative, neighbour or village');
  }
  if (_stopCareRe.hasMatch(text)) out.add('tells someone to stop treatment or ignore a report');
  if (_fastRe.hasMatch(text)) {
    if (_dryFastRe.hasMatch(text)) out.add('describes a fast without water');
    if (!RegExp('water', caseSensitive: false).hasMatch(text)) {
      out.add('mentions a fast without saying never water');
    }
  }
  return out;
}

/// Problems with one point: its line and its single reference.
List<PrayerProblem> pointProblems(
  String where,
  PrayerPoint p,
  Set<String> proper,
  VerseIndex index, {
  Ref? mustBeIn,
}) {
  final out = [for (final m in lineProblems(p.text, proper)) PrayerProblem(where, m)];
  final ref = parseSingleRef(p.ref);
  if (ref == null) return [...out, PrayerProblem(where, '"${p.ref}" is not one reference')];
  if (ref.verseStart == null) out.add(PrayerProblem(where, '"${p.ref}" needs a verse'));
  final missing = index.problemWith(ref);
  if (missing != null) out.add(PrayerProblem(where, missing));
  if (mustBeIn != null && (ref.book.id != mustBeIn.book.id || ref.chapter != mustBeIn.chapter)) {
    out.add(PrayerProblem(where, '"${p.ref}" is outside ${mustBeIn.label}'));
  }
  return out;
}

/// Every problem in [content] that a build must refuse. [dailyList] is the verse of the day list,
/// each of which needs a line.
List<PrayerProblem> checkPrayerContent(
  PrayerContent content,
  Set<String> proper,
  VerseIndex index, {
  List<String> dailyList = const [],
}) {
  final out = <PrayerProblem>[];
  void line(String where, String text) =>
      out.addAll([for (final m in lineProblems(text, proper)) PrayerProblem(where, m)]);

  final ids = <String>{};
  for (final t in content.topics) {
    if (!ids.add(t.id)) out.add(PrayerProblem(t.id, 'topic id is used twice'));
    line('${t.id} title', t.title);
    final texts = <String>{};
    for (var i = 0; i < t.points.length; i++) {
      final p = t.points[i];
      out.addAll(pointProblems('${t.id}.${i + 1}', p, proper, index));
      if (!texts.add(p.text)) out.add(PrayerProblem('${t.id}.${i + 1}', 'repeats an earlier line'));
    }
  }
  for (final b in content.biblePrayers) {
    line('${b.id} title', b.title);
    final ref = parseSingleRef(b.ref);
    final problem = ref == null ? '"${b.ref}" is not one reference' : index.problemWith(ref);
    if (problem != null) out.add(PrayerProblem(b.id, problem));
  }
  for (final e in content.chapters.entries) {
    final parts = e.key.split('.');
    final chapter = Ref(bookById(int.parse(parts[0])), int.parse(parts[1]));
    for (var i = 0; i < e.value.length; i++) {
      out.addAll(
        pointProblems(
          '${chapter.label} line ${i + 1}',
          e.value[i],
          proper,
          index,
          mustBeIn: chapter,
        ),
      );
    }
  }
  for (final e in content.daily.entries) {
    line('daily ${e.key}', e.value);
    final ref = parseSingleRef(e.key);
    final problem = ref == null ? 'is not one reference' : index.problemWith(ref);
    if (problem != null) out.add(PrayerProblem('daily ${e.key}', problem));
  }
  for (final ref in dailyList) {
    if (!content.daily.containsKey(ref)) out.add(PrayerProblem('daily $ref', 'has no line'));
  }
  for (final plan in content.plans) {
    if (!ids.add(plan.id)) out.add(PrayerProblem(plan.id, 'plan id is used twice'));
    line('${plan.id} title', plan.title);
    line('${plan.id} summary', plan.summary);
    for (var i = 0; i < plan.days.length; i++) {
      final d = plan.days[i];
      final where = '${plan.id} day ${i + 1}';
      line('$where title', d.title);
      final ref = parseSingleRef(d.ref);
      final problem = ref == null ? '"${d.ref}" is not one reference' : index.problemWith(ref);
      if (problem != null) out.add(PrayerProblem(where, problem));
      for (var k = 0; k < d.points.length; k++) {
        out.addAll(pointProblems('$where point ${k + 1}', d.points[k], proper, index));
      }
    }
  }
  out.addAll(_repeats(content));
  line('the fasting note', prayerFastingNote);
  if (!prayerFastingNote.contains('never water') || !prayerFastingNote.contains('health worker')) {
    out.add(
      const PrayerProblem('the fasting note', 'must say never water and ask a health worker'),
    );
  }
  return out;
}

/// A line used twice outside the topics. Topics may share a line, since the same need can be
/// prayed from two places; everywhere else a repeat means a writer copied a line.
List<PrayerProblem> _repeats(PrayerContent content) {
  final seen = <String, String>{};
  final out = <PrayerProblem>[];
  void see(String where, String text) {
    final key = text.toLowerCase();
    final first = seen[key];
    if (first == null) {
      seen[key] = where;
    } else if (!(first.startsWith('topic') && where.startsWith('topic'))) {
      out.add(PrayerProblem(where, 'repeats the line at $first'));
    }
  }

  for (final t in content.topics) {
    for (var i = 0; i < t.points.length; i++) {
      see('topic ${t.id}.${i + 1}', t.points[i].text);
    }
  }
  for (final e in content.chapters.entries) {
    for (final p in e.value) {
      see('chapter ${e.key}', p.text);
    }
  }
  for (final e in content.daily.entries) {
    see('daily ${e.key}', e.value);
  }
  for (final plan in content.plans) {
    for (var d = 0; d < plan.days.length; d++) {
      for (final p in plan.days[d].points) {
        see('${plan.id} day ${d + 1}', p.text);
      }
    }
  }
  return out;
}
