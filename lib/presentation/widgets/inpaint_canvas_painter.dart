import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/entities/inpaint_workspace.dart';
import 'package:nai_huishi/presentation/controllers/inpaint_mask_controller.dart';

/// Draws the local image edits and the merged inpaint mask.
///
/// The workspace supplies [maskController] to reuse committed geometry and
/// append live input without boolean path operations or page rebuilds. Mask
/// erasers are isolated from the source image and result layers. Optional path
/// caches remain available for standalone painter callers.
class InpaintCanvasPainter extends CustomPainter {
  final InpaintTransform transform;

  /// Committed strokes. Used for image overlays and as a fallback mask source
  /// in standalone painter callers that do not supply [maskPath].
  final List<InpaintStroke> strokes;
  final bool showMask;
  final bool showImageStrokes;
  final ui.Path? maskPath;
  final ui.Path? previewMaskPath;
  final ValueListenable<ui.Path?>? previewMaskPathListenable;
  final InpaintMaskController? maskController;

  InpaintCanvasPainter({
    required this.transform,
    required this.strokes,
    this.showMask = true,
    this.showImageStrokes = true,
    this.maskPath,
    this.previewMaskPath,
    this.previewMaskPathListenable,
    this.maskController,
  }) : super(repaint: maskController ?? previewMaskPathListenable);

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);

    final controller = maskController;
    if (controller == null) {
      if (showMask) _paintMask(canvas);
      if (showImageStrokes) _paintImageStrokes(canvas, bounds);
    } else {
      if (showMask) controller.paintMask(canvas, bounds, transform);
      if (showImageStrokes) {
        controller.paintImageStrokes(canvas, bounds, transform);
      }
    }

    canvas.restore();
  }

  void _paintMask(Canvas canvas) {
    // A non-null maskPath is an explicitly supplied cache even when empty.
    // Only standalone callers without a cache rebuild from strokes.
    final mask = previewMaskPathListenable?.value ??
        previewMaskPath ??
        maskPath ??
        mergeMaskStrokes(strokes);
    if (mask == null || mask.getBounds().isEmpty) return;

    _paintWorldPath(
      canvas,
      mask,
      Paint()
        ..color = const Color(0x802196F3)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
    _paintWorldPath(
      canvas,
      mask,
      Paint()
        ..color = const Color(0xFF80D8FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 / transform.scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  void _paintWorldPath(Canvas canvas, ui.Path path, Paint paint) {
    canvas.save();
    canvas.translate(transform.offsetX, transform.offsetY);
    canvas.scale(transform.scale);
    canvas.drawPath(path, paint);
    canvas.restore();
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
      return;
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = stroke.size * transform.scale;
    canvas.drawPath(path, paint);
  }

  /// Builds one stroke in source-image coordinates. The returned path is not
  /// boolean-normalized; callers may append it to a composite preview path.
  static ui.Path strokePath(InpaintStroke stroke) {
    final path = ui.Path();
    if (stroke.type == InpaintStrokeType.rectangle &&
        stroke.rectangle != null) {
      path.addRect(stroke.rectangle!);
      return path;
    }
    if (stroke.square) {
      // Build a committed square stroke from its fully deduplicated grid-cell
      // set. Appending point segments here would add shared cells repeatedly,
      // which Path.combine can reject during history rebuilds.
      for (final cell in inpaintSquareBrushCells(stroke)) {
        path.addRect(
          Rect.fromLTWH(
            cell.$1 * inpaintBrushGridCellSize,
            cell.$2 * inpaintBrushGridCellSize,
            inpaintBrushGridCellSize,
            inpaintBrushGridCellSize,
          ),
        );
      }
      return path;
    }
    for (var index = 0; index < stroke.points.length; index++) {
      appendStrokePoint(
        path,
        stroke,
        stroke.points[index],
        previous: index == 0 ? null : stroke.points[index - 1],
      );
    }
    return path;
  }

  /// Appends only the geometry added by [point] to an active stroke.
  ///
  /// [previous] is null for the first point. Square strokes rasterize just the
  /// one-point stamp or the Bresenham segment since the previous pointer event.
  static void appendStrokePoint(
    ui.Path path,
    InpaintStroke stroke,
    InpaintPoint point, {
    InpaintPoint? previous,
  }) {
    if (stroke.type == InpaintStrokeType.rectangle) return;

    if (stroke.square) {
      final segment = InpaintStroke(
        target: stroke.target,
        mode: stroke.mode,
        type: stroke.type,
        size: stroke.size,
        square: true,
        points: previous == null ? [point] : [previous, point],
      );
      for (final cell in inpaintSquareBrushCells(segment)) {
        path.addRect(
          Rect.fromLTWH(
            cell.$1 * inpaintBrushGridCellSize,
            cell.$2 * inpaintBrushGridCellSize,
            inpaintBrushGridCellSize,
            inpaintBrushGridCellSize,
          ),
        );
      }
      return;
    }

    final radius = math.max(0.5, stroke.size / 2);
    final current = point.offset;
    path.addOval(Rect.fromCircle(center: current, radius: radius));
    if (previous == null) return;

    final from = previous.offset;
    final delta = current - from;
    final length = delta.distance;
    if (length == 0) return;
    final normal = Offset(-delta.dy / length, delta.dx / length) * radius;
    path.addPolygon(
      [from - normal, current - normal, current + normal, from + normal],
      true,
    );
  }

  /// Applies one committed mask stroke to an existing canonical union path.
  /// This stroke-level operation is used while rebuilding history; interactive
  /// drawing instead uses [appendMaskPreviewPoint] with only the new segment.
  static ui.Path? appendMaskStroke(
    ui.Path? current,
    InpaintStroke stroke,
  ) {
    if (stroke.target != InpaintPaintTarget.mask) return current;
    final rawShape = strokePath(stroke);
    if (rawShape.getBounds().isEmpty) return current;
    final shape = ui.Path.combine(
      ui.PathOperation.union,
      rawShape,
      rawShape,
    );

    if (stroke.mode == InpaintStrokeMode.erase) {
      if (current == null) return null;
      final result = ui.Path.combine(
        ui.PathOperation.difference,
        current,
        shape,
      );
      return result.getBounds().isEmpty ? null : result;
    }
    if (current == null) return shape;
    return ui.Path.combine(ui.PathOperation.union, current, shape);
  }

  /// Merges only the geometry from a newly received pointer point into an
  /// already normalized preview. The returned path can be used for both fill
  /// and the visible outer contour during the gesture.
  static ui.Path appendMaskPreviewPoint(
    ui.Path current,
    InpaintStroke stroke,
    InpaintPoint point, {
    InpaintPoint? previous,
  }) {
    if (stroke.target != InpaintPaintTarget.mask) return current;
    final segment = ui.Path();
    appendStrokePoint(segment, stroke, point, previous: previous);
    if (segment.getBounds().isEmpty) return current;

    final isEmpty = current.getBounds().isEmpty;
    if (stroke.mode == InpaintStrokeMode.erase) {
      if (isEmpty) return current;
      final result = ui.Path.combine(
        ui.PathOperation.difference,
        current,
        segment,
      );
      return result.getBounds().isEmpty ? ui.Path() : result;
    }
    if (isEmpty) {
      return ui.Path.combine(ui.PathOperation.union, segment, segment);
    }
    return ui.Path.combine(ui.PathOperation.union, current, segment);
  }

  /// Rebuilds a canonical mask path for standalone painter uses and history
  /// restoration. The interactive page maintains this path incrementally.
  static ui.Path? mergeMaskStrokes(Iterable<InpaintStroke> strokes) {
    ui.Path? result;
    for (final stroke in strokes) {
      result = appendMaskStroke(result, stroke);
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant InpaintCanvasPainter oldDelegate) =>
      oldDelegate.transform != transform ||
      oldDelegate.strokes != strokes ||
      oldDelegate.showMask != showMask ||
      oldDelegate.showImageStrokes != showImageStrokes ||
      oldDelegate.maskController != maskController ||
      oldDelegate.maskPath != maskPath ||
      oldDelegate.previewMaskPath != previewMaskPath ||
      oldDelegate.previewMaskPathListenable != previewMaskPathListenable;
}
