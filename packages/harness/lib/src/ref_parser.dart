import 'books.dart';

class Ref {
  final Book book;
  final int chapter;
  final int? verseStart;
  final int? verseEnd;
  const Ref(this.book, this.chapter, [this.verseStart, this.verseEnd]);

  String get label {
    if (verseStart == null) return '${book.name} $chapter';
    if (verseEnd == null || verseEnd == verseStart) {
      return '${book.name} $chapter:$verseStart';
    }
    return '${book.name} $chapter:$verseStart-$verseEnd';
  }

  /// True when both refer to at least one common verse.
  bool overlaps(Ref o) {
    if (o.book.id != book.id || o.chapter != chapter) return false;
    if (verseStart == null || o.verseStart == null) return true;
    final aEnd = verseEnd ?? verseStart!;
    final bEnd = o.verseEnd ?? o.verseStart!;
    return verseStart! <= bEnd && o.verseStart! <= aEnd;
  }

  @override
  bool operator ==(Object other) =>
      other is Ref &&
      other.book.id == book.id &&
      other.chapter == chapter &&
      other.verseStart == verseStart &&
      other.verseEnd == verseEnd;

  @override
  int get hashCode => Object.hash(book.id, chapter, verseStart, verseEnd);

  @override
  String toString() => label;
}

class RefMatch {
  final Ref ref;
  final int start;
  final int end;
  const RefMatch(this.ref, this.start, this.end);
}

class RefParser {
  /// Every book name, STEP code and alias, longest first so "psalm" wins over "ps".
  static final String _bookAlt = () {
    final keys = <String>{
      for (final b in books) ...[normalizeBookKey(b.name), normalizeBookKey(b.step), ...b.aliases],
      'songofsongs',
    }.toList()..sort((a, b) => b.length.compareTo(a.length));
    return keys.map(_aliasPattern).join('|');
  }();

  /// "1cor" becomes `(?:1|i)\s*cor`, "songofsolomon" becomes `song\s*of\s*solomon`.
  static String _aliasPattern(String key) {
    const numerals = {'1': '(?:1|i)', '2': '(?:2|ii)', '3': '(?:3|iii)'};
    var p = key.replaceFirstMapped(RegExp(r'^([1-3])'), (m) => '${numerals[m[1]]}\\s*');
    p = p.replaceAll('songof', 'song\\s*of\\s*');
    return p;
  }

  static final _re = RegExp(
    '\\b($_bookAlt)\\.?\\s*(\\d{1,3})(?:\\s*[:.]\\s*(\\d{1,3})(?:\\s*[-\\u2013]\\s*(\\d{1,3}))?)?(?!\\d)',
    caseSensitive: false,
  );

  static List<RefMatch> matches(String text) {
    final out = <RefMatch>[];
    for (final m in _re.allMatches(text)) {
      final book = bookFor(m[1]!);
      if (book == null) continue;
      final chapter = int.parse(m[2]!);
      if (chapter == 0) continue;
      final vs = m[3] == null ? null : int.parse(m[3]!);
      var ve = m[4] == null ? null : int.parse(m[4]!);
      if (vs != null && ve != null && ve < vs) ve = vs;
      out.add(RefMatch(Ref(book, chapter, vs, ve), m.start, m.end));
    }
    return out;
  }

  static List<Ref> parse(String text) {
    final seen = <Ref>{};
    return [
      for (final m in matches(text))
        if (seen.add(m.ref)) m.ref,
    ];
  }
}
