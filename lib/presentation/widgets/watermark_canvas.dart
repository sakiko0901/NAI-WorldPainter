import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/entities/watermark.dart';
import 'package:nai_huishi/presentation/controllers/watermark_compositor.dart';

class WatermarkCanvas extends StatefulWidget {
  final ui.Image base;
  final List<WatermarkLayer> layers;
  final Map<String, ui.Image> images;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String?> onSelected;
  final ValueChanged<WatermarkLayer> onChanged;

  const WatermarkCanvas({
    super.key,
    required this.base,
    required this.layers,
    required this.images,
    required this.selectedId,
    required this.enabled,
    required this.onSelected,
    required this.onChanged,
  });

  @override
  State<WatermarkCanvas> createState() => _WatermarkCanvasState();
}

class _WatermarkCanvasState extends State<WatermarkCanvas> {
  WatermarkLayer? _startLayer;
  Offset _startFocal = Offset.zero;
  Offset? _downPoint;
  bool _transformHandle = false;

  WatermarkLayer? get _selected {
    for (final layer in widget.layers) {
      if (layer.id == widget.selectedId) return layer;
    }
    return null;
  }

  bool _hitsHandle(Offset point, WatermarkLayer layer, Rect rect) {
    final image = widget.images[layer.assetId];
    if (image == null) return false;
    return _corners(layer, image, rect)
        .any((corner) => (corner - point).distance <= 24);
  }

  Rect _imageRect(Size size) {
    final imageSize =
        Size(widget.base.width.toDouble(), widget.base.height.toDouble());
    final fit = applyBoxFit(BoxFit.contain, imageSize, size);
    return Alignment.center.inscribe(fit.destination, Offset.zero & size);
  }

  WatermarkLayer? _hit(Offset point, Rect rect) {
    if (!rect.contains(point)) return null;
    for (final layer in widget.layers.reversed) {
      final image = widget.images[layer.assetId];
      if (image != null &&
          layer.contains(point - rect.topLeft, rect.size,
              Size(image.width.toDouble(), image.height.toDouble()))) {
        return layer;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final rect = _imageRect(constraints.biggest);
        return GestureDetector(
          key: const ValueKey('watermark-canvas-gestures'),
          behavior: HitTestBehavior.opaque,
          onTapUp: widget.enabled
              ? (details) {
                  final hit = _hit(details.localPosition, rect);
                  if (hit != null) widget.onSelected(hit.id);
                }
              : null,
          onScaleStart: widget.enabled
              ? (details) {
                  final point = _downPoint ?? details.localFocalPoint;
                  _startLayer = _selected ?? _hit(point, rect);
                  _startFocal = details.localFocalPoint;
                  _transformHandle = details.pointerCount == 1 &&
                      _startLayer != null &&
                      _hitsHandle(point, _startLayer!, rect);
                  if (_transformHandle) _startFocal = point;
                  if (_startLayer != null) widget.onSelected(_startLayer!.id);
                }
              : null,
          onScaleUpdate: widget.enabled
              ? (details) {
                  final start = _startLayer;
                  if (start == null) return;
                  final center = rect.topLeft +
                      Offset(start.center.dx * rect.width,
                          start.center.dy * rect.height);
                  var scale = details.scale;
                  var rotation = details.rotation;
                  var next = center + details.localFocalPoint - _startFocal;
                  if (_transformHandle && details.pointerCount == 1) {
                    final from = _startFocal - center;
                    final to = details.localFocalPoint - center;
                    if (from.distance > 1) {
                      scale = to.distance / from.distance;
                      rotation = to.direction - from.direction;
                    }
                    next = center;
                  }
                  next -= rect.topLeft;
                  widget.onChanged(start.copyWith(
                    center: Offset((next.dx / rect.width).clamp(0.0, 1.0),
                        (next.dy / rect.height).clamp(0.0, 1.0)),
                    widthFraction:
                        (start.widthFraction * scale).clamp(.02, 1.5),
                    rotation:
                        (start.rotation + rotation + math.pi) % (2 * math.pi) -
                            math.pi,
                  ));
                }
              : null,
          onScaleEnd: (_) => _startLayer = null,
          child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) => _downPoint = event.localPosition,
              onPointerUp: (_) => _downPoint = null,
              onPointerCancel: (_) => _downPoint = null,
              child: RepaintBoundary(
                  child: CustomPaint(
                painter: _WatermarkPainter(
                    widget.base,
                    widget.layers,
                    widget.images,
                    widget.selectedId,
                    rect,
                    Theme.of(context).colorScheme.primary),
                child: const SizedBox.expand(),
              ))),
        );
      });
}

class _WatermarkPainter extends CustomPainter {
  final ui.Image base;
  final List<WatermarkLayer> layers;
  final Map<String, ui.Image> images;
  final String? selectedId;
  final Rect imageRect;
  final Color selectionColor;

  _WatermarkPainter(this.base, this.layers, this.images, this.selectedId,
      this.imageRect, this.selectionColor);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(imageRect.left, imageRect.top);
    WatermarkCompositor.paint(canvas, imageRect.size, base, layers, images);

    for (final layer in layers) {
      final image = images[layer.assetId];
      if (layer.id != selectedId || image == null) continue;
      final width = imageRect.width * layer.widthFraction;
      final height = width * image.height / image.width;
      canvas.save();
      canvas.translate(layer.center.dx * imageRect.width,
          layer.center.dy * imageRect.height);
      canvas.rotate(layer.rotation);
      final rect =
          Rect.fromCenter(center: Offset.zero, width: width, height: height);
      canvas.drawRect(
          rect,
          Paint()
            ..color = Colors.black54
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
      canvas.drawRect(
          rect,
          Paint()
            ..color = selectionColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      for (final point in [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight
      ]) {
        canvas.drawCircle(point, 12, Paint()..color = Colors.white);
        canvas.drawCircle(
            point,
            12,
            Paint()
              ..color = selectionColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
        canvas.drawLine(
            point - const Offset(5, 0),
            point + const Offset(5, 0),
            Paint()
              ..color = selectionColor
              ..strokeWidth = 2);
        canvas.drawLine(
            point - const Offset(0, 5),
            point + const Offset(0, 5),
            Paint()
              ..color = selectionColor
              ..strokeWidth = 2);
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WatermarkPainter oldDelegate) => true;
}

List<Offset> _corners(WatermarkLayer layer, ui.Image image, Rect rect) {
  final width = rect.width * layer.widthFraction;
  final bounds = Rect.fromCenter(
      center: Offset.zero,
      width: width,
      height: width * image.height / image.width);
  final center = rect.topLeft +
      Offset(layer.center.dx * rect.width, layer.center.dy * rect.height);
  final cos = math.cos(layer.rotation);
  final sin = math.sin(layer.rotation);
  return [
    bounds.topLeft,
    bounds.topRight,
    bounds.bottomLeft,
    bounds.bottomRight
  ]
      .map((p) =>
          center + Offset(p.dx * cos - p.dy * sin, p.dx * sin + p.dy * cos))
      .toList();
}
