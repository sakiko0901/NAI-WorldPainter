import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/inpaint_workspace.dart';
import 'package:nai_huishi/domain/repositories/generation_repository.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/controllers/inpaint_mask_controller.dart';
import 'package:nai_huishi/presentation/pages/inpaint_workspace_page.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/inpaint_canvas_painter.dart';

import '../../support/frontend_generation_fake.dart';

const _crossingStrokeCount = 8;
const _moveEventsPerStroke = 50;
const _movesPerFrame = 10;

void main() {
  late _StressGenerationViewModel viewModel;
  late _UnusedHistoryRepository history;

  setUp(() {
    viewModel = _StressGenerationViewModel();
    history = _UnusedHistoryRepository();
    sl.registerSingleton<GenerationViewModel>(viewModel);
    sl.registerSingleton<GenerationQueue>(
      GenerationQueue(_UnusedGenerationRepository(), history),
    );
    sl.registerSingleton<SaveImageUseCase>(SaveImageUseCase(history));
  });

  tearDown(() async {
    InpaintWorkspaceCard.gestureActive.value = false;
    await sl.reset();
    viewModel.dispose();
  });

  testWidgets(
    '800 coalesced mask events survive erase, history, and camera gestures',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final stage = find.byKey(const ValueKey('inpaint-workspace-stage'));
      final maskCanvas = find.byKey(const ValueKey('inpaint-live-mask'));
      final workspaceBoundaryKey = GlobalKey();
      await tester.pumpWidget(
        _host(
          SingleChildScrollView(
            child: RepaintBoundary(
              key: workspaceBoundaryKey,
              child: const InpaintWorkspaceCard(),
            ),
          ),
        ),
      );
      await _loadWorkspaceImage(tester, viewModel);
      await _settleFileImages(tester);

      // Baseline pixels let the test inspect the rendered mask without
      // depending on how the painter stores or merges its geometry.
      await tester.ensureVisible(stage);
      var canvasRect = tester.getRect(maskCanvas);
      final centerSample = Offset(canvasRect.width / 2, canvasRect.height / 2);
      final armSample = centerSample + const Offset(55, 0);
      final baselineCenter = await _captureCanvasPixel(
        tester,
        workspaceBoundaryKey,
        canvasRect,
        centerSample,
      );
      final baselineArm = await _captureCanvasPixel(
        tester,
        workspaceBoundaryKey,
        canvasRect,
        armSample,
      );

      await tester.ensureVisible(find.text('画笔'));
      await _selectDrawingTool(tester, '画笔');
      await tester.pump();
      await tester.ensureVisible(stage);

      // Eight long lines cross at the center. Each gesture sends 50 move
      // events, with ten events delivered before each frame pump.
      var moveEventCount = 0;
      for (var index = 0; index < _crossingStrokeCount; index++) {
        canvasRect = tester.getRect(maskCanvas);
        moveEventCount += await _dragStroke(
          tester,
          _radialStroke(
            canvasRect,
            angle: index * math.pi / _crossingStrokeCount,
            halfLength: 74,
          ),
        );
      }
      expect(moveEventCount, 400);

      var painter = _painter(tester, maskCanvas);
      var controller = _controller(painter);
      expect(controller.strokes, hasLength(_crossingStrokeCount));
      expect(
        controller.strokes.every(
          (stroke) =>
              stroke.mode == InpaintStrokeMode.paint &&
              stroke.points.length == _moveEventsPerStroke + 1,
        ),
        isTrue,
      );
      expect(_pointCount(controller.strokes), 408);
      await _waitForMaskPreview(tester);
      canvasRect = tester.getRect(maskCanvas);
      final paintedCenter = await _captureCanvasPixel(
        tester,
        workspaceBoundaryKey,
        canvasRect,
        centerSample,
      );
      final paintedArm = await _captureCanvasPixel(
        tester,
        workspaceBoundaryKey,
        canvasRect,
        armSample,
      );
      expect(paintedCenter, isNot(equals(baselineCenter)));
      expect(paintedArm, isNot(equals(baselineArm)));

      await tester.ensureVisible(find.text('橡皮'));
      await _selectDrawingTool(tester, '橡皮');
      await tester.pump();
      await tester.ensureVisible(stage);

      // Seven shorter crossing erasures clear the center. The last follows
      // the positive horizontal arm so undo/redo has a distinct pixel oracle.
      for (var index = 0; index < _crossingStrokeCount - 1; index++) {
        canvasRect = tester.getRect(maskCanvas);
        moveEventCount += await _dragStroke(
          tester,
          _radialStroke(
            canvasRect,
            angle: index * math.pi / _crossingStrokeCount,
            halfLength: 27,
          ),
        );
      }
      canvasRect = tester.getRect(maskCanvas);
      moveEventCount += await _dragStroke(
        tester,
        _segmentStroke(
          canvasRect,
          const Offset(-20, 0),
          const Offset(70, 0),
        ),
      );
      expect(moveEventCount, 800);

      painter = _painter(tester, maskCanvas);
      controller = _controller(painter);
      expect(controller.strokes, hasLength(_crossingStrokeCount * 2));
      expect(
        controller.strokes
            .where((stroke) => stroke.mode == InpaintStrokeMode.erase)
            .every(
                (stroke) => stroke.points.length == _moveEventsPerStroke + 1),
        isTrue,
      );
      expect(_pointCount(controller.strokes), 816);
      await _waitForMaskPreview(tester);
      canvasRect = tester.getRect(maskCanvas);
      final erasedCenter = await _captureCanvasPixel(
        tester,
        workspaceBoundaryKey,
        canvasRect,
        centerSample,
      );
      final erasedArm = await _captureCanvasPixel(
        tester,
        workspaceBoundaryKey,
        canvasRect,
        armSample,
      );
      expect(erasedCenter, equals(baselineCenter));
      expect(erasedArm, equals(baselineArm));

      // Undo restores the arm sample; redo removes it again. The center stays
      // erased by the seven earlier crossing strokes.
      await tester.ensureVisible(find.byTooltip('撤销笔迹'));
      await tester.tap(find.byTooltip('撤销笔迹'));
      await tester.pump();
      painter = _painter(tester, maskCanvas);
      controller = _controller(painter);
      expect(controller.strokes, hasLength(_crossingStrokeCount * 2 - 1));
      await _waitForMaskPreview(tester);
      canvasRect = tester.getRect(maskCanvas);
      final restoredArm = await _captureCanvasPixel(
        tester,
        workspaceBoundaryKey,
        canvasRect,
        armSample,
      );
      final stillErasedCenter = await _captureCanvasPixel(
        tester,
        workspaceBoundaryKey,
        canvasRect,
        centerSample,
      );
      expect(restoredArm, isNot(equals(baselineArm)));
      expect(stillErasedCenter, equals(baselineCenter));

      await tester.ensureVisible(find.byTooltip('重做笔迹'));
      await tester.tap(find.byTooltip('重做笔迹'));
      await tester.pump();
      painter = _painter(tester, maskCanvas);
      controller = _controller(painter);
      expect(controller.strokes, hasLength(_crossingStrokeCount * 2));
      await _waitForMaskPreview(tester);
      canvasRect = tester.getRect(maskCanvas);
      final redoneArm = await _captureCanvasPixel(
        tester,
        workspaceBoundaryKey,
        canvasRect,
        armSample,
      );
      expect(redoneArm, equals(baselineArm));

      // The completed paint and erase gestures append one incremental point
      // per move. Erasing and history restoration never run boolean ops.
      expect(controller.debugPointAppendCount, 800);

      // Camera gestures operate on the accumulated strokes. Their immutable
      // stroke objects and point counts must survive pan and zoom unchanged.
      await tester.ensureVisible(find.text('整体'));
      await tester.tap(find.text('整体'));
      await tester.pump();
      painter = _painter(tester, maskCanvas);
      controller = _controller(painter);
      final controllerBeforeCamera = controller;
      final strokesBeforeCamera = List.of(controller.strokes);
      final pointCountBeforeCamera = _pointCount(controller.strokes);
      final transformBeforePan = painter.transform;
      final geometryBuildsBeforeCamera = controller.debugGeometryBuildCount;
      final pointAppendsBeforeCamera = controller.debugPointAppendCount;
      final pictureBuildsBeforeCamera = controller.debugPictureBuildCount;
      final cachedGeometryCountBeforeCamera =
          controller.debugCachedGeometryCount;
      final maskPictureCountBeforeCamera = controller.debugMaskPictureCount;
      final imagePictureCountBeforeCamera = controller.debugImagePictureCount;

      await tester.ensureVisible(stage);
      canvasRect = tester.getRect(maskCanvas);
      var panEventCount = 0;
      for (var panIndex = 0; panIndex < 3; panIndex++) {
        canvasRect = tester.getRect(maskCanvas);
        panEventCount += await _panCanvas(tester, canvasRect, panIndex);
      }
      expect(panEventCount, 144);
      painter = _painter(tester, maskCanvas);
      controller = _controller(painter);
      expect(painter.transform.offsetX, isNot(transformBeforePan.offsetX));
      _expectSameStrokeObjects(controller.strokes, strokesBeforeCamera);
      expect(_pointCount(controller.strokes), pointCountBeforeCamera);

      final scaleBeforeZoom = painter.transform.scale;
      for (var zoomIndex = 0; zoomIndex < 3; zoomIndex++) {
        await tester.ensureVisible(find.byTooltip('放大'));
        await tester.tap(find.byTooltip('放大'));
        await tester.pump();
      }
      painter = _painter(tester, maskCanvas);
      controller = _controller(painter);
      expect(painter.transform.scale, greaterThan(scaleBeforeZoom));
      _expectSameStrokeObjects(controller.strokes, strokesBeforeCamera);
      expect(_pointCount(controller.strokes), pointCountBeforeCamera);
      expect(identical(controller, controllerBeforeCamera), isTrue);
      expect(controller.debugGeometryBuildCount, geometryBuildsBeforeCamera);
      expect(controller.debugPointAppendCount, pointAppendsBeforeCamera);
      expect(controller.debugPictureBuildCount, pictureBuildsBeforeCamera);
      expect(
        controller.debugCachedGeometryCount,
        cachedGeometryCountBeforeCamera,
      );
      expect(controller.debugMaskPictureCount, maskPictureCountBeforeCamera);
      expect(controller.debugImagePictureCount, imagePictureCountBeforeCamera);
      expect(tester.takeException(), isNull);
    },
  );
}

