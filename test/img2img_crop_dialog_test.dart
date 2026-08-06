import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/widgets/img2img_crop_dialog.dart';

void main() {
  test('matching ratio uses the full image bounds', () {
    const bounds = Rect.fromLTWH(20, 30, 416, 608);
    final crop = largestCropRectForRatio(bounds, 832 / 1216);
    expect(crop, bounds);
  });

  test('different ratio stays inside image bounds', () {
    const bounds = Rect.fromLTWH(20, 30, 416, 608);
    final crop = largestCropRectForRatio(bounds, 1);
    expect(crop.width, 416);
    expect(crop.height, 416);
    expect(crop.left, greaterThanOrEqualTo(bounds.left));
    expect(crop.top, greaterThanOrEqualTo(bounds.top));
    expect(crop.right, lessThanOrEqualTo(bounds.right));
    expect(crop.bottom, lessThanOrEqualTo(bounds.bottom));
  });
}
