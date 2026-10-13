import 'package:flutter/material.dart';

class FountainPenIcon extends StatelessWidget {
  final Color? color;
  final double size;
  const FountainPenIcon({super.key, this.color, this.size = 20});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
          child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
            painter: _NibPainter(
                color ?? Theme.of(context).colorScheme.onSurfaceVariant)),
      ));
}

class _NibPainter extends CustomPainter {
  final Color color;
  const _NibPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.55
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(4, 20)
      ..lineTo(7, 8)
      ..lineTo(14, 3)
      ..lineTo(21, 10)
      ..lineTo(16, 17)
      ..close()
      ..moveTo(4, 20)
      ..lineTo(11, 13);
    canvas.drawPath(path, paint);
    canvas.drawCircle(const Offset(12, 12), 1.6, paint);
  }

  @override
  bool shouldRepaint(covariant _NibPainter oldDelegate) =>
      oldDelegate.color != color;
}
