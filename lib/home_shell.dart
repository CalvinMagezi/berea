import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'brand/lamp_mark.dart';
import 'brand/prayer_icon.dart';
import 'chat_screen.dart';
import 'download_details_sheet.dart';
import 'notes_screen.dart';
import 'plans_screen.dart';
import 'prayer_screen.dart';
import 'reader_screen.dart';
import 'setup_screen.dart';
import 'study_button.dart';
import 'theme.dart';

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

/// Sidebar rows keep a full touch target where a finger, not a pointer, taps them.
const _sidebarTouchRow = 48.0;
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
    widget.state.openStudyRequest.addListener(_openStudy);
    widget.state.openPlansRequest.addListener(_openPlans);
    // The Bible is on screen first; the helper loads behind it.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.state.startHelper());
  }

  void _jumpToBible() => _select(HomeTab.bible);

  void _openStudy() => _select(HomeTab.study);

  void _openPlans() => _select(HomeTab.plans);

  /// The microphone stops listening as soon as Berea is not in front.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => widget.state.voice.onLifecycle(state);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.pendingQuestion.removeListener(_jumpToStudy);
    widget.state.openReaderRequest.removeListener(_jumpToBible);
    widget.state.openStudyRequest.removeListener(_openStudy);
    widget.state.openPlansRequest.removeListener(_openPlans);
    _notesRoutes.open.dispose();
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

  /// The Notes place keeps its own pages, so a notebook opens under the bar or beside the
  /// sidebar, as the other places do.
  final _notesNav = GlobalKey<NavigatorState>();
  final _notesRoutes = OpenNotebookObserver();

  void _openNotebook(BuildContext context, int id) {
    _select(HomeTab.notes);
    final nav = _notesNav.currentState;
    if (nav == null) return;
    nav.popUntil((r) => r.isFirst);
    nav.push(notebookRoute(widget.state, id));
  }

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
        PrayerScreen(
          store: s.prayers,
          passage: passageLookupFor(s.db, () => s.settings.translation),
          translation: () => s.settings.translation,
        ),
        NavigatorPopHandler(
          enabled: _tab == HomeTab.notes,
          onPopWithResult: (_) => _notesNav.currentState?.maybePop(),
          child: Navigator(
            key: _notesNav,
            observers: [_notesRoutes],
            // Taking focus while hidden would leave the place shortcuts with nothing focused.
            requestFocus: false,
            onGenerateRoute: (_) =>
                MaterialPageRoute<void>(builder: (_) => NotesScreen(state: s)),
          ),
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
                    ValueListenableBuilder(
                      valueListenable: _notesRoutes.open,
                      builder: (context, open, _) => _Sidebar(
                        state: s,
                        selected: _tab,
                        openNotebook: _tab == HomeTab.notes ? open : null,
                        onSelect: _select,
                        onOpenNotebook: _openNotebook,
                      ),
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
                            // While the helper downloads, the button opens its details.
                            onTap: () => state.helperState is HelperDownloading
                                ? showDownloadDetails(context, state)
                                : onSelect(t),
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
  return '$status · $engine';
}

/// The wide layout: the five places in the same order, notebooks under Notes, the helper below.
class _Sidebar extends StatelessWidget {
  final AppState state;
  final HomeTab selected;

  /// The notebook open in Notes; it is lit in place of the Notes row.
  final int? openNotebook;
  final ValueChanged<HomeTab> onSelect;
  final void Function(BuildContext context, int id) onOpenNotebook;
  const _Sidebar({
    required this.state,
    required this.selected,
    required this.openNotebook,
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
                  ListenableBuilder(
                    listenable: state,
                    builder: (context, _) => _SidebarRow(
                      leading: t == HomeTab.study
                          ? const _SidebarMark()
                          : _placeIcon(t, selected: selected == t),
                      label: _placeLabels[t]!,
                      // Study says what the raised button says: ask Berea, and the helper's state.
                      semanticsLabel: t == HomeTab.study
                          ? studySemanticsLabel(state.helperState, writing: state.answering)
                          : null,
                      shortcut: '${Platform.isMacOS ? '⌘' : 'Ctrl+'}${t.index + 1}',
                      selected: selected == t && (t != HomeTab.notes || openNotebook == null),
                      onTap: () => onSelect(t),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 6),
                  // Read as a word, drawn in capitals.
                  child: Semantics(
                    container: true,
                    header: true,
                    label: _notebooksCaption,
                    excludeSemantics: true,
                    child: Text(_notebooksCaption.toUpperCase(), style: muted),
                  ),
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
                            selected: n.id == openNotebook,
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

const _notebooksCaption = 'Notebooks';

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

  /// What a screen reader hears in place of [label], when it needs more.
  final String? semanticsLabel;
  const _SidebarRow({
    required this.leading,
    required this.label,
    required this.selected,
    required this.onTap,
    this.shortcut,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.surface : scheme.onSurface;
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      onTap: semanticsLabel == null ? null : onTap,
      child: Material(
        color: selected ? scheme.onSurfaceVariant : Colors.transparent,
        borderRadius: BorderRadius.circular(_radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_radius),
          onTap: onTap,
          child: SizedBox(
            height: touch ? _sidebarTouchRow : _sidebarRow,
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
