import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'word_study_screen.dart';

/// How long a finger must rest on a verse before the word under it is marked.
const wordPressPreviewDelay = Duration(milliseconds: 120);

/// How long the mark takes to fill. It ends at the 500 ms long press, and the study opens then.
const wordPressFillTime = Duration(milliseconds: 380);

/// A finger that wanders further than this is scrolling, not pressing. A mouse is not held to it.
const _touchSlop = kTouchSlop;

/// Label for a press that is on the verse number or between words.
const wholeVerseLabel = 'All words in this verse';

/// What a press has marked: a word (with its place among the verse's words), or the whole verse.
class PressTarget {
  final ({String word, int index, int occurrence})? hit;

  /// Where the marked glyphs are, in the verse region's own coordinates.
  final List<Rect> boxes;
  final String label;
  const PressTarget(this.hit, this.boxes, this.label);

  bool sameAs(PressTarget? o) => o != null && o.hit?.index == hit?.index;
}

/// One verse of the reader. A press on a word marks it, names it above the finger, fills over the
/// rest of the long press and then opens its study; a press off any word marks the verse and opens
/// the interlinear. A tap and a long press from assistive technology behave as in the plain list.
class WordPressRegion extends StatefulWidget {
  /// The verse text, laid out by the widget under [textKey] after [prefixLength] characters.
  final String text;
  final int prefixLength;
  final GlobalKey textKey;
  final String Function(({String word, int index, int occurrence})? hit) labelFor;
  final void Function(({String word, int index, int occurrence}) hit) onWord;
  final VoidCallback onVerse;
  final VoidCallback onTap;
  final Widget child;

  const WordPressRegion({
    super.key,
    required this.text,
    required this.prefixLength,
    required this.textKey,
    required this.labelFor,
    required this.onWord,
    required this.onVerse,
    required this.onTap,
    required this.child,
  });

  /// Drops a press in progress, as when the list starts to scroll.
  static void cancelActive() => WordPressRegionState._active?._cancel();

  @override
  State<WordPressRegion> createState() => WordPressRegionState();
}

@visibleForTesting
class WordPressRegionState extends State<WordPressRegion> with SingleTickerProviderStateMixin {
  static WordPressRegionState? _active;

  late final _fill = AnimationController(vsync: this, duration: wordPressFillTime);
  Timer? _previewTimer, _commitTimer;
  OverlayEntry? _label;
  Offset _downAt = Offset.zero, _at = Offset.zero;
  PointerDeviceKind _kind = PointerDeviceKind.touch;
  var _pressing = false;

  /// The one pointer a press follows; a second finger's events are not its own.
  int? _pointer;

  /// Set when the press opened a study, so the tap the same gesture leaves behind is dropped.
  var _committed = false;
  PressTarget? _target;

  PressTarget? get target => _target;

  @visibleForTesting
  double get fillValue => _fill.value;

  RenderBox? get _box => context.findRenderObject() as RenderBox?;

