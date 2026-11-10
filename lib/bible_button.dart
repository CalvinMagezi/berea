import 'package:flutter/material.dart';

import 'brand/lamp_mark.dart';
import 'theme.dart';

const bibleCircle = 60.0;
const bibleRing = 4.0;
const bibleButtonSize = bibleCircle + bibleRing * 2;

/// The brand guide sets the mark at 57.8% of its round mask.
const _markScale = 0.578;
const _selectedRing = 2.5;
const _hairline = 1.0;

/// The Berea mark in a Night circle: the raised button in the middle of the phone bar, which
/// opens the Bible. It shows no state; the mark is not tied to any feature.
class BibleButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onPressed;
  const BibleButton({super.key, required this.selected, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Bible',
      onTap: onPressed,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: bibleButtonSize,
        // A surface disc cuts the circle from the bar; selected, its edge turns gold.
        child: DecoratedBox(
          key: const ValueKey('bible-circle'),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.surface,
            border: selected ? Border.all(color: scheme.primary, width: _selectedRing) : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(bibleRing),
            child: Material(
              color: BereaColors.night,
              shape: CircleBorder(
                side: dark
                    ? const BorderSide(color: BereaColors.linenMuted, width: _hairline)
                    : BorderSide.none,
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: const Center(
                  child: LampMark(
                    size: bibleCircle * _markScale,
                    ink: BereaColors.linen,
                    flame: BereaColors.goldDark,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
