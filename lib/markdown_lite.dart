import 'package:flutter/material.dart';

/// Renders the small markdown subset the system prompt allows: headings, bullets, numbered
/// lists, bold and italic. Everything else is a paragraph.
class MarkdownLite extends StatelessWidget {
  final String text;
  const MarkdownLite(this.text, {super.key});

  static final _heading = RegExp(r'^(#{1,3})\s+(.*)$');
  static final _bullet = RegExp(r'^\s*[-*]\s+(.*)$');
  static final _numbered = RegExp(r'^\s*(\d+)[.)]\s+(.*)$');
  static final _inline = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyLarge!.copyWith(height: 1.55);
    final children = <Widget>[];
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty) continue;
      final h = _heading.firstMatch(line);
      if (h != null) {
        final level = h[1]!.length;
        children.add(
          Padding(
            padding: EdgeInsets.only(top: level == 1 ? 14 : 10, bottom: 4),
            child: Text(
              h[2]!,
              style: (level == 1 ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)!
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        );
        continue;
      }
      final b = _bullet.firstMatch(line);
      final n = _numbered.firstMatch(line);
      if (b != null || n != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 24, child: Text(b != null ? '•' : '${n![1]}.', style: body)),
                Expanded(child: _inlineText(b?[1] ?? n![2]!, body)),
              ],
            ),
          ),
        );
        continue;
      }
      children.add(
        Padding(padding: const EdgeInsets.only(bottom: 8), child: _inlineText(line, body)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _inlineText(String s, TextStyle style) {
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in _inline.allMatches(s)) {
      if (m.start > cursor) spans.add(TextSpan(text: s.substring(cursor, m.start)));
      if (m[1] != null) {
        spans.add(
          TextSpan(
            text: m[1],
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: m[2],
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      cursor = m.end;
    }
    if (cursor < s.length) spans.add(TextSpan(text: s.substring(cursor)));
    return SelectableText.rich(TextSpan(style: style, children: spans));
  }
}
