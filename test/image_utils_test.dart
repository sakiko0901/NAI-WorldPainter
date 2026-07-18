import 'package:flutter_test/flutter_test.dart';
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
}
