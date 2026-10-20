import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/domain/entities/inpaint_source_transparency.dart';
import 'package:nai_huishi/domain/entities/inpaint_workspace.dart';
import 'package:nai_huishi/domain/services/inpaint_rasterizer.dart';

void main() {
  const rasterizer = InpaintRasterizer();

  test('opaque source needs no persistent per-pixel preview buffer', () {
    final source = img.Image(width: 1024, height: 1024, numChannels: 4);
    img.fill(source, color: img.ColorRgba8(10, 20, 30, 255));
    final alpha = InpaintSourceTransparency.fromImage(source);
    expect(alpha.storageBytes, 0);
    expect(alpha.isTransparent(0, 0), isFalse);
    expect(alpha.isTransparent(1023, 1023), isFalse);
  });

  test('compact transparency preview matches full RGB rasterization exactly',
      () {
    final source = img.Image(width: 23, height: 17, numChannels: 4);
    for (final pixel in source) {
      final alpha =
          (pixel.x + pixel.y) % 5 == 0 ? 0 : (pixel.x % 3 == 0 ? 64 : 255);
      source.setPixelRgba(pixel.x, pixel.y, 30, 60, 90, alpha);
    }
    final transparency = InpaintSourceTransparency.fromImage(source);
    expect(transparency.storageBytes, (23 * 17 + 7) ~/ 8);
    final strokes = [
      const InpaintStroke(
        target: InpaintPaintTarget.mask,
        mode: InpaintStrokeMode.paint,
        type: InpaintStrokeType.path,
        size: 6,
        points: [InpaintPoint(3, 4), InpaintPoint(17, 12)],
      ),
      const InpaintStroke(
        target: InpaintPaintTarget.mask,
        mode: InpaintStrokeMode.erase,
        type: InpaintStrokeType.path,
        size: 4,
        square: true,
        points: [InpaintPoint(8, 4), InpaintPoint(8, 13)],
      ),
    ];
    for (final world in [
      const InpaintViewport(x: 0, y: 0, width: 23, height: 17),
      const InpaintViewport(x: -2.4, y: -1.6, width: 28, height: 21),
      const InpaintViewport(x: 22.6, y: 15.8, width: 2, height: 2),
    ]) {
      for (final expansion in [0, 2]) {
        for (final size in [(24, 16), (17, 23)]) {
          final full = rasterizer
              .rasterize(
                source: source,
                worldRect: world,
                outputWidth: size.$1,
                outputHeight: size.$2,
                strokes: strokes,
                expandPixels: expansion,
              )
              .mask;
          final compact = rasterizer.rasterizeMask(
            source: transparency,
            worldRect: world,
            outputWidth: size.$1,
            outputHeight: size.$2,
            strokes: strokes,
            expandPixels: expansion,
          );
          expect(img.encodePng(compact), orderedEquals(img.encodePng(full)));
          expect(
            img.encodePng(ImageUtils.alignNovelAiMask(compact)),
            orderedEquals(rasterizer.encodeMask(full)),
          );
        }
      }
    }
  });

  test('direct latent alignment preserves every selected 8-pixel cell', () {
    final mask = img.Image(width: 19, height: 11, numChannels: 4);
    mask.setPixelRgba(9, 1, 255, 255, 255, 255);
    mask.setPixelRgba(18, 10, 255, 255, 255, 255);
    final aligned = ImageUtils.alignNovelAiMask(mask);
    expect(aligned.numChannels, 1);
    for (final pixel in aligned) {
      final selected = (pixel.x >= 8 && pixel.x < 16 && pixel.y < 8) ||
          (pixel.x >= 16 && pixel.y >= 8);
      expect(pixel.r, selected ? 255 : 0);
    }
  });
}
