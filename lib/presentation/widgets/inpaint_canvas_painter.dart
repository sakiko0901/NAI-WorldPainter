import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/entities/inpaint_workspace.dart';

/// Draws the local image edits and a merged, translucent inpaint mask.
///
/// Mask strokes are combined in order so paint strokes add to the mask and
/// erasers subtract from it. The resulting mask is filled and outlined once,
/// which keeps overlapping strokes at a consistent opacity.
class InpaintCanvasPainter extends CustomPainter {
  final InpaintTransform transform;
  final List<InpaintStroke> strokes;
  final bool showMask;

  const InpaintCanvasPainter({
    required this.transform,
    required this.strokes,
    this.showMask = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);

    if (showMask) _paintMask(canvas);
    _paintImageStrokes(canvas, bounds);

    canvas.restore();
  }

  void _paintMask(Canvas canvas) {
    ui.Path? mask;
    for (final stroke in strokes) {
      if (stroke.target != InpaintPaintTarget.mask) continue;
      final rawShape = _strokeShape(stroke);
      if (rawShape == null || _isEmptyPath(rawShape)) continue;
      // A brush path can contain many overlapping discs, segment rectangles,
      // or grid cells. Normalize those subpaths before stroking the final
      // outline so their shared edges never appear as internal contours.
      final shape = ui.Path.combine(
        ui.PathOperation.union,
        rawShape,
        rawShape,
      );

      if (stroke.mode == InpaintStrokeMode.erase) {
        if (mask == null || _isEmptyPath(mask)) continue;
        mask = ui.Path.combine(ui.PathOperation.difference, mask, shape);
      } else {
        mask = mask == null || _isEmptyPath(mask)
            ? shape
            : ui.Path.combine(ui.PathOperation.union, mask, shape);
      }
    }

    if (mask == null || _isEmptyPath(mask)) return;
    canvas.drawPath(
      mask,
      Paint()
        ..color = const Color(0x802196F3)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      mask,
      Paint()
        ..color = const Color(0xFF80D8FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  bool _isEmptyPath(ui.Path path) => path.computeMetrics().isEmpty;

  ui.Path? _strokeShape(InpaintStroke stroke) {
    final path = ui.Path();
    if (stroke.type == InpaintStrokeType.rectangle &&
        stroke.rectangle != null) {
      final rect = stroke.rectangle!;
      path.addRect(
        Rect.fromLTRB(
          rect.left * transform.scale + transform.offsetX,
          rect.top * transform.scale + transform.offsetY,
          rect.right * transform.scale + transform.offsetX,
          rect.bottom * transform.scale + transform.offsetY,
        ),
      );
      return path;
    }
    if (stroke.points.isEmpty) return null;

    if (stroke.square) {
      for (final cell in inpaintSquareBrushCells(stroke)) {
        path.addRect(
          Rect.fromLTWH(
            cell.$1 * inpaintBrushGridCellSize * transform.scale +
                transform.offsetX,
            cell.$2 * inpaintBrushGridCellSize * transform.scale +
                transform.offsetY,
            inpaintBrushGridCellSize * transform.scale,
            inpaintBrushGridCellSize * transform.scale,
          ),
        );
      }
      return path.computeMetrics().isEmpty ? null : path;
    }

    final points = stroke.points
        .map(
          (point) => Offset(
            point.x * transform.scale + transform.offsetX,
            point.y * transform.scale + transform.offsetY,
          ),
        )
        .toList(growable: false);
    final radius = math.max(0.5, stroke.size * transform.scale / 2);
    if (points.length == 1) {
      path.addOval(Rect.fromCircle(center: points.single, radius: radius));
      return path;
    }

    // A polyline with round joins and caps is the union of its segment
    // rectangles and a disc at every vertex. All subpaths have the same
    // winding, so overlaps do not introduce internal contours.
    for (var index = 0; index < points.length; index++) {
      path.addOval(Rect.fromCircle(center: points[index], radius: radius));
      if (index == 0) continue;

      final from = points[index - 1];
      final to = points[index];
      final delta = to - from;
      final length = delta.distance;
      if (length == 0) continue;
      final normal = Offset(-delta.dy / length, delta.dx / length) * radius;
      path.addPolygon(
        [
          from - normal,
          to - normal,
          to + normal,
          from + normal,
        ],
        true,
      );
    }
    return path;
  }

  void _paintImageStrokes(Canvas canvas, Rect bounds) {
    final imageStrokes = strokes.where(
      (stroke) => stroke.target == InpaintPaintTarget.image,
    );
    if (imageStrokes.isEmpty) return;

    canvas.saveLayer(bounds, Paint());
    for (final stroke in imageStrokes) {
      _drawImageStroke(canvas, stroke);
    }
    canvas.restore();
  }

  void _drawImageStroke(Canvas canvas, InpaintStroke stroke) {
    final erase = stroke.mode == InpaintStrokeMode.erase;
    final paint = Paint()
      ..color = Color(stroke.color).withValues(alpha: stroke.opacity)
      ..blendMode = erase ? BlendMode.clear : BlendMode.srcOver
      ..isAntiAlias = true;

    if (stroke.type == InpaintStrokeType.rectangle &&
        stroke.rectangle != null) {
      final rect = stroke.rectangle!;
      canvas.drawRect(
        Rect.fromLTRB(
          rect.left * transform.scale + transform.offsetX,
          rect.top * transform.scale + transform.offsetY,
          rect.right * transform.scale + transform.offsetX,
          rect.bottom * transform.scale + transform.offsetY,
        ),
        paint,
      );
      return;
    }
    if (stroke.points.isEmpty) return;
    if (stroke.square) {
      for (final cell in inpaintSquareBrushCells(stroke)) {
        canvas.drawRect(
          Rect.fromLTWH(
            cell.$1 * inpaintBrushGridCellSize * transform.scale +
                transform.offsetX,
            cell.$2 * inpaintBrushGridCellSize * transform.scale +
                transform.offsetY,
            inpaintBrushGridCellSize * transform.scale,
            inpaintBrushGridCellSize * transform.scale,
          ),
          paint,
        );
      }
      return;
    }

    final path = ui.Path();
    for (var index = 0; index < stroke.points.length; index++) {
      final point = stroke.points[index];
      final screen = Offset(
        point.x * transform.scale + transform.offsetX,
        point.y * transform.scale + transform.offsetY,
      );
      if (index == 0) {
        path.moveTo(screen.dx, screen.dy);
      } else {
        path.lineTo(screen.dx, screen.dy);
      }
    }
    if (stroke.points.length == 1) {
      final point = stroke.points.single;
      canvas.drawCircle(
        Offset(
          point.x * transform.scale + transform.offsetX,
          point.y * transform.scale + transform.offsetY,
        ),
        math.max(0.5, stroke.size * transform.scale / 2),
        paint,
      );
    } else {
      paint
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke.size * transform.scale;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant InpaintCanvasPainter oldDelegate) =>
      oldDelegate.transform != transform ||
      oldDelegate.strokes != strokes ||
      oldDelegate.showMask != showMask;
}
