import 'package:flutter/material.dart';

import 'app_state.dart';
import 'chat_screen.dart';
import 'notebook_chat_screen.dart';
import 'notebook_store.dart';
import 'notebooks_screen.dart';
import 'notes_screen.dart';
import 'reader_screen.dart';

const wideLayoutBreakpoint = 760.0;

enum HomeTab { study, bible, notes, notebooks }

class HomeShell extends StatefulWidget {
  final AppState state;
  const HomeShell({super.key, required this.state});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  var _tab = HomeTab.study;

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

  /// The same study, same history, from any tab.
  void _quickChat() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.92,
        child: ChatScreen(state: widget.state, onClose: () => Navigator.pop(ctx)),
      ),
    );
  }

  Widget? get _fab => _tab != HomeTab.notes
      ? null
      : FloatingActionButton(
          tooltip: 'Ask Berea',
          onPressed: _quickChat,
          child: const Icon(Icons.chat_bubble_outline),
        );

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

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final body = IndexedStack(
      index: _tab.index,
      children: [
        ChatScreen(state: s),
        ReaderScreen(state: s, onQuickChat: _quickChat),
        NotesScreen(state: s, onOpenStudy: () => _select(HomeTab.study)),
        NotebooksScreen(store: s.notebooks, lookup: _lookup, onChat: _openNotebookChat),
      ],
    );
    const destinations = [
      (Icons.auto_stories_outlined, Icons.auto_stories, 'Study'),
      (Icons.menu_book_outlined, Icons.menu_book, 'Bible'),
      (Icons.sticky_note_2_outlined, Icons.sticky_note_2, 'Notes'),
      (Icons.collections_bookmark_outlined, Icons.collections_bookmark, 'Notebooks'),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= wideLayoutBreakpoint) {
          return Scaffold(
            floatingActionButton: _fab,
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _tab.index,
                  onDestinationSelected: (i) => _select(HomeTab.values[i]),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in destinations)
                      NavigationRailDestination(
                        icon: Icon(d.$1),
                        selectedIcon: Icon(d.$2),
                        label: Text(d.$3),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          floatingActionButton: _fab,
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab.index,
            onDestinationSelected: (i) => _select(HomeTab.values[i]),
            destinations: [
              for (final d in destinations)
                NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
            ],
          ),
        );
      },
    );
  }
}
