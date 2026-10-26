/// Closing marks that may follow the full stop that ends a sentence.
final _sentenceEnd = RegExp('[.!?]["”\')\\]*_]*(?=\\s|\$)');

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

/// Where the earliest quotation that never closes begins, or null when every one closes.
int? _firstOpenQuote(String text) {
  final curly = <int>[];
  int? straight;
  for (var i = 0; i < text.length; i++) {
    switch (text[i]) {
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
