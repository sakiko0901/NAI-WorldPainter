import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/widgets/img2img_crop_dialog.dart';

void main() {
  testWidgets('custom resolution is selected and exported by the crop dialog',
      (tester) async {
    final folder = Directory.systemTemp.createTempSync('crop-custom-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final source = File('${folder.path}/image.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 64, height: 64)));
    Img2ImgCropResult? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await showDialog<Img2ImgCropResult>(
                            context: context,
                            builder: (_) => Img2ImgCropDialog(
                                imagePath: source.path,
                                imageWidth: 64,
                                imageHeight: 64,
                                initialTarget: (704, 960)));
                      },
                      child: const Text('裁剪')),
                ))));
    await tester.tap(find.text('裁剪'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '704 × 960'))
            .selected,
        isTrue);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(result!.targetWidth, 704);
    expect(result!.targetHeight, 960);
    expect(result!.width * 960, result!.height * 704);
    expect(tester.takeException(), isNull);
  });

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
