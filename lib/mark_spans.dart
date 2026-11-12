import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/painting.dart';

/// The verse text cut at every edge of a mark, each piece styled by the marks it lies inside:
/// [redStyle] for the words of Jesus the BSB publisher prints in red, italic for the words the
/// translators supplied. Marks the reader has switched off, and a verse without any, give the
/// text whole.
List<InlineSpan> markedText(
  String text,
  List<MarkSpan> spans, {
  required bool red,
  required bool supplied,
  required TextStyle redStyle,
}) {
  final shown = [
    for (final s in spans)
      if (s.kind == MarkKind.red ? red : supplied) s,
  ];
  if (shown.isEmpty) return [TextSpan(text: text)];
  final edges = {0, text.length};
  for (final s in shown) {
    edges
      ..add(s.start.clamp(0, text.length))
      ..add(s.end.clamp(0, text.length));
  }
  final cuts = edges.toList()..sort();
  return [
    for (var i = 0; i + 1 < cuts.length; i++)
      TextSpan(
        text: text.substring(cuts[i], cuts[i + 1]),
        style: _styleAt(shown, cuts[i], redStyle),
      ),
  ];
}

TextStyle? _styleAt(List<MarkSpan> spans, int at, TextStyle redStyle) {
  var style = const TextStyle();
  var any = false;
  for (final s in spans) {
    if (at < s.start || at >= s.end) continue;
    any = true;
    style = s.kind == MarkKind.red
        ? style.merge(redStyle)
        : style.merge(const TextStyle(fontStyle: FontStyle.italic));
  }
  return any ? style : null;
}
