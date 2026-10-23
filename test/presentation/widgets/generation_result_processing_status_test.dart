import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/widgets/generation_result_card.dart';

void main() {
  late Directory imageDirectory;
  late String imagePath;

  setUp(() async {
    imageDirectory =
        await Directory.systemTemp.createTemp('processing-status-');
    imagePath = '${imageDirectory.path}${Platform.pathSeparator}result.png';
    final image = img.Image(width: 4, height: 2);
    image.setPixelRgba(0, 0, 240, 120, 90, 255);
    image.setPixelRgba(3, 1, 50, 100, 220, 255);
    await File(imagePath).writeAsBytes(img.encodePng(image));
  });

  tearDown(() async {
    if (await imageDirectory.exists()) {
      await imageDirectory.delete(recursive: true);
    }
  });

  testWidgets(
      'shows processing overlay on its source and status after switching',
      (tester) async {
    final source = _task('processing-source', imagePath);
    final other = _task('other-result', imagePath);
    var selected = source;
    var processing = true;
    StateSetter? updateCard;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateCard = setState;
              return GenerationResultCard(
                task: selected,
                results: [source, other],
                workspaceHeight: 260,
                processing: processing,
                processingSourceTaskId: source.taskId,
                processingLabel: '官方超分处理中',
                processingStatus: '第 1/2 次超分',
                onSelect: (task) => setState(() => selected = task),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('result-processing-overlay')),
        findsOneWidget);
    expect(find.text('官方超分处理中'), findsOneWidget);
    expect(find.text('第 1/2 次超分'), findsOneWidget);
    expect(find.byKey(const ValueKey('result-processing-global-status')),
        findsNothing);

    await tester.tap(find.byTooltip('第 2 张结果'));
    await tester.pump();

    expect(selected.taskId, other.taskId);
    expect(
        find.byKey(const ValueKey('result-processing-overlay')), findsNothing);
    expect(find.byKey(const ValueKey('result-processing-global-status')),
        findsOneWidget);
    expect(find.textContaining('第 1/2 次超分'), findsOneWidget);
    updateCard!(() => processing = false);
    await tester.pump();
    expect(find.byKey(const ValueKey('result-processing-global-status')),
        findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

GenerationTask _task(String id, String imagePath) => GenerationTask(
      taskId: id,
      model: 'nai-diffusion-4-5-full',
      prompt: 'silver hair',
      negativePrompt: 'low quality',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0,
      sampler: 'k_euler',
      noiseSchedule: 'native',
      status: 'success',
      imagePath: imagePath,
      createdAt: DateTime(2026, 10, 23),
    );
