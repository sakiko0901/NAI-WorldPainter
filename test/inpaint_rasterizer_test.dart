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
}
