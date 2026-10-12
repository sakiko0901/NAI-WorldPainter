import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/domain/entities/inpaint_workspace.dart';

class InpaintRasterResult {
  final img.Image image;
  final img.Image mask;

  const InpaintRasterResult(this.image, this.mask);
}

class InpaintExtractedPatch {
  final img.Image image;
  final InpaintViewport worldRect;

  const InpaintExtractedPatch(this.image, this.worldRect);
}

class InpaintRasterLayer {
  final img.Image image;
  final InpaintViewport worldRect;

  const InpaintRasterLayer({required this.image, required this.worldRect});
}

/// 局部重绘的像素算法。所有坐标均使用源图像素坐标。
class InpaintRasterizer {
  const InpaintRasterizer();

  /// Rasterizes [worldRect] into an output image and mask.
  ///
  /// [sourceBounds] is the world-space extent represented by [source]; it
  /// defaults to the source image's zero-origin bounds.
  InpaintRasterResult rasterize({
    required img.Image source,
    InpaintViewport? sourceBounds,
    required InpaintViewport worldRect,
    required int outputWidth,
    required int outputHeight,
    required List<InpaintStroke> strokes,
    int expandPixels = 0,
  }) {
    final image =
        img.Image(width: outputWidth, height: outputHeight, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
    final mask =
        img.Image(width: outputWidth, height: outputHeight, numChannels: 4);
    img.fill(mask, color: img.ColorRgba8(0, 0, 0, 0));

    final scaleX = outputWidth / worldRect.width;
    final scaleY = outputHeight / worldRect.height;
    final boundsX = sourceBounds?.x ?? 0.0;
    final boundsY = sourceBounds?.y ?? 0.0;
    final boundsWidth = sourceBounds?.width ?? source.width.toDouble();
    final boundsHeight = sourceBounds?.height ?? source.height.toDouble();
    final boundsRight = boundsX + boundsWidth;
    final boundsBottom = boundsY + boundsHeight;
    final sourceScaleX = source.width / boundsWidth;
    final sourceScaleY = source.height / boundsHeight;

    for (var y = 0; y < outputHeight; y++) {
      final worldY = worldRect.y + (y + 0.5) / scaleY;
      final hasSourceY = worldY >= boundsY && worldY < boundsBottom;
      final sy = hasSourceY ? ((worldY - boundsY) * sourceScaleY).floor() : -1;
      for (var x = 0; x < outputWidth; x++) {
        final worldX = worldRect.x + (x + 0.5) / scaleX;
        if (hasSourceY && worldX >= boundsX && worldX < boundsRight) {
          final sx = ((worldX - boundsX) * sourceScaleX).floor();
          final pixel = source.getPixel(sx, sy);
          image.setPixel(x, y, pixel);
          if (pixel.a == 0) mask.setPixelRgba(x, y, 255, 255, 255, 255);
        } else {
          mask.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
    }

    for (final stroke in strokes) {
      if (stroke.target == InpaintPaintTarget.mask) {
        _drawStroke(mask, stroke, worldRect, scaleX, scaleY);
      }
    }
    if (expandPixels > 0) {
      _dilate(mask, expandPixels);
    }
    return InpaintRasterResult(image, mask);
  }

  Uint8List encodeMask(img.Image mask) => ImageUtils.encodeNovelAiMask(mask);

  img.Image composeBase({
    required img.Image source,
    required List<InpaintStroke> strokes,
  }) {
    final base = img.Image.from(source);
    final rect = InpaintViewport(
      x: 0,
      y: 0,
      width: source.width.toDouble(),
      height: source.height.toDouble(),
    );
    for (final stroke in strokes) {
      if (stroke.target == InpaintPaintTarget.image) {
        _drawImageStroke(base, stroke, rect, 1, 1);
      }
    }
    return base;
  }

  /// Builds an alpha-masked overlay while preserving the exact request frame.
  img.Image maskGeneratedLayer({
    required img.Image generated,
    required img.Image mask,
    required int outwardFeatherPixels,
  }) {
    if (generated.width != mask.width || generated.height != mask.height) {
      throw ArgumentError('生成图与遮罩尺寸不一致');
    }
    final alpha = _featherAlpha(mask, outwardFeatherPixels);
    final layer = img.Image(
      width: generated.width,
      height: generated.height,
      numChannels: 4,
    );
    img.fill(layer, color: img.ColorRgba8(0, 0, 0, 0));
    for (var y = 0; y < generated.height; y++) {
      for (var x = 0; x < generated.width; x++) {
        final opacity = alpha[y][x];
        if (opacity == 0) continue;
        final pixel = generated.getPixel(x, y);
        layer.setPixelRgba(
          x,
          y,
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
          (pixel.a.toInt() * opacity / 255).round(),
        );
      }
    }
    return layer;
  }

  /// Composites image brush marks and result layers without mutating the source.
  img.Image composeLayers({
    required img.Image source,
    required List<InpaintStroke> strokes,
    required List<InpaintRasterLayer> layers,
  }) {
    final base = composeBase(source: source, strokes: strokes);
    if (layers.isEmpty) return base;

    var left = 0;
    var top = 0;
    var right = base.width;
    var bottom = base.height;
    for (final layer in layers) {
      left = math.min(left, layer.worldRect.x.floor());
      top = math.min(top, layer.worldRect.y.floor());
      right =
          math.max(right, (layer.worldRect.x + layer.worldRect.width).ceil());
      bottom =
          math.max(bottom, (layer.worldRect.y + layer.worldRect.height).ceil());
    }

    final output = img.Image(
      width: right - left,
      height: bottom - top,
      numChannels: 4,
    );
    img.fill(output, color: img.ColorRgba8(0, 0, 0, 0));
    img.compositeImage(output, base, dstX: -left, dstY: -top);
    for (final layer in layers) {
      final width = math.max(1, layer.worldRect.width.round());
      final height = math.max(1, layer.worldRect.height.round());
      final sized = layer.image.width == width && layer.image.height == height
          ? layer.image
          : img.copyResize(
              layer.image,
              width: width,
              height: height,
              interpolation: img.Interpolation.linear,
            );
      img.compositeImage(
        output,
        sized,
        dstX: layer.worldRect.x.round() - left,
        dstY: layer.worldRect.y.round() - top,
      );
    }
    return output;
  }

  InpaintExtractedPatch? extractPatch({
    required img.Image generated,
    required img.Image mask,
    required InpaintViewport worldRect,
    required int outwardFeatherPixels,
  }) {
    final patch = img.Image(
        width: generated.width, height: generated.height, numChannels: 4);
    img.fill(patch, color: img.ColorRgba8(0, 0, 0, 0));
    final alpha = _featherAlpha(mask, outwardFeatherPixels);
    for (var y = 0; y < generated.height; y++) {
      for (var x = 0; x < generated.width; x++) {
        final a = alpha[y][x];
        if (a == 0) continue;
        final pixel = generated.getPixel(x, y);
        patch.setPixelRgba(
            x, y, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt(), a);
      }
    }
    final bounds = _alphaBounds(patch);
    if (bounds == null) return null;
    final cropped = img.copyCrop(patch,
        x: bounds.$1, y: bounds.$2, width: bounds.$3, height: bounds.$4);
    final scaleX = worldRect.width / generated.width;
    final scaleY = worldRect.height / generated.height;
    return InpaintExtractedPatch(
      cropped,
      InpaintViewport(
        x: worldRect.x + bounds.$1 * scaleX,
        y: worldRect.y + bounds.$2 * scaleY,
        width: bounds.$3 * scaleX,
        height: bounds.$4 * scaleY,
      ),
    );
  }

  img.Image mergePatch({
    required img.Image base,
    required img.Image patch,
    required InpaintViewport patchRect,
    required InpaintFeather feather,
  }) {
    final left = math.min(0, patchRect.x.round());
    final top = math.min(0, patchRect.y.round());
    final right = math.max(base.width, (patchRect.x + patchRect.width).round());
    final bottom =
        math.max(base.height, (patchRect.y + patchRect.height).round());
    final result =
        img.Image(width: right - left, height: bottom - top, numChannels: 4);
    img.fill(result, color: img.ColorRgba8(0, 0, 0, 0));
    img.compositeImage(result, base, dstX: -left, dstY: -top);
    final resized = img.copyResize(patch,
        width: patchRect.width.round(), height: patchRect.height.round());
    _applyEdgeFeather(resized, feather);
    img.compositeImage(result, resized,
        dstX: patchRect.x.round() - left, dstY: patchRect.y.round() - top);
    return result;
  }

  Uint8List exportPng(img.Image image, {bool whiteBackground = false}) {
    if (whiteBackground) {
      final output =
          img.Image(width: image.width, height: image.height, numChannels: 4);
      img.fill(output, color: img.ColorRgba8(255, 255, 255, 255));
      img.compositeImage(output, image);
      return Uint8List.fromList(img.encodePng(output));
    }
    return Uint8List.fromList(img.encodePng(image));
  }

  void _drawImageStroke(img.Image target, InpaintStroke stroke,
      InpaintViewport rect, double sx, double sy) {
    if (stroke.mode == InpaintStrokeMode.erase) {
      _eraseStroke(target, stroke, rect, sx, sy);
      return;
    }
    final color = stroke.mode == InpaintStrokeMode.erase
        ? img.ColorRgba8(0, 0, 0, 0)
        : img.ColorRgba8(
            (stroke.color >> 16) & 0xff,
            (stroke.color >> 8) & 0xff,
            stroke.color & 0xff,
            (stroke.opacity.clamp(0, 1) * 255).round(),
          );
    _drawStroke(target, stroke, rect, sx, sy, colorOverride: color);
  }

  void _drawStroke(img.Image target, InpaintStroke stroke, InpaintViewport rect,
      double sx, double sy,
      {img.Color? colorOverride}) {
    if (stroke.mode == InpaintStrokeMode.erase && colorOverride == null) {
      _eraseStroke(target, stroke, rect, sx, sy);
      return;
    }
    final color = colorOverride ??
        (stroke.mode == InpaintStrokeMode.erase
            ? img.ColorRgba8(0, 0, 0, 0)
            : img.ColorRgba8(255, 255, 255, 255));
    final width = math.max(1, (stroke.size * (sx + sy) / 2).round());
    if (stroke.type == InpaintStrokeType.rectangle &&
        stroke.rectangle != null) {
      final r = stroke.rectangle!;
      img.fillRect(target,
          x1: ((r.left - rect.x) * sx).round(),
          y1: ((r.top - rect.y) * sy).round(),
          x2: ((r.right - rect.x) * sx).round(),
          y2: ((r.bottom - rect.y) * sy).round(),
          color: color);
      return;
    }
    final points = stroke.points;
    if (points.isEmpty) return;
    if (stroke.square) {
      for (final cell in inpaintSquareBrushCells(stroke)) {
        final worldLeft = cell.$1 * inpaintBrushGridCellSize;
        final worldTop = cell.$2 * inpaintBrushGridCellSize;
        final x1 = ((worldLeft - rect.x) * sx).floor();
        final y1 = ((worldTop - rect.y) * sy).floor();
        final x2 =
            (((worldLeft + inpaintBrushGridCellSize - rect.x) * sx).ceil()) - 1;
        final y2 =
            (((worldTop + inpaintBrushGridCellSize - rect.y) * sy).ceil()) - 1;
        img.fillRect(
          target,
          x1: x1,
          y1: y1,
          x2: math.max(x1, x2),
          y2: math.max(y1, y2),
          color: color,
        );
      }
      return;
    }
    for (var i = 0; i < points.length; i++) {
      final x = ((points[i].x - rect.x) * sx).round();
      final y = ((points[i].y - rect.y) * sy).round();
      if (i == 0) {
        img.fillCircle(target, x: x, y: y, radius: width ~/ 2, color: color);
      } else {
        img.drawLine(target,
            x1: ((points[i - 1].x - rect.x) * sx).round(),
            y1: ((points[i - 1].y - rect.y) * sy).round(),
            x2: x,
            y2: y,
            thickness: width,
            color: color);
      }
    }
  }

  void _eraseStroke(img.Image target, InpaintStroke stroke,
      InpaintViewport rect, double sx, double sy) {
    final coverage = img.Image(
      width: target.width,
      height: target.height,
      numChannels: 4,
    );
    img.fill(coverage, color: img.ColorRgba8(0, 0, 0, 0));
    _drawStroke(
      coverage,
      stroke,
      rect,
      sx,
      sy,
      colorOverride: img.ColorRgba8(255, 255, 255, 255),
    );
    for (final pixel in coverage) {
      if (pixel.a > 0) {
        target.setPixelRgba(pixel.x, pixel.y, 0, 0, 0, 0);
      }
    }
  }

  void _dilate(img.Image mask, int radius) {
    final distances = _squaredMaskDistances(mask);
    final limit = radius * radius;
    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        if (distances[y * mask.width + x] <= limit) {
          mask.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
    }
  }

  List<List<int>> _featherAlpha(img.Image mask, int radius) {
    final result =
        List.generate(mask.height, (_) => List.filled(mask.width, 0));
    final distances = radius > 0 ? _squaredMaskDistances(mask) : null;
    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        if (mask.getPixel(x, y).r > 0) {
          result[y][x] = 255;
        } else if (distances != null) {
          final squared = distances[y * mask.width + x];
          if (!squared.isFinite) continue;
          final distance = math.sqrt(squared).round();
          if (distance <= radius) {
            result[y][x] = ((1 - distance / radius) * 255).round();
          }
        }
      }
    }
    return result;
  }

  /// Exact Euclidean distances in O(width * height). Horizontal nearest-point
  /// scans are followed by the lower envelope of vertical squared distances.
  /// This avoids a radius-sized neighborhood search for every output pixel.
  Float64List _squaredMaskDistances(img.Image mask) {
    final width = mask.width;
    final height = mask.height;
    final distances = Float64List(width * height);
    final unreachable = (width * width + height * height + 1).toDouble();
    var hasSelectedPixel = false;
    for (var y = 0; y < height; y++) {
      var nearest = -width;
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (mask.getPixel(x, y).r > 0) {
          nearest = x;
          hasSelectedPixel = true;
        }
        distances[row + x] = nearest < 0
            ? unreachable
            : ((x - nearest) * (x - nearest)).toDouble();
      }
      nearest = width * 2;
      for (var x = width - 1; x >= 0; x--) {
        if (mask.getPixel(x, y).r > 0) nearest = x;
        if (nearest < width) {
          distances[row + x] = math.min(
            distances[row + x],
            ((nearest - x) * (nearest - x)).toDouble(),
          );
        }
      }
    }
    if (!hasSelectedPixel) {
      distances.fillRange(0, distances.length, double.infinity);
      return distances;
    }

    final values = Float64List(height);
    final sites = Int32List(height);
    final boundaries = Float64List(height + 1);
    for (var x = 0; x < width; x++) {
      for (var y = 0; y < height; y++) {
        values[y] = distances[y * width + x];
      }
      var last = 0;
      sites[0] = 0;
      boundaries[0] = double.negativeInfinity;
      boundaries[1] = double.infinity;
      for (var y = 1; y < height; y++) {
        double crossing;
        while (true) {
          final previous = sites[last];
          crossing =
              ((values[y] + y * y) - (values[previous] + previous * previous)) /
                  (2 * (y - previous));
          if (crossing > boundaries[last]) break;
          last--;
        }
        sites[++last] = y;
        boundaries[last] = crossing;
        boundaries[last + 1] = double.infinity;
      }
      var active = 0;
      for (var y = 0; y < height; y++) {
        while (boundaries[active + 1] < y) {
          active++;
        }
        final delta = y - sites[active];
        distances[y * width + x] = delta * delta + values[sites[active]];
      }
    }
    return distances;
  }

  (int, int, int, int)? _alphaBounds(img.Image image) {
    var minX = image.width;
    var minY = image.height;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (image.getPixel(x, y).a == 0) continue;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
    }
    return maxX < 0 ? null : (minX, minY, maxX - minX + 1, maxY - minY + 1);
  }

  void _applyEdgeFeather(img.Image image, InpaintFeather feather) {
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        var factor = 1.0;
        if (feather.top > 0 && y < feather.top)
          factor = math.min(factor, y / feather.top);
        if (feather.bottom > 0 && y >= image.height - feather.bottom)
          factor = math.min(factor, (image.height - 1 - y) / feather.bottom);
        if (feather.left > 0 && x < feather.left)
          factor = math.min(factor, x / feather.left);
        if (feather.right > 0 && x >= image.width - feather.right)
          factor = math.min(factor, (image.width - 1 - x) / feather.right);
        if (factor < 1) {
          final p = image.getPixel(x, y);
          image.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(),
              (p.a * factor).round());
        }
      }
    }
  }
}
