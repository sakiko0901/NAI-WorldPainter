import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/generate_page.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';

import '../../support/frontend_generation_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _GenerationSettingsFake vm;

  setUp(() {
    vm = _GenerationSettingsFake();
    sl.registerSingleton<GenerationViewModel>(vm);
  });

  tearDown(() async {
    await sl.reset();
    vm.dispose();
  });

  testWidgets(
      'blocks generation settings and generation during image processing',
      (tester) async {
    vm.processingImage = true;
    vm.imageProcessingLabel = '官方 Enhance';
    vm.imageProcessingStatus = '上传原图…';

    await tester.pumpWidget(_host(const GeneratePage()));
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('generate-primary-button')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '生成参数',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(find.byKey(const ValueKey('result-processing-global-status')),
        findsOneWidget);
    expect(find.textContaining('官方 Enhance'), findsOneWidget);
    expect(find.textContaining('上传原图…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'side settings preserve the creation draft and scroll',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_host(const GeneratePage()));
      await tester.pumpAndSettle();

      final promptField = find
          .descendant(
            of: find.byType(GeneratePage),
            matching: find.byType(TextField),
          )
          .first;
      final creationScroll = _creationScrollable();
      await tester.ensureVisible(promptField);
      await tester.pumpAndSettle();
      await tester.tap(promptField);
      await tester.enterText(promptField, 'keep this prompt draft');
      await tester.pump();
      expect(vm.prompt, 'keep this prompt draft');

      final creationScrollRect = tester.getRect(creationScroll);
      await tester.dragFrom(
        Offset(creationScrollRect.left + 4, creationScrollRect.center.dy),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      final creationOffset =
          tester.state<ScrollableState>(creationScroll).position.pixels;
      expect(creationOffset, greaterThan(0));

      await tester.tap(find.byTooltip('生成参数'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      final entering = tester.getRect(
        find.byKey(const ValueKey('generation-settings-page')),
      );
      expect(entering.left, greaterThan(0));
      expect(entering.left, lessThan(393));
      await tester.pumpAndSettle();

      final settingsPage =
          find.byKey(const ValueKey('generation-settings-page'));
      expect(settingsPage, findsOneWidget);
      expect(
        ModalRoute.of(tester.element(settingsPage))?.settings.name,
        '/generation-settings',
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('模型选择'), findsOneWidget);
      expect(find.text('图像尺寸'), findsOneWidget);
      expect(tester.getRect(settingsPage).left, greaterThan(0));
      expect(tester.getRect(settingsPage).right, closeTo(393, 0.1));
      expect(find.descendant(of: settingsPage, matching: find.text('批量生成')),
          findsNothing);
      expect(
          find.descendant(
              of: settingsPage, matching: find.textContaining('预计')),
          findsNothing);
      await tester.ensureVisible(find.text('高级参数'));
      await tester.pumpAndSettle();
      expect(find.text('Seed'), findsOneWidget);
      expect(find.text('采样算法'), findsOneWidget);
      vm.updateSeed(12345);
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byTooltip('生成参数'), findsOneWidget);
      expect(vm.seed, 12345);
      expect(vm.prompt, 'keep this prompt draft');
      expect(
        tester.widget<TextField>(promptField).controller!.text,
        'keep this prompt draft',
      );
      final restoredOffset =
          tester.state<ScrollableState>(creationScroll).position.pixels;
      expect(restoredOffset, closeTo(creationOffset, 0.1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings content scrolls at 320dp with double text and keyboard insets',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(_host(const GeneratePage(), textScale: 2));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('生成参数'));
      await tester.pumpAndSettle();

      final settingsPage =
          find.byKey(const ValueKey('generation-settings-page'));
      expect(settingsPage, findsOneWidget);
      expect(find.text('图像尺寸'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final settingsScroll = find
          .descendant(
            of: settingsPage,
            matching: find.byType(Scrollable),
          )
          .first;
      final scrollState = tester.state<ScrollableState>(settingsScroll);
      expect(scrollState.position.maxScrollExtent, greaterThan(0));
      await tester.ensureVisible(find.text('高级参数'));
      await tester.pumpAndSettle();
      expect(scrollState.position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('batch slider is in the workspace and spans 1 to 30',
      (tester) async {
    vm.receive(frontendResult(id: 'A'));
    vm.receive(frontendResult(id: 'B'));
    await tester.pumpWidget(_host(const GeneratePage()));
    await tester.pumpAndSettle();
    final finder = find.byKey(const ValueKey('workspace-batch-slider'));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(finder);
    expect(tester.getTopLeft(finder).dy,
        greaterThan(tester.getBottomLeft(find.byTooltip('第 1 张结果')).dy));
    expect(tester.getBottomLeft(finder).dy,
        lessThan(tester.getTopLeft(find.text('保存图片')).dy));
    expect(slider.min, 1);
    expect(slider.max, 30);
    slider.onChanged!(30);
    await tester.pump();
    expect(vm.batchCount, 30);
    expect(find.text('30 张'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings remain reachable when reduced motion is enabled', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _host(const GeneratePage(), disableAnimations: true),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('生成参数'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('generation-settings-page')),
      findsOneWidget,
    );
    expect(find.text('模型选择'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(
  Widget home, {
  double textScale = 1,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildNaiHuishiTheme(Brightness.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: child!,
    ),
    home: home,
  );
}

Finder _creationScrollable() {
  final creationList = find.byWidgetPredicate(
    (widget) =>
        widget is ListView &&
        widget.key is PageStorageKey &&
        (widget.key as PageStorageKey).value == 'creation-scroll',
  );
  return find
      .descendant(
        of: creationList,
        matching: find.byType(Scrollable),
      )
      .first;
}

class _GenerationSettingsFake extends FrontendGenerationFake {
  int batchUpdateCount = 0;

  @override
  int steps = 28;
  @override
  double scale = 5;
  @override
  double cfgRescale = 0;
  @override
  int? seed;
  @override
  String selectedSampler = 'k_euler';
  @override
  String selectedNoiseSchedule = 'karras';
  @override
  bool isStepsLocked = false;

  @override
  Future<void> updateBatchCount(int value) async {
    batchCount = value;
    batchUpdateCount++;
    notifyListeners();
  }

  @override
  Future<void> updateSteps(int value) async {
    steps = value;
    notifyListeners();
  }

  @override
  Future<void> updateScale(double value) async {
    scale = value;
    notifyListeners();
  }

  @override
  Future<void> updateCfgRescale(double value) async {
    cfgRescale = value;
    notifyListeners();
  }

  @override
  Future<void> updateSelectedSampler(String value) async {
    selectedSampler = value;
    notifyListeners();
  }

  @override
  Future<void> updateSelectedNoiseSchedule(String value) async {
    selectedNoiseSchedule = value;
    notifyListeners();
  }

  @override
  Future<void> toggleStepsLock() async {
    isStepsLocked = !isStepsLocked;
    notifyListeners();
  }

  @override
  void updateSeed(int? value) {
    seed = value;
    notifyListeners();
  }
}
