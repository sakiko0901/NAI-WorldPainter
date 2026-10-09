import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/entities/comic_project.dart';
import 'package:nai_huishi/domain/services/comic_overlay_renderer.dart';

class ComicRasterizer {
  Future<Uint8List> renderPanel(ComicPanel panel, String imagePath) async {
    final base = await _loadImage(imagePath);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(base.width.toDouble(), base.height.toDouble());
    canvas.drawImage(base, Offset.zero, Paint());
    ComicOverlayRenderer.drawAll(canvas, size, panel.overlays);
    final image =
        await recorder.endRecording().toImage(base.width, base.height);
    return _pngBytes(image);
  }

  Future<Uint8List> renderProject(ComicProject project) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final pageSize = Size(
      project.canvasWidth.toDouble(),
      project.canvasHeight.toDouble(),
    );
    canvas.drawColor(Colors.white, BlendMode.src);
    for (final panel in project.panels) {
      final candidate = panel.selectedCandidate;
      if (candidate == null || candidate.imagePath.isEmpty) continue;
      final file = File(candidate.imagePath);
      if (!await file.exists()) continue;
      final source = await _loadImage(candidate.imagePath);
      final panelImage = await _renderPanelImage(panel, source);
      final destination = Rect.fromLTWH(
        panel.rect.x * pageSize.width,
        panel.rect.y * pageSize.height,
        panel.rect.width * pageSize.width,
        panel.rect.height * pageSize.height,
      );
      canvas.drawImageRect(
        panelImage,
        Rect.fromLTWH(
          0,
          0,
          panelImage.width.toDouble(),
          panelImage.height.toDouble(),
        ),
        destination,
        Paint()..filterQuality = FilterQuality.high,
      );
    }
    final image = await recorder
        .endRecording()
        .toImage(project.canvasWidth, project.canvasHeight);
    return _pngBytes(image);
  }

  Future<ui.Image> _renderPanelImage(ComicPanel panel, ui.Image base) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(base.width.toDouble(), base.height.toDouble());
    canvas.drawImage(base, Offset.zero, Paint());
    ComicOverlayRenderer.drawAll(canvas, size, panel.overlays);
    return recorder.endRecording().toImage(base.width, base.height);
  }

  Future<ui.Image> _loadImage(String path) async {
    final data = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  Future<Uint8List> _pngBytes(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('无法编码漫画图片');
    return data.buffer.asUint8List();
  }
}
