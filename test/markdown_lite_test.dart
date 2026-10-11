import 'package:berea/markdown_lite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders headings, lists and inline emphasis', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownLite(
            '## The Word\n\n1. **Divine Agency:** God acts.\n- a bullet\nPlain *italic* line',
          ),
        ),
      ),
    );
    expect(find.text('The Word'), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('•'), findsOneWidget);
    expect(find.textContaining('Divine Agency:'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('*italic*'), findsNothing);
    expect(find.textContaining('italic'), findsOneWidget);
  });
}
