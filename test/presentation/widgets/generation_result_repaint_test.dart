import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/generation_result_card.dart';

enum _AnimationScenario {
  waiting,
  streaming,
  processingOverlay,
  processingNotice,
  historyWithPendingThumbnail,
}

void main() {
  late Directory imageDirectory;
  late File resultImage;
  late Uint8List previewBytes;

  setUp(() async {
    imageDirectory = await Directory.systemTemp.createTemp('result-repaint-');
    resultImage =
        File('${imageDirectory.path}${Platform.pathSeparator}result.png');
    final image = img.Image(width: 8, height: 4);
    img.fill(image, color: img.ColorRgba8(60, 120, 220, 255));
    previewBytes = Uint8List.fromList(img.encodePng(image));
    await resultImage.writeAsBytes(previewBytes);
  });

  tearDown(() async {
    if (await imageDirectory.exists()) {
      await imageDirectory.delete(recursive: true);
    }
  });

  for (final scenario in _AnimationScenario.values) {
    testWidgets('${scenario.name} animates without repainting the workspace',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final theme = buildNaiHuishiTheme(Brightness.dark);
      await tester
          .pumpWidget(MaterialApp(theme: theme, home: const Scaffold()));
      final context = tester.element(find.byType(Scaffold));
      await tester.runAsync(() async {
        await Future.wait([
          precacheImage(FileImage(resultImage), context),
          precacheImage(MemoryImage(previewBytes), context),
        ]);
      });

      final source = _task('source', imagePath: resultImage.path);
      final other = _task('other', imagePath: resultImage.path);
      final pending = _task('pending');
      final generating = switch (scenario) {
        _AnimationScenario.waiting ||
        _AnimationScenario.streaming ||
        _AnimationScenario.historyWithPendingThumbnail =>
          true,
        _ => false,
      };
      final processing = scenario == _AnimationScenario.processingOverlay ||
          scenario == _AnimationScenario.processingNotice;
      final selected = switch (scenario) {
        _AnimationScenario.waiting || _AnimationScenario.streaming => pending,
        _AnimationScenario.processingNotice => other,
        _ => source,
      };
      final results = switch (scenario) {
        _AnimationScenario.streaming ||
        _AnimationScenario.historyWithPendingThumbnail =>
          [source, pending],
        _ => [selected],
      };

      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GenerationResultCard(
                task: selected,
                results: results,
                workspaceHeight: 260,
                generating: generating,
                processing: processing,
                processingSourceTaskId: processing ? source.taskId : null,
                processingLabel: '官方超分处理中',
                processingStatus: '第 1/2 次超分',
                streamPreviewBytes: scenario == _AnimationScenario.streaming
                    ? previewBytes
                    : null,
                streamPreviewStep: 3,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      ));
      // Let decoded images and the first animation frame finish before counting.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      final workspaceKey = switch (scenario) {
        _AnimationScenario.waiting => 'result-workspace-empty',
        _AnimationScenario.streaming => 'result-workspace-preview',
        _ => 'result-workspace-stage',
      };
      // The workspace's first painter draws the actual static grid. Delegate to
      // it so the measurement keeps the real component and its rendering path.
      final grid = tester.renderObject<RenderCustomPaint>(find
          .descendant(
            of: find.byKey(ValueKey(workspaceKey)),
            matching: find.byType(CustomPaint),
          )
          .first);
      final counter = _CountingPainter(grid.painter!);
      grid.painter = counter;
      await tester.pump();
      final initialPaints = counter.paints;
      expect(initialPaints, greaterThan(0));

      final indicators = find.byType(CircularProgressIndicator);
      expect(indicators,
          findsNWidgets(scenario == _AnimationScenario.streaming ? 2 : 1));
      final boundaries = <RenderRepaintBoundary>[];
      final indicatorSizes = <Size>[];
      for (var index = 0; index < indicators.evaluate().length; index++) {
        final indicator = indicators.at(index);
        RenderObject? ancestor = tester.renderObject(indicator);
        while (ancestor != null && ancestor is! RenderRepaintBoundary) {
          ancestor = ancestor.parent;
        }
        expect(ancestor, isA<RenderRepaintBoundary>());
        final boundary = ancestor! as RenderRepaintBoundary;
        boundary.debugResetMetrics();
        boundaries.add(boundary);
        indicatorSizes.add(tester.getSize(indicator));
      }

      const frames = 8;
      for (var frame = 0; frame < frames; frame++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      expect(counter.paints, initialPaints,
          reason: 'The static workspace must not repaint with a spinner tick');
      for (var index = 0; index < boundaries.length; index++) {
        final boundary = boundaries[index];
        // A card-wide boundary would still repaint all static content.
        expect(boundary.size, indicatorSizes[index]);
        expect(boundary.debugAsymmetricPaintCount, greaterThanOrEqualTo(frames),
            reason: 'Each spinner must keep repainting independently');
        expect(boundary.debugSymmetricPaintCount, 0);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

GenerationTask _task(String id, {String? imagePath}) => GenerationTask(
      taskId: id,
      model: 'nai-diffusion-5-full',
      prompt: 'silver hair',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0,
      sampler: 'k_euler',
      noiseSchedule: 'native',
      status: imagePath == null ? 'running' : 'success',
      imagePath: imagePath,
      createdAt: DateTime(2026, 10, 27),
    );

class _CountingPainter extends CustomPainter {
  final CustomPainter delegate;
  int paints = 0;

  _CountingPainter(this.delegate);

  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    delegate.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _CountingPainter oldDelegate) =>
      oldDelegate.delegate != delegate;
}
