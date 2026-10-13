import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/widgets/generation_result_card.dart';
import 'package:nai_huishi/presentation/widgets/fullscreen_image_preview.dart';

void main() {
  late Directory imageDirectory;
  late File resultImage;

  setUp(() async {
    imageDirectory = await Directory.systemTemp.createTemp('result-workspace-');
    resultImage =
        File('${imageDirectory.path}${Platform.pathSeparator}wide.png');
    final image = img.Image(width: 4, height: 2);
    image.setPixelRgba(0, 0, 240, 120, 90, 255);
    image.setPixelRgba(3, 1, 50, 100, 220, 255);
    await resultImage.writeAsBytes(img.encodePng(image));
  });

  tearDown(() async {
    if (await imageDirectory.exists()) {
      await imageDirectory.delete(recursive: true);
    }
  });

  testWidgets('empty workspace stays usable and exposes the real import action',
      (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(280, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var importCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GenerationResultCard(
              task: null,
              onSelect: (_) {},
              onImport: () => importCount++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('result-workspace-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('result-import-button')), findsOneWidget);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('result-workspace-empty')))
            .height,
        greaterThanOrEqualTo(220));
    expect(
        tester.getRect(find.byTooltip('导入新图片')).right, lessThanOrEqualTo(280));
    await tester.tap(find.byKey(const ValueKey('result-import-button')));
    expect(importCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'image remains contained, fit resets zoom, and selection resets it', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final first = _result('first', imagePath: resultImage.path, seed: 73);
    final second = _result('second', imagePath: resultImage.path, seed: 98);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _SelectableResultCard(results: [first, second]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final stage =
        tester.getRect(find.byKey(const ValueKey('result-workspace-stage')));
    expect(stage.height, 280);
    final viewerFinder = find.byKey(const ValueKey('result-image-viewer'));
    final imageFinder = find.descendant(
      of: viewerFinder,
      matching: find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is FileImage,
      ),
    );
    expect(tester.widget<Image>(imageFinder).fit, BoxFit.contain);
    expect(stage.contains(tester.getCenter(imageFinder)), isTrue);
    expect(find.text('${first.width} × ${first.height}'), findsOneWidget);
    expect(find.text('Seed 73'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _pinch(tester, viewerFinder, 1.6);
    await tester.pumpAndSettle();
    expect(_viewerScale(tester, viewerFinder), greaterThan(1.05));

    await tester.tap(find.byTooltip('重置缩放'));
    await tester.pumpAndSettle();
    expect(_viewerScale(tester, viewerFinder), closeTo(1, 0.02));

    await _pinch(tester, viewerFinder, 1.5);
    await tester.pumpAndSettle();
    expect(_viewerScale(tester, viewerFinder), greaterThan(1.05));

    final semantics = tester.ensureSemantics();
    await tester.tap(find.bySemanticsLabel('查看第 2 张结果'));
    await tester.pumpAndSettle();
    semantics.dispose();

    expect(_viewerScale(tester, viewerFinder), closeTo(1, 0.02));
    expect(find.text('Seed 98'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vertical swipes over a fit image still scroll the results page',
      (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 520);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final result = _result('scroll', imagePath: resultImage.path, seed: 42);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              children: [
                GenerationResultCard(
                  task: result,
                  results: [result],
                  workspaceHeight: 280,
                  onSelect: (_) {},
                  onPreview: () {},
                  onSave: () {},
                ),
                const SizedBox(height: 700),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('result-workspace-stage')),
      const Offset(0, -140),
    );
    await tester.pumpAndSettle();
    expect(scrollController.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace toolbar and actions fit short and tall phone widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final result = _result('one', imagePath: resultImage.path, seed: 12);
    for (final viewport in [const Size(320, 600), const Size(390, 900)]) {
      tester.view.physicalSize = viewport;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  viewport.height == 600 ? 2 : 1,
                ),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: GenerationResultCard(
                    task: result,
                    results: [result],
                    workspaceHeight: viewport.height == 600 ? 240 : 480,
                    onSelect: (_) {},
                    onImport: () {},
                    onPreview: () {},
                    onSave: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('导入新图片'), findsOneWidget);
      expect(find.byTooltip('全屏查看'), findsOneWidget);
      expect(find.byKey(const ValueKey('result-save-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('result-more-button')), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('result-more-button'))).right,
        lessThanOrEqualTo(viewport.width),
      );
      final stage = tester.getRect(
        find.byKey(const ValueKey('result-workspace-stage')),
      );
      final metadata = tester.getRect(
        find.byKey(const ValueKey('result-workspace-metadata')),
      );
      expect(metadata.top, greaterThanOrEqualTo(stage.bottom));
      expect(metadata.left, greaterThanOrEqualTo(stage.left));
      expect(
        tester.getRect(find.byKey(const ValueKey('result-save-button'))).bottom,
        lessThanOrEqualTo(viewport.height),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('default stage grows with height and keeps save in the viewport',
      (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final result =
        _result('default-height', imagePath: resultImage.path, seed: 7);
    double? shortStageHeight;
    double? tallStageHeight;
    for (final viewport in [const Size(390, 600), const Size(390, 852)]) {
      tester.view.physicalSize = viewport;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GenerationResultCard(
                task: result,
                results: [result],
                onSelect: (_) {},
                onSave: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final stageHeight = tester
          .getSize(find.byKey(const ValueKey('result-workspace-stage')))
          .height;
      if (viewport.height == 600) {
        shortStageHeight = stageHeight;
      } else {
        tallStageHeight = stageHeight;
      }
      expect(
        tester.getRect(find.byKey(const ValueKey('result-save-button'))).bottom,
        lessThanOrEqualTo(viewport.height),
      );
      expect(tester.takeException(), isNull);
    }
    expect(tallStageHeight, greaterThan(shortStageHeight!));
  });

  testWidgets('fullscreen preview opens contained and can return to fit', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showFullscreenImagePreview(
                  context,
                  imagePath: resultImage.path,
                ),
                child: const Text('预览图片'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('预览图片'));
    await tester.pumpAndSettle();

    final viewerFinder = find.byKey(const ValueKey('fullscreen-image-viewer'));
    final viewer = tester.widget<InteractiveViewer>(viewerFinder);
    expect(viewer.minScale, 1);
    expect(
      tester
          .widget<Image>(
            find.byWidgetPredicate(
              (widget) => widget is Image && widget.image is FileImage,
            ),
          )
          .fit,
      BoxFit.contain,
    );

    await _pinch(tester, viewerFinder, 1.5);
    await tester.pumpAndSettle();
    expect(find.byTooltip('重置缩放'), findsOneWidget);
    await tester.tap(find.byTooltip('重置缩放'));
    await tester.pumpAndSettle();
    expect(_viewerScale(tester, viewerFinder), closeTo(1, 0.02));
    expect(find.byTooltip('适应窗口'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

double _viewerScale(WidgetTester tester, Finder finder) {
  final viewer = tester.widget<InteractiveViewer>(finder);
  return viewer.transformationController!.value.getMaxScaleOnAxis();
}

Future<void> _pinch(WidgetTester tester, Finder finder, double scale) async {
  final center = tester.getRect(finder).center;
  const initialOffset = 50.0;
  final travel = initialOffset * (scale - 1);
  final first = await tester.startGesture(
    center - const Offset(initialOffset, 0),
    pointer: 11,
    kind: PointerDeviceKind.touch,
  );
  final second = await tester.startGesture(
    center + const Offset(initialOffset, 0),
    pointer: 12,
    kind: PointerDeviceKind.touch,
  );
  await tester.pump(const Duration(milliseconds: 30));
  await first.moveTo(center - Offset(initialOffset + travel, 0));
  await second.moveTo(center + Offset(initialOffset + travel, 0));
  await tester.pump(const Duration(milliseconds: 30));
  await first.up();
  await second.up();
  await tester.pumpAndSettle();
}

GenerationTask _result(
  String id, {
  required String imagePath,
  required int seed,
}) =>
    GenerationTask(
      taskId: id,
      model: 'nai-diffusion-4-5-full',
      prompt: 'silver hair',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0.25,
      sampler: 'k_euler',
      noiseSchedule: 'native',
      seed: seed,
      status: 'success',
      imagePath: imagePath,
      createdAt: DateTime(2026, 10, 13),
    );

class _SelectableResultCard extends StatefulWidget {
  final List<GenerationTask> results;

  const _SelectableResultCard({required this.results});

  @override
  State<_SelectableResultCard> createState() => _SelectableResultCardState();
}

class _SelectableResultCardState extends State<_SelectableResultCard> {
  late GenerationTask selected = widget.results.first;

  @override
  Widget build(BuildContext context) => GenerationResultCard(
        task: selected,
        results: widget.results,
        workspaceHeight: 280,
        onSelect: (result) => setState(() => selected = result),
        onPreview: () {},
        onSave: () {},
      );
}
