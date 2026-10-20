import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/inpaint_workspace.dart';
import 'package:nai_huishi/presentation/controllers/inpaint_mask_controller.dart';
import 'package:nai_huishi/presentation/widgets/inpaint_canvas_painter.dart';

const _canvasSize = Size(80, 80);

Future<Uint8List> _render(
  InpaintMaskController controller, {
  InpaintTransform transform = const InpaintTransform(),
  bool showMask = true,
  bool showImageStrokes = true,
}) async {
  final recorder = ui.PictureRecorder();
  final painter = InpaintCanvasPainter(
    transform: transform,
    strokes: const [],
    maskController: controller,
    showMask: showMask,
    showImageStrokes: showImageStrokes,
  );
  painter.paint(ui.Canvas(recorder), _canvasSize);
  final picture = recorder.endRecording();
  final image = await picture.toImage(80, 80);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = Uint8List.fromList(
    bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
  image.dispose();
  picture.dispose();
  return result;
}

List<int> _pixel(Uint8List rgba, int x, int y) {
  final offset = (y * 80 + x) * 4;
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
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opaque composition keeps repeated mask coverage flat', () async {
    final stroke = _maskStroke(
      mode: InpaintStrokeMode.paint,
      size: 20,
      points: const [InpaintPoint(32, 32)],
    );
    final controller = InpaintMaskController()..replaceStrokes([stroke]);
    final single = await _render(controller);
    controller.replaceStrokes([stroke, stroke]);
    final repeated = await _render(controller);

    expect(repeated, equals(single));
    controller.dispose();
  });

  test('live appended path renders identically after commit', () async {
    final draft = _maskStroke(
      mode: InpaintStrokeMode.paint,
      size: 14,
      points: const [InpaintPoint(16, 32)],
    );
    final completed = _maskStroke(
      mode: InpaintStrokeMode.paint,
      size: 14,
      points: const [
        InpaintPoint(16, 32),
        InpaintPoint(32, 32),
        InpaintPoint(48, 32),
      ],
    );
    final controller = InpaintMaskController()..beginStroke(draft);
    controller
      ..appendPoint(const InpaintPoint(32, 32))
      ..appendPoint(const InpaintPoint(48, 32));
    final live = await _render(controller);
    controller.finishStroke(completed);
    final committed = await _render(controller);

    expect(committed, equals(live));
    expect(controller.debugPointAppendCount, 2);
    expect(controller.debugGeometryBuildCount, 0);
    controller.dispose();
  });

  test('erase updates the hole immediately and contour follows the union',
      () async {
    final base = _maskStroke(
      mode: InpaintStrokeMode.paint,
      size: 44,
      points: const [InpaintPoint(40, 40)],
    );
    final eraseDraft = _maskStroke(
      mode: InpaintStrokeMode.erase,
      size: 12,
      points: const [InpaintPoint(40, 40)],
    );
    final controller = InpaintMaskController()..replaceStrokes([base]);
    controller.beginStroke(eraseDraft);
    final live = await _render(controller);
    controller.finishStroke(eraseDraft);
    final committed = await _render(controller);

    expect(committed, equals(live));
    expect(_pixel(live, 40, 40)[3], 0);
    expect(_pixel(live, 60, 40)[3], greaterThan(0));
    expect(_pixel(live, 46, 40)[2], greaterThan(_pixel(live, 46, 40)[0]));
    controller.dispose();
  });

  test('contour is from the union and does not draw overlap seams', () async {
    final left = _maskStroke(
      mode: InpaintStrokeMode.paint,
      size: 24,
      points: const [InpaintPoint(30, 40)],
    );
    final right = _maskStroke(
      mode: InpaintStrokeMode.paint,
      size: 24,
      points: const [InpaintPoint(46, 40)],
    );
    final controller = InpaintMaskController()..replaceStrokes([left, right]);
    final pixels = await _render(controller);

    // This point lies inside both stamps and away from the outside union edge.
    expect(_pixel(pixels, 38, 40)[0], lessThan(80));
    expect(_pixel(pixels, 38, 40)[2], greaterThan(_pixel(pixels, 38, 40)[0]));
    controller.dispose();
  });

  test('square mask stamps preserve the 8 px cell geometry', () async {
    final square = _maskStroke(
      mode: InpaintStrokeMode.paint,
      size: 16,
      square: true,
      points: const [InpaintPoint(32, 32)],
    );
    final controller = InpaintMaskController()..replaceStrokes([square]);
    final pixels = await _render(controller);

    expect(_pixel(pixels, 24, 24)[3], greaterThan(0));
    expect(_pixel(pixels, 39, 39)[3], greaterThan(0));
    expect(_pixel(pixels, 42, 42)[3], 0);
    controller.dispose();
  });

  test('picture and geometry caches do not rebuild during paint or pan',
      () async {
    final stroke = _maskStroke(
      mode: InpaintStrokeMode.paint,
      size: 18,
      points: const [InpaintPoint(32, 32), InpaintPoint(36, 36)],
    );
    final controller = InpaintMaskController()..replaceStrokes([stroke]);
    final geometryBuilds = controller.debugGeometryBuildCount;
    final pictureBuilds = controller.debugPictureBuildCount;
    await _render(controller);
    await _render(
      controller,
      transform: const InpaintTransform(scale: 1.2, offsetX: -4, offsetY: 2),
    );

    expect(controller.debugGeometryBuildCount, geometryBuilds);
    expect(controller.debugPictureBuildCount, pictureBuilds);
    controller.dispose();
  });

  test('800 pointer appends remain incremental until the stroke is committed',
      () {
    const initial = InpaintPoint(4, 40);
    final draft = _maskStroke(
      mode: InpaintStrokeMode.paint,
      size: 16,
      points: const [initial],
    );
    final points = <InpaintPoint>[initial];
    final controller = InpaintMaskController()..beginStroke(draft);
    for (var index = 1; index <= 800; index++) {
      final point = InpaintPoint(4 + index * 0.05, 40 + index % 3);
      points.add(point);
      controller.appendPoint(point);
    }

    expect(controller.debugPointAppendCount, 800);
    expect(controller.debugGeometryBuildCount, 0);
    controller.finishStroke(_maskStroke(
      mode: InpaintStrokeMode.paint,
      size: 16,
      points: List<InpaintPoint>.unmodifiable(points),
    ));
    expect(controller.debugGeometryBuildCount, 0);
    expect(controller.debugPointAppendCount, 800);
    controller.dispose();
  });

  test('image overlays can be drawn below results without mask painter replay',
      () async {
    const imageStroke = InpaintStroke(
      target: InpaintPaintTarget.image,
      mode: InpaintStrokeMode.paint,
      type: InpaintStrokeType.path,
      size: 12,
      color: 0xffff0000,
      opacity: 1,
      points: [InpaintPoint(32, 32)],
    );
    final controller = InpaintMaskController()
      ..replaceStrokes(const [imageStroke]);
    final visible = await _render(
      controller,
      showMask: false,
      showImageStrokes: true,
    );
    final hidden = await _render(
      controller,
      showMask: false,
      showImageStrokes: false,
    );

    expect(_pixel(visible, 32, 32)[3], greaterThan(0));
    expect(_pixel(hidden, 32, 32)[3], 0);
    controller.dispose();
  });
}