  @override
  void dispose() {
    _cancel(redraw: false);
    _fill.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.mouse && (e.buttons & kSecondaryMouseButton) != 0) {
      _menu(e.position);
      return;
    }
    // A second finger on this verse, or a press in another verse, does not take the press over.
    if (_pressing && e.pointer != _pointer) return;
    final other = _active;
    if (other != null && !identical(other, this)) other._cancel();
    _cancel();
    _active = this;
    _pressing = true;
    _committed = false;
    _pointer = e.pointer;
    _kind = e.kind;
    _downAt = _at = e.position;
    _previewTimer = Timer(wordPressPreviewDelay, () => _mark(_targetAt(_at)));
  }

  void _move(PointerMoveEvent e) {
    if (!_pressing || _committed || e.pointer != _pointer) return;
    if (_kind != PointerDeviceKind.mouse && (e.position - _downAt).distance > _touchSlop) {
      _cancel();
      return;
    }
    _at = e.position;
    if (_target == null) return;
    final (inside, hit) = _hitAt(_at);
    if (!inside) {
      _cancel();
    } else if (hit?.index != _target!.hit?.index) {
      _mark(_targetFor(hit));
    }
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    final opened = _committed;
    _cancel();
    if (!opened) return;
    // The tap that follows a long press arrives in this same event; drop it, then forget.
    _committed = true;
    scheduleMicrotask(() => _committed = false);
  }

  /// Whether [global] is inside the verse, and the word under it, if any.
  (bool, ({String word, int index, int occurrence})?) _hitAt(Offset global) {
    final box = _box;
    if (box == null || !box.hasSize) return (false, null);
    if (!(Offset.zero & box.size).contains(box.globalToLocal(global))) return (false, null);
    final ctx = widget.textKey.currentContext;
    return (true, ctx == null ? null : pressedWord(ctx, global, widget.text, widget.prefixLength));
  }

  PressTarget? _targetAt(Offset global) {
    final (inside, hit) = _hitAt(global);
    return inside ? _targetFor(hit) : null;
  }

  /// The mark for [hit], or for the whole verse when it is null.
  PressTarget _targetFor(({String word, int index, int occurrence})? hit) {
    final box = _box!;
    final ctx = widget.textKey.currentContext;
    final (start, end) = hit == null ? (0, widget.text.length) : wordRange(widget.text, hit.index);
    final prefix = hit == null ? 0 : widget.prefixLength;
    return PressTarget(hit, [
      if (ctx != null)
        for (final r in verseBoxes(ctx, start, end, prefix))
          box.globalToLocal(r.topLeft) & r.size,
    ], widget.labelFor(hit));
  }

  /// Marks [t] and starts the fill again; the study opens when it is full.
  void _mark(PressTarget? t) {
    if (!mounted || !_pressing || t == null) return;
    setState(() => _target = t);
    _showLabel(t);
    _commitTimer?.cancel();
    _commitTimer = Timer(wordPressFillTime, _commit);
    if (MediaQuery.disableAnimationsOf(context)) {
      _fill.value = 1;
    } else {
      _fill.forward(from: 0);
    }
  }

  void _commit() {
    final t = _target;
    if (!mounted || t == null) return;
    HapticFeedback.selectionClick();
    _committed = true;
    _clear();
    final hit = t.hit;
    hit == null ? widget.onVerse() : widget.onWord(hit);
  }

  void _cancel({bool redraw = true}) {
    _previewTimer?.cancel();
    _commitTimer?.cancel();
    _pressing = false;
    _committed = false;
    if (identical(_active, this)) _active = null;
    _clear(redraw: redraw);
  }

  void _clear({bool redraw = true}) {
    _label?.remove();
    _label = null;
    _fill.stop();
    if (redraw && mounted && _target != null) setState(() => _target = null);
  }

  void _showLabel(PressTarget t) {
    final box = _box;
    if (box == null || t.boxes.isEmpty) return;
    _label?.remove();
    final first = t.boxes.first;
    final anchor = box.localToGlobal(first.topCenter);
    _label = OverlayEntry(builder: (_) => _PressLabel(anchor: anchor, text: t.label));
    Overlay.of(context).insert(_label!);
  }

  Future<void> _menu(Offset at) async {
    final target = _targetAt(at);
    final hit = target?.hit;
    final choice = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        if (hit != null) PopupMenuItem(value: true, child: Text('Study the word ${hit.word}')),
        const PopupMenuItem(value: false, child: Text(wholeVerseLabel)),
      ],
    );
    if (choice == null) return;
    choice ? widget.onWord(hit!) : widget.onVerse();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      onLongPressHint: 'Study the words of this verse',
      child: Listener(
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: InkWell(
          // The press has its own tick; the long-press feedback would be a second, earlier one.
          enableFeedback: false,
          onTap: () {
            if (_committed) return;
            Feedback.forTap(context);
            widget.onTap();
          },
          // A pointer long press is handled by the Listener; this is the screen reader's action.
          onLongPress: () {
            if (!_pressing) widget.onVerse();
          },
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              widget.child,
              if (_target case final t?)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _PillPainter(t.boxes, scheme.primary, _fill),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fraction of primary the marked word is drawn in, and the fill that sweeps over it.
const _markAlpha = 0.08, _fillAlpha = 0.2;
const _pillRadius = Radius.circular(6);
const _pillPad = 2.0;

class _PillPainter extends CustomPainter {
  final List<Rect> boxes;
  final Color color;
  final Animation<double> fill;
  _PillPainter(this.boxes, this.color, this.fill) : super(repaint: fill);

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in boxes) {
      final pill = RRect.fromRectAndRadius(b.inflate(_pillPad), _pillRadius);
      canvas.drawRRect(pill, Paint()..color = color.withValues(alpha: _markAlpha));
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(pill.left, pill.top, pill.left + pill.width * fill.value, pill.bottom));
      canvas.drawRRect(pill, Paint()..color = color.withValues(alpha: _fillAlpha));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PillPainter old) => old.boxes != boxes || old.color != color;
}

/// The small label above the finger, so the finger does not hide it.
class _PressLabel extends StatelessWidget {
  final Offset anchor;
  final String text;
  const _PressLabel({required this.anchor, required this.text});

  static const _gap = 10.0, _height = 36.0, _edge = 12.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final above = anchor.dy - _height - _gap;
    return Positioned(
      left: _edge,
      right: _edge,
      top: above < MediaQuery.paddingOf(context).top ? anchor.dy + _height : above,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment(((anchor.dx / screen.width) * 2 - 1).clamp(-0.85, 0.85), 0),
          child: Material(
            color: scheme.inverseSurface,
            borderRadius: BorderRadius.circular(8),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                text,
                style: TextStyle(
                  color: scheme.onInverseSurface,
                  fontSize: 14,
                  fontFamilyFallback: scriptureFontFallback,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
