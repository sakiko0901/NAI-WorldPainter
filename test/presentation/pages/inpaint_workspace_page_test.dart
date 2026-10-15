import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/repositories/generation_repository.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/inpaint_workspace_page.dart';
import 'package:nai_huishi/presentation/widgets/inpaint_canvas_painter.dart';
import 'package:nai_huishi/presentation/widgets/inpaint_comparison.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';

import '../../support/frontend_generation_fake.dart';

void main() {
  late _InpaintGenerationFake vm;
  late _UnusedHistoryRepository history;
  late Directory outputDirectory;
  late _SuccessfulGenerationRepository generationRepository;
  late bool cleanupOutputAfterUnmount;

  setUp(() async {
    cleanupOutputAfterUnmount = false;
    outputDirectory = await Directory.systemTemp.createTemp('inpaint_widget_');
    generationRepository = _SuccessfulGenerationRepository(outputDirectory);
    vm = _InpaintGenerationFake();
    history = _UnusedHistoryRepository();
    sl.registerSingleton<GenerationViewModel>(vm);
    sl.registerSingleton<GenerationQueue>(
      GenerationQueue(generationRepository, history),
    );
    sl.registerSingleton<SaveImageUseCase>(SaveImageUseCase(history));
  });

  tearDown(() async {
    InpaintWorkspaceCard.gestureActive.value = false;
    await sl.reset();
    vm.dispose();
    if (!cleanupOutputAfterUnmount && await outputDirectory.exists()) {
      await outputDirectory.delete(recursive: true);
    }
  });

  testWidgets('workspace shows the full canvas before tools and prompts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      _host(
        ValueListenableBuilder<bool>(
          valueListenable: InpaintWorkspaceCard.gestureActive,
          builder: (context, locked, child) => SingleChildScrollView(
            controller: scrollController,
            physics: locked
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
            child: child,
          ),
          child: const InpaintWorkspaceCard(),
        ),
      ),
    );
    await _loadWorkspaceImage(tester, vm);

    final header = tester.getTopLeft(
      find.byKey(const ValueKey('inpaint-workspace-header')),
    );
    final stage = find.byKey(const ValueKey('inpaint-workspace-stage'));
    final toolbar = tester.getTopLeft(
      find.byKey(const ValueKey('inpaint-workspace-toolbar')),
    );
    final promptPanel = tester.getTopLeft(
      find.byKey(const ValueKey('inpaint-prompt-panel')),
    );
    expect(tester.getTopLeft(stage).dy, greaterThan(header.dy));
    expect(toolbar.dy, greaterThan(tester.getTopLeft(stage).dy));
    expect(promptPanel.dy, greaterThan(toolbar.dy));
    expect(find.textContaining('px'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.minLines, 3);
      expect(field.maxLines, 6);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('painting locks parent scroll until the pointer is released', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      _host(
        ValueListenableBuilder<bool>(
          valueListenable: InpaintWorkspaceCard.gestureActive,
          builder: (context, locked, child) => SingleChildScrollView(
            controller: scrollController,
            physics: locked
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
            child: child,
          ),
          child: const InpaintWorkspaceCard(),
        ),
      ),
    );
    await _loadWorkspaceImage(tester, vm);
    await tester.tap(find.text('画笔'));
    await tester.pumpAndSettle();

    final stageRect = tester.getRect(
      find.byKey(const ValueKey('inpaint-workspace-stage')),
    );
    final gesture = await tester.startGesture(stageRect.center);
    await tester.pump();
    expect(InpaintWorkspaceCard.gestureActive.value, isTrue);
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 50));
    expect(scrollController.offset, 0);
    expect(InpaintWorkspaceCard.gestureActive.value, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(InpaintWorkspaceCard.gestureActive.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'square brush stays square during dragging and mask can be hidden',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 1600), textScaler: TextScaler.linear(2)),
        child: const SingleChildScrollView(child: InpaintWorkspaceCard()),
      )),
    );
    await _loadWorkspaceImage(tester, vm);
    await tester.ensureVisible(find.text('画笔'));
    await tester.tap(find.text('画笔'));
    await tester.pumpAndSettle();
    final squareChip = find.widgetWithText(ChoiceChip, '方格');
    await tester.ensureVisible(squareChip);
    await tester.pumpAndSettle();
    await tester.tap(squareChip);
    await tester.pumpAndSettle();
    final stage = find.byKey(const ValueKey('inpaint-workspace-stage'));
    await tester.ensureVisible(stage);
    final gesture = await tester.startGesture(tester.getRect(stage).center);
    await tester.pump();
    InpaintCanvasPainter painter() => tester
        .widget<CustomPaint>(find.byKey(const ValueKey('inpaint-live-mask')))
        .painter! as InpaintCanvasPainter;
    final painterBeforeMove = painter();
    final initialPreview = painterBeforeMove.previewMaskPathListenable!.value!;
    final initialBounds = initialPreview.getBounds();
    const maskBoundaryKey = ValueKey('inpaint-mask-repaint-boundary');
    final pixelsBeforeMove =
        await _captureRepaintBoundaryPixels(tester, maskBoundaryKey);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(identical(painter(), painterBeforeMove), isTrue);
    final movedPreview = painter().previewMaskPathListenable!.value!;
    expect(identical(movedPreview, initialPreview), isFalse);
    expect(movedPreview.getBounds().right, greaterThan(initialBounds.right));
    final pixelsAfterMove =
        await _captureRepaintBoundaryPixels(tester, maskBoundaryKey);
    expect(_pixelsDiffer(pixelsBeforeMove, pixelsAfterMove), isTrue);
    expect(painter().strokes.single.square, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(painter().strokes.single.square, isTrue);
    expect(painter().maskPath!.getBounds().isEmpty, isFalse);

    final undoMask = find.byTooltip('撤销蒙版');
    await tester.ensureVisible(undoMask);
    await tester.tap(undoMask);
    await tester.pumpAndSettle();
    expect(painter().maskPath!.getBounds().isEmpty, isTrue);
    final redoMask = find.byTooltip('重做蒙版');
    await tester.ensureVisible(redoMask);
    await tester.tap(redoMask);
    await tester.pumpAndSettle();
    expect(painter().maskPath!.getBounds().isEmpty, isFalse);

    await tester.ensureVisible(find.byTooltip('隐藏蒙版'));
    await tester.tap(find.byTooltip('隐藏蒙版'));
    await tester.pumpAndSettle();
    expect(painter().showMask, isFalse);
    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .where((image) => image.image is MemoryImage),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing a held mask stroke cannot restore stale cached content',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(
      const SingleChildScrollView(child: InpaintWorkspaceCard()),
    ));
    await _loadWorkspaceImage(tester, vm);
    await tester.tap(find.text('画笔'));
    await tester.pumpAndSettle();
    final stage = find.byKey(const ValueKey('inpaint-workspace-stage'));
    await tester.drag(stage, const Offset(25, 0));
    await tester.pumpAndSettle();
    InpaintCanvasPainter painter() => tester
        .widget<CustomPaint>(find.byKey(const ValueKey('inpaint-live-mask')))
        .painter! as InpaintCanvasPainter;
    expect(painter().maskPath!.getBounds().isEmpty, isFalse);
    final held =
        await tester.startGesture(tester.getCenter(stage), pointer: 33);
    await tester.pump();
    await held.moveBy(const Offset(-25, 10));
    await tester.pump();
    await tester.tap(find.byTooltip('清空蒙版'));
    await tester.pump();
    await held.up();
    await tester.pumpAndSettle();
    expect(painter().strokes, isEmpty);
    expect(painter().maskPath!.getBounds().isEmpty, isTrue);
    expect(painter().previewMaskPathListenable!.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'candidates compare before selection and only the winner is applied', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    cleanupOutputAfterUnmount = true;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      tester.binding.imageCache.clear();
      tester.binding.imageCache.clearLiveImages();
      try {
        if (await outputDirectory.exists()) {
          await outputDirectory.delete(recursive: true);
        }
      } on PathAccessException {
        // Windows may hold decoded FileImage data until the test engine exits.
      }
    });
    _setDocumentsDirectory(tester, outputDirectory);
    await tester.pumpWidget(
      _host(
        const MediaQuery(
          data: MediaQueryData(
              size: Size(320, 1600), textScaler: TextScaler.linear(2)),
          child: SingleChildScrollView(child: InpaintWorkspaceCard()),
        ),
      ),
    );
    await _loadWorkspaceImage(tester, vm);
    await tester.ensureVisible(find.text('画笔'));
    await tester.tap(find.text('画笔'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('inpaint-workspace-stage')),
    );
    final stage = tester.getRect(
      find.byKey(const ValueKey('inpaint-workspace-stage')),
    );
    final gesture = await tester.startGesture(stage.center);
    await gesture.moveBy(const Offset(42, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    vm.batchCount = 3;
    final generate = vm.inpaintWorkspaceHandler;
    expect(generate, isNotNull);
    final firstHandled = await tester.runAsync(generate!);
    await tester.pumpAndSettle();
    expect(firstHandled, isTrue);
    expect(find.text('结果图层 1'), findsNothing);
    expect(find.byType(InpaintComparison), findsOneWidget);
    expect(find.text('候选结果 3 / 3'), findsOneWidget);
    expect(generationRepository.submittedTasks, hasLength(3));
    final immutableSource =
        generationRepository.submittedTasks.first.sourceImagePath;
    expect(immutableSource, isNot(generationRepository.generatedPaths.first));

    // A failed new request must not remove the previous candidates.
    vm.batchCount = 1;
    generationRepository.failNext = true;
    await tester.runAsync(generate);
    await tester.pumpAndSettle();
    expect(find.text('候选结果 3 / 3'), findsOneWidget);
    expect(find.byType(InpaintComparison), findsOneWidget);

    // Discard an inferior candidate, then apply exactly one of the remaining two.
    await tester
        .ensureVisible(find.byKey(const ValueKey('inpaint-discard-candidate')));
    await tester.tap(find.byKey(const ValueKey('inpaint-discard-candidate')));
    await tester.pumpAndSettle();
    expect(find.text('候选结果 2 / 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('inpaint-candidate-0')));
    await tester.pumpAndSettle();
    final firstReview =
        tester.widget<InpaintComparison>(find.byType(InpaintComparison));
    final firstPreview =
        img.decodePng(File(firstReview.afterPath).readAsBytesSync())!;
    expect(firstPreview.getPixel(64, 64).r.toInt(), 247);
    await tester.tap(find.byKey(const ValueKey('inpaint-apply-candidate')));
    await tester.pumpAndSettle();
    expect(find.text('结果图层 1'), findsOneWidget);
    expect(find.byType(InpaintComparison), findsNothing);

    // Picking a better alternative replaces this batch's winner instead of stacking it.
    await tester.tap(find.byKey(const ValueKey('inpaint-candidate-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inpaint-apply-candidate')));
    await tester.pumpAndSettle();
    expect(find.text('结果图层 1'), findsOneWidget);
    expect(find.text('结果图层 2'), findsNothing);

    vm.batchCount = 1;
    await tester.ensureVisible(find.byTooltip('清空蒙版'));
    await tester.tap(find.byTooltip('清空蒙版'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('画笔'));
    await tester.tap(find.text('画笔'));
    await tester.pumpAndSettle();
    final nextStage = find.byKey(const ValueKey('inpaint-workspace-stage'));
    await tester.ensureVisible(nextStage);
    final nextStroke = await tester.startGesture(
      tester.getRect(nextStage).center - const Offset(0, 12),
    );
    await nextStroke.up();
    await tester.pumpAndSettle();

    final secondHandled = await tester.runAsync(generate);
    await tester.pumpAndSettle();
    expect(secondHandled, isTrue);
    expect(find.text('结果图层 1'), findsOneWidget);
    expect(generationRepository.submittedTasks, hasLength(5));
    final secondReview =
        tester.widget<InpaintComparison>(find.byType(InpaintComparison));
    final secondBefore =
        img.decodePng(File(secondReview.beforePath).readAsBytesSync())!;
    final secondAfter =
        img.decodePng(File(secondReview.afterPath).readAsBytesSync())!;
    expect(secondBefore.getPixel(64, 80).g.toInt(), 87);
    expect(secondAfter.getPixel(64, 80).g.toInt(), 87);
    expect(secondAfter.getPixel(64, 12).g.toInt(), 111);
    expect(
      generationRepository.submittedTasks.last.sourceImagePath,
      isNot(generationRepository.generatedPaths.first),
    );
    final firstBase = File(immutableSource!).readAsBytesSync();
    final secondBase = File(
      generationRepository.submittedTasks.last.sourceImagePath!,
    ).readAsBytesSync();
    expect(secondBase, orderedEquals(firstBase));
    await tester
        .ensureVisible(find.byKey(const ValueKey('inpaint-apply-candidate')));
    await tester.tap(find.byKey(const ValueKey('inpaint-apply-candidate')));
    await tester.pumpAndSettle();
    expect(find.text('结果图层 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture rendered inpaint workspace for mobile visual QA', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('FRONTEND_CAPTURE')) return;
    cleanupOutputAfterUnmount = true;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      tester.binding.imageCache.clear();
      tester.binding.imageCache.clearLiveImages();
      try {
        if (await outputDirectory.exists()) {
          await outputDirectory.delete(recursive: true);
        }
      } on PathAccessException {
        // Windows may hold decoded FileImage data until the test engine exits.
      }
    });
    await _loadCaptureFonts();
    vm.selectedResolution = '832x1216';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final preloadKey = const ValueKey('inpaint-capture-preload');
    _setDocumentsDirectory(tester, outputDirectory);

    await tester.pumpWidget(_host(SizedBox(key: preloadKey)));
    await tester.runAsync(() async {
      await precacheImage(
        FileImage(File(_sourceImagePath).absolute),
        tester.element(find.byKey(preloadKey)),
      );
    });
    await tester.pumpWidget(
      _host(
        SingleChildScrollView(
          child: RepaintBoundary(
            key: key,
            child: const InpaintWorkspaceCard(),
          ),
        ),
      ),
    );
    await _loadWorkspaceImage(tester, vm);
    await tester.tap(find.text('画笔'));
    await tester.pumpAndSettle();
    final stage = tester.getRect(
      find.byKey(const ValueKey('inpaint-workspace-stage')),
    );
    final brush = await tester.startGesture(stage.center);
    await brush.moveBy(const Offset(42, 0));
    await brush.up();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '方格'));
    await tester.pumpAndSettle();
    final square =
        await tester.startGesture(stage.center - const Offset(50, 60));
    await square.moveBy(const Offset(36, 0));
    await square.up();
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (tester
          .widgetList<Image>(find.byType(Image))
          .any((image) => image.image is MemoryImage)) break;
    }
    await _captureBoundary(tester, key, 'inpaint-mask-revision.png');
    await tester.runAsync(vm.inpaintWorkspaceHandler!);
    await tester.pumpAndSettle();
    await _settleFileImages(tester);
    expect(find.text('候选结果 1 / 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _captureBoundary(tester, key, 'inpaint-comparison-revision.png');
    await tester
        .ensureVisible(find.byKey(const ValueKey('inpaint-apply-candidate')));
    await tester.tap(find.byKey(const ValueKey('inpaint-apply-candidate')));
    await tester.pumpAndSettle();
    await _settleFileImages(tester);
    expect(find.text('结果图层 1'), findsOneWidget);
    await _captureBoundary(tester, key, 'inpaint-applied-revision.png');
  });
}

