import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/inpaint_workspace.dart';
import 'package:nai_huishi/presentation/widgets/inpaint_canvas_painter.dart';

const _canvasSize = Size(64, 64);

Future<Uint8List> _render(List<InpaintStroke> strokes) async {
  final recorder = ui.PictureRecorder();
  final painter = InpaintCanvasPainter(
    transform: const InpaintTransform(),
    strokes: strokes,
  );
  painter.paint(ui.Canvas(recorder), _canvasSize);

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    _canvasSize.width.toInt(),
    _canvasSize.height.toInt(),
  );
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final result = Uint8List.fromList(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
  image.dispose();
  picture.dispose();
  return result;
}

List<int> _pixel(Uint8List rgba, int x, int y) {
  final offset = (y * _canvasSize.width.toInt() + x) * 4;
  return rgba.sublist(offset, offset + 4);
}

InpaintStroke _maskStroke({
  required InpaintStrokeMode mode,
  required double size,
  required List<InpaintPoint> points,
  bool square = false,
}) =>
    InpaintStroke(
      target: InpaintPaintTarget.mask,
      mode: mode,
      type: InpaintStrokeType.path,
      size: size,
      points: points,
      square: square,
    );

void main() {
  test('a repeated mask stroke renders the same pixels as one stroke',
      () async {
    final stroke = _maskStroke(
      mode: InpaintStrokeMode.paint,
      size: 18,
      points: const [InpaintPoint(32, 32)],
    );

    final single = await _render([stroke]);
    final repeated = await _render([stroke, stroke]);

    expect(repeated, equals(single));
  });

  test('erasing subtracts the center from the visible mask', () async {
    final outer = _maskStroke(
      mode: InpaintStrokeMode.paint,
      size: 34,
      points: const [InpaintPoint(32, 32)],
    );
    final eraser = _maskStroke(
      mode: InpaintStrokeMode.erase,
      size: 10,
      points: const [InpaintPoint(32, 32)],
    );

    final pixels = await _render([outer, eraser]);

    expect(_pixel(pixels, 32, 32)[3], 0);
    expect(_pixel(pixels, 48, 32)[3], greaterThan(0));
  });

  test('circular and square brushes have distinct outer contours', () async {
    const point = [InpaintPoint(32, 32)];
    final circle = await _render([
      _maskStroke(
        mode: InpaintStrokeMode.paint,
        size: 20,
        points: point,
      ),
    ]);
    final square = await _render([
      _maskStroke(
        mode: InpaintStrokeMode.paint,
        size: 20,
        points: point,
        square: true,
      ),
    ]);

    expect(_pixel(circle, 45, 32)[3], 0);
    expect(_pixel(square, 45, 32)[3], greaterThan(0));
    expect(_pixel(square, 32, 32)[0], lessThan(80));
  });

  test('the merged mask has a bright highlighted outer edge', () async {
    final pixels = await _render([
      _maskStroke(
        mode: InpaintStrokeMode.paint,
        size: 20,
        points: const [InpaintPoint(32, 32)],
      ),
    ]);
    final edge = _pixel(pixels, 41, 32);

    expect(edge[3], greaterThan(220));
    expect(edge[2], greaterThan(edge[0]));
  });
}
