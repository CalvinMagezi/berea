import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'confirm.dart';
import 'practice_store.dart';
import 'search_screen.dart';
import 'step_through_screen.dart';
import 'theme.dart';

/// What the Practice place says it is. Fixed wording from the plan: Berea chooses mechanics only.
const practiceCaption =
    'Things Berea can do with a passage you choose. Berea chose these mechanics. This is not a '
    'list of what Scripture asks.';

const _labelSpacing = 1.4;
const _labelFontSize = 12.0;
const _sectionTopPadding = 20.0;
const _sectionBottomPadding = 8.0;

/// The Practice place with mechanics that run over passages chosen by the reader or their plan.
class PracticeScreen extends StatelessWidget {
  final AppState state;
  const PracticeScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Practice'), actions: [SearchButton(state: state)]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListenableBuilder(
            // Rebuild whenever state or practice sets change.
            listenable: Listenable.merge([state, state.practice]),
            builder: (context, _) {
              final reading = state.todaysReading;
              final currentChapterRef = Ref(
                bookById(state.readerBook),
                state.readerChapter,
              );
              final sets = state.practice.sets();
              final highlights = state.study.highlightedVerses();

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Text(
                      practiceCaption,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  ListTile(
                    title: const Text('Where you are reading'),
                    subtitle: Text(currentChapterRef.label),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => StepThroughScreen(
                          state: state,
                          title: 'Where you are reading',
                          refs: [currentChapterRef],
                        ),
                      ),
                    ),
                  ),
                  if (state.activePlan != null && reading != null)
                    ListTile(
                      title: const Text("Today's plan reading"),
                      subtitle: Text(reading.map((r) => r.label).join('; ')),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => StepThroughScreen(
                            state: state,
                            title: "Today's plan reading",
                            refs: reading,
                          ),
                        ),
                      ),
                    ),
                  _section(context, 'My sets'),
                  if (sets.isEmpty && highlights.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        'Sets you save appear here.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  else ...[
                    for (final set in sets)
                      ListTile(
                        title: Text(set.label),
                        subtitle: Text(
                          '${set.refs.length} ${set.refs.length == 1 ? 'passage' : 'passages'}',
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => StepThroughScreen(
                              state: state,
                              title: set.label,
                              refs: set.refs,
                            ),
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) async {
                            if (action == 'rename') {
                              await _renameSet(context, set);
                            } else if (action == 'delete') {
                              final ok = await confirmAction(
                                context,
                                'Delete set',
                                'Delete "${set.label}"?',
                                'Delete',
                              );
                              if (ok) {
                                state.practice.delete(set.id);
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                    if (highlights.isNotEmpty)
                      ListTile(
                        title: const Text('Your highlighted verses'),
                        subtitle: Text(
                          '${highlights.length} ${highlights.length == 1 ? 'passage' : 'passages'}',
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => StepThroughScreen(
                              state: state,
                              title: 'Your highlighted verses',
                              refs: highlights,
                            ),
                          ),
                        ),
                        trailing: TextButton(
                          onPressed: () => state.practice.saveSet(
                            highlights,
                            title: 'Your highlighted verses',
                          ),
                          child: const Text('Save as a set'),
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // Asks for a new title for a practice set.
  Future<void> _renameSet(BuildContext context, PracticeSet set) async {
    final controller = TextEditingController(text: set.title ?? '');
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename set'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Set title'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newTitle != null) {
      state.practice.rename(set.id, newTitle);
    }
  }

  // Section header matching the style in plans_screen.dart.
  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(top: _sectionTopPadding, bottom: _sectionBottomPadding, left: 16),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: _labelFontSize,
          letterSpacing: _labelSpacing,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );
}
