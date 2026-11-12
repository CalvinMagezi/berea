import 'package:berea/mark_spans.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _red = TextStyle(color: Color(0xFFB00020));
const _text = '“Let it be so now,” Jesus replied.';

String _show(List<InlineSpan> spans) => [
  for (final s in spans.cast<TextSpan>())
    if (s.style?.color != null && s.style?.fontStyle == FontStyle.italic)
      '[red+italic:${s.text}]'
    else if (s.style?.color != null)
      '[red:${s.text}]'
    else if (s.style?.fontStyle == FontStyle.italic)
      '[italic:${s.text}]'
    else
      s.text!,
].join();

void main() {
  final spans = <MarkSpan>[
    (kind: MarkKind.red, start: 0, end: 19),
    (kind: MarkKind.supplied, start: 5, end: 7),
  ];

  test('red and italic nest: a supplied word inside red words is both', () {
    expect(
      _show(
        markedText(_text, spans, red: true, supplied: true, redStyle: _red),
      ),
      '[red:“Let ][red+italic:it][red: be so now,”] Jesus replied.',
    );
  });

  test('a switched-off kind leaves its words plain', () {
    expect(
      _show(
        markedText(_text, spans, red: false, supplied: true, redStyle: _red),
      ),
      '“Let [italic:it] be so now,” Jesus replied.',
    );
    expect(
      _show(
        markedText(_text, spans, red: true, supplied: false, redStyle: _red),
      ),
      '[red:“Let it be so now,”] Jesus replied.',
    );
  });

  test('a verse with no marks, or none showing, is its text whole', () {
    for (final out in [
      markedText(_text, const [], red: true, supplied: true, redStyle: _red),
      markedText(_text, spans, red: false, supplied: false, redStyle: _red),
    ]) {
      expect(out, hasLength(1));
      expect((out.single as TextSpan).text, _text);
    }
  });

  test('the pieces always add up to the verse text', () {
    final joined = markedText(
      _text,
      spans,
      red: true,
      supplied: true,
      redStyle: _red,
    ).cast<TextSpan>().map((s) => s.text).join();
    expect(joined, _text);
  });
}
