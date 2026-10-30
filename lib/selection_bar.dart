import 'package:flutter/material.dart';

import 'brand/lamp_mark.dart';
import 'brand/prayer_icon.dart';

/// Space between the phone card and the five-place bar, so the raised Study button never covers
/// an action.
const selectionBarGap = 24.0;

const _actionMin = 48.0;
const _iconSize = 20.0;
const _labelSize = 12.0;
const _cardRadius = 16.0;
const _cardElevation = 3.0;

enum _More { words, commentary, studyPage, copy, share }

/// What a selection of verses can do: Highlight, Note, Pray, Ask and More on a phone card; on a
/// wide screen a toolbar with Words and Commentary out of More.
class SelectionBar extends StatelessWidget {
  final String label;

  /// How many verses are selected, shown beside the label when more than one.
  final int count;
  final bool wide;
  final VoidCallback onHighlight;
  final VoidCallback onNote;
  final VoidCallback onPray;
  final VoidCallback onAsk;
  final VoidCallback onWords;
  final VoidCallback onCommentary;
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
    required this.onAsk,
    required this.onWords,
    required this.onCommentary,
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
      _Action(
        label: 'Ask',
        icon: LampMark(size: _iconSize, ink: scheme.onSurface, flame: scheme.primary),
        onTap: onAsk,
      ),
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
    return Material(
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
                            label: Text('Study notebook: $section', overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _moreButton() => Builder(
    builder: (context) => PopupMenuButton<_More>(
      tooltip: 'More',
      onSelected: (m) => switch (m) {
        _More.words => onWords(),
        _More.commentary => onCommentary(),
        _More.studyPage => onStudyPage(),
        _More.copy => onCopy(),
        _More.share => onShare(context),
      },
      itemBuilder: (_) => [
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
