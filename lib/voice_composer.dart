import 'package:flutter/material.dart';

import 'voice.dart';

/// Sliding this far off the microphone while holding throws the recording away.
const slideToCancelDistance = 80.0;

const holdHint = 'Ask by voice. Hold to talk, or tap to start and tap again to stop.';
const stopHint = 'Stop recording';
const notLoadedHint = 'Voice works once the model has loaded';
const needsGemma4Hint = 'Voice needs Gemma 4';
const transcribingHint = 'Transcribing';

String voiceClock(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Hold to talk, or tap to start and tap again to stop, for anyone who cannot hold.
class VoiceMicButton extends StatelessWidget {
  final VoiceInput voice;
  final VoiceSupport support;

  /// False while the model is answering or another transcription runs.
  final bool modelFree;
  final VoidCallback onOpenSettings;
  const VoiceMicButton({
    super.key,
    required this.voice,
    required this.support,
    required this.modelFree,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    if (support == VoiceSupport.needsGemma4) {
      return IconButton(
        tooltip: needsGemma4Hint,
        icon: const Icon(Icons.mic_off_outlined),
        onPressed: () => _explain(context),
      );
    }
    if (voice.phase == VoicePhase.transcribing) {
      return const IconButton(
        tooltip: transcribingHint,
        onPressed: null,
        icon: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final recording = voice.active;
    final usable = support == VoiceSupport.ready && (recording || modelFree);
    final button = IconButton(
      isSelected: recording,
      icon: const Icon(Icons.mic_none),
      selectedIcon: const Icon(Icons.stop_circle_outlined),
      onPressed: usable ? () => recording ? voice.stop() : voice.start() : null,
    );
    // A long-press tooltip would take the hold gesture, so the hint shows on hover only.
    return Tooltip(
      message: recording ? stopHint : (usable ? holdHint : notLoadedHint),
      triggerMode: TooltipTriggerMode.manual,
      child: !usable
          ? button
          : GestureDetector(
              onLongPressStart: (_) => voice.start(),
              onLongPressMoveUpdate: (d) {
                if (d.offsetFromOrigin.distance > slideToCancelDistance) voice.cancel();
              },
              onLongPressEnd: (_) => voice.stop(),
              child: button,
            ),
    );
  }

  void _explain(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Voice questions'),
        content: const Text(needsGemma4Message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Not now')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onOpenSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

/// The timer while recording, progress while transcribing, and what to do next.
class VoiceStatusLine extends StatelessWidget {
  final VoiceInput voice;
  const VoiceStatusLine(this.voice, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(color: scheme.onSurfaceVariant, fontSize: 13);
    final Widget? child = switch (voice.phase) {
      VoicePhase.recording => Row(
        children: [
          Icon(Icons.fiber_manual_record, size: 14, color: scheme.error),
          const SizedBox(width: 6),
          Text(
            'Listening ${voiceClock(voice.elapsed)} of ${voiceClock(voice.maxDuration)}',
            style: style,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LinearProgressIndicator(
              value: voice.elapsed.inMilliseconds / voice.maxDuration.inMilliseconds,
            ),
          ),
          TextButton(onPressed: voice.cancel, child: const Text('Cancel')),
        ],
      ),
      VoicePhase.transcribing => Text('Transcribing on this device…', style: style),
      VoicePhase.confirm => Text('Check the words, edit them if needed, then send.', style: style),
      VoicePhase.idle when voice.message != null => Text(
        voice.message!,
        style: style.copyWith(color: scheme.error),
      ),
      _ => null,
    };
    if (child == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 0), child: child),
    );
  }
}
