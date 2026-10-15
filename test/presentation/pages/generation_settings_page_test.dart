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
    'settings are a full page and edits preserve the creation draft and scroll',
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
      await tester.pumpAndSettle();

      final settingsPage =
          find.byKey(const ValueKey('generation-settings-page'));
      expect(settingsPage, findsOneWidget);
      expect(
        ModalRoute.of(tester.element(settingsPage))?.settings.name,
        '/generation-settings',
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('AI 模型'), findsOneWidget);
      expect(find.text('图像尺寸'), findsOneWidget);
      expect(find.text('批量生成'), findsOneWidget);
      final contentViewport = tester.getRect(
        find.descendant(
          of: settingsPage,
          matching: find.byType(SingleChildScrollView),
        ),
      );
      for (final label in ['图像尺寸', '批量生成']) {
        final labelRect = tester.getRect(find.text(label));
        expect(labelRect.top, greaterThanOrEqualTo(contentViewport.top));
        expect(labelRect.bottom, lessThanOrEqualTo(contentViewport.bottom));
      }

      final batchSlider = find.descendant(
        of: settingsPage,
        matching: find.byType(Slider),
      );
      expect(batchSlider, findsOneWidget);
      final sliderRect = tester.getRect(batchSlider);
      await tester.tapAt(
        Offset(sliderRect.right - 48, sliderRect.center.dy),
      );
      await tester.pumpAndSettle();
      expect(vm.batchCount, greaterThan(1));
      expect(vm.batchUpdateCount, greaterThan(0));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byTooltip('生成参数'), findsOneWidget);
      expect(vm.batchCount, greaterThan(1));
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
      await tester.ensureVisible(find.text('采样与高级参数'));
      await tester.pumpAndSettle();
      expect(scrollState.position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('advanced parameters return through settings to creation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_host(const GeneratePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('生成参数'));
    await tester.pumpAndSettle();

    final settingsPage = find.byKey(const ValueKey('generation-settings-page'));
    await tester.ensureVisible(find.text('采样与高级参数'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('采样与高级参数'));
    await tester.pumpAndSettle();
    expect(find.text('高级参数'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(settingsPage, findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('生成参数'), findsOneWidget);
    expect(find.text('创作'), findsOneWidget);
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
    expect(find.text('AI 模型'), findsOneWidget);
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
