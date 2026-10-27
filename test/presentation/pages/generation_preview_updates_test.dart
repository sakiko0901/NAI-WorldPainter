import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/generate_page.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/generation_result_card.dart';
import 'package:nai_huishi/presentation/widgets/studio_background.dart';

import '../../support/frontend_generation_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PreviewGenerationFake vm;
  late Directory directory;
  late File historyImage;

  setUp(() async {
    vm = _PreviewGenerationFake();
    sl.registerSingleton<GenerationViewModel>(vm);
    directory = await Directory.systemTemp.createTemp('generate-preview-');
    historyImage =
        File('${directory.path}${Platform.pathSeparator}history.png');
    await historyImage.writeAsBytes(_frame(0));
    vm.sessionResults = [_pendingResult()];
    vm.selectedResultTaskId = 'streaming';
    vm.isGenerating = true;
  });

  tearDown(() async {
    await sl.reset();
    vm.dispose();
    await directory.delete(recursive: true);
  });

  testWidgets(
      'twenty preview frames refresh the viewport without rebuilding the page or background',
      (tester) async {
    await _mount(tester);
    final builds = _BuildCounts();
    addTearDown(builds.restore);

    for (var step = 1; step <= 20; step++) {
      final bytes = _frame(step);
      vm.receivePreview('streaming', bytes, step);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('流式预览 · 第 $step 步'), findsOneWidget);
      expect(_visiblePreviewBytes(tester), same(bytes));
    }
    expect(builds.results, 20);
    expect(builds.pages, 0);
    expect(builds.backgrounds, 0,
        reason:
            'blurred ambient imagery must not rebuild for intermediate frames');

    vm.receivePreview('streaming', _frame(21), 21);
    vm.receivePreview('streaming', _frame(22), 22);
    final latestBurst = _frame(23);
    vm.receivePreview('streaming', latestBurst, 23);
    expect(builds.results, 20,
        reason: 'notifications do not build widgets before the display frame');
    await tester.pump();
    expect(builds.results, 21,
        reason:
            'one display frame coalesces intermediate preview notifications');
    expect(find.text('流式预览 · 第 23 步'), findsOneWidget);
    expect(_visiblePreviewBytes(tester), same(latestBurst));
    expect(builds.pages, 0);
    expect(builds.backgrounds, 0);

    await vm.updatePrompt('changed while the preview is streaming');
    await tester.pump();
    final prompt = find
        .descendant(
            of: find.byType(GeneratePage), matching: find.byType(TextField))
        .first;
    expect(tester.widget<TextField>(prompt).controller!.text, vm.prompt);
    expect(builds.pages, greaterThan(0),
        reason: 'ordinary draft changes still reach the page listener');

    final beforeCompletion = builds.pages;
    vm.complete(frontendResult(
      id: 'streaming',
      imagePath: historyImage.path,
      seed: 73,
    ));
    await tester.pump();
    expect(builds.pages, greaterThan(beforeCompletion));
    expect(
        find.byKey(const ValueKey('result-workspace-preview')), findsNothing);
    expect(find.text('Seed 73'), findsOneWidget);
    expect(find.text('生成图片'), findsOneWidget);
    expect(
        tester
            .widget<GenerationResultCard>(find.byType(GenerationResultCard))
            .task!
            .status,
        'success');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('preview frames preserve a user-selected historical result',
      (tester) async {
    final history = frontendResult(
      id: 'history',
      imagePath: historyImage.path,
      seed: 41,
    );
    vm.sessionResults = [history, _pendingResult()];
    vm.lastCompletedTask = history;
    await _mount(tester);
    vm.receivePreview('streaming', _frame(1), 1);
    await tester.pump();
    expect(
        find.byKey(const ValueKey('result-workspace-preview')), findsOneWidget);

    final semantics = tester.ensureSemantics();
    final firstThumbnail = find.bySemanticsLabel('查看第 1 张结果');
    await tester.ensureVisible(firstThumbnail);
    await tester.tap(firstThumbnail);
    await tester.pump();
    semantics.dispose();
    expect(vm.selectedResultTaskId, history.taskId);

    for (var step = 2; step <= 4; step++) {
      vm.receivePreview('streaming', _frame(step), step);
      await tester.pump();
    }
    expect(vm.selectedResultTaskId, history.taskId);
    expect(
        find.byKey(const ValueKey('result-workspace-preview')), findsNothing);
    expect(find.text('Seed 41'), findsOneWidget);
    final image = find.descendant(
      of: find.byKey(const ValueKey('result-image-viewer')),
      matching: find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is FileImage,
      ),
    );
    expect((tester.widget<Image>(image).image as FileImage).file.path,
        historyImage.path);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('inactive preview regions resume directly at the latest frame',
      (tester) async {
    final tickersEnabled = ValueNotifier(true);
    addTearDown(tickersEnabled.dispose);
    await _mount(
      tester,
      home: ValueListenableBuilder<bool>(
        valueListenable: tickersEnabled,
        child: const GeneratePage(),
        builder: (context, enabled, child) => TickerMode(
          enabled: enabled,
          child: child!,
        ),
      ),
    );
    vm.receivePreview('streaming', _frame(1), 1);
    await tester.pump();
    final builds = _BuildCounts();
    addTearDown(builds.restore);

    tickersEnabled.value = false;
    await tester.pump();
    final beforeHiddenFrames = builds.results;
    vm.receivePreview('streaming', _frame(2), 2);
    await tester.pump();
    final latestHidden = _frame(3);
    vm.receivePreview('streaming', latestHidden, 3);
    await tester.pump();
    expect(builds.results, beforeHiddenFrames);
    expect(find.text('流式预览 · 第 1 步'), findsOneWidget);

    tickersEnabled.value = true;
    await tester.pump();
    expect(find.text('流式预览 · 第 3 步'), findsOneWidget);
    expect(_visiblePreviewBytes(tester), same(latestHidden));

    addTearDown(() => _resume(tester));
    var step = 3;
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.paused
    ]) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      if (state == AppLifecycleState.paused) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      await tester.pump();
      final beforeBackgroundFrames = builds.results;
      final previousStep = step;
      vm.receivePreview('streaming', _frame(++step), step);
      await tester.pump();
      final latestBackground = _frame(++step);
      vm.receivePreview('streaming', latestBackground, step);
      await tester.pump();
      expect(builds.results, beforeBackgroundFrames);
      expect(find.text('流式预览 · 第 $previousStep 步'), findsOneWidget);

      _resume(tester);
      await tester.pump();
      expect(find.text('流式预览 · 第 $step 步'), findsOneWidget);
      expect(_visiblePreviewBytes(tester), same(latestBackground));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _resume(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

Future<void> _mount(WidgetTester tester,
    {Widget home = const GeneratePage()}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 920);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(MaterialApp(
    theme: buildNaiHuishiTheme(Brightness.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    home: home,
  ));
  await tester.pump();
}

Uint8List _frame(int value) {
  final image = img.Image(width: 8, height: 4);
  img.fill(image, color: img.ColorRgba8(value * 7, 91, 219, 255));
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _visiblePreviewBytes(WidgetTester tester) {
  final image = find.descendant(
    of: find.byKey(const ValueKey('result-workspace-preview')),
    matching: find.byWidgetPredicate(
      (widget) => widget is Image && widget.image is MemoryImage,
    ),
  );
  return (tester.widget<Image>(image).image as MemoryImage).bytes;
}

GenerationTask _pendingResult() => frontendResult(id: 'streaming').copyWith(
      status: 'generating',
    );

class _PreviewGenerationFake extends FrontendGenerationFake {
  void complete(GenerationTask task) {
    isGenerating = false;
    sessionResults = [
      for (final result in sessionResults)
        result.taskId == task.taskId ? task : result,
    ];
    lastCompletedTask = task;
    streamPreviews.remove(task.taskId);
    streamPreviewSteps.remove(task.taskId);
    streamPreviewBytes = null;
    streamPreviewStep = null;
    notifyListeners();
  }
}

class _BuildCounts {
  final _previous = debugOnRebuildDirtyWidget;
  var pages = 0;
  var backgrounds = 0;
  var results = 0;

  _BuildCounts() {
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      _previous?.call(element, builtOnce);
      if (element.widget is GeneratePage) pages++;
      if (element.widget is StudioBackground) backgrounds++;
      if (element.widget is GenerationResultCard) results++;
    };
  }

  void restore() => debugOnRebuildDirtyWidget = _previous;
}
