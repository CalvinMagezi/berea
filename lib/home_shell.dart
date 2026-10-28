import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'brand/lamp_mark.dart';
import 'brand/prayer_icon.dart';
import 'chat_screen.dart';
import 'notebook_chat_screen.dart';
import 'notebook_store.dart';
import 'notebooks_screen.dart';
import 'notes_screen.dart';
import 'plans_screen.dart';
import 'reader_screen.dart';
import 'setup_screen.dart';
import 'study_button.dart';
import 'theme.dart';

const wideLayoutBreakpoint = 760.0;
const sidebarWidth = 232.0;

/// The five places, in the order they appear on the bar and in the sidebar.
enum HomeTab { bible, plans, study, prayer, notes }

const _placeLabels = {
  HomeTab.bible: 'Bible',
  HomeTab.plans: 'Plans',
  HomeTab.study: 'Study',
  HomeTab.prayer: 'Prayer',
  HomeTab.notes: 'Notes',
};

const _raise = 16.0;
const _barHeight = 78.0;
const _pillWidth = 56.0;
const _pillHeight = 32.0;
const _labelGap = 4.0;
const _labelBottom = 8.0;
const _labelSize = 12.0;
const _sidebarRow = 40.0;
const _sidebarIcon = 20.0;
const _sidebarMark = 22.0;
const _statusDot = 8.0;
const _radius = 10.0;

class HomeShell extends StatefulWidget {
  final AppState state;
  const HomeShell({super.key, required this.state});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  var _tab = HomeTab.bible;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.pendingQuestion.addListener(_jumpToStudy);
    widget.state.openReaderRequest.addListener(_jumpToBible);
    // The Bible is on screen first; the helper loads behind it.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.state.startHelper());
  }

  void _jumpToBible() => _select(HomeTab.bible);

  /// The microphone stops listening as soon as Berea is not in front.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => widget.state.voice.onLifecycle(state);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.pendingQuestion.removeListener(_jumpToStudy);
    widget.state.openReaderRequest.removeListener(_jumpToBible);
    super.dispose();
  }

  void _jumpToStudy() {
    if (widget.state.pendingQuestion.value != null) _select(HomeTab.study);
  }

  void _select(HomeTab t) {
    // A hidden Study tab must not keep listening.
    if (t != _tab) widget.state.voice.cancelRecording();
    setState(() => _tab = t);
  }

  late final _lookup = SourceLookup(
    notes: () => widget.state.study.notes(),
    passage: (r) => passageSource(widget.state.db, r, widget.state.settings.translation),
    commentary: (r) => commentarySources(widget.state.commentary.library, r),
    hasCommentary: () => !widget.state.commentary.library.isEmpty,
  );

  void _openNotebookChat(BuildContext context, int notebookId) {
    final s = widget.state;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NotebookChatScreen(
          store: s.notebooks,
          notebookId: notebookId,
          db: s.db,
          translation: () => s.settings.translation,
          commentary: s.commentary.library,
          engineNotice: EngineNotice(state: s),
          chat: s.notebookChat(notebookId),
          engine: s,
          privacyNotice: () => switch (s.offDeviceHost) {
            final host? =>
              'Questions here send sections of your sources to the Ollama server at $host.',
            null => null,
          },
        ),
      ),
    );
  }

  void _openNotebooks(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => NotebooksScreen(
        store: widget.state.notebooks,
        lookup: _lookup,
        onChat: _openNotebookChat,
      ),
    ),
  );

  void _openNotebook(BuildContext context, int id) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => NotebookScreen(
        store: widget.state.notebooks,
        lookup: _lookup,
        notebookId: id,
        onChat: _openNotebookChat,
      ),
    ),
  );

  /// Cmd 1 to Cmd 5 on a Mac, Ctrl elsewhere, in the order of the places.
  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
    ];
    return {
      for (final t in HomeTab.values)
        SingleActivator(digits[t.index], meta: Platform.isMacOS, control: !Platform.isMacOS): () =>
            _select(t),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final body = IndexedStack(
      index: _tab.index,
      children: [
        ReaderScreen(state: s, onQuickChat: () => _select(HomeTab.study)),
        PlansScreen(state: s),
        ChatScreen(state: s),
        const _PrayerPlace(),
        _NotesPlace(
          state: s,
          onOpenStudy: () => _select(HomeTab.study),
          onOpenNotebooks: _openNotebooks,
          onOpenNotebook: _openNotebook,
        ),
      ],
    );
    return CallbackShortcuts(
      bindings: _shortcuts,
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth >= wideLayoutBreakpoint) {
              return Scaffold(
                body: Row(
                  children: [
                    _Sidebar(
                      state: s,
                      selected: _tab,
                      onSelect: _select,
                      onOpenNotebook: _openNotebook,
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                ),
              );
            }
            return Scaffold(
              body: body,
              bottomNavigationBar: _PlaceBar(state: s, selected: _tab, onSelect: _select),
            );
          },
        ),
      ),
    );
  }
}

