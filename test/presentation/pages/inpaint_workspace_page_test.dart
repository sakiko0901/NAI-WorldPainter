import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/inpaint_workspace.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/repositories/generation_repository.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/inpaint_workspace_page.dart';
import 'package:nai_huishi/presentation/pages/generate_page.dart';
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
    vm.setGenerationMode(GenerationMode.inpainting);
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

  testWidgets('batch count syncs in both directions across generation modes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    vm.setGenerationMode(GenerationMode.textToImage);
    await tester.pumpWidget(_host(const GeneratePage()));
    await tester.pumpAndSettle();
    final normalSlider = find.byKey(const ValueKey('workspace-batch-slider'));
    await tester.ensureVisible(normalSlider);
    await tester.tapAt(tester.getRect(normalSlider).center);
    await tester.pumpAndSettle();
    final normalCount = vm.batchCount;
    expect(normalCount, greaterThan(1));

    vm.setGenerationMode(GenerationMode.inpainting);
    await tester.pumpAndSettle();
    final retainedWorkspace = tester.state(find.byType(InpaintWorkspaceCard));
    final inpaintSlider = find.byKey(const ValueKey('inpaint-batch-slider'));
    await tester.ensureVisible(inpaintSlider);
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(inpaintSlider).value, normalCount.toDouble());
    final rect = tester.getRect(inpaintSlider);
    await tester.dragFrom(rect.center, Offset(rect.width, 0));
    await tester.pumpAndSettle();
    expect(vm.batchCount, 30);
    expect(tester.widget<Slider>(inpaintSlider).value, 30);
    expect(find.text('生成 30 张图片'), findsOneWidget);

    vm.setGenerationMode(GenerationMode.textToImage);
    await tester.pumpAndSettle();
    await tester.ensureVisible(normalSlider);
    expect(tester.widget<Slider>(normalSlider).value, 30);
    await tester.dragFrom(tester.getCenter(normalSlider),
        Offset(-tester.getSize(normalSlider).width, 0));
    await tester.pumpAndSettle();
    expect(vm.batchCount, 1);
    vm.setGenerationMode(GenerationMode.inpainting);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(InpaintWorkspaceCard)),
        same(retainedWorkspace));
    await tester.ensureVisible(inpaintSlider);
    expect(tester.widget<Slider>(inpaintSlider).value, 1);
    vm.isGenerating = true;
    vm.notifyListeners();
    await tester.pump();
    expect(tester.widget<Slider>(inpaintSlider).onChanged, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final success in [true, false]) {
    testWidgets(
        'composite gallery export cleans only its temporary copy on success=$success',
        (tester) async {
      _setDocumentsDirectory(tester, outputDirectory);
      final messenger = tester.binding.defaultBinaryMessenger;
      const galleryChannel = MethodChannel('image_gallery_saver_plus');
      final exported = Completer<String>();
      messenger.setMockMethodCallHandler(galleryChannel, (call) async {
        expect(call.method, 'saveFileToGallery');
        final path = (call.arguments as Map)['file'] as String;
        expect(path, contains('nai_edit_png_'));
        expect(File(path).existsSync(), isTrue);
        final decoded = img.decodePng(await File(path).readAsBytes());
        expect(decoded, isNotNull);
        exported.complete(path);
        return {'isSuccess': success};
      });
      addTearDown(
          () => messenger.setMockMethodCallHandler(galleryChannel, null));
      await tester.pumpWidget(
          _host(const SingleChildScrollView(child: InpaintWorkspaceCard())));
      await _loadWorkspaceImage(tester, vm);
      final sourcePath = vm.sourceImagePath!;
      await tester.ensureVisible(find.text('保存合成'));
      await tester.tap(find.text('保存合成'));
      for (var attempt = 0; attempt < 400; attempt++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        if (exported.isCompleted && outputDirectory.listSync().isEmpty) break;
      }
      expect(exported.isCompleted, isTrue,
          reason: 'Gallery export did not finish');
      final path = await exported.future;
      expect(File(path).existsSync(), isFalse);
      expect(outputDirectory.listSync(), isEmpty);
      expect(File(sourcePath).existsSync(), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    });
  }

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
    expect(find.text('选择原图'), findsNothing);
    expect(find.text('重绘提示词'), findsNothing);
    final resolution = find.byKey(const ValueKey('inpaint-resolution'));
    expect(tester.getTopLeft(resolution).dx,
        lessThan(tester.getTopLeft(find.byTooltip('更换图片')).dx));
    expect(find.byTooltip('撤销蒙版'), findsNothing);
    expect(find.byTooltip('重做蒙版'), findsNothing);
    expect(find.byTooltip('隐藏蒙版'), findsNothing);
    expect(find.byTooltip('适应窗口'), findsNothing);
    expect(find.byTooltip('清空蒙版'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.minLines, 6);
      expect(field.maxLines, 14);
      expect(field.decoration!.border, InputBorder.none);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('brush sheet slides up and retains shape and all ten sizes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 852);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_host(
      const SingleChildScrollView(child: InpaintWorkspaceCard()),
    ));
    await _loadWorkspaceImage(tester, vm);
    await tester.ensureVisible(find.text('画笔'));
    await tester.tap(find.text('画笔'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    await tester.longPress(find.text('画笔'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final midwayTop = tester.getTopLeft(find.byType(BottomSheet)).dy;
    await tester.pumpAndSettle();
    expect(
        midwayTop, greaterThan(tester.getTopLeft(find.byType(BottomSheet)).dy));
    final slider = find.byKey(const ValueKey('inpaint-brush-size'));
    expect(find.text('绘制到'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(tester.widget<Slider>(slider).min, 1);
    expect(tester.widget<Slider>(slider).max, 10);
    expect(tester.widget<Slider>(slider).divisions, 9);
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, 10);
    final square = find.byKey(const ValueKey('inpaint-brush-square'));
    await tester.ensureVisible(square);
    await tester.tap(square);
    final done = find.byKey(const ValueKey('inpaint-brush-done'));
    await tester.ensureVisible(done);
    await tester.tap(done);
    await tester.pumpAndSettle();
    final stage = find.byKey(const ValueKey('inpaint-workspace-stage'));
    await tester.ensureVisible(stage);
    await tester.drag(stage, const Offset(20, 0));
    await tester.pumpAndSettle();
    final cache = (tester
            .widget<CustomPaint>(
                find.byKey(const ValueKey('inpaint-live-mask')))
            .painter! as InpaintCanvasPainter)
        .maskController!;
    expect(cache.strokes.single.square, isTrue);
    expect(cache.strokes.single.size, 160);
    await _selectDrawingTool(tester, '画笔', close: false);
    expect(tester.widget<Slider>(slider).value, 10);
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, 1);
    final round = find.byKey(const ValueKey('inpaint-brush-round'));
    await tester.ensureVisible(round);
    await tester.tap(round);
    await tester.ensureVisible(done);
    await tester.tap(done);
    await tester.pumpAndSettle();
    await tester.ensureVisible(stage);
    await tester.drag(stage, const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(cache.strokes.last.square, isFalse);
    expect(cache.strokes.last.size, 16);
    expect(cache.strokes.first.square, isTrue);
    await tester.ensureVisible(find.text('橡皮'));
    await tester.tap(find.text('橡皮'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    await tester.longPress(find.text('橡皮'));
    await tester.pumpAndSettle();
    expect(find.text('橡皮设置'), findsOneWidget);
    await tester.ensureVisible(done);
    await tester.tap(done);
    await tester.pumpAndSettle();
    await tester.ensureVisible(stage);
    await tester.drag(stage, const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(cache.strokes.last.mode, InpaintStrokeMode.erase);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace menu animates and retains settings for generation',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _setDocumentsDirectory(tester, outputDirectory);
    await tester.pumpWidget(_host(const MediaQuery(
      data: MediaQueryData(
          size: Size(320, 1400), textScaler: TextScaler.linear(2)),
      child: SingleChildScrollView(child: InpaintWorkspaceCard()),
    )));
    await _loadWorkspaceImage(tester, vm);
    final toggle = find.byKey(const ValueKey('inpaint-workspace-menu-toggle'));
    final animation =
        find.byKey(const ValueKey('inpaint-workspace-menu-animation'));
    expect(find.text('重绘强度'), findsNothing);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final halfwayHeight = tester.getSize(animation).height;
    await tester.pumpAndSettle();
    expect(halfwayHeight, greaterThan(0));
    expect(halfwayHeight, lessThan(tester.getSize(animation).height));
    expect(find.text('放大图片分辨率'), findsNothing);
    expect(find.text('生成参数'), findsNothing);
    expect(find.text('清空笔迹与遮罩'), findsOneWidget);
    final strength = find.byKey(const ValueKey('inpaint-setting-重绘强度'));
    await tester.ensureVisible(strength);
    await tester.tapAt(tester.getCenter(strength));
    await tester.pumpAndSettle();
    expect(vm.inpaintStrength, closeTo(0.51, 0.02));
    final expectedStrength = vm.inpaintStrength;
    for (final key in ['inpaint-color-correct', 'inpaint-ignore-original']) {
      final setting = find.byKey(ValueKey(key));
      await tester.ensureVisible(setting);
      await tester.tap(setting);
      await tester.pumpAndSettle();
    }
    expect(vm.colorCorrect, isFalse);
    expect(vm.disabledOriginalImage, isTrue);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('重绘强度'), findsNothing);
    await _openWorkspaceMenu(tester);
    expect(tester.widget<Slider>(strength).value, expectedStrength);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('画笔'));
    await _selectDrawingTool(tester, '画笔');
    await tester.pumpAndSettle();
    final stage = find.byKey(const ValueKey('inpaint-workspace-stage'));
    await tester.ensureVisible(stage);
    await tester.drag(stage, const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(await _generateWhilePumping(tester, vm.inpaintWorkspaceHandler!),
        isTrue);
    final task = generationRepository.submittedTasks.single;
    expect(task.inpaintStrength, expectedStrength);
    expect(task.colorCorrect, isFalse);
    expect(task.disabledOriginalImage, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded inpaint editor saves to the inpaint prompt only',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    vm.prompt = 'text to image prompt';
    await tester.pumpWidget(_host(
      const SingleChildScrollView(child: InpaintWorkspaceCard()),
    ));
    final expand = find.byTooltip('放大编辑').first;
    await tester.ensureVisible(expand);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    final editor = find.descendant(
        of: find.byType(BottomSheet), matching: find.byType(TextField));
    await tester.enterText(editor, 'silver hair, blue eyes');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(vm.inpaintPrompt, 'silver hair, blue eyes');
    expect(vm.prompt, 'text to image prompt');
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('inpaint-positive-prompt')))
            .controller!
            .text,
        vm.inpaintPrompt);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not start inpaint while official image processing is busy',
      (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(const SingleChildScrollView(child: InpaintWorkspaceCard())),
    );
    await _loadWorkspaceImage(tester, vm);

    vm.processingImage = true;
    final handled = await vm.inpaintWorkspaceHandler!();
    await tester.pump(const Duration(seconds: 2));

    expect(handled, isFalse);
    expect(generationRepository.submittedTasks, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'inpaint roles edit positive and negative prompts with V5 auto position',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    vm.selectedModel = 'nai-diffusion-5-full';

    await tester.pumpWidget(
      _host(const SingleChildScrollView(child: InpaintWorkspaceCard())),
    );
    await _loadWorkspaceImage(tester, vm);

    await tester
        .ensureVisible(find.byKey(const ValueKey('inpaint-add-character')));
    await tester.tap(find.byKey(const ValueKey('inpaint-add-character')));
    await tester.pumpAndSettle();
    expect(vm.characters, hasLength(1));
    expect(vm.characters.single.centerX, isNull);
    expect(vm.characters.single.centerY, isNull);

    final positive = find.byKey(const ValueKey('inpaint-character-prompt-1'));
    final negative = find.byKey(const ValueKey('inpaint-character-negative-1'));
    await tester.ensureVisible(positive);
    await tester.enterText(positive, '1girl, silver hair');
    await tester.pump();
    await tester.enterText(negative, 'blurry, extra fingers');
    await tester.pump();
    expect(vm.characters.single.prompt, '1girl, silver hair');
    expect(vm.characters.single.uc, 'blurry, extra fingers');

    final roleCard = find.byKey(const ValueKey('inpaint-character-0'));
    await tester.ensureVisible(roleCard);
    await tester.tap(find.descendant(of: roleCard, matching: find.text('手动')));
    await tester.pumpAndSettle();
    expect(vm.characters.single.centerX, 0.5);
    expect(vm.characters.single.centerY, 0.5);

    await tester.enterText(positive, '1girl, blue eyes');
    await tester.pump();
    expect(vm.characters.single.centerX, 0.5);
    expect(vm.characters.single.centerY, 0.5);

    await tester.tap(find.descendant(of: roleCard, matching: find.text('自动')));
    await tester.pumpAndSettle();
    expect(vm.characters.single.centerX, isNull);
    expect(vm.characters.single.centerY, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inpaint role editors fit a narrow screen with enlarged text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(
        const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 852),
            textScaler: TextScaler.linear(1.35),
          ),
          child: SingleChildScrollView(child: InpaintWorkspaceCard()),
        ),
      ),
    );
    await _loadWorkspaceImage(tester, vm);
    await tester
        .ensureVisible(find.byKey(const ValueKey('inpaint-add-character')));
    await tester.tap(find.byKey(const ValueKey('inpaint-add-character')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('inpaint-character-negative-1')),
    );

    expect(find.byKey(const ValueKey('inpaint-character-prompt-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('inpaint-character-negative-1')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('external prompt replacement refreshes mounted role editors',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    vm.inpaintPrompt = 'old global positive';
    vm.inpaintNegativePrompt = 'old global negative';
    vm.characters = [
      const CharacterSpec(
        prompt: 'old character prompt',
        uc: 'old character negative',
        centerX: 0.7,
        centerY: 0.3,
      ),
    ];

    await tester.pumpWidget(
      _host(const SingleChildScrollView(child: InpaintWorkspaceCard())),
    );
    await _loadWorkspaceImage(tester, vm);
    expect(
      tester
          .widget<TextField>(
              find.byKey(const ValueKey('inpaint-positive-prompt')))
          .controller!
          .text,
      'old global positive',
    );

    vm.inpaintPrompt = 'new global positive';
    vm.inpaintNegativePrompt = 'new global negative';
    vm.characters = [
      const CharacterSpec(
        prompt: 'new character prompt',
        uc: 'new character negative',
        centerX: 0.2,
        centerY: 0.8,
      ),
    ];
    vm.notifyListeners();
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
              find.byKey(const ValueKey('inpaint-positive-prompt')))
          .controller!
          .text,
      'new global positive',
    );
    expect(
      tester
          .widget<TextField>(
              find.byKey(const ValueKey('inpaint-negative-prompt')))
          .controller!
          .text,
      'new global negative',
    );
    expect(
      tester
          .widget<TextField>(
              find.byKey(const ValueKey('inpaint-character-prompt-1')))
          .controller!
          .text,
      'new character prompt',
    );
    expect(
      tester
          .widget<TextField>(
              find.byKey(const ValueKey('inpaint-character-negative-1')))
          .controller!
          .text,
      'new character negative',
    );
    expect(vm.characters.single.centerX, 0.2);
    expect(vm.characters.single.centerY, 0.8);
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
    await _selectDrawingTool(tester, '画笔');
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

  testWidgets('square brush stays square through drawing and unified undo redo',
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
    await _selectDrawingTool(tester, '画笔');
    await tester.pumpAndSettle();
    await _selectDrawingTool(tester, '画笔', close: false);
    final squareChip = find.byKey(const ValueKey('inpaint-brush-square'));
    await tester.ensureVisible(squareChip);
    await tester.pumpAndSettle();
    await tester.tap(squareChip);
    await tester.tap(find.byKey(const ValueKey('inpaint-brush-done')));
    await tester.pumpAndSettle();
    final stage = find.byKey(const ValueKey('inpaint-workspace-stage'));
    await tester.ensureVisible(stage);
    final gesture = await tester.startGesture(tester.getRect(stage).center);
    await tester.pump();
    InpaintCanvasPainter painter() => tester
        .widget<CustomPaint>(find.byKey(const ValueKey('inpaint-live-mask')))
        .painter! as InpaintCanvasPainter;
    final painterBeforeMove = painter();
    final cache = painterBeforeMove.maskController!;
    final initialAppends = cache.debugPointAppendCount;
    final initialBuilds = cache.debugGeometryBuildCount;
    const maskBoundaryKey = ValueKey('inpaint-mask-repaint-boundary');
    final pixelsBeforeMove =
        await _captureRepaintBoundaryPixels(tester, maskBoundaryKey);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(identical(painter(), painterBeforeMove), isTrue);
    expect(painter().maskController, same(cache));
    expect(cache.debugPointAppendCount, greaterThan(initialAppends));
    expect(cache.debugGeometryBuildCount, initialBuilds);
    final pixelsAfterMove =
        await _captureRepaintBoundaryPixels(tester, maskBoundaryKey);
    expect(_pixelsDiffer(pixelsBeforeMove, pixelsAfterMove), isTrue);
    expect(cache.activeStroke!.square, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(cache.strokes.single.square, isTrue);
    expect(cache.activeStroke, isNull);

    final undoMask = find.byTooltip('撤销笔迹');
    await tester.ensureVisible(undoMask);
    await tester.tap(undoMask);
    await tester.pumpAndSettle();
    expect(cache.strokes, isEmpty);
    final redoMask = find.byTooltip('重做笔迹');
    await tester.ensureVisible(redoMask);
    await tester.tap(redoMask);
    await tester.pumpAndSettle();
    expect(cache.strokes.single.square, isTrue);

    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled strokes do not consume a committed undo step',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(
      const SingleChildScrollView(child: InpaintWorkspaceCard()),
    ));
    await _loadWorkspaceImage(tester, vm);
    await _selectDrawingTool(tester, '画笔');
    await tester.pumpAndSettle();
    final stage = find.byKey(const ValueKey('inpaint-workspace-stage'));
    await tester.ensureVisible(stage);
    await tester.drag(stage, const Offset(20, 0));
    await tester.pump();
    final cache = (tester
            .widget<CustomPaint>(
              find.byKey(const ValueKey('inpaint-live-mask')),
            )
            .painter! as InpaintCanvasPainter)
        .maskController!;
    final committed = cache.strokes.single;
    final cancelled = await tester.startGesture(tester.getCenter(stage));
    await cancelled.moveBy(const Offset(0, 30));
    await tester.pump();
    await cancelled.cancel();
    await tester.pump();
    expect(cache.activeStroke, isNull);
    expect(cache.strokes.single, same(committed));

    final undo = find.byTooltip('撤销笔迹');
    await tester.ensureVisible(undo);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(cache.strokes, isEmpty);
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
    await _selectDrawingTool(tester, '画笔');
    await tester.pumpAndSettle();
    await _openWorkspaceMenu(tester);
    await tester
        .ensureVisible(find.byKey(const ValueKey('inpaint-workspace-stage')));
    final stage = find.byKey(const ValueKey('inpaint-workspace-stage'));
    await tester.drag(stage, const Offset(25, 0));
    await tester.pumpAndSettle();
    InpaintCanvasPainter painter() => tester
        .widget<CustomPaint>(find.byKey(const ValueKey('inpaint-live-mask')))
        .painter! as InpaintCanvasPainter;
    expect(painter().maskController!.strokes, isNotEmpty);
    final held =
        await tester.startGesture(tester.getCenter(stage), pointer: 33);
    await tester.pump();
    await held.moveBy(const Offset(-25, 10));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('inpaint-clear-strokes')));
    await tester.pump();
    await held.up();
    await tester.pumpAndSettle();
    expect(painter().maskController!.strokes, isEmpty);
    expect(painter().maskController!.activeStroke, isNull);
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
    await _selectDrawingTool(tester, '画笔');
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

    tester
        .widget<Slider>(find.byKey(const ValueKey('inpaint-batch-slider')))
        .onChanged!(3);
    await tester.pump();
    final generate = vm.inpaintWorkspaceHandler;
    expect(generate, isNotNull);
    final firstHandled = await _generateWhilePumping(tester, generate!);
    await tester.pumpAndSettle();
    expect(firstHandled, isTrue);
    expect(find.text('结果图层 1'), findsNothing);
    expect(find.byType(InpaintComparison), findsOneWidget);
    expect(find.text('候选结果 3 / 3'), findsOneWidget);
    expect(generationRepository.submittedTasks, hasLength(3));
    expect(vm.sessionResults, hasLength(3));
    expect(
      vm.sessionResults.every((task) =>
          task.status == 'success' &&
          task.imagePath != null &&
          File(task.imagePath!).existsSync() &&
          !task.isInternal),
      isTrue,
    );
    final immutableSource =
        generationRepository.submittedTasks.first.sourceImagePath;
    expect(immutableSource, isNot(generationRepository.generatedPaths.first));

    // A failed new request must not remove the previous candidates.
    vm.batchCount = 1;
    generationRepository.failNext = true;
    await _generateWhilePumping(tester, generate);
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
    await _openWorkspaceMenu(tester);
    await tester
        .ensureVisible(find.byKey(const ValueKey('inpaint-clear-strokes')));
    await tester.tap(find.byKey(const ValueKey('inpaint-clear-strokes')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('画笔'));
    await _selectDrawingTool(tester, '画笔');
    await tester.pumpAndSettle();
    final nextStage = find.byKey(const ValueKey('inpaint-workspace-stage'));
    await tester.ensureVisible(nextStage);
    final nextStroke = await tester.startGesture(
      tester.getRect(nextStage).center - const Offset(0, 12),
    );
    await nextStroke.up();
    await tester.pumpAndSettle();

    final secondHandled = await _generateWhilePumping(tester, generate);
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
    final screenKey = GlobalKey();
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
      RepaintBoundary(
        key: screenKey,
        child: _host(
          SingleChildScrollView(
            child: RepaintBoundary(
              key: key,
              child: const InpaintWorkspaceCard(),
            ),
          ),
        ),
      ),
    );
    await _loadWorkspaceImage(tester, vm);
    await _selectDrawingTool(tester, '画笔', close: false);
    await _captureBoundary(tester, screenKey, 'inpaint-brush-sheet.png');
    await tester.tap(find.byKey(const ValueKey('inpaint-brush-done')));
    await tester.pumpAndSettle();
    final stage = tester.getRect(
      find.byKey(const ValueKey('inpaint-workspace-stage')),
    );
    final brush = await tester.startGesture(stage.center);
    await brush.moveBy(const Offset(42, 0));
    await brush.up();
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.pumpAndSettle();
    await _captureBoundary(tester, key, 'inpaint-round-brush.png');
    await _selectDrawingTool(tester, '画笔', close: false);
    await tester.tap(find.byKey(const ValueKey('inpaint-brush-square')));
    await tester.tap(find.byKey(const ValueKey('inpaint-brush-done')));
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
    await _openWorkspaceMenu(tester);
    await _captureBoundary(tester, key, 'inpaint-workspace-menu.png');
    await tester.ensureVisible(
        find.byKey(const ValueKey('inpaint-workspace-menu-toggle')));
    await tester
        .tap(find.byKey(const ValueKey('inpaint-workspace-menu-toggle')));
    await tester.pumpAndSettle();
    await _generateWhilePumping(tester, vm.inpaintWorkspaceHandler!);
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

Future<void> _openWorkspaceMenu(WidgetTester tester) async {
  if (find
      .byKey(const ValueKey('inpaint-workspace-menu'))
      .evaluate()
      .isNotEmpty) return;
  final toggle = find.byKey(const ValueKey('inpaint-workspace-menu-toggle'));
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

Future<bool?> _generateWhilePumping(
  WidgetTester tester,
  Future<bool?> Function() generate,
) async {
  bool? result;
  Object? error;
  var completed = false;
  await tester.runAsync(() async {
    unawaited(generate().then((value) {
      result = value;
      completed = true;
    }, onError: (Object failure) {
      error = failure;
      completed = true;
    }));
  });
  // A preview begun in the fake clock zone must be allowed to finish before
  // generation takes its worker slot. Keep pumping while native isolates run.
  for (var attempt = 0; attempt < 600 && !completed; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (error != null) throw error!;
  expect(completed, isTrue, reason: 'Workspace generation did not finish');
  return result;
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
      debugShowCheckedModeBanner: false,
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
  void updateInpaintStrength(double value) {
    inpaintStrength = value;
    notifyListeners();
  }

  @override
  void updateInpaintOptions({bool? disabledOriginalImage, bool? colorCorrect}) {
    this.disabledOriginalImage =
        disabledOriginalImage ?? this.disabledOriginalImage;
    this.colorCorrect = colorCorrect ?? this.colorCorrect;
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
  void setStreamPreviewHandler(
      String taskId, void Function(Uint8List bytes, int? step)? onFrame) {}

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
