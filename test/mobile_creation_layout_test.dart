import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/generate_page.dart';
import 'package:nai_huishi/presentation/pages/home_page.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/generation_result_card.dart';

import 'support/frontend_generation_fake.dart';

void main() {
  late FrontendGenerationFake vm;
  setUp(() {
    vm = FrontendGenerationFake();
    sl.registerSingleton<GenerationViewModel>(vm);
  });
  tearDown(() async {
    await sl.reset();
    vm.dispose();
  });

  Widget host(
    Widget child, {
    double scale = 1,
    Brightness brightness = Brightness.dark,
  }) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildNaiHuishiTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: child,
      );

  for (final width in [320.0, 360.0, 393.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('creation fits $width dp at ${scale}x text', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          host(GeneratePage(onNavigate: (_) {}), scale: scale),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('生成图片'), findsOneWidget);
        expect(find.text('生成参数'), findsNothing);
        expect(find.byTooltip('生成参数'), findsOneWidget);
        final buttonRect = tester.getRect(
          find.byKey(const ValueKey('generate-primary-button')),
        );
        final summaryRect = tester.getRect(
          find.byKey(const ValueKey('generation-summary')),
        );
        expect(summaryRect.top, greaterThanOrEqualTo(buttonRect.bottom));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('生成参数'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('模型与基础参数'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a later failure does not replace a successful result', (
    tester,
  ) async {
    final a = frontendResult(seed: 42);
    final b = frontendResult(id: 'B', seed: 73);
    String? selected;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        Scaffold(
          body: SingleChildScrollView(
            child: GenerationResultCard(
              task: a,
              results: [a, b],
              error: '本次请求失败，请检查连接',
              onSelect: (task) => selected = task.taskId,
              onSave: () {},
            ),
          ),
        ),
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('本次请求失败，请检查连接'), findsOneWidget);
    expect(find.textContaining('42'), findsOneWidget);
    expect(find.text('记录 Seed：73'), findsNothing);
    expect(find.text('保存图片'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('第 2 张结果'));
    expect(selected, 'B');
  });

  testWidgets(
    'arrival during editing preserves focus and scroll; keyboard clears CTA',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(host(const GeneratePage()));
      await tester.pumpAndSettle();
      final editor = find.byType(TextField).first;
      await tester.ensureVisible(editor);
      await tester.pumpAndSettle();
      await tester.tap(editor);
      await tester.enterText(editor, 'my unsaved draft');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.text('生成图片'), findsNothing);
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final offset = scroll.position.pixels;
      vm.receive(frontendResult());
      await tester.pumpAndSettle();
      expect(vm.prompt, 'my unsaved draft');
      expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);
      expect(scroll.position.pixels, offset);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
      'character starts empty and V5 drag stores continuous coordinates',
      (tester) async {
    vm.selectedModel = 'nai-diffusion-5';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(const GeneratePage()));
    await tester.pumpAndSettle();
    expect(vm.characters, isEmpty);
    await tester.scrollUntilVisible(find.byTooltip('添加角色'), 240,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byTooltip('添加角色'));
    await tester.pumpAndSettle();
    expect(vm.characters, hasLength(1));
    expect(vm.characters.single.centerX, isNull);
    await tester.ensureVisible(find.text('位置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('位置'));
    await tester.pumpAndSettle();
    final grid = find.byKey(const ValueKey('free-character-position'));
    await tester.scrollUntilVisible(grid, 180,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(grid);
    await tester.pumpAndSettle();
    final rect = tester.getRect(grid);
    await tester
        .tapAt(rect.topLeft + Offset(rect.width * .37, rect.height * .63));
    await tester.pumpAndSettle();
    expect(vm.characters.single.centerX, closeTo(.37, .005));
    expect(vm.characters.single.centerY, closeTo(.63, .005));
    expect(rect.width / rect.height, closeTo(832 / 1216, .0001));
    expect(find.text('角色1'), findsOneWidget);
    expect(find.text('未命名角色'), findsNothing);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final scrollOffset = scroll.position.pixels;
    final gesture = await tester.startGesture(rect.center);
    await tester.pump();
    await gesture
        .moveTo(rect.topLeft + Offset(rect.width * .7, rect.height * .7));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, scrollOffset);
    expect(vm.characters.single.centerX, closeTo(.7, .005));
    expect(vm.characters.single.centerY, closeTo(.7, .005));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact home navigation fits at doubled text size',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 852);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(host(
        HomePage(
            appearanceMode: AppearanceMode.dark, onAppearanceChanged: (_) {}),
        scale: 2));
    await tester.pumpAndSettle();
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(nav.height, lessThan(80));
    expect(find.text('AI 助手'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace save is visible with Android system insets',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    vm.receive(frontendResult(seed: 42));
    await tester.pumpWidget(host(HomePage(
        appearanceMode: AppearanceMode.dark, onAppearanceChanged: (_) {})));
    await tester.pumpAndSettle();
    expect(
        tester.getRect(find.byKey(const ValueKey('result-save-button'))).bottom,
        lessThanOrEqualTo(tester
            .getRect(find.byKey(const ValueKey('generate-primary-button')))
            .top));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'image stage fills its width using the displayed image dimensions',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final dimensions in [
      const Size(832, 1216),
      const Size(1024, 1024),
      const Size(1216, 832),
      const Size(300, 4000),
    ]) {
      vm.sessionResults = [];
      vm.receive(frontendResult().copyWith(
        width: dimensions.width.toInt(),
        height: dimensions.height.toInt(),
      ));
      await tester.pumpWidget(host(GeneratePage(key: ValueKey(dimensions))));
      await tester.pumpAndSettle();
      final stage = tester.getSize(
        find.byKey(const ValueKey('result-workspace-stage')),
      );
      if (dimensions.height / dimensions.width < 2) {
        expect(stage.height,
            closeTo(stage.width * dimensions.height / dimensions.width, 0.01));
      } else {
        expect(stage.height, lessThanOrEqualTo(852 * .85));
      }
      expect(
        tester.getRect(find.byKey(const ValueKey('result-save-button'))).bottom,
        lessThanOrEqualTo(tester
            .getRect(find.byKey(const ValueKey('generate-primary-button')))
            .top),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('capture actual Flutter creation widgets', (tester) async {
    if (!const bool.fromEnvironment('FRONTEND_CAPTURE')) return;
    final fontPath = Platform.environment['FRONTEND_QA_FONT'];
    if (fontPath != null) {
      final bytes = File(fontPath).readAsBytesSync();
      for (final family in ['Microsoft YaHei', 'Roboto']) {
        await (FontLoader(family)
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
      }
    }
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final family in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(family['family'] as String);
      for (final font
          in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    for (final brightness in Brightness.values) {
      await tester
          .pumpWidget(host(const SizedBox(key: ValueKey('capture-preload'))));
      await tester.runAsync(() async {
        await precacheImage(
            FileImage(File('assets/style_presets/style_001.jpg').absolute),
            tester.element(find.byKey(const ValueKey('capture-preload'))));
      });
      vm.sessionResults = [];
      vm.characters = [];
      vm.selectedModel = 'nai-diffusion-5';
      vm.imageModelOptions = const [
        ImageModelOption(
            modelId: 'nai-diffusion-5',
            displayName: 'NovelAI V5',
            provider: ImageProviderType.novelAi,
            actualModel: 'nai-diffusion-5')
      ];
      vm.batchCount = 4;
      vm.selectedResolution = '832x1216';
      vm.prompt = 'silver hair, warm afternoon light, by the window';
      vm.negativePrompt = 'low quality, blurry, extra fingers';
      vm.receive(
        frontendResult(
          imagePath: File('assets/style_presets/style_001.jpg').absolute.path,
          seed: 12345678,
        ),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: host(
            HomePage(
                appearanceMode: AppearanceMode.dark,
                onAppearanceChanged: (_) {}),
            brightness: brightness,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      Future<void> capture(String name) async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'build/frontend-preview/$name-${brightness.name}.png',
          );
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('creation');
      await tester.tap(find.byTooltip('生成参数'));
      await tester.pumpAndSettle();
      await capture('settings');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('正向提示词'), 240,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('prompts');
      await tester.scrollUntilVisible(find.byTooltip('添加角色'), 180,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byTooltip('添加角色'));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(tester.element(find.text('角色1')),
          alignment: .08);
      await tester.pumpAndSettle();
      await capture('characters');
      await tester.ensureVisible(find.text('位置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('位置'));
      await tester.pumpAndSettle();
      final board = find.byKey(const ValueKey('free-character-position'));
      await tester.ensureVisible(board);
      await tester.pumpAndSettle();
      final boardRect = tester.getRect(board);
      await tester.tapAt(boardRect.topLeft +
          Offset(boardRect.width * .3, boardRect.height * .5));
      await tester.pumpAndSettle();
      await capture('position-portrait');
      vm.selectedResolution = '1216x832';
      vm.updateCharacter(0, vm.characters.first);
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(tester.element(find.text('角色1')),
          alignment: .08);
      await tester.pumpAndSettle();
      await capture('position-landscape');
      vm.sessionResults = [];
      vm.lastCompletedTask = null;
      vm.selectedResultTaskId = null;
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: host(
          HomePage(
            key: const ValueKey('empty-workspace-capture'),
            appearanceMode: AppearanceMode.dark,
            onAppearanceChanged: (_) {},
          ),
          brightness: brightness,
        ),
      ));
      await tester.pumpAndSettle();
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await capture('workspace-empty');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
