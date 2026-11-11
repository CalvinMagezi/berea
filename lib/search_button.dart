import 'package:flutter/material.dart';

import 'brand/lamp_mark.dart';
import 'theme.dart';

const searchCircle = 60.0;
const searchRing = 4.0;
const searchButtonSize = searchCircle + searchRing * 2;
const _markScale = 0.62;
const _selectedRing = 2.5;
const _hairline = 1.0;

/// The Berea mark in a Night circle, raised in the middle of the phone bar: the button for Search.
/// A surface disc cuts the circle from the bar; selected, its edge turns gold.
class SearchButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onPressed;
  const SearchButton({super.key, required this.selected, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Search',
      onTap: onPressed,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: searchButtonSize,
        child: DecoratedBox(
          key: const ValueKey('search-circle'),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.surface,
            border: selected ? Border.all(color: scheme.primary, width: _selectedRing) : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(searchRing),
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
                    size: searchCircle * _markScale,
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
