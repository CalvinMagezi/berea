import 'package:flutter/material.dart';

import 'app_state.dart';
import 'chat_screen.dart';
import 'notes_screen.dart';
import 'reader_screen.dart';

const wideLayoutBreakpoint = 760.0;

enum HomeTab { study, bible, notes }

class HomeShell extends StatefulWidget {
  final AppState state;
  const HomeShell({super.key, required this.state});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  var _tab = HomeTab.study;

  @override
  void initState() {
    super.initState();
    widget.state.pendingQuestion.addListener(_jumpToStudy);
  }

  @override
  void dispose() {
    widget.state.pendingQuestion.removeListener(_jumpToStudy);
    super.dispose();
  }

  void _jumpToStudy() {
    if (widget.state.pendingQuestion.value != null) _select(HomeTab.study);
  }

  void _select(HomeTab t) => setState(() => _tab = t);

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final body = IndexedStack(
      index: _tab.index,
      children: [
        ChatScreen(state: s),
        ReaderScreen(state: s),
        NotesScreen(state: s, onOpenStudy: () => _select(HomeTab.study)),
      ],
    );
    const destinations = [
      (Icons.auto_stories_outlined, Icons.auto_stories, 'Study'),
      (Icons.menu_book_outlined, Icons.menu_book, 'Bible'),
      (Icons.sticky_note_2_outlined, Icons.sticky_note_2, 'Notes'),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= wideLayoutBreakpoint) {
          return Scaffold(
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