List<Offset> _radialStroke(
  Rect canvas, {
  required double angle,
  required double halfLength,
}) =>
    List<Offset>.generate(_moveEventsPerStroke + 1, (index) {
      final progress = index / _moveEventsPerStroke;
      final distance = (progress * 2 - 1) * halfLength;
      return canvas.center +
          Offset(math.cos(angle) * distance, math.sin(angle) * distance);
    });

List<Offset> _segmentStroke(Rect canvas, Offset from, Offset to) =>
    List<Offset>.generate(_moveEventsPerStroke + 1, (index) {
      final progress = index / _moveEventsPerStroke;
      return canvas.topLeft +
          Offset(canvas.width / 2, canvas.height / 2) +
          Offset.lerp(from, to, progress)!;
    });

Future<int> _panCanvas(
  WidgetTester tester,
  Rect canvas,
  int gestureIndex,
) async {
  const moves = 48;
  final start = canvas.center + Offset(-30, -20 + gestureIndex * 2);
  final gesture = await tester.startGesture(start);
  await tester.pump();
  for (var index = 1; index <= moves; index++) {
    await gesture.moveTo(start + Offset(index * 0.5, index * 0.25));
    if (index % 8 == 0 || index == moves) await tester.pump();
  }
  await gesture.up();
  await tester.pump();
  return moves;
}

