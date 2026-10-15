import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/inpaint_workspace.dart';
import 'package:nai_huishi/presentation/widgets/inpaint_canvas_painter.dart';

const _canvasSize = Size(64, 64);

Future<Uint8List> _render(
  List<InpaintStroke> strokes, {
  InpaintTransform transform = const InpaintTransform(),
  ui.Path? maskPath,
  ui.Path? previewMaskPath,
}) async {
  final recorder = ui.PictureRecorder();
  final painter = InpaintCanvasPainter(
    transform: transform,
    strokes: strokes,
    maskPath: maskPath,
    previewMaskPath: previewMaskPath,
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

ui.Path _previewStroke(ui.Path base, InpaintStroke stroke) {
  var preview = ui.Path.from(base);
  for (var index = 0; index < stroke.points.length; index++) {
    preview = InpaintCanvasPainter.appendMaskPreviewPoint(
      preview,
      stroke,
      stroke.points[index],
      previous: index == 0 ? null : stroke.points[index - 1],
    );
  }
  return preview;
}

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

  test('incremental paint preview matches the committed merged contour',
      () async {
    final base = _maskStroke(
      mode: InpaintStrokeMode.paint,
      size: 34,
      points: const [InpaintPoint(32, 32)],
    );
    final draft = _maskStroke(
      mode: InpaintStrokeMode.paint,
      size: 18,
      points: const [
        InpaintPoint(20, 32),
        InpaintPoint(32, 32),
        InpaintPoint(44, 32),
      ],
    );
    final committedPath = InpaintCanvasPainter.mergeMaskStrokes([base]);
    final previewPath = _previewStroke(committedPath!, draft);
    const transform = InpaintTransform(scale: 1.25, offsetX: -8, offsetY: -8);

    final live = await _render(
      [base, draft],
      transform: transform,
      previewMaskPath: previewPath,
    );
    final committed = await _render([base, draft], transform: transform);

    expect(live, equals(committed));
    expect(_pixel(live, 32, 32)[3], lessThanOrEqualTo(130));
  });

  test('incremental eraser preview matches committed subtraction', () async {
    final outer = _maskStroke(
      mode: InpaintStrokeMode.paint,
      size: 34,
      points: const [InpaintPoint(32, 32)],
    );
    final eraser = _maskStroke(
      mode: InpaintStrokeMode.erase,
      size: 10,
      points: const [InpaintPoint(32, 32), InpaintPoint(32, 38)],
    );
    final basePath = InpaintCanvasPainter.mergeMaskStrokes([outer]);
    final previewPath = _previewStroke(basePath!, eraser);

    final live = await _render(
      [outer, eraser],
      previewMaskPath: previewPath,
    );
    final committed = await _render([outer, eraser]);

    expect(live, equals(committed));
    expect(_pixel(live, 32, 32)[3], 0);
    expect(_pixel(live, 48, 32)[3], greaterThan(0));
  });

  test('an explicitly empty cached mask does not rebuild from old strokes',
      () async {
    final staleStroke = _maskStroke(
      mode: InpaintStrokeMode.paint,
      size: 20,
      points: const [InpaintPoint(32, 32)],
    );

    final pixels = await _render([staleStroke], maskPath: ui.Path());

    expect(_pixel(pixels, 32, 32)[3], 0);
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

  test(
    'optional mask hot-path timing sample',
    skip: !const bool.fromEnvironment('INPAINT_MASK_BENCHMARK'),
    () {
      const pointCount = 96;
      const meta = InpaintStroke(
        target: InpaintPaintTarget.mask,
        mode: InpaintStrokeMode.paint,
        type: InpaintStrokeType.path,
        size: 18,
      );
      final points = List<InpaintPoint>.generate(
        pointCount,
        (index) => InpaintPoint(4 + index * 0.5, 24 + (index % 9) * 2),
      );
      final history = List<InpaintStroke>.generate(
        6,
        (strokeIndex) => _maskStroke(
          mode: InpaintStrokeMode.paint,
          size: 5 + strokeIndex.toDouble(),
          points: List<InpaintPoint>.generate(
            12,
            (index) => InpaintPoint(
              6 + index * 3.5,
              4 + strokeIndex * 8 + (index % 3) * 2,
            ),
          ),
        ),
      );

      final oldTimer = Stopwatch()..start();
      final oldPrefix = <InpaintPoint>[];
      var oldBounds = Rect.zero;
      for (var index = 0; index < points.length; index++) {
        oldPrefix.add(points[index]);
        final oldPath = InpaintCanvasPainter.mergeMaskStrokes([
          ...history,
          _maskStroke(
            mode: InpaintStrokeMode.paint,
            size: meta.size,
            points: List<InpaintPoint>.of(oldPrefix),
          ),
        ]);
        if (oldPath != null) oldBounds = oldPath.getBounds();
      }
      oldTimer.stop();

      var livePath =
          InpaintCanvasPainter.mergeMaskStrokes(history) ?? ui.Path();
      final newTimer = Stopwatch()..start();
      for (var index = 0; index < points.length; index++) {
        livePath = InpaintCanvasPainter.appendMaskPreviewPoint(
          livePath,
          meta,
          points[index],
          previous: index == 0 ? null : points[index - 1],
        );
      }
      final newBounds = livePath.getBounds();
      newTimer.stop();

      expect(oldBounds.isEmpty, isFalse);
      expect(newBounds.isEmpty, isFalse);
      print(
        'Mask geometry sample ($pointCount events, ${history.length} history strokes): '
        'old rebuild all strokes=${oldTimer.elapsedMicroseconds}us; '
        'incremental segment merge=${newTimer.elapsedMicroseconds}us. '
        'Local path preparation only; not a device frame-rate measurement.',
      );
    },
  );
}