Future<void> _captureBoundary(
    WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/frontend-preview/$name');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<Uint8List> _captureRepaintBoundaryPixels(
  WidgetTester tester,
  Key key,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return Uint8List.fromList(
        data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  }))!;
}

bool _pixelsDiffer(Uint8List first, Uint8List second) {
  if (first.length != second.length) return true;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return true;
  }
  return false;
}

Future<void> _settleFileImages(WidgetTester tester) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final loaded = tester.widgetList<Image>(find.byType(Image)).every((image) {
      final status = tester.binding.imageCache.statusForKey(image.image);
      return !status.pending && (status.live || status.keepAlive);
    });
    if (loaded) return;
  }
  fail('Screenshot images did not finish decoding');
}

Widget _host(Widget child) => MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: Scaffold(body: child),
    );

const _sourceImagePath = 'assets/style_presets/style_001.jpg';

Future<void> _loadWorkspaceImage(
  WidgetTester tester,
  _InpaintGenerationFake vm,
) async {
  vm.setSourceImagePath(File(_sourceImagePath).absolute.path);
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (find.byType(Image).evaluate().isNotEmpty) break;
  }
  await tester.pumpAndSettle();
}

Future<void> _loadCaptureFonts() async {
  final fontPath = Platform.environment['FRONTEND_QA_FONT'];
  if (fontPath != null) {
    final bytes = File(fontPath).readAsBytesSync();
    for (final family in ['Roboto', 'Microsoft YaHei']) {
      await (FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  }
  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final family = entry['family'] as String;
    if (fontPath != null &&
        (family == 'Roboto' || family == 'Microsoft YaHei')) {
      continue;
    }
    final loader = FontLoader(family);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

void _setDocumentsDirectory(WidgetTester tester, Directory directory) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) => Future<Object?>.value(directory.path),
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });
}

