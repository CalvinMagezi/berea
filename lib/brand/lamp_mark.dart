import 'package:flutter/material.dart';

/// The Berea mark: a lowercase b whose stem is a lamp, its flame above (Psalm 119:105).
/// Drawn on a 100 unit square; ink or linen for the b, lamp gold for the flame.
class LampMark extends StatelessWidget {
  final double size;
  final Color ink;
  final Color flame;
  const LampMark({super.key, required this.size, required this.ink, required this.flame});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: LampMarkPainter(ink: ink, flame: flame),
    ),
  );
}

class LampMarkPainter extends CustomPainter {
  final Color ink;
  final Color flame;
  const LampMarkPainter({required this.ink, required this.flame});

  static const _viewBox = 100.0;
  static const _stroke = 12.0;
  static const _stemX = 32.5;
  static const _stemTop = 40.0;
  static const _stemBottom = 88.0;
  static const _bowlCentre = Offset(50.5, 70);
  static const _bowlRadius = 18.0;
  static const _flameRadius = Radius.circular(7);

  static Path flamePath() => Path()
    ..moveTo(32.5, 6)
    ..cubicTo(36, 11, 39.5, 15, 39.5, 20)
    ..arcToPoint(const Offset(25.5, 20), radius: _flameRadius)
    ..cubicTo(25.5, 15, 29, 11, 32.5, 6)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _viewBox, size.height / _viewBox);
    final b = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(_stemX, _stemTop), const Offset(_stemX, _stemBottom), b);
    canvas.drawCircle(_bowlCentre, _bowlRadius, b);
    canvas.drawPath(flamePath(), Paint()..color = flame);
  }

  @override
  bool shouldRepaint(LampMarkPainter old) => old.ink != ink || old.flame != flame;
}
