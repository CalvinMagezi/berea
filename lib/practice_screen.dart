import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';

/// What the Practice place says it is. Fixed wording from the plan: Berea chooses mechanics only.
const practiceCaption =
    'Things Berea can do with a passage you choose. Berea chose these mechanics. This is not a '
    'list of what Scripture asks.';

/// The Practice place. Its rows arrive with the mechanics; until then it names itself.
class PracticeScreen extends StatelessWidget {
  final AppState state;
  const PracticeScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Practice')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(practiceCaption, style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        ),
      ),
    );
  }
}