Widget _placeIcon(HomeTab t, {required bool selected}) => switch (t) {
  HomeTab.bible => Icon(selected ? Icons.book : Icons.book_outlined),
  HomeTab.plans => Icon(selected ? Icons.calendar_today : Icons.calendar_today_outlined),
  HomeTab.prayer => const PrayerIcon(),
  HomeTab.notes => Icon(selected ? Icons.sticky_note_2 : Icons.sticky_note_2_outlined),
  HomeTab.study => const SizedBox.shrink(),
};

/// The phone bar: five equal places with Study raised in the middle, its circle cut from the bar.
class _PlaceBar extends StatelessWidget {
  final AppState state;
  final HomeTab selected;
  final ValueChanged<HomeTab> onSelect;
  const _PlaceBar({required this.state, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    // Checked here, not in the shell, so the keyboard's animation does not rebuild every place.
    if (MediaQuery.viewInsetsOf(context).bottom > 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: _raise + _barHeight + bottom,
      child: Stack(
        children: [
          Positioned.fill(
            top: _raise,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(top: BorderSide(color: scheme.outline.withValues(alpha: 0.3))),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final t in HomeTab.values)
                  Expanded(
                    child: t == HomeTab.study
                        ? _StudyPlace(
                            state: state,
                            selected: selected == t,
                            onTap: () => onSelect(t),
                          )
                        : _Place(tab: t, selected: selected == t, onTap: () => onSelect(t)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

TextStyle _labelStyle(ColorScheme scheme, bool selected) => TextStyle(
  fontSize: _labelSize,
  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
);

class _Place extends StatelessWidget {
  final HomeTab tab;
  final bool selected;
  final VoidCallback onTap;
  const _Place({required this.tab, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = _placeLabels[tab]!;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: _labelBottom),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: _pillWidth,
                height: _pillHeight,
                decoration: BoxDecoration(
                  color: selected ? scheme.onSurfaceVariant : null,
                  borderRadius: BorderRadius.circular(_pillHeight / 2),
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: selected ? scheme.surface : scheme.onSurfaceVariant),
                  child: Center(child: _placeIcon(tab, selected: selected)),
                ),
              ),
              const SizedBox(height: _labelGap),
              Text(label, style: _labelStyle(scheme, selected)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Study's place: the circle and its label are one target, like the other places.
class _StudyPlace extends StatelessWidget {
  final AppState state;
  final bool selected;
  final VoidCallback onTap;
  const _StudyPlace({required this.state, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: _labelBottom),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ListenableBuilder(
              listenable: state,
              builder: (context, _) => StudyButton(
                helper: state.helperState,
                selected: selected,
                writing: state.answering,
                onPressed: onTap,
              ),
            ),
            ExcludeSemantics(
              child: Text(_placeLabels[HomeTab.study]!, style: _labelStyle(scheme, selected)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The helper's state in a sentence for the sidebar footer, such as "Helper ready, Ollama on
/// this Mac".
String helperFooter(AppState s) {
  final words = helperStatusWords(s.helperState);
  final status = '${words[0].toUpperCase()}${words.substring(1)}';
  final engine = switch (s.settings.engine) {
    EngineKind.ollama => switch (s.offDeviceHost) {
      final host? => 'Ollama at $host',
      null => 'Ollama on this $deviceNoun',
    },
    EngineKind.device => s.settings.deviceModel.label,
  };
  return '$status, $engine';
}

/// The wide layout: the five places in the same order, notebooks under Notes, the helper below.
class _Sidebar extends StatelessWidget {
  final AppState state;
  final HomeTab selected;
  final ValueChanged<HomeTab> onSelect;
  final void Function(BuildContext context, int id) onOpenNotebook;
  const _Sidebar({
    required this.state,
    required this.selected,
    required this.onSelect,
    required this.onOpenNotebook,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 1);
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SizedBox(
        width: sidebarWidth,
        child: SafeArea(
          right: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final t in HomeTab.values)
                  _SidebarRow(
                    leading: t == HomeTab.study
                        ? const _SidebarMark()
                        : _placeIcon(t, selected: selected == t),
                    label: _placeLabels[t]!,
                    shortcut: '${Platform.isMacOS ? '⌘' : 'Ctrl+'}${t.index + 1}',
                    selected: selected == t,
                    onTap: () => onSelect(t),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 6),
                  child: Text('NOTEBOOKS', style: muted),
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: state.notebooks,
                    builder: (context, _) => ListView(
                      children: [
                        for (final n in state.notebooks.notebooks())
                          _SidebarRow(
                            leading: const Icon(Icons.class_outlined),
                            label: n.title,
                            selected: false,
                            onTap: () => onOpenNotebook(context, n.id),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                ListenableBuilder(
                  listenable: state,
                  builder: (context, _) => _HelperFooter(state: state),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarMark extends StatelessWidget {
  const _SidebarMark();

  @override
  Widget build(BuildContext context) => Container(
    width: _sidebarMark,
    height: _sidebarMark,
    decoration: const BoxDecoration(color: BereaColors.night, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: const LampMark(
      size: _sidebarMark * 0.7,
      ink: BereaColors.linen,
      flame: BereaColors.goldDark,
    ),
  );
}

class _SidebarRow extends StatelessWidget {
  final Widget leading;
  final String label;
  final String? shortcut;
  final bool selected;
  final VoidCallback onTap;
  const _SidebarRow({
    required this.leading,
    required this.label,
    required this.selected,
    required this.onTap,
    this.shortcut,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.surface : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.onSurfaceVariant : Colors.transparent,
        borderRadius: BorderRadius.circular(_radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_radius),
          onTap: onTap,
          child: SizedBox(
            height: _sidebarRow,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  IconTheme.merge(
                    data: IconThemeData(size: _sidebarIcon, color: fg),
                    child: leading,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (shortcut case final keys?)
                    ExcludeSemantics(
                      child: Text(
                        keys,
                        style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: _labelSize),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HelperFooter extends StatelessWidget {
  final AppState state;
  const _HelperFooter({required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dot = switch (state.helperState) {
      HelperReady() => scheme.primary,
      HelperFailed() => scheme.error,
      _ => scheme.onSurfaceVariant,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          Container(
            width: _statusDot,
            height: _statusDot,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              helperFooter(state),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Interim Prayer place until the prayer list lands.
class _PrayerPlace extends StatelessWidget {
  const _PrayerPlace();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Prayer',
          style: TextStyle(fontFamilyFallback: scriptureFontFallback, fontSize: 24),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme.merge(
                data: IconThemeData(size: 48, color: scheme.onSurfaceVariant),
                child: const PrayerIcon(),
              ),
              const SizedBox(height: 16),
              Text(
                'Your prayer list will live here. It stays on this $deviceNoun and never needs '
                'the helper.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Interim Notes place: the notes, with the notebooks one row above them.
class _NotesPlace extends StatelessWidget {
  final AppState state;
  final VoidCallback onOpenStudy;
  final void Function(BuildContext context) onOpenNotebooks;
  final void Function(BuildContext context, int id) onOpenNotebook;
  const _NotesPlace({
    required this.state,
    required this.onOpenStudy,
    required this.onOpenNotebooks,
    required this.onOpenNotebook,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: SizedBox(
            height: 48,
            child: ListenableBuilder(
              listenable: state.notebooks,
              builder: (context, _) => ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.collections_bookmark_outlined),
                    label: const Text('Notebooks'),
                    onPressed: () => onOpenNotebooks(context),
                  ),
                  for (final n in state.notebooks.notebooks())
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ActionChip(
                        label: Text(n.title),
                        onPressed: () => onOpenNotebook(context, n.id),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: NotesScreen(state: state, onOpenStudy: onOpenStudy),
          ),
        ),
      ],
    );
  }
}