class _InpaintGenerationFake extends FrontendGenerationFake {
  int _nextTaskId = 0;
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
  String selectedResolution = '128x128';
  @override
  Future<bool?> Function()? inpaintWorkspaceHandler;
  @override
  ImageProviderType get currentProvider => ImageProviderType.novelAi;

  @override
  GenerationTask buildInpaintTask({
    required String sourcePath,
    required String maskPath,
    required String prompt,
    required String negativePrompt,
    required double strength,
    required bool disabledOriginalImage,
    required bool colorCorrect,
    int? seed,
    String? taskId,
  }) {
    final dimensions = selectedResolution.split('x');
    return GenerationTask(
      taskId: taskId ?? 'inpaint-test-${++_nextTaskId}',
      model: 'nai-diffusion-4-5-full',
      prompt: prompt,
      negativePrompt: negativePrompt,
      width: int.parse(dimensions[0]),
      height: int.parse(dimensions[1]),
      scale: 5,
      cfgRescale: 0,
      sampler: 'k_euler_ancestral',
      noiseSchedule: 'karras',
      status: 'pending',
      createdAt: DateTime.now(),
      mode: GenerationMode.inpainting,
      sourceImagePath: sourcePath,
      maskImagePath: maskPath,
      inpaintStrength: strength,
      disabledOriginalImage: disabledOriginalImage,
      colorCorrect: colorCorrect,
    );
  }

