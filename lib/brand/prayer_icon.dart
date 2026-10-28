import 'package:flutter/material.dart';

/// Folded hands for the Prayer place. The bundled Material icons have no praying hands, so it
/// is drawn on the 24 unit icon grid and takes its colour and size from the icon theme.
class PrayerIcon extends StatelessWidget {
  const PrayerIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return SizedBox.square(
      dimension: theme.size ?? _grid,
      child: CustomPaint(painter: _PrayerPainter(theme.color ?? Colors.black)),
    );
  }
}

const _grid = 24.0;
const _strokeWidth = 1.6;

class _PrayerPainter extends CustomPainter {
  final Color color;
  const _PrayerPainter(this.color);

  static Path _hands() => Path()
    ..moveTo(12, 3)
    ..cubicTo(10.8, 4.2, 9.8, 6.2, 9.6, 8.6)
    ..lineTo(9.4, 11.6)
    ..cubicTo(9.4, 12.6, 8.8, 13.6, 8, 14.4)
    ..lineTo(4.5, 17.8)
    ..lineTo(7.2, 20.5)
    ..lineTo(11, 16.9)
    ..cubicTo(11.6, 16.3, 12, 15.6, 12, 14.8)
    ..cubicTo(12, 15.6, 12.4, 16.3, 13, 16.9)
    ..lineTo(16.8, 20.5)
    ..lineTo(19.5, 17.8)
    ..lineTo(16, 14.4)
    ..cubicTo(15.2, 13.6, 14.6, 12.6, 14.6, 11.6)
    ..lineTo(14.4, 8.6)
    ..cubicTo(14.2, 6.2, 13.2, 4.2, 12, 3)
    ..close()
    ..moveTo(12, 3)
    ..lineTo(12, 14.8);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _grid, size.height / _grid);
    canvas.drawPath(
      _hands(),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_PrayerPainter old) => old.color != color;
}
