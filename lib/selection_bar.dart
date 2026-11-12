import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand/prayer_icon.dart';

/// Space between the phone card and the five-place bar, so the raised Study button never covers
/// an action.
const selectionBarGap = 24.0;

const _actionMin = 48.0;
const _iconSize = 20.0;
const _labelSize = 12.0;
const _cardRadius = 16.0;
const _cardElevation = 3.0;

/// How far the phone card follows a sideways drag, and how far it must go to count as a swipe.
const _swipeTravel = 96.0;
const _swipeDistance = 56.0;
const _swipeVelocity = 600.0;
const _swipeReturn = Duration(milliseconds: 180);

enum _More { thisVerse, words, commentary, studyPage, copy, share }

/// What a selection of verses can do: Highlight, Note, Pray and More on a phone card; on a
/// wide screen a toolbar with Words and Commentary out of More. On a phone, swiping the card, or
/// anywhere on the reader while verses are selected, right opens Commentary and left opens Words.
class SelectionBar extends StatelessWidget {
  final String label;

  /// How many verses are selected, shown beside the label when more than one.
  final int count;
  final bool wide;
  final VoidCallback onHighlight;
  final VoidCallback onNote;
  final VoidCallback onPray;
  final VoidCallback onWords;
  final VoidCallback onCommentary;
  final VoidCallback onThisVerse;
  final VoidCallback onStudyPage;
  final VoidCallback onCopy;

  /// Given the More button's context, so the share popover can point from it.
  final ValueChanged<BuildContext> onShare;
  final VoidCallback onClear;

