import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/official_upscale_page.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';

import '../../support/frontend_generation_fake.dart';

class _UpscaleGenerationFake extends FrontendGenerationFake {
  final requests = <(String, int)>[];
  GenerationTask? sourceTask;

  @override
  Future<String> upscaleFileWithOfficial(
    String inputPath,
    int scale, {
    GenerationTask? sourceTask,
  }) async {
    requests.add((inputPath, scale));
    this.sourceTask = sourceTask;
    if (sourceTask != null) {
      receive(
        sourceTask.copyWith(
          taskId: 'upscaled-${sourceTask.taskId}',
          imagePath: inputPath,
          width: sourceTask.width * scale,
          height: sourceTask.height * scale,
          completedAt: DateTime.now(),
        ),
      );
    }
    return inputPath;
  }
}

class _SaveImageFake implements SaveImageUseCase {
  @override
  Future<bool> saveToGallery(String filePath) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _UpscaleGenerationFake generation;

  setUp(() {
    generation = _UpscaleGenerationFake();
    sl.registerSingleton<GenerationViewModel>(generation);
    sl.registerSingleton<SaveImageUseCase>(_SaveImageFake());
  });

  tearDown(() async {
    await sl.reset();
    generation.dispose();
  });

  testWidgets('uses the selected initial file and chosen official scale', (
    tester,
  ) async {
    final sourcePath = File('assets/style_presets/style_001.jpg').absolute.path;
    expect(File(sourcePath).existsSync(), isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildNaiHuishiTheme(Brightness.dark),
        home: OfficialUpscalePage(initialImagePath: sourcePath),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('原图'), findsOneWidget);
    await tester.tap(find.text('4×'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('official-upscale-run')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('开始 4× 放大'));
    await tester.pumpAndSettle();
    expect(find.text('开始 4× 官方 Upscale？'), findsOneWidget);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(generation.requests, [(sourcePath, 4)]);
    expect(find.text('放大结果'), findsOneWidget);
    expect(find.text('保存到相册'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('binds history source metadata and can return to workspace', (
    tester,
  ) async {
    final sourcePath = File('assets/style_presets/style_001.jpg').absolute.path;
    final sourceTask = frontendResult(
      id: 'history-upscale-source',
      imagePath: sourcePath,
    );
    bool? returnedToWorkspace;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildNaiHuishiTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                returnedToWorkspace = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => OfficialUpscalePage(
                      initialTask: sourceTask,
                    ),
                  ),
                );
              },
              child: const Text('打开 Upscale'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开 Upscale'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('official-upscale-run')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('开始 2× 放大'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(generation.sourceTask?.taskId, sourceTask.taskId);
    expect(generation.selectedResult?.taskId, 'upscaled-${sourceTask.taskId}');
    expect(find.text('放大结果'), findsOneWidget);
    expect(find.text('保存到相册'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('official-upscale-return-to-workspace')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('official-upscale-return-to-workspace')),
        findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('official-upscale-return-to-workspace')),
    );
    await tester.pumpAndSettle();
    expect(returnedToWorkspace, isTrue);
    expect(tester.takeException(), isNull);
  });
}
