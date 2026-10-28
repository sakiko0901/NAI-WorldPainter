import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/entities/inpaint_workspace.dart';

/// Caches stroke geometry and paints the live mask without boolean path ops.
///
/// Committed strokes are recorded into small world-space pictures. The active
/// stroke remains a pair of append-only paths so pointer moves never rebuild
/// history geometry or normalize the complete mask.
class InpaintMaskController extends ChangeNotifier {
  static const int _pictureGroupSize = 32;
  static const int _maxCachedGeometries = 128;
  static const double _outlineRadius = 2;

  static const Color _maskColor = Color(0x802196F3);
  static const Color _outlineColor = Color(0xFF80D8FF);

  final LinkedHashMap<InpaintStroke, _StrokeGeometry> _geometryCache =
      LinkedHashMap<InpaintStroke, _StrokeGeometry>.identity();
  final List<InpaintStroke> _strokes = [];
  final List<ui.Picture> _maskPictures = [];
  final List<ui.Picture> _imagePictures = [];
  final List<_StrokeRecord> _maskTail = [];
  final List<_StrokeRecord> _imageTail = [];

  ui.Picture? _maskTailPicture;
  ui.Picture? _imageTailPicture;
  InpaintStroke? _activeStroke;
  ui.Path _activeMaskPath = ui.Path();
  ui.Path _activeImagePath = ui.Path();
  InpaintPoint? _lastPoint;
  int _activePointCount = 0;
  int _geometryBuildCount = 0;
  int _pointAppendCount = 0;
  int _pictureBuildCount = 0;
  bool _disposed = false;

  List<InpaintStroke> get strokes => List.unmodifiable(_strokes);

  InpaintStroke? get activeStroke => _activeStroke;

  int get debugGeometryBuildCount => _geometryBuildCount;

  int get debugPointAppendCount => _pointAppendCount;

  int get debugPictureBuildCount => _pictureBuildCount;

  int get debugCachedGeometryCount => _geometryCache.length;

  int get debugMaskPictureCount =>
      _maskPictures.length + (_maskTailPicture == null ? 0 : 1);

  int get debugImagePictureCount =>
      _imagePictures.length + (_imageTailPicture == null ? 0 : 1);

  /// Replaces committed history, as used after clear, undo, and redo.
  ///
  /// Identity comparisons avoid hashing Equatable strokes, whose hash includes
  /// every point in a long stroke.
  void replaceStrokes(Iterable<InpaintStroke> strokes) {
    if (_disposed) return;
    final next = List<InpaintStroke>.of(strokes);
    if (_sameIdentitySequence(_strokes, next)) return;

    _clearActiveStroke();
    _disposePictures();
    _strokes
      ..clear()
      ..addAll(next);

    for (final stroke in _strokes) {
      _appendCommittedRecord(stroke, _geometryFor(stroke));
    }
    notifyListeners();
  }

  /// Starts a live path. The draft's existing points, usually its first point,
  /// are appended once so a tap still produces a visible dab.
  void beginStroke(InpaintStroke draft) {
    if (_disposed) return;
    _clearActiveStroke();
    _activeStroke = draft;
    for (final point in draft.points) {
      _appendActivePoint(point);
    }
    notifyListeners();
  }

  /// Appends the geometry between the previous pointer sample and [point].
  void appendPoint(InpaintPoint point) {
    if (_disposed || _activeStroke == null) return;
    _appendActivePoint(point);
    _pointAppendCount++;
    notifyListeners();
  }

  /// Commits the current draft without a union/difference operation.
  void finishStroke(InpaintStroke completed) {
    if (_disposed) return;
    final active = _activeStroke;
    final geometry = active == null
        ? _geometryFor(completed)
        : _StrokeGeometry(
            maskPath: ui.Path.from(_activeMaskPath),
            imagePath: ui.Path.from(_activeImagePath),
          );
    if (active != null) _rememberGeometry(completed, geometry);
    _strokes.add(completed);
    _appendCommittedRecord(completed, geometry);
    _clearActiveStroke();
    notifyListeners();
  }

  /// Drops only the active draft. Committed strokes remain available to undo.
  void cancelStroke() {
    if (_disposed || _activeStroke == null) return;
    _clearActiveStroke();
    notifyListeners();
  }

