import 'bible_db.dart';
import 'ref_parser.dart';
import 'retriever.dart';

class GuardResult {
  final String text;
  final List<Ref> verified;
  final List<Ref> unverified;
  final List<String> unverifiedQuotes;
  const GuardResult(this.text, this.verified, this.unverified, this.unverifiedQuotes);
}

const minQuoteChars = 30;

class CitationGuard {
  final BibleDb db;
  final String translation;
  CitationGuard(this.db, {this.translation = defaultTranslation});

  static const _open = '\u201c';
  static const _close = '\u201d';

  /// Pairs quote marks left to right within a line, so a short quote's closing mark never
  /// becomes the opening of a bogus long one.
  static List<(int, int)> quoteSpans(String s) {
    final spans = <(int, int)>[];
    int? open;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == '\n') {
        open = null;
      } else if (ch == _open || (ch == '"' && open == null)) {
        open = i + 1;
      } else if ((ch == _close || ch == '"') && open != null) {
        spans.add((open, i));
        open = null;
      }
    }
    return spans;
  }

  static final _nonWord = RegExp(r'[^a-z0-9 ]');
  static final _spaces = RegExp(r'\s+');

  static String normalize(String s) =>
      s.toLowerCase().replaceAll(_nonWord, ' ').replaceAll(_spaces, ' ').trim();

  GuardResult apply(String output, StudyContext ctx) {
    final verified = <Ref>{};
    final unverified = <Ref>{};
    final buf = StringBuffer();
    var cursor = 0;
    for (final m in RefParser.matches(output)) {
      buf.write(output.substring(cursor, m.start));
      if (db.exists(m.ref, translation: translation)) {
        verified.add(m.ref);
        buf.write(output.substring(m.start, m.end));
      } else {
        unverified.add(m.ref);
        buf.write('[unverified: ${m.ref.label}]');
      }
      cursor = m.end;
    }
    buf.write(output.substring(cursor));

    final shown = normalize(ctx.allVerses.map((v) => v.text).join(' '));
    final badQuotes = <String>[];
    final withRefs = buf.toString();
    final out = StringBuffer();
    cursor = 0;
    for (final (start, end) in quoteSpans(withRefs)) {
      final quoted = withRefs.substring(start, end);
      if (quoted.length < minQuoteChars || shown.contains(normalize(quoted))) continue;
      badQuotes.add(quoted);
      out.write(withRefs.substring(cursor, end + 1));
      out.write(' [unverified quote]');
      cursor = end + 1;
    }
    out.write(withRefs.substring(cursor));
    final text = out.toString();

    return GuardResult(text, verified.toList(), unverified.toList(), badQuotes);
  }
}
