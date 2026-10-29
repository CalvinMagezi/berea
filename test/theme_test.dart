import 'package:berea/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2 contrast ratio.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

const _smallTextRatio = 4.5;
const _highlightAlpha = 0.18;

void main() {
  for (final brightness in Brightness.values) {
    group('${brightness.name} theme', () {
      final scheme = bereaTheme(brightness).colorScheme;
      final raised = scheme.surfaceContainerHighest;

      test('primary text holds 4.5:1 on every ground it sits on', () {
        final washed = Color.alphaBlend(
          scheme.primary.withValues(alpha: _highlightAlpha),
          scheme.surface,
        );
        expect(_contrast(scheme.primary, scheme.surface), greaterThanOrEqualTo(_smallTextRatio));
        expect(_contrast(scheme.primary, raised), greaterThanOrEqualTo(_smallTextRatio));
        expect(_contrast(scheme.primary, washed), greaterThanOrEqualTo(_smallTextRatio));
      });

      test('labels on a primary fill hold 4.5:1', () {
        expect(_contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(_smallTextRatio));
      });

      test('a focused text field draws a visible ring', () {
        final fields = bereaTheme(brightness).inputDecorationTheme;
        final ring = (fields.focusedBorder! as OutlineInputBorder).borderSide;
        final errorRing = (fields.focusedErrorBorder! as OutlineInputBorder).borderSide;
        expect(ring.width, focusRingWidth);
        expect(ring.color, scheme.primary);
        expect(errorRing.color, scheme.error);
        expect(_contrast(ring.color, raised), greaterThanOrEqualTo(3));
        expect(_contrast(ring.color, scheme.surface), greaterThanOrEqualTo(3));
      });
    });
  }
}