  /// Draws the composed binary mask, tint, and one outer/hole contour.
  ///
  /// All mask operations occur inside stage-bounded saveLayers, so clear-mode
  /// erasers cannot punch through the source image or neighboring widgets.
  void paintMask(
    ui.Canvas canvas,
    Rect bounds,
    InpaintTransform transform,
  ) {
    if (_disposed || !_hasMaskGeometry) return;
    canvas.save();
    canvas.clipRect(bounds);

    canvas.saveLayer(bounds, ui.Paint());
    _drawMaskGeometry(canvas, transform);
    canvas.drawRect(
      bounds,
      ui.Paint()
        ..color = _maskColor
        ..blendMode = ui.BlendMode.srcIn,
    );
    canvas.restore();

    // Highlight the inside of the union boundary, including eraser holes.
    // Keeping the contour inside avoids visually enlarging a round selection.
    canvas.saveLayer(bounds, ui.Paint());
    _drawMaskGeometry(canvas, transform);
    canvas.saveLayer(
      bounds,
      ui.Paint()
        ..blendMode = ui.BlendMode.dstOut
        ..imageFilter = ui.ImageFilter.erode(
          radiusX: _outlineRadius,
          radiusY: _outlineRadius,
        ),
    );
    _drawMaskGeometry(canvas, transform);
    canvas.restore();

    canvas.drawRect(
      bounds,
      ui.Paint()
        ..color = _outlineColor
        ..blendMode = ui.BlendMode.srcIn,
    );
    canvas.restore();
    canvas.restore();
  }

  /// Draws cached image strokes into one isolated layer.
  void paintImageStrokes(
    ui.Canvas canvas,
    Rect bounds,
    InpaintTransform transform,
  ) {
    if (_disposed || !_hasImageGeometry) return;
    canvas.saveLayer(bounds, ui.Paint());
    canvas.save();
    _applyTransform(canvas, transform);
    for (final picture in _imagePictures) {
      canvas.drawPicture(picture);
    }
    final tailPicture = _imageTailPicture;
    if (tailPicture != null) canvas.drawPicture(tailPicture);
    final active = _activeStroke;
    if (active?.target == InpaintPaintTarget.image) {
      _drawImageStroke(canvas, active!, _activeImagePath, _activePointCount);
    }
    canvas.restore();
    canvas.restore();
  }

  void _drawMaskGeometry(ui.Canvas canvas, InpaintTransform transform) {
    canvas.save();
    _applyTransform(canvas, transform);
    for (final picture in _maskPictures) {
      canvas.drawPicture(picture);
    }
    final tailPicture = _maskTailPicture;
    if (tailPicture != null) canvas.drawPicture(tailPicture);
    final active = _activeStroke;
    if (active?.target == InpaintPaintTarget.mask) {
      canvas.drawPath(
        _activeMaskPath,
        _maskPaint(active!.mode),
      );
    }
    canvas.restore();
  }

  bool get _hasMaskGeometry =>
      _maskPictures.isNotEmpty ||
      _maskTailPicture != null ||
      _activeStroke?.target == InpaintPaintTarget.mask;

  bool get _hasImageGeometry =>
      _imagePictures.isNotEmpty ||
      _imageTailPicture != null ||
      _activeStroke?.target == InpaintPaintTarget.image;

  void _appendActivePoint(InpaintPoint point) {
    final stroke = _activeStroke!;
    final previous = _lastPoint;
    if (stroke.target == InpaintPaintTarget.mask) {
      _appendMaskPoint(_activeMaskPath, stroke, point, previous);
    } else {
      _appendImagePoint(_activeImagePath, stroke, point, previous);
    }
    _lastPoint = point;
    _activePointCount++;
  }

  void _appendCommittedRecord(
    InpaintStroke stroke,
    _StrokeGeometry geometry,
  ) {
    if (stroke.target == InpaintPaintTarget.mask) {
      _maskTail.add(_StrokeRecord(stroke, geometry));
      _replaceTailPicture(mask: true);
      if (_maskTail.length == _pictureGroupSize) {
        _maskPictures.add(_maskTailPicture!);
        _maskTailPicture = null;
        _maskTail.clear();
      }
    } else {
      _imageTail.add(_StrokeRecord(stroke, geometry));
      _replaceTailPicture(mask: false);
      if (_imageTail.length == _pictureGroupSize) {
        _imagePictures.add(_imageTailPicture!);
        _imageTailPicture = null;
        _imageTail.clear();
      }
    }
  }

