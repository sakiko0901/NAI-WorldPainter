import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:nai_huishi/domain/entities/watermark.dart';

class WatermarkCompositor {
  static void paint(ui.Canvas canvas, ui.Size size, ui.Image base,
      List<WatermarkLayer> layers, Map<String, ui.Image> images) {
    canvas.save();
    canvas.clipRect(ui.Offset.zero & size);
    canvas.drawImageRect(
        base,
        ui.Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
        ui.Offset.zero & size,
        ui.Paint()..filterQuality = ui.FilterQuality.medium);
    for (final layer in layers) {
      final image = images[layer.assetId];
      if (image == null || layer.opacity <= 0) continue;
      final width = size.width * layer.widthFraction;
      final height = width * image.height / image.width;
      canvas.save();
      canvas.translate(
          layer.center.dx * size.width, layer.center.dy * size.height);
      canvas.rotate(layer.rotation);
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromCenter(
            center: ui.Offset.zero, width: width, height: height),
        ui.Paint()
          ..isAntiAlias = true
          // Mipmaps preserve thin strokes during strong reductions; bicubic
          // filtering is useful nearer the original size and when enlarging.
          ..filterQuality = width < image.width * .5
              ? ui.FilterQuality.medium
              : ui.FilterQuality.high
          ..color = ui.Color.fromRGBO(255, 255, 255, layer.opacity),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  static Future<Uint8List> exportPng(ui.Image base, List<WatermarkLayer> layers,
      Map<String, ui.Image> images) async {
    final recorder = ui.PictureRecorder();
    paint(
        ui.Canvas(recorder),
        ui.Size(base.width.toDouble(), base.height.toDouble()),
        base,
        layers,
        images);
    final picture = recorder.endRecording();
    ui.Image? output;
    try {
      output = await picture.toImage(base.width, base.height);
      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('无法编码导出的图片');
      return Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } finally {
      output?.dispose();
      picture.dispose();
    }
  }

  static Future<ui.Image> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }
}
