import 'dart:io';

import 'package:flutter/material.dart';

import 'brand/lamp_mark.dart';
import 'theme.dart';

/// What this device is called in plain words.
/// Android or iOS, the phones Berea's helper timings were measured on; read from the theme so a
/// test can choose.
bool onPhone(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.android || TargetPlatform.iOS => true,
  _ => false,
};

String get deviceNoun => Platform.isMacOS
    ? 'Mac'
    : Platform.isAndroid || Platform.isIOS
    ? 'phone'
    : 'computer';

const _markSize = 72.0;
const _cardMaxWidth = 360.0;

/// Shown while the Bible opens. On first launch and after an update, when the bundled Bible is
/// copied into place, it says so; a normal launch shows only the mark for a moment.
class SetupScreen extends StatelessWidget {
  final bool settingUp;

  /// Plain words when Berea could not open the Bible; replaces the setup card.
  final String? failure;
  const SetupScreen({super.key, this.settingUp = false, this.failure});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              LampMark(size: _markSize, ink: scheme.onSurface, flame: scheme.primary),
              const SizedBox(height: 8),
              Text(
                'Berea',
                style: TextStyle(
                  fontFamilyFallback: scriptureFontFallback,
                  fontSize: 36,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _cardMaxWidth),
                child: switch ((failure, settingUp)) {
                  (final String reason, _) => Text(
                    reason,
                    textAlign: TextAlign.center,
                    style: muted,
                  ),
                  (null, true) => Column(
                    children: [
                      Text(
                        'Setting up the Bible on this $deviceNoun',
                        textAlign: TextAlign.center,
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'This happens once, and again after an update. About 85 MB, already '
                        'inside the app: nothing is downloaded.',
                        textAlign: TextAlign.center,
                        style: muted,
                      ),
                    ],
                  ),
                  (null, false) => const SizedBox.shrink(),
                },
              ),
              const Spacer(),
              Text(
                'No account. What you read and write stays on this $deviceNoun.',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