Future<int> _dragStroke(WidgetTester tester, List<Offset> points) async {
  final gesture = await tester.startGesture(points.first);
  await tester.pump();
  var moveEventCount = 0;
  for (var index = 1; index < points.length; index++) {
    await gesture.moveTo(points[index]);
    moveEventCount++;
    if (index % _movesPerFrame == 0 || index == points.length - 1) {
      // Dispatch ten move callbacks before each frame without advancing the
      // debounce clock between strokes.
      await tester.pump(Duration.zero);
    }
  }
  await gesture.up();
  await tester.pump(Duration.zero);
  return moveEventCount;
}

void _expectSameStrokeObjects(
  List<InpaintStroke> actual,
  List<InpaintStroke> expected,
) {
  expect(actual, hasLength(expected.length));
  for (var index = 0; index < expected.length; index++) {
    expect(identical(actual[index], expected[index]), isTrue);
  }
}

int _pointCount(List<InpaintStroke> strokes) => strokes.fold<int>(
      0,
      (count, stroke) => count + stroke.points.length,
    );

InpaintCanvasPainter _painter(WidgetTester tester, Finder maskCanvas) =>
    tester.widget<CustomPaint>(maskCanvas).painter! as InpaintCanvasPainter;

InpaintMaskController _controller(InpaintCanvasPainter painter) {
  final controller = painter.maskController;
  expect(controller, isNotNull);
  return controller!;
}