  void _replaceTailPicture({required bool mask}) {
    final tail = mask ? _maskTail : _imageTail;
    final oldPicture = mask ? _maskTailPicture : _imageTailPicture;
    oldPicture?.dispose();
    if (tail.isEmpty) {
      if (mask) {
        _maskTailPicture = null;
      } else {
        _imageTailPicture = null;
      }
      return;
    }

    final recorder = ui.PictureRecorder();
    final recordCanvas = ui.Canvas(recorder);
    for (final record in tail) {
      if (mask) {
        recordCanvas.drawPath(
          record.geometry.maskPath,
          _maskPaint(record.stroke.mode),
        );
      } else {
        _drawImageStroke(
          recordCanvas,
          record.stroke,
          record.geometry.imagePath,
          record.stroke.points.length,
        );
      }
    }
    final picture = recorder.endRecording();
    _pictureBuildCount++;
    if (mask) {
      _maskTailPicture = picture;
    } else {
      _imageTailPicture = picture;
    }
  }

  _StrokeGeometry _geometryFor(InpaintStroke stroke) {
    final cached = _geometryCache.remove(stroke);
    if (cached != null) {
      _geometryCache[stroke] = cached;
      return cached;
    }

    final geometry = _buildGeometry(stroke);
    _rememberGeometry(stroke, geometry);
    _geometryBuildCount++;
    return geometry;
  }

  void _rememberGeometry(InpaintStroke stroke, _StrokeGeometry geometry) {
    _geometryCache.remove(stroke);
    _geometryCache[stroke] = geometry;
    while (_geometryCache.length > _maxCachedGeometries) {
      _geometryCache.remove(_geometryCache.keys.first);
    }
  }

  static _StrokeGeometry _buildGeometry(InpaintStroke stroke) {
    final maskPath = ui.Path();
    final imagePath = ui.Path();
    if (stroke.type == InpaintStrokeType.rectangle &&
        stroke.rectangle != null) {
      (stroke.target == InpaintPaintTarget.mask ? maskPath : imagePath)
          .addRect(stroke.rectangle!);
      return _StrokeGeometry(maskPath: maskPath, imagePath: imagePath);
    }

    for (var index = 0; index < stroke.points.length; index++) {
      final point = stroke.points[index];
      final previous = index == 0 ? null : stroke.points[index - 1];
      if (stroke.target == InpaintPaintTarget.mask) {
        _appendMaskPoint(maskPath, stroke, point, previous);
      } else {
        _appendImagePoint(imagePath, stroke, point, previous);
      }
    }
    return _StrokeGeometry(maskPath: maskPath, imagePath: imagePath);
  }

  static ui.Paint _maskPaint(InpaintStrokeMode mode) => ui.Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = ui.PaintingStyle.fill
    ..blendMode = mode == InpaintStrokeMode.erase
        ? ui.BlendMode.clear
        : ui.BlendMode.srcOver
    ..isAntiAlias = false;

  static void _appendMaskPoint(
    ui.Path path,
    InpaintStroke stroke,
    InpaintPoint point,
    InpaintPoint? previous,
  ) {
    if (stroke.type == InpaintStrokeType.rectangle) return;
    if (previous != null && previous.x == point.x && previous.y == point.y) {
      return;
    }
    if (stroke.square) {
      _appendSquareSegment(path, stroke, point, previous);
      return;
    }

    final radius = math.max(0.5, stroke.size / 2);
    final current = point.offset;
    path.addOval(ui.Rect.fromCircle(center: current, radius: radius));
    if (previous == null) return;

    final from = previous.offset;
    final delta = current - from;
    final length = delta.distance;
    if (length == 0) return;
    final normal = ui.Offset(-delta.dy / length, delta.dx / length) * radius;
    path.addPolygon(
      [from - normal, current - normal, current + normal, from + normal],
      true,
    );
  }

  static void _appendImagePoint(
    ui.Path path,
    InpaintStroke stroke,
    InpaintPoint point,
    InpaintPoint? previous,
  ) {
    if (stroke.type == InpaintStrokeType.rectangle) return;
    if (stroke.square) {
      _appendSquareSegment(path, stroke, point, previous);
      return;
    }
    if (previous == null) {
      path.moveTo(point.x, point.y);
    } else {
      path.lineTo(point.x, point.y);
    }
  }

