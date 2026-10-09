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

/// 局部重绘的像素算法。所有坐标均使用源图像素坐标。
class InpaintRasterizer {
  const InpaintRasterizer();

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
    final sourceLeft = worldRect.x.round();
    final sourceTop = worldRect.y.round();
    final sourceRight = (worldRect.x + worldRect.width).round();
    final sourceBottom = (worldRect.y + worldRect.height).round();

    for (var y = 0; y < outputHeight; y++) {
      final sy = sourceTop + (y / scaleY).floor();
      for (var x = 0; x < outputWidth; x++) {
        final sx = sourceLeft + (x / scaleX).floor();
        if (sx >= 0 &&
            sy >= 0 &&
            sx < source.width &&
            sy < source.height &&
            sx < sourceRight &&
            sy < sourceBottom) {
          image.setPixel(x, y, source.getPixel(sx, sy));
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
      // 方形笔刷：沿路径逐点绘制方块。
      final half = width ~/ 2;
      for (var i = 0; i < points.length; i++) {
        final x = ((points[i].x - rect.x) * sx).round();
        final y = ((points[i].y - rect.y) * sy).round();
        if (i == 0) {
          img.fillRect(target,
              x1: x - half,
              y1: y - half,
              x2: x + half,
              y2: y + half,
              color: color);
        } else {
          // 线段上按步长补方块，避免快速划过出现断点。
          final prevX = ((points[i - 1].x - rect.x) * sx).round();
          final prevY = ((points[i - 1].y - rect.y) * sy).round();
          final dx = x - prevX;
          final dy = y - prevY;
          final steps = math.max(dx.abs(), dy.abs());
          final stepCount = steps <= 1 ? 1 : steps;
          for (var t = 0; t <= stepCount; t++) {
            final ix = prevX + dx * t ~/ stepCount;
            final iy = prevY + dy * t ~/ stepCount;
            img.fillRect(target,
                x1: ix - half,
                y1: iy - half,
                x2: ix + half,
                y2: iy + half,
                color: color);
          }
        }
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

  void _dilate(img.Image mask, int radius) {
    final original = img.Image.from(mask);
    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        var white = false;
        for (var dy = -radius; dy <= radius && !white; dy++) {
          for (var dx = -radius; dx <= radius; dx++) {
            if (dx * dx + dy * dy > radius * radius) continue;
            final px = x + dx;
            final py = y + dy;
            if (px >= 0 &&
                py >= 0 &&
                px < original.width &&
                py < original.height &&
                original.getPixel(px, py).r > 0) {
              white = true;
              break;
            }
          }
        }
        if (white) mask.setPixelRgba(x, y, 255, 255, 255, 255);
      }
    }
  }

  List<List<int>> _featherAlpha(img.Image mask, int radius) {
    final result =
        List.generate(mask.height, (_) => List.filled(mask.width, 0));
    if (radius <= 0) {
      for (var y = 0; y < mask.height; y++) {
        for (var x = 0; x < mask.width; x++) {
          result[y][x] = mask.getPixel(x, y).r > 0 ? 255 : 0;
        }
      }
      return result;
    }
    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        if (mask.getPixel(x, y).r > 0) {
          result[y][x] = 255;
          continue;
        }
        var distance = radius + 1;
        for (var dy = -radius; dy <= radius; dy++) {
          for (var dx = -radius; dx <= radius; dx++) {
            final px = x + dx;
            final py = y + dy;
            if (px < 0 || py < 0 || px >= mask.width || py >= mask.height)
              continue;
            if (mask.getPixel(px, py).r > 0) {
              distance =
                  math.min(distance, math.sqrt(dx * dx + dy * dy).round());
            }
          }
        }
        if (distance <= radius)
          result[y][x] = ((1 - distance / radius) * 255).round();
      }
    }
    return result;
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
