import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/utils/image_utils.dart';

void main() {
  test('img2img dimensions satisfy gateway limits', () {
    for (final input in const [
      (1024, 1024),
      (1536, 1024),
      (2048, 1024),
      (2000, 2000),
      (731, 1099),
      (400, 300),
    ]) {
      final output = ImageUtils.calculateImg2ImgDimensions(input.$1, input.$2);
      expect(output.$1 % 64, 0);
      expect(output.$2 % 64, 0);
      expect(output.$1 * output.$2, lessThanOrEqualTo(1024 * 1024));
      expect(output.$1, lessThanOrEqualTo(1600));
      expect(output.$2, lessThanOrEqualTo(1600));

      final sourceRatio = input.$1 / input.$2;
      final outputRatio = output.$1 / output.$2;
      expect((sourceRatio - outputRatio).abs() / sourceRatio, lessThan(0.12));
    }
  });

  test('img2img dimensions reject invalid sizes', () {
    expect(
      () => ImageUtils.calculateImg2ImgDimensions(0, 1024),
      throwsArgumentError,
    );
  });

  test('img2img crop maps the visible viewport back to original pixels', () {
    final centered = ImageUtils.calculateImg2ImgCropRect(
      imageWidth: 4000,
      imageHeight: 3000,
      viewportWidth: 300,
      viewportHeight: 300,
      displayScale: 0.1,
      offsetX: 0,
      offsetY: 0,
      targetWidth: 1024,
      targetHeight: 1024,
    );
    expect(centered, (500, 0, 3000, 3000));

    final shifted = ImageUtils.calculateImg2ImgCropRect(
      imageWidth: 4000,
      imageHeight: 3000,
      viewportWidth: 300,
      viewportHeight: 300,
      displayScale: 0.1,
      offsetX: -50,
      offsetY: 0,
      targetWidth: 1024,
      targetHeight: 1024,
    );
    expect(shifted, (1000, 0, 3000, 3000));
  });

  test('img2img crop uses the exact reduced NovelAI ratio', () {
    final portrait = ImageUtils.calculateImg2ImgCropRect(
      imageWidth: 2000,
      imageHeight: 2000,
      viewportWidth: 208,
      viewportHeight: 304,
      displayScale: 0.152,
      offsetX: 0,
      offsetY: 0,
      targetWidth: 832,
      targetHeight: 1216,
    );
    expect(portrait.$3 * 1216, portrait.$4 * 832);
    expect(portrait.$3, 1365);
    expect(portrait.$4, 1995);
  });

  test('img2img crop exports all NovelAI aspect ratios without stretching', () {
    final source = img.Image(width: 2432, height: 2432);
    img.fill(source, color: img.ColorRgb8(20, 40, 60));
    final bytes = img.encodePng(source);

    for (final target in const [
      (832, 1216),
      (1024, 1024),
      (1216, 832),
    ]) {
      final divisor = target.$1 == target.$2 ? 1 : 64;
      final cropWidth = target.$1 ~/ divisor * 2;
      final cropHeight = target.$2 ~/ divisor * 2;
      final output = ImageUtils.cropImg2ImgBytes(
        bytes,
        cropX: 10,
        cropY: 20,
        cropWidth: cropWidth,
        cropHeight: cropHeight,
        targetWidth: target.$1,
        targetHeight: target.$2,
      );
      final decoded = img.decodePng(output)!;
      expect(decoded.width, target.$1);
      expect(decoded.height, target.$2);
    }
  });

  test('img2img crop rejects out-of-bounds and mismatched ratios', () {
    final bytes = img.encodePng(img.Image(width: 100, height: 100));
    expect(
      () => ImageUtils.cropImg2ImgBytes(
        bytes,
        cropX: 90,
        cropY: 0,
        cropWidth: 20,
        cropHeight: 20,
        targetWidth: 1024,
        targetHeight: 1024,
      ),
      throwsArgumentError,
    );
    expect(
      () => ImageUtils.cropImg2ImgBytes(
        bytes,
        cropX: 0,
        cropY: 0,
        cropWidth: 50,
        cropHeight: 40,
        targetWidth: 1024,
        targetHeight: 1024,
      ),
      throwsArgumentError,
    );
  });

  test('NovelAI mask preserves repaint strokes inside a latent cell', () {
    final mask = img.Image(width: 8, height: 8, numChannels: 4);
    img.fill(mask, color: img.ColorRgba8(0, 0, 0, 255));
    mask.setPixelRgba(4, 4, 255, 255, 255, 255);

    final decoded = img.decodePng(ImageUtils.encodeNovelAiMask(mask))!;

    for (final pixel in decoded) {
      expect(pixel.r, 255);
    }
  });

  test('NovelAI mask is grayscale, binary and aligned to 8px cells', () {
    final mask = img.Image(width: 16, height: 16, numChannels: 4);
    img.fill(mask, color: img.ColorRgba8(0, 0, 0, 255));
    img.fillRect(
      mask,
      x1: 3,
      y1: 3,
      x2: 10,
      y2: 10,
      color: img.ColorRgba8(255, 255, 255, 255),
    );

    final encoded = ImageUtils.encodeNovelAiMask(mask);
    final decoded = img.decodePng(encoded)!;

    expect(decoded.numChannels, 1);
    for (var cellY = 0; cellY < decoded.height; cellY += 8) {
      for (var cellX = 0; cellX < decoded.width; cellX += 8) {
        final value = decoded.getPixel(cellX, cellY).r;
        expect(value, anyOf(0, 255));
        for (var y = cellY; y < cellY + 8; y++) {
          for (var x = cellX; x < cellX + 8; x++) {
            expect(decoded.getPixel(x, y).r, value);
          }
        }
      }
    }
  });
}
