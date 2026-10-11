import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
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
        await tester.scrollUntilVisible(
          find.text('生成参数'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('生成参数'));
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
    expect(tester.takeException(), isNull);
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
      await tester.scrollUntilVisible(find.text('正向提示词'), 240,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('prompts');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
