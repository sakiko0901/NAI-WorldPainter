import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/widgets/generation_result_card.dart';

void main() {
  testWidgets('result workspace keeps only save and the exact image menu', (
    tester,
  ) async {
    final result = _result();
    final dispatched = <String>[];
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GenerationResultCard(
              task: result,
              results: [result],
              onSelect: (_) {},
              onPreview: () {},
              onSave: () {},
              onInpaint: (task) async =>
                  dispatched.add('inpaint:${task.taskId}'),
              onUpscale: (task) async =>
                  dispatched.add('upscale:${task.taskId}'),
              onEnhance: (task) async =>
                  dispatched.add('enhance:${task.taskId}'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('保存图片'), findsOneWidget);
    expect(find.byKey(const ValueKey('result-save-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('result-more-button')), findsOneWidget);
    expect(find.byTooltip('提示词与参数'), findsNothing);
    expect(find.text('复用'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('result-more-button')));
    await tester.pumpAndSettle();
    expect(find.text('导入到局部重绘'), findsOneWidget);
    expect(find.text('Upscale'), findsOneWidget);
    expect(find.text('Enhance'), findsOneWidget);
    expect(find.text('Pixiv'), findsNothing);

    for (final (label, action) in [
      ('导入到局部重绘', 'inpaint'),
      ('Upscale', 'upscale'),
      ('Enhance', 'enhance'),
    ]) {
      if (dispatched.isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('result-more-button')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(dispatched.last, '$action:${result.taskId}');
    }
    expect(dispatched, [
      'inpaint:${result.taskId}',
      'upscale:${result.taskId}',
      'enhance:${result.taskId}',
    ]);
    expect(tester.takeException(), isNull);
  });
}

GenerationTask _result() => GenerationTask(
      taskId: 'workspace-result',
      model: 'nai-diffusion-4-5-full',
      prompt: 'silver hair',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0.25,
      sampler: 'k_euler',
      noiseSchedule: 'native',
      seed: 73,
      status: 'success',
      createdAt: DateTime(2026, 10, 11),
    );