Future<List<int>> _captureCanvasPixel(
  WidgetTester tester,
  GlobalKey boundaryKey,
  Rect canvasRect,
  Offset canvasOffset,
) async {
  final boundaryFinder = find.byKey(boundaryKey);
  final boundary = tester.renderObject<RenderRepaintBoundary>(boundaryFinder);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final rgba =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final boundaryRect = tester.getRect(boundaryFinder);
      final point = canvasRect.topLeft + canvasOffset - boundaryRect.topLeft;
      final x = point.dx.floor().clamp(0, image.width - 1).toInt();
      final y = point.dy.floor().clamp(0, image.height - 1).toInt();
      final index = (y * image.width + x) * 4;
      return rgba.sublist(index, index + 4);
    } finally {
      image.dispose();
    }
  }))!;
}

Future<void> _waitForMaskPreview(WidgetTester tester) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final hasPreview = tester.widgetList<Image>(find.byType(Image)).any(
          (image) => image.image is MemoryImage,
        );
    if (hasPreview) {
      await _settleFileImages(tester);
      return;
    }
  }
  fail('The current inpaint mask preview did not finish rendering');
}

Widget _host(Widget child) => MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: Scaffold(body: child),
    );

const _sourceImagePath = 'assets/style_presets/style_001.jpg';

Future<void> _loadWorkspaceImage(
  WidgetTester tester,
  _StressGenerationViewModel viewModel,
) async {
  viewModel.setSourceImagePath(File(_sourceImagePath).absolute.path);
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (find.byType(Image).evaluate().isNotEmpty) break;
  }
  await tester.pumpAndSettle();
}

Future<void> _settleFileImages(WidgetTester tester) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    final loaded = images.isNotEmpty &&
        images.every((image) {
          final status = tester.binding.imageCache.statusForKey(image.image);
          return !status.pending && (status.live || status.keepAlive);
        });
    if (loaded) return;
  }
  fail('Workspace image did not finish decoding');
}

class _StressGenerationViewModel extends FrontendGenerationFake {
  @override
  String? sourceImagePath;

  @override
  double inpaintStrength = 0.96;

  @override
  bool disabledOriginalImage = false;

  @override
  bool colorCorrect = true;

  @override
  bool isBatchCancelling = false;

  @override
  String selectedResolution = '832x1216';

  @override
  Future<bool?> Function()? inpaintWorkspaceHandler;

  @override
  ImageProviderType get currentProvider => ImageProviderType.novelAi;

  @override
  void setSourceImagePath(String? path) {
    sourceImagePath = path;
    notifyListeners();
  }
}

class _UnusedGenerationRepository implements GenerationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedHistoryRepository implements HistoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _selectDrawingTool(WidgetTester tester, String label,
    {bool close = true}) async {
  await tester.ensureVisible(find.text(label));
  if (close) {
    await tester.tap(find.text(label));
  } else {
    await tester.longPress(find.text(label));
  }
  await tester.pumpAndSettle();
  if (close) {
    expect(find.byType(BottomSheet), findsNothing);
  }
}
