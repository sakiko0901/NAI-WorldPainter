import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/entities/comic_project.dart';

class ComicOverlayRenderer {
  const ComicOverlayRenderer._();

  static void drawAll(
    Canvas canvas,
    Size size,
    List<ComicOverlay> overlays,
  ) {
    final sorted = [...overlays]
      ..sort((left, right) => left.zIndex.compareTo(right.zIndex));
    for (final overlay in sorted) {
      if (!overlay.visible) continue;
      draw(canvas, size, overlay);
    }
  }

  static void draw(Canvas canvas, Size size, ComicOverlay overlay) {
    final rect = rectFor(size, overlay.rect);
    switch (overlay.type) {
      case ComicOverlayType.whiteCover:
        _drawCover(canvas, size, rect, overlay);
      case ComicOverlayType.bubble:
        _drawBubble(canvas, rect, overlay);
        _drawText(canvas, rect, overlay, inset: true);
      case ComicOverlayType.text:
        _drawText(canvas, rect, overlay, inset: false);
    }
  }

  static Rect rectFor(Size size, ComicRect rect) => Rect.fromLTWH(
        rect.x * size.width,
        rect.y * size.height,
        rect.width * size.width,
        rect.height * size.height,
      );

  static Offset tailTargetFor(Rect rect, ComicOverlay overlay) => Offset(
        rect.left + overlay.tailX * rect.width,
        rect.top + overlay.tailY * rect.height,
      );

  static void _drawCover(
    Canvas canvas,
    Size size,
    Rect rect,
    ComicOverlay overlay,
  ) {
    final paint = Paint()
      ..color = Color(overlay.backgroundColor)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height * 0.08)),
      paint,
    );
    for (final stroke in overlay.brushStrokes) {
      if (stroke.points.isEmpty) continue;
      final width = (stroke.width * size.width).clamp(2.0, 256.0);
      final strokePaint = Paint()
        ..color = Color(overlay.backgroundColor)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (stroke.points.length == 1) {
        final point = stroke.points.single;
        canvas.drawCircle(
          Offset(point.x * size.width, point.y * size.height),
          width / 2,
          strokePaint..style = PaintingStyle.fill,
        );
        continue;
      }
      final first = stroke.points.first;
      final path = Path()..moveTo(first.x * size.width, first.y * size.height);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.x * size.width, point.y * size.height);
      }
      canvas.drawPath(path, strokePaint);
    }
  }

  static void _drawBubble(Canvas canvas, Rect rect, ComicOverlay overlay) {
    final fill = Paint()
      ..color = Color(overlay.backgroundColor)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = Color(overlay.borderColor)
      ..style = PaintingStyle.stroke
      ..strokeWidth =
          (overlay.borderWidth * rect.shortestSide).clamp(1.0, 16.0);
    final isOval = overlay.bubbleShape == ComicBubbleShape.oval;
    if (isOval) {
      canvas.drawOval(rect, fill);
      canvas.drawOval(rect, stroke);
    } else {
      final radiusFactor = switch (overlay.bubbleType) {
        ComicBubbleType.speech => 0.18,
        ComicBubbleType.thought => 0.42,
        ComicBubbleType.narration => 0.04,
        ComicBubbleType.shout => 0.08,
      };
      final shape = RRect.fromRectAndRadius(
        rect,
        Radius.circular(rect.height * radiusFactor),
      );
      canvas.drawRRect(shape, fill);
      canvas.drawRRect(shape, stroke);
    }
    if (overlay.bubbleType != ComicBubbleType.narration) {
      _drawTail(canvas, rect, overlay, fill, stroke);
    }
  }

  static void _drawTail(
    Canvas canvas,
    Rect rect,
    ComicOverlay overlay,
    Paint fill,
    Paint stroke,
  ) {
    final target = tailTargetFor(rect, overlay);
    final center = rect.center;
    final dx = target.dx - center.dx;
    final dy = target.dy - center.dy;
    final horizontal = dx.abs() > dy.abs();
    final baseHalf = (rect.shortestSide * 0.1).clamp(5.0, 80.0);
    Offset first;
    Offset second;
    if (horizontal) {
      final x = dx >= 0 ? rect.right : rect.left;
      final y = target.dy.clamp(rect.top + baseHalf, rect.bottom - baseHalf);
      first = Offset(x, y - baseHalf);
      second = Offset(x, y + baseHalf);
    } else {
      final y = dy >= 0 ? rect.bottom : rect.top;
      final x = target.dx.clamp(rect.left + baseHalf, rect.right - baseHalf);
      first = Offset(x - baseHalf, y);
      second = Offset(x + baseHalf, y);
    }
    final path = Path()
      ..moveTo(first.dx, first.dy)
      ..lineTo(target.dx, target.dy)
      ..lineTo(second.dx, second.dy)
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  static void _drawText(
    Canvas canvas,
    Rect rect,
    ComicOverlay overlay, {
    required bool inset,
  }) {
    if (overlay.text.trim().isEmpty) return;
    final padding = inset ? rect.shortestSide * 0.12 : 0.0;
    final painter = TextPainter(
      text: TextSpan(
        text: overlay.text,
        style: TextStyle(
          color: Color(overlay.textColor),
          fontFamily: overlay.fontFamily,
          fontSize: (overlay.fontSize * rect.width).clamp(10.0, 256.0),
          height: 1.18,
          fontWeight: FontWeight.w600,
          shadows: overlay.type == ComicOverlayType.text
              ? const [Shadow(color: Colors.white, blurRadius: 2)]
              : null,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 12,
      ellipsis: '…',
    )..layout(maxWidth: (rect.width - padding * 2).clamp(1.0, double.infinity));
    painter.paint(
      canvas,
      Offset(
        rect.left + (rect.width - painter.width) / 2,
        rect.top + (rect.height - painter.height) / 2,
      ),
    );
  }
}