  @override
  void setSourceImagePath(String? path) {
    sourceImagePath = path;
    notifyListeners();
  }

  @override
  Future<void> updateInpaintPrompt(String value) async {
    inpaintPrompt = value;
    notifyListeners();
  }

  @override
  Future<void> updateInpaintNegativePrompt(String value) async {
    inpaintNegativePrompt = value;
    notifyListeners();
  }
}

class _SuccessfulGenerationRepository implements GenerationRepository {
  final Directory outputDirectory;
  final submittedTasks = <GenerationTask>[];
  final generatedPaths = <String>[];
  bool failNext = false;

  _SuccessfulGenerationRepository(this.outputDirectory);

  @override
  Future<GenerationTask> submitGeneration(GenerationTask task) async {
    submittedTasks.add(task);
    if (failNext) {
      failNext = false;
      return task.copyWith(status: 'failed', errorMessage: 'fixture failure');
    }
    final generated = img.Image(
      width: task.width,
      height: task.height,
      numChannels: 4,
    );
    img.fill(generated,
        color: img.ColorRgba8(
            247, 79 + (submittedTasks.length - 1) * 8, 126, 255));
    final file = File('${outputDirectory.path}/generated_${task.taskId}.png');
    await file.writeAsBytes(img.encodePng(generated), flush: true);
    generatedPaths.add(file.path);
    return task.copyWith(
      status: 'success',
      imagePath: file.path,
      completedAt: DateTime.now(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedHistoryRepository implements HistoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