  /// The heading of the section selected whole, which can become a study notebook in one tap.
  final String? section;
  final VoidCallback? onStudySection;
  const SelectionBar({
    super.key,
    required this.label,
    required this.count,
    required this.wide,
    required this.onHighlight,
    required this.onNote,
    required this.onPray,
    required this.onWords,
    required this.onCommentary,
    required this.onThisVerse,
    required this.onStudyPage,
    required this.onCopy,
    required this.onShare,
    required this.onClear,
    this.section,
    this.onStudySection,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final study = onStudySection;
    final actions = [
      if (wide && section != null && study != null)
        _Action(
          label: 'Study notebook',
          icon: const Icon(Icons.auto_stories_outlined),
          onTap: study,
        ),
      _Action(
        label: 'Highlight',
        icon: const Icon(Icons.border_color_outlined),
        onTap: onHighlight,
      ),
      _Action(label: 'Note', icon: const Icon(Icons.edit_outlined), onTap: onNote),
      _Action(label: 'Pray', icon: const PrayerIcon(), onTap: onPray),
      if (wide) ...[
        _Action(label: 'Words', icon: const Icon(Icons.translate), onTap: onWords),
        _Action(
          label: 'Commentary',
          icon: const Icon(Icons.library_books_outlined),
          onTap: onCommentary,
        ),
      ],
      _moreButton(),
    ];
    final clear = IconButton(
      tooltip: 'Clear selection',
      icon: const Icon(Icons.close),
      onPressed: onClear,
    );
    final card = Material(
      color: scheme.surfaceContainerHighest,
      elevation: _cardElevation,
      shadowColor: scheme.shadow,
      borderRadius: BorderRadius.circular(_cardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: IconTheme.merge(
          data: IconThemeData(size: _iconSize, color: scheme.primary),
          child: wide
              ? Row(mainAxisSize: MainAxisSize.min, children: [...actions, clear])
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
                          ),
                        ),
                        if (count > 1)
                          Text(
                            '$count verses',
                            style: TextStyle(fontSize: _labelSize, color: scheme.onSurfaceVariant),
                          ),
                        clear,
                      ],
                    ),
                    Row(children: [for (final a in actions) Expanded(child: a)]),
                    if (section != null && study != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: study,
                            icon: const Icon(Icons.auto_stories_outlined),
                            label: Text(
                              'Study notebook: $section',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
    if (wide) return card;
    return _SwipeCard(onRight: onCommentary, onLeft: onWords, child: card);
  }

  Widget _moreButton() => Builder(
    builder: (context) => PopupMenuButton<_More>(
      tooltip: 'More',
      onSelected: (m) => switch (m) {
        _More.thisVerse => onThisVerse(),
        _More.words => onWords(),
        _More.commentary => onCommentary(),
        _More.studyPage => onStudyPage(),
        _More.copy => onCopy(),
        _More.share => onShare(context),
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: _More.thisVerse, child: Text('This verse')),
        if (!wide) ...[
          const PopupMenuItem(value: _More.words, child: Text('Words')),
          const PopupMenuItem(value: _More.commentary, child: Text('Commentary')),
        ],
        const PopupMenuItem(value: _More.studyPage, child: Text('Study page')),
        const PopupMenuItem(value: _More.copy, child: Text('Copy')),
        const PopupMenuItem(value: _More.share, child: Text('Share')),
      ],
      child: _ActionFace(
        label: 'More',
        icon: Icon(Icons.more_vert, color: Theme.of(context).colorScheme.onSurface),
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  const _Action({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: InkWell(
      borderRadius: BorderRadius.circular(_cardRadius / 2),
      onTap: onTap,
      child: _ActionFace(label: label, icon: icon),
    ),
  );
}

/// An icon over its label, at least 48 px each way; the label shrinks rather than wrap.
class _ActionFace extends StatelessWidget {
  final String label;
  final Widget icon;
  const _ActionFace({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: _actionMin, minHeight: _actionMin),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: _labelSize,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Runs [onRight] or [onLeft] when a sideways drag of [dx] ending at [velocity] is a swipe: far
/// enough, or quick in the direction it moved. Shared by the card and the reader around it.
void selectionSwipe(
  double dx,
  double velocity, {
  required VoidCallback onRight,
  required VoidCallback onLeft,
}) {
  final right = dx >= _swipeDistance || (velocity >= _swipeVelocity && dx > 0);
  final left = dx <= -_swipeDistance || (velocity <= -_swipeVelocity && dx < 0);
  if (!right && !left) return;
  HapticFeedback.selectionClick();
  right ? onRight() : onLeft();
}

/// The phone card on a sideways drag, with the action it will open shown in the space it leaves.
class _SwipeCard extends StatefulWidget {
  final VoidCallback onRight;
  final VoidCallback onLeft;
  final Widget child;
  const _SwipeCard({required this.onRight, required this.onLeft, required this.child});

  @override
  State<_SwipeCard> createState() => _SwipeCardState();
}

class _SwipeCardState extends State<_SwipeCard> with SingleTickerProviderStateMixin {
  late final _shift = AnimationController(
    vsync: this,
    lowerBound: -_swipeTravel,
    upperBound: _swipeTravel,
    value: 0,
    duration: _swipeReturn,
  );

  @override
  void dispose() {
    _shift.dispose();
    super.dispose();
  }

  void _end(DragEndDetails d) {
    final dx = _shift.value;
    final v = d.primaryVelocity ?? 0;
    _shift.animateTo(0, curve: Curves.easeOut);
    selectionSwipe(dx, v, onRight: widget.onRight, onLeft: widget.onLeft);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) => _shift.value += d.delta.dx,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: () => _shift.animateTo(0),
      child: AnimatedBuilder(
        animation: _shift,
        child: widget.child,
        builder: (context, card) {
          final dx = _shift.value;
          final reach = (dx.abs() / _swipeDistance).clamp(0.0, 1.0);
          return Stack(
            children: [
              if (dx != 0)
                Positioned.fill(
                  child: Opacity(
                    opacity: reach,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: dx > 0 ? Alignment.centerLeft : Alignment.centerRight,
                        child: dx > 0
                            ? const _SwipeHint(
                                icon: Icons.library_books_outlined,
                                label: 'Commentary',
                              )
                            : const _SwipeHint(icon: Icons.translate, label: 'Words'),
                      ),
                    ),
                  ),
                ),
              Transform.translate(offset: Offset(dx, 0), child: card),
            ],
          );
        },
      ),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SwipeHint({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color),
        Text(
          label,
          style: TextStyle(fontSize: _labelSize, color: color),
        ),
      ],
    );
  }
}