  static void _appendSquareSegment(
    ui.Path path,
    InpaintStroke stroke,
    InpaintPoint point,
    InpaintPoint? previous,
  ) {
    final diameter =
        math.max(1, (stroke.size / inpaintBrushGridCellSize).round());
    final half = diameter ~/ 2;
    final shift = diameter.isEven ? 0.5 : 0.0;
    final startX = previous == null
        ? _squareCenterCell(point.x, shift)
        : _squareCenterCell(previous.x, shift);
    final startY = previous == null
        ? _squareCenterCell(point.y, shift)
        : _squareCenterCell(previous.y, shift);
    final endX = _squareCenterCell(point.x, shift);
    final endY = _squareCenterCell(point.y, shift);
    if (previous != null && startX == endX && startY == endY) return;

    var x = startX;
    var y = startY;
    final dx = (endX - x).abs();
    final dy = (endY - y).abs();
    final sx = x < endX ? 1 : -1;
    final sy = y < endY ? 1 : -1;
    var error = dx - dy;
    var first = true;
    while (true) {
      if (!first || previous == null) {
        path.addRect(ui.Rect.fromLTWH(
          (x - half) * inpaintBrushGridCellSize,
          (y - half) * inpaintBrushGridCellSize,
          diameter * inpaintBrushGridCellSize,
          diameter * inpaintBrushGridCellSize,
        ));
      }
      first = false;
      if (x == endX && y == endY) break;
      final twice = error * 2;
      if (twice > -dy) {
        error -= dy;
        x += sx;
      }
      if (twice < dx) {
        error += dx;
        y += sy;
      }
    }
  }

  static int _squareCenterCell(double value, double shift) =>
      (value / inpaintBrushGridCellSize + shift).floor();

  static void _drawImageStroke(
    ui.Canvas canvas,
    InpaintStroke stroke,
    ui.Path path,
    int pointCount,
  ) {
    final erase = stroke.mode == InpaintStrokeMode.erase;
    final paint = ui.Paint()
      ..color = Color(stroke.color).withValues(alpha: stroke.opacity)
      ..blendMode = erase ? ui.BlendMode.clear : ui.BlendMode.srcOver
      ..isAntiAlias = !stroke.square;

    if (stroke.type == InpaintStrokeType.rectangle || stroke.square) {
      canvas.drawPath(path, paint);
      return;
    }
    if (pointCount <= 1) {
      if (stroke.points.isNotEmpty) {
        final point = stroke.points.single;
        canvas.drawCircle(
          point.offset,
          math.max(0.5, stroke.size / 2),
          paint,
        );
      }
      return;
    }
    paint
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..strokeWidth = stroke.size;
    canvas.drawPath(path, paint);
  }

  static void _applyTransform(ui.Canvas canvas, InpaintTransform transform) {
    canvas.translate(transform.offsetX, transform.offsetY);
    canvas.scale(transform.scale);
  }

  static bool _sameIdentitySequence(
    List<InpaintStroke> a,
    List<InpaintStroke> b,
  ) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!identical(a[index], b[index])) return false;
    }
    return true;
  }

  void _clearActiveStroke() {
    _activeStroke = null;
    _activeMaskPath = ui.Path();
    _activeImagePath = ui.Path();
    _lastPoint = null;
    _activePointCount = 0;
  }

  void _disposePictures() {
    for (final picture in _maskPictures) {
      picture.dispose();
    }
    for (final picture in _imagePictures) {
      picture.dispose();
    }
    _maskPictures.clear();
    _imagePictures.clear();
    _maskTailPicture?.dispose();
    _imageTailPicture?.dispose();
    _maskTailPicture = null;
    _imageTailPicture = null;
    _maskTail.clear();
    _imageTail.clear();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _disposePictures();
    _geometryCache.clear();
    _strokes.clear();
    _clearActiveStroke();
    super.dispose();
  }
}

class _StrokeGeometry {
  final ui.Path maskPath;
  final ui.Path imagePath;

  const _StrokeGeometry({required this.maskPath, required this.imagePath});
}

class _StrokeRecord {
  final InpaintStroke stroke;
  final _StrokeGeometry geometry;

  const _StrokeRecord(this.stroke, this.geometry);
}
