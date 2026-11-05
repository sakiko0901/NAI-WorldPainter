import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/domain/entities/watermark.dart';
import 'package:nai_huishi/presentation/controllers/watermark_compositor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ui.Image> solid(int width, int height, img.Color color) async {
    final image = img.Image(width: width, height: height, numChannels: 4);
    img.fill(image, color: color);
    return WatermarkCompositor.decode(Uint8List.fromList(img.encodePng(image)));
  }

  test('exports original dimensions and preserves transparent watermark edges',
      () async {
    final base = await solid(200, 100, img.ColorRgba8(255, 255, 255, 255));
    final pixels = img.Image(width: 40, height: 40, numChannels: 4);
    img.fillRect(pixels,
        x1: 10, y1: 10, x2: 29, y2: 29, color: img.ColorRgba8(255, 0, 0, 255));
    final mark = await WatermarkCompositor.decode(
        Uint8List.fromList(img.encodePng(pixels)));
    addTearDown(base.dispose);
    addTearDown(mark.dispose);
    final bytes = await WatermarkCompositor.exportPng(base, [
      const WatermarkLayer(
          id: '1', assetId: 'mark', widthFraction: .2, opacity: .5)
    ], {
      'mark': mark
    });
    final output = img.decodePng(bytes)!;
    expect(output.width, 200);
    expect(output.height, 100);
    final center = output.getPixel(100, 50);
    expect(center.r, 255);
    expect(center.g, closeTo(127, 2));
    expect(center.b, closeTo(127, 2));
    final transparentEdge = output.getPixel(82, 50);
    expect(transparentEdge.r, 255);
    expect(transparentEdge.g, 255);
    expect(transparentEdge.b, 255);
    expect(output.getPixel(0, 0).a, 255);
  });

  test('rotation, layer order and off-canvas clipping match export', () async {
    final base = await solid(200, 100, img.ColorRgba8(255, 255, 255, 255));
    final red = await solid(40, 10, img.ColorRgba8(255, 0, 0, 255));
    final blue = await solid(10, 10, img.ColorRgba8(0, 0, 255, 255));
    addTearDown(base.dispose);
    addTearDown(red.dispose);
    addTearDown(blue.dispose);
    final output = img.decodePng(await WatermarkCompositor.exportPng(base, [
      const WatermarkLayer(
          id: '1', assetId: 'red', widthFraction: .2, rotation: math.pi / 2),
      const WatermarkLayer(id: '2', assetId: 'blue', widthFraction: .05),
      const WatermarkLayer(
          id: '3', assetId: 'blue', center: ui.Offset(0, 0), widthFraction: .2),
    ], {
      'red': red,
      'blue': blue
    }))!;
    expect(output.getPixel(100, 50).b, 255);
    expect(output.getPixel(100, 36).r, 255);
    expect(output.getPixel(100, 36).g, 0);
    expect(output.getPixel(114, 50).g, 255);
    expect(output.getPixel(0, 0).b, 255);
    expect(output.width, 200);
  });

  test('strong reduction and rotation keep partially covered edge pixels',
      () async {
    final base = await solid(120, 120, img.ColorRgba8(255, 255, 255, 255));
    final mark = await solid(240, 80, img.ColorRgba8(0, 0, 0, 255));
    addTearDown(base.dispose);
    addTearDown(mark.dispose);
    final output = img.decodePng(await WatermarkCompositor.exportPng(base, [
      const WatermarkLayer(
          id: '1', assetId: 'mark', widthFraction: .2, rotation: .37)
    ], {
      'mark': mark
    }))!;
    final edgePixels =
        output.where((pixel) => pixel.r > 0 && pixel.r < 255).length;
    expect(edgePixels, greaterThan(8));
  });

  test('hit testing respects rotated bounds', () {
    const layer = WatermarkLayer(
        id: '1', assetId: 'mark', widthFraction: .4, rotation: math.pi / 2);
    expect(
        layer.contains(const ui.Offset(100, 80), const ui.Size(200, 100),
            const ui.Size(80, 20)),
        isTrue);
    expect(
        layer.contains(const ui.Offset(130, 50), const ui.Size(200, 100),
            const ui.Size(80, 20)),
        isFalse);
  });
}
