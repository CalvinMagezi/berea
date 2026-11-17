import 'package:material_ui/material_ui.dart';

import 'app_update.dart';

/// A bar at the foot of the page, above the places, when a newer Berea is out. One tap
/// downloads it and opens the installer; Later puts it away until the next release.
class UpdateBar extends StatelessWidget {
  final UpdateService updates;
  const UpdateBar({super.key, required this.updates});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: updates,
    builder: (context, _) {
      final release = updates.available;
      if (release == null || !release.installable) return const SizedBox.shrink();
      final scheme = Theme.of(context).colorScheme;
      final stage = updates.stage;
      final (got, total) = updates.progress;
      final busy = stage == UpdateStage.downloading || stage == UpdateStage.installing;
      final text = switch (stage) {
        UpdateStage.downloading =>
          total == null || total == 0
              ? 'Downloading Berea ${release.version}'
              : 'Downloading Berea ${release.version} · ${(got * 100 ~/ total).clamp(0, 100)}%',
        UpdateStage.installing => 'Opening the installer',
        UpdateStage.failed => updates.failure ?? 'The update did not finish.',
        UpdateStage.idle => 'Berea ${release.version} is available',
      };
      return Material(
        color: scheme.primaryContainer,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.system_update_alt, size: 20, color: scheme.onPrimaryContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (!busy) ...[
                      TextButton(onPressed: updates.later, child: const Text('Later')),
                      FilledButton(
                        onPressed: updates.update,
                        child: Text(stage == UpdateStage.failed ? 'Try again' : 'Update'),
                      ),
                    ],
                  ],
                ),
                if (stage == UpdateStage.downloading)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: LinearProgressIndicator(
                      value: total == null || total == 0 ? null : (got / total).clamp(0.0, 1.0),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
