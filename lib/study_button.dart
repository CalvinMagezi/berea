import 'package:flutter/material.dart';

import 'app_state.dart';
import 'brand/lamp_mark.dart';
import 'theme.dart';

const studyCircle = 60.0;
const studyRing = 4.0;
const studyButtonSize = studyCircle + studyRing * 2;
const _markScale = 0.62;
const _selectedRing = 2.5;
const _progressStroke = 3.0;
const _hairline = 1.0;
const _badgeSize = 18.0;
const _badgeIcon = 12.0;
const _glowBlur = 18.0;
const _glowSpread = 3.0;
const _glowPeriod = Duration(seconds: 2);

/// The arc a loading ring shows, unmoving, when Reduce motion is on.
const _stillArc = 0.25;

/// What a screen reader hears about the helper, such as "helper downloading, 42 percent".
String helperStatusWords(HelperState helper) => switch (helper) {
  HelperNotInstalled() => 'helper not downloaded',
  HelperDownloading(waitingForWifi: true) => 'helper waiting for Wi-Fi',
  HelperDownloading(waitingForNetwork: true) => 'helper waiting for a connection',
  // A paused download starts again from the beginning, so it usually has nothing to count.
  HelperDownloading(paused: true, :final percent) =>
    percent == 0 ? 'helper download paused' : 'helper download paused, $percent percent',
  HelperDownloading(:final percent) => 'helper downloading, $percent percent',
  HelperChecking() => 'helper starting',
  HelperLoading() => 'helper loading',
  HelperReady() => 'helper ready',
  HelperResting() => 'helper resting while a deep dive is recorded',
  HelperFailed() => 'helper needs a look',
};

String studySemanticsLabel(HelperState helper, {required bool writing}) =>
    'Study, ask Berea, ${writing ? 'writing an answer' : helperStatusWords(helper)}';

/// The Berea mark in a Night circle: the button for Study, the one place that uses the helper.
/// Its ring and badges show the helper's state, and it glows slowly while an answer is written.
class StudyButton extends StatefulWidget {
  final HelperState helper;
  final bool selected;
  final bool writing;
  final VoidCallback onPressed;
  const StudyButton({
    super.key,
    required this.helper,
    required this.selected,
    required this.writing,
    required this.onPressed,
  });

  @override
  State<StudyButton> createState() => _StudyButtonState();
}

class _StudyButtonState extends State<StudyButton> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: _glowPeriod);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(StudyButton old) {
    super.didUpdateWidget(old);
    _syncPulse();
  }

  /// Reduce motion turns the glow off; at rest nothing animates.
  bool get _glows => widget.writing && !MediaQuery.disableAnimationsOf(context);

  void _syncPulse() {
    if (_glows && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!_glows && _pulse.isAnimating) _pulse.reset();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final helper = widget.helper;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: studySemanticsLabel(helper, writing: widget.writing),
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: studyButtonSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: _circle(context)),
            if (_ring(context) case final ring?) Positioned.fill(child: ring),
            if (_badge(context) case final badge?) Positioned(top: 0, right: 0, child: badge),
          ],
        ),
      ),
    );
  }

  /// A surface disc cuts the circle from the bar; selected, its edge turns gold.
  Widget _circle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => DecoratedBox(
        key: const ValueKey('study-circle'),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surface,
          border: widget.selected ? Border.all(color: scheme.primary, width: _selectedRing) : null,
          boxShadow: [
            if (_glows)
              BoxShadow(
                color: scheme.primary.withValues(alpha: _pulse.value),
                blurRadius: _glowBlur,
                spreadRadius: _glowSpread * _pulse.value,
              ),
          ],
        ),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.all(studyRing),
        child: Material(
          color: BereaColors.night,
          shape: CircleBorder(
            side: dark
                ? const BorderSide(color: BereaColors.linenMuted, width: _hairline)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onPressed,
            child: const Center(
              child: LampMark(
                size: studyCircle * _markScale,
                ink: BereaColors.linen,
                flame: BereaColors.goldDark,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The ring holds the bytes so far through every download state, held or paused included,
  /// and turns while the helper checks its files and loads.
  Widget? _ring(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return switch (widget.helper) {
      HelperDownloading(:final fraction) => CircularProgressIndicator(
        key: const ValueKey('study-download-ring'),
        value: fraction,
        strokeWidth: _progressStroke,
        color: color,
        backgroundColor: Colors.transparent,
      ),
      HelperChecking() || HelperLoading() => CircularProgressIndicator(
        key: const ValueKey('study-loading-ring'),
        // Reduce motion keeps a still arc rather than a spinning one.
        value: MediaQuery.disableAnimationsOf(context) ? _stillArc : null,
        strokeWidth: _progressStroke,
        color: color,
        backgroundColor: Colors.transparent,
      ),
      _ => null,
    };
  }

  Widget? _badge(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (key, color, icon) = switch (widget.helper) {
      HelperDownloading(waitingForWifi: true) => ('study-wifi-badge', scheme.primary, Icons.wifi),
      HelperFailed() => ('study-failed-badge', scheme.error, Icons.priority_high),
      _ => (null, null, null),
    };
    if (key == null || color == null || icon == null) return null;
    return Container(
      key: ValueKey(key),
      width: _badgeSize,
      height: _badgeSize,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: _hairline * 2),
      ),
      child: Icon(icon, size: _badgeIcon, color: scheme.onPrimary),
    );
  }
}
