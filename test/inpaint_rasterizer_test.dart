import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/domain/entities/inpaint_workspace.dart';
import 'package:nai_huishi/domain/services/inpaint_rasterizer.dart';

void main() {
  const rasterizer = InpaintRasterizer();
  final world = InpaintViewport(x: 0, y: 0, width: 16, height: 16);

  img.Image source() {
    final image = img.Image(width: 16, height: 16, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(20, 40, 60, 255));
    return image;
  }

  test('视口超出源图边界的区域会进入重绘遮罩', () {
    final result = rasterizer.rasterize(
      source: source(),
      worldRect: const InpaintViewport(x: -4, y: -4, width: 16, height: 16),
      outputWidth: 16,
      outputHeight: 16,
      strokes: const [],
    );

    expect(result.mask.getPixel(0, 0).a, 255);
    expect(result.mask.getPixel(12, 12).a, 0);
  });

  test('遮罩画笔与橡皮擦按顺序覆盖', () {
    final paint = InpaintStroke(
      target: InpaintPaintTarget.mask,
      mode: InpaintStrokeMode.paint,
      type: InpaintStrokeType.path,
      size: 6,
      points: const [InpaintPoint(8, 8)],
    );
    final erase = InpaintStroke(
      target: InpaintPaintTarget.mask,
      mode: InpaintStrokeMode.erase,
      type: InpaintStrokeType.path,
      size: 6,
      points: const [InpaintPoint(8, 8)],
    );

    final result = rasterizer.rasterize(
      source: source(),
      worldRect: world,
      outputWidth: 16,
      outputHeight: 16,
      strokes: [paint, erase],
    );

    expect(result.mask.getPixel(8, 8).a, 0);
  });

  test('图像层仅合成一次，栅格化不会重复绘制', () {
    final stroke = InpaintStroke(
      target: InpaintPaintTarget.image,
      mode: InpaintStrokeMode.paint,
      type: InpaintStrokeType.path,
      size: 4,
      color: 0xffff0000,
      opacity: 0.5,
      points: const [InpaintPoint(8, 8)],
    );
    final base = rasterizer.composeBase(source: source(), strokes: [stroke]);
    final result = rasterizer.rasterize(
      source: base,
      worldRect: world,
      outputWidth: 16,
      outputHeight: 16,
      strokes: [stroke],
    );

    expect(result.image.getPixel(8, 8).r, base.getPixel(8, 8).r);
  });

  test('零羽化可提取遮罩 patch 且不发生除零', () {
    final mask = img.Image(width: 16, height: 16, numChannels: 4);
    img.fill(mask, color: img.ColorRgba8(0, 0, 0, 0));
    mask.setPixelRgba(8, 8, 255, 255, 255, 255);
    final generated = source()..setPixelRgba(8, 8, 255, 0, 0, 255);

    final patch = rasterizer.extractPatch(
      generated: generated,
      mask: mask,
      worldRect: world,
      outwardFeatherPixels: 0,
    );

    expect(patch, isNotNull);
    expect(patch!.image.width, 1);
    expect(patch.image.height, 1);
    expect(patch.image.getPixel(0, 0).a, 255);
  });

  test('透明与白底导出保留预期 alpha', () {
    final patch = img.Image(width: 2, height: 2, numChannels: 4);
    img.fill(patch, color: img.ColorRgba8(0, 0, 0, 0));
    patch.setPixelRgba(0, 0, 255, 0, 0, 128);

    final transparent = img.decodePng(rasterizer.exportPng(patch))!;
    final white = img.decodePng(
      rasterizer.exportPng(patch, whiteBackground: true),
    )!;

    expect(transparent.getPixel(1, 1).a, 0);
    expect(white.getPixel(1, 1).a, 255);
  });

  test('方格笔刷使用 8px 网格并连接快速移动的笔迹', () {
    final stroke = InpaintStroke(
      target: InpaintPaintTarget.mask,
      mode: InpaintStrokeMode.paint,
      type: InpaintStrokeType.path,
      size: 16,
      square: true,
      points: const [InpaintPoint(4, 4), InpaintPoint(28, 4)],
    );

    final cells = inpaintSquareBrushCells(stroke);

    expect(cells, hasLength(10));
    for (var x = 0; x < 5; x++) {
      expect(cells, contains((x, 0)));
      expect(cells, contains((x, 1)));
    }
  });

  test('结果图层按请求遮罩保留透明边缘并应用羽化', () {
    final mask = img.Image(width: 16, height: 16, numChannels: 4);
    img.fill(mask, color: img.ColorRgba8(0, 0, 0, 0));
    mask.setPixelRgba(8, 8, 255, 255, 255, 255);
    final generated = source();

    final layer = rasterizer.maskGeneratedLayer(
      generated: generated,
      mask: mask,
      outwardFeatherPixels: 2,
    );

    expect(layer.width, generated.width);
    expect(layer.height, generated.height);
    expect(layer.getPixel(8, 8).a, 255);
    expect(layer.getPixel(9, 8).a, greaterThan(0));
    expect(layer.getPixel(10, 8).a, 0);
  });

  test('结果图层可越出原图合成且不修改锁定底图', () {
    final base = source();
    final layer = img.Image(width: 4, height: 4, numChannels: 4);
    img.fill(layer, color: img.ColorRgba8(255, 0, 0, 255));

    final composite = rasterizer.composeLayers(
      source: base,
      strokes: const [],
      layers: [
        InpaintRasterLayer(
          image: layer,
          worldRect: const InpaintViewport(x: -2, y: 4, width: 4, height: 4),
        ),
      ],
    );

    expect(composite.width, 18);
    expect(composite.height, 16);
    expect(composite.getPixel(0, 4).r, 255);
    expect(composite.getPixel(2, 0).r, 20);
    expect(base.getPixel(0, 4).r, 20);
  });
  test(
      'distance feather matches a direct pixel oracle for sparse and empty masks',
      () {
    for (final dimensions in [(13, 9), (1, 7), (8, 1)]) {
      final (width, height) = dimensions;
      final generated = img.Image(width: width, height: height, numChannels: 4);
      img.fill(generated, color: img.ColorRgba8(90, 120, 200, 255));
      for (final pattern in [0, 1, 2, 3]) {
        final mask = img.Image(width: width, height: height, numChannels: 4);
        final selected = <(int, int)>[];
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            if (pattern == 1 ||
                (pattern == 2 && (x * 7 + y * 11) % 17 == 0) ||
                (pattern == 3 && x == width - 1 && y == height - 1)) {
              mask.setPixelRgba(x, y, 255, 255, 255, 255);
              selected.add((x, y));
            }
          }
        }
        for (final radius in [0, 1, 2, 4, 24]) {
          final layer = rasterizer.maskGeneratedLayer(
              generated: generated, mask: mask, outwardFeatherPixels: radius);
          for (var y = 0; y < height; y++) {
            for (var x = 0; x < width; x++) {
              var nearest = double.infinity;
              for (final point in selected) {
                final dx = x - point.$1;
                final dy = y - point.$2;
                nearest = math.min(nearest, math.sqrt(dx * dx + dy * dy));
              }
              final distance = nearest.isFinite ? nearest.round() : radius + 1;
              final expected = distance == 0
                  ? 255
                  : radius > 0 && distance <= radius
                      ? ((1 - distance / radius) * 255).round()
                      : 0;
              expect(layer.getPixel(x, y).a, expected,
                  reason:
                      '$dimensions pattern=$pattern radius=$radius at $x,$y');
            }
          }
        }
      }
    }
  });

  test('distance dilation preserves circular neighborhood selection', () {
    final base = source();
    final strokes = [
      InpaintStroke(
          target: InpaintPaintTarget.mask,
          mode: InpaintStrokeMode.paint,
          type: InpaintStrokeType.path,
          size: 1,
          points: const [InpaintPoint(2, 3), InpaintPoint(11, 8)]),
    ];
    final raw = rasterizer
        .rasterize(
            source: base,
            worldRect: world,
            outputWidth: 16,
            outputHeight: 16,
            strokes: strokes,
            expandPixels: 0)
        .mask;
    for (final radius in [1, 2, 4, 24]) {
      final expanded = rasterizer
          .rasterize(
              source: base,
              worldRect: world,
              outputWidth: 16,
              outputHeight: 16,
              strokes: strokes,
              expandPixels: radius)
          .mask;
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          var selected = false;
          for (var sy = 0; sy < 16; sy++) {
            for (var sx = 0; sx < 16; sx++) {
              if (raw.getPixel(sx, sy).r > 0 &&
                  (x - sx) * (x - sx) + (y - sy) * (y - sy) <=
                      radius * radius) {
                selected = true;
              }
            }
          }
          expect(expanded.getPixel(x, y).r > 0, selected,
              reason: 'radius=$radius at $x,$y');
        }
      }
    }
  });
}
