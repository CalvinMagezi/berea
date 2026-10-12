import 'dart:async';

import 'package:flutter/material.dart';

import 'voice.dart';

/// Sliding this far off the microphone while holding throws the recording away.
const slideToCancelDistance = 80.0;

/// A press released sooner is a tap: the recording keeps going until the next tap.
const holdThreshold = Duration(milliseconds: 300);

const micTapTarget = 48.0;

/// Material's opacity for a disabled icon.
const disabledIconOpacity = 0.38;

const holdHint = 'Ask by voice. Hold to talk, or tap to start and tap again to stop.';
const stopHint = 'Stop recording';
const notLoadedHint = 'Voice works once the model has loaded';
const needsGemma4Hint = 'Voice needs Gemma 4';
const transcribingHint = 'Transcribing';
const releaseHint = 'Release to finish.';
const tapAgainHint = 'Tap the microphone again to stop.';

String voiceClock(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Recording starts on press: hold and release, or tap to start and tap again to stop.
class VoiceMicButton extends StatefulWidget {
  final VoiceInput voice;

  /// The composer this button belongs to; another composer's session disables it.
  final Object owner;
  final VoiceSupport support;

  /// False while the model is answering or another question is in flight.
  final bool modelFree;
  final VoidCallback onOpenSettings;
  const VoiceMicButton({
    super.key,
    required this.voice,
    required this.owner,
    required this.support,
    required this.modelFree,
    required this.onOpenSettings,
  });

  @override
  State<VoiceMicButton> createState() => _VoiceMicButtonState();
}

class _VoiceMicButtonState extends State<VoiceMicButton> {
  Stopwatch? _press;
  Offset? _origin;
  bool _startedHere = false;
  bool _stopsHere = false;
  bool _focused = false;

  VoiceInput get _voice => widget.voice;
  bool get _mine => _voice.ownedBy(widget.owner);
  bool get _recording => _voice.recording && _mine;
  bool get _usable =>
      widget.support == VoiceSupport.ready &&
      (_voice.recording ? _mine : widget.modelFree && !_voice.inUse);

  void _down(PointerDownEvent e) {
    if (!_usable) return;
    _origin = e.position;
    _press = _voice.newStopwatch()..start();
    if (_recording) {
      _stopsHere = true;
      return;
    }
    _startedHere = true;
    unawaited(_voice.start(widget.owner));
  }

  void _up(PointerUpEvent e) {
    final held = (_press?.elapsed ?? Duration.zero) >= holdThreshold;
    if (_stopsHere || (_startedHere && held)) {
      unawaited(_voice.stop());
    } else if (_startedHere) {
      _voice.switchToTapMode();
    }
    _reset();
  }

  /// A dialog, a call or a system gesture took the pointer; keep nothing from this press.
  void _cancel(PointerCancelEvent e) {
    if (_startedHere || _stopsHere) unawaited(_voice.cancelRecording());
    _reset();
  }

  void _move(PointerMoveEvent e) {
    if (!_startedHere || (e.position - _origin!).distance <= slideToCancelDistance) return;
    unawaited(_voice.cancelRecording());
    _reset();
  }

  void _reset() {
    _press = null;
    _origin = null;
    _startedHere = false;
    _stopsHere = false;
  }

  /// Keyboard and screen reader activation: always tap to start and tap again to stop.
  void _toggle() {
    if (!_usable) return;
    if (_recording) {
      unawaited(_voice.stop());
      return;
    }
    unawaited(_voice.start(widget.owner));
    _voice.switchToTapMode();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.support == VoiceSupport.needsGemma4 ||
        widget.support == VoiceSupport.unavailable) {
      return IconButton(
        tooltip: needsGemma4Hint,
        icon: const Icon(Icons.mic_off_outlined),
        onPressed: () => _explain(context),
      );
    }
    if (_mine && _voice.phase == VoicePhase.transcribing) {
      return const IconButton(
        tooltip: transcribingHint,
        onPressed: null,
        icon: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final usable = _usable;
    final hint = _recording ? stopHint : (usable ? holdHint : notLoadedHint);
    final color = _recording
        ? scheme.error
        : usable
        ? scheme.onSurfaceVariant
        : scheme.onSurface.withValues(alpha: disabledIconOpacity);
    return Tooltip(
      message: hint,
      // A long-press tooltip would take the hold gesture, so it shows on hover only.
      triggerMode: TooltipTriggerMode.manual,
      child: Semantics(
        button: true,
        enabled: usable,
        label: hint,
        onTap: usable ? _toggle : null,
        excludeSemantics: true,
        child: FocusableActionDetector(
          enabled: usable,
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _toggle())},
          child: Listener(
            onPointerDown: _down,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            onPointerMove: _move,
            child: Container(
              width: micTapTarget,
              height: micTapTarget,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: _focused ? Border.all(color: scheme.primary, width: 2) : null,
              ),
              child: Icon(_recording ? Icons.stop_circle_outlined : Icons.mic_none, color: color),
            ),
          ),
        ),
      ),
    );
  }

  void _explain(BuildContext context) {
    final unavailable = widget.support == VoiceSupport.unavailable;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Voice questions'),
        content: Text(unavailable ? audioUnavailableMessage : needsGemma4Message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(unavailable ? 'OK' : 'Not now'),
          ),
          if (!unavailable)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                widget.onOpenSettings();
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
  final Object owner;
  const VoiceStatusLine(this.voice, {super.key, required this.owner});

  @override
  Widget build(BuildContext context) {
    if (!voice.ownedBy(owner)) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(color: scheme.onSurfaceVariant, fontSize: 13);
    final cancel = TextButton(onPressed: voice.cancel, child: const Text('Cancel'));
    final Widget? child = switch (voice.phase) {
      VoicePhase.starting => Text('Starting the microphone…', style: style),
      VoicePhase.recording => Row(
        children: [
          Icon(Icons.fiber_manual_record, size: 14, color: scheme.error),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Listening ${voiceClock(voice.elapsed)} of ${voiceClock(voice.maxDuration)}. '
              '${voice.held ? releaseHint : tapAgainHint}',
              style: style,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LinearProgressIndicator(
              value: voice.elapsed.inMilliseconds / voice.maxDuration.inMilliseconds,
            ),
          ),
          cancel,
        ],
      ),
      VoicePhase.transcribing => Row(
        children: [
          Expanded(child: Text('Transcribing on this device…', style: style)),
          cancel,
        ],
      ),
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
