/// What may follow the mark that ends a sentence: closing quotes and brackets, and markdown. A
/// number and a point at the start of a line is a list marker, not a sentence end.
final _sentenceEnd = RegExp(
  '(?<!^[ \\t]*\\d{1,3})[.!?…]["”’»\')\\]*_]*(?=\\s|\$)',
  multiLine: true,
);

/// [raw] cut back to its last finished sentence, with no quotation left open. An answer that was
/// stopped or hit its length cap ends mid-sentence, and the citation check only sees a quotation
/// that has closed and a reference that is complete: "Romans 8:2" cut from "Romans 8:28" would
/// verify as a different verse. A text that already ends a sentence comes back unchanged.
String withoutUnfinishedSentence(String raw) {
  var text = raw.trimRight();
  while (text.isNotEmpty) {
    final end = _sentenceEnd.allMatches(text).fold<int>(0, (_, m) => m.end);
    if (end == 0) return '';
    text = text.substring(0, end).trimRight();
    final open = _firstOpenQuote(text);
    if (open == null) return text;
    text = text.substring(0, open).trimRight();
  }
  return '';
}

/// Where the earliest quotation that never closes begins, or null when every one closes. A
/// quotation does not run past the end of a line, which is how the citation check reads it too.
int? _firstOpenQuote(String text) {
  final curly = <int>[];
  int? straight;
  for (var i = 0; i < text.length; i++) {
    switch (text[i]) {
      case '\n':
        curly.clear();
        straight = null;
      case '“':
        curly.add(i);
      case '”':
        if (curly.isNotEmpty) curly.removeLast();
      case '"':
        straight = straight == null ? i : null;
    }
  }
  final open = [...curly, ?straight];
  return open.isEmpty ? null : open.reduce((a, b) => a < b ? a : b);
}
