import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/pages/history_detail_page.dart';
import 'package:nai_huishi/presentation/pages/official_upscale_page.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';

import '../../support/frontend_generation_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '8000-character prompt and character prompt stay selectable and copy whole at 320dp/200%',
    (tester) async {
      const longPromptPart = 'tag, ';
      final longPrompt = List.filled(1600, longPromptPart).join();
      final characterPrompt = List.filled(500, 'character detail, ').join();
      var copiedText = '';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText =
                (call.arguments as Map<Object?, Object?>)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await _openDetail(
        tester,
        task: _task(
          prompt: longPrompt,
          characters: [CharacterSpec(prompt: characterPrompt, uc: 'blue eyes')],
        ),
        width: 320,
        textScale: 2,
      );

      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == longPrompt,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(
        find.byKey(const ValueKey('copy-positive-prompt')),
      );
      await tester.tap(find.byKey(const ValueKey('copy-positive-prompt')));
      await tester.pump();
      expect(copiedText, longPrompt);

      await tester.ensureVisible(
        find.byKey(const ValueKey('copy-character-0-positive')),
      );
      await tester.tap(find.byKey(const ValueKey('copy-character-0-positive')));
      await tester.pump();
      expect(copiedText, characterPrompt);

      await tester.ensureVisible(
        find.byKey(const ValueKey('copy-character-0-negative')),
      );
      await tester.tap(find.byKey(const ValueKey('copy-character-0-negative')));
      await tester.pump();
      expect(copiedText, 'blue eyes');

      await tester.ensureVisible(
        find.byKey(const ValueKey('reuse-prompts-button')),
      );
      await tester.tap(find.byKey(const ValueKey('reuse-prompts-button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('cancel-prompt-reuse')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets('prompt reuse can be canceled or limited to negative prompt', (
    tester,
  ) async {
    final scopes = <HistoryPromptReuseScope>[];
    var navigationCount = 0;

    await _openDetail(
      tester,
      task: _task(prompt: 'positive', negativePrompt: 'negative'),
      onReusePrompt: (task, scope) async {
        scopes.add(scope);
      },
      onNavigate: (_) {
        navigationCount++;
      },
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('reuse-prompts-button')),
    );
    await tester.tap(find.byKey(const ValueKey('reuse-prompts-button')));
    await tester.pumpAndSettle();
    expect(find.text('仅正向提示词'), findsOneWidget);
    expect(find.text('仅负向提示词'), findsOneWidget);
    expect(find.text('正向与负向提示词'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cancel-prompt-reuse')));
    await tester.pumpAndSettle();
    expect(scopes, isEmpty);
    expect(navigationCount, 0);

    await tester.ensureVisible(
      find.byKey(const ValueKey('reuse-prompts-button')),
    );
    await tester.tap(find.byKey(const ValueKey('reuse-prompts-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reuse-prompt-negative')));
    await tester.pumpAndSettle();
    expect(scopes, [HistoryPromptReuseScope.negative]);
    expect(navigationCount, 1);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('detail image menu dispatches all three actions with its task', (
    tester,
  ) async {
    final source = _task();
    final dispatched = <String>[];

    await _openDetail(
      tester,
      task: source,
      onInpaint: (task) async {
        expect(task, same(source));
        dispatched.add('inpaint');
      },
      onUpscale: (task) async {
        expect(task, same(source));
        dispatched.add('upscale');
      },
      onEnhance: (task) async {
        expect(task, same(source));
        dispatched.add('enhance');
      },
    );

    expect(find.byKey(const ValueKey('detail-more-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('detail-more-button')));
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
        await tester.tap(find.byKey(const ValueKey('detail-more-button')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(dispatched.last, action);
    }
    expect(dispatched, ['inpaint', 'upscale', 'enhance']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history inpaint import uses the recorded image and route', (
    tester,
  ) async {
    final services = _installHistoryActionServices(tester);
    var navigationCount = 0;
    final source = _task(
      imagePath: services.imagePath,
      characters: const [CharacterSpec(prompt: 'blue hair', uc: 'red eyes')],
    );

    await _openDetail(
      tester,
      task: source,
      onNavigate: (_) => navigationCount++,
    );
    await tester.tap(find.byKey(const ValueKey('detail-more-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入到局部重绘'));
    await tester.pump();
    await _flushFileIo(tester);
    await tester.pumpAndSettle();

    expect(services.generation.generationMode, GenerationMode.inpainting);
    expect(services.generation.sourceImagePath, services.imagePath);
    expect(services.generation.maskImagePath, isNull);
    expect(services.generation.loadedHistoryTask, isNull);
    expect(services.generation.importedInpaintTask?.taskId, source.taskId);
    expect(services.generation.inpaintPrompt, source.prompt);
    expect(
      services.generation.inpaintNegativePrompt,
      source.negativePrompt,
    );
    expect(services.generation.characters.single.prompt, 'blue hair');
    expect(services.generation.characters.single.uc, 'red eyes');
    expect(navigationCount, 1);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('history Upscale opens the official page with the source image', (
    tester,
  ) async {
    final services = _installHistoryActionServices(tester);
    await _openDetail(
      tester,
      task: _task(imagePath: services.imagePath),
    );
    await tester.tap(find.byKey(const ValueKey('detail-more-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upscale'));
    await tester.pump();
    await _flushFileIo(tester);
    await tester.pumpAndSettle();

    expect(find.byType(OfficialUpscalePage), findsOneWidget);
    expect(
      tester
          .widget<OfficialUpscalePage>(find.byType(OfficialUpscalePage))
          .initialTask
          ?.taskId,
      'history-detail-test',
    );
    expect(find.text('NovelAI Upscale'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
              find.byKey(const ValueKey('official-upscale-run')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('history Upscale returns its bound result to the workbench', (
    tester,
  ) async {
    final services = _installHistoryActionServices(tester);
    final source = _task(imagePath: services.imagePath);
    var navigationCount = 0;

    await _openDetail(
      tester,
      task: source,
      onNavigate: (_) => navigationCount++,
    );
    await tester.tap(find.byKey(const ValueKey('detail-more-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upscale'));
    await tester.pump();
    await _flushFileIo(tester);
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('official-upscale-return-to-workspace')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(const ValueKey('official-upscale-return-to-workspace')),
    );
    await tester.pumpAndSettle();

    expect(services.generation.upscaleSource?.taskId, source.taskId);
    expect(
      services.generation.selectedResult?.taskId,
      'upscaled-history-result',
    );
    expect(navigationCount, 1);
    expect(find.byType(HistoryDetailPage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('history Enhance supplies an out-of-session source and saves it',
      (
    tester,
  ) async {
    final services = _installHistoryActionServices(tester);
    services.generation.prompt = 'keep the current draft';
    services.generation.selectedModel = 'gpt:image-1';
    final source = _task(
      imagePath: services.imagePath,
      protocol: AppConstants.novelAiOfficialProtocol,
    );
    var navigationCount = 0;

    await _openDetail(
      tester,
      task: source,
      onNavigate: (_) => navigationCount++,
    );
    await tester.tap(find.byKey(const ValueKey('detail-more-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enhance'));
    await tester.pumpAndSettle();
    expect(find.text('Enhance · 官方重绘放大'), findsOneWidget);
    expect(find.textContaining('会消耗 Anlas'), findsOneWidget);
    await tester.tap(find.text('开始 Enhance'));
    await tester.pump();
    await _flushFileIo(tester);
    await tester.pumpAndSettle();

    expect(services.generation.enhanceSource?.taskId, source.taskId);
    expect(services.generation.prompt, 'keep the current draft');
    expect(services.generation.selectedModel, 'gpt:image-1');
    expect(services.history.saved.single.taskId, 'enhanced-history-result');
    expect(navigationCount, 1);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
    'full parameter reuse ignores repeated taps and navigates after it completes',
    (tester) async {
      final allowReuse = Completer<void>();
      var reuseCount = 0;
      var navigationCount = 0;

      await _openDetail(
        tester,
        task: _task(),
        onReuseParameters: (_) async {
          reuseCount++;
          await allowReuse.future;
        },
        onNavigate: (_) {
          navigationCount++;
        },
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('reuse-parameters-button')),
      );
      await tester.tap(find.byKey(const ValueKey('reuse-parameters-button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('范围受历史记录和现有方法支持限制'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-parameter-reuse')));
      await tester.pump();
      await tester.pump();
      expect(reuseCount, 1);
      expect(navigationCount, 0);

      await tester.ensureVisible(
        find.byKey(const ValueKey('reuse-parameters-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('reuse-parameters-button')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(reuseCount, 1);
      expect(navigationCount, 0);

      allowReuse.complete();
      await tester.pumpAndSettle();
      expect(reuseCount, 1);
      expect(navigationCount, 1);
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'missing seed is shown as not recorded and missing image is explicit',
    (tester) async {
      await _openDetail(tester, task: _task());

      expect(find.text('Seed'), findsOneWidget);
      expect(find.text('随机'), findsNothing);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('parameter-seed-value')),
            )
            .data,
        '未记录',
      );
      expect(find.text('历史记录没有可预览的图片'), findsOneWidget);
    },
  );
}

Future<void> _openDetail(
  WidgetTester tester, {
  required GenerationTask task,
  double width = 420,
  double textScale = 1,
  HistoryPromptReuseCallback? onReusePrompt,
  HistoryParameterReuseCallback? onReuseParameters,
  HistoryDetailImageAction? onInpaint,
  HistoryDetailImageAction? onUpscale,
  HistoryDetailImageAction? onEnhance,
  ValueChanged<int>? onNavigate,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey('open-history-detail'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => HistoryDetailPage(
                    task: task,
                    onNavigate: onNavigate,
                    onReusePrompt: onReusePrompt,
                    onReuseParameters: onReuseParameters,
                    onInpaint: onInpaint,
                    onUpscale: onUpscale,
                    onEnhance: onEnhance,
                  ),
                ),
              ),
              child: const Text('打开详情'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.byKey(const ValueKey('open-history-detail')));
  await tester.pumpAndSettle();
}

GenerationTask _task({
  String prompt = 'recorded prompt',
  String? negativePrompt = 'recorded negative prompt',
  List<CharacterSpec>? characters,
  String? imagePath,
  String? protocol,
}) {
  return GenerationTask(
    taskId: 'history-detail-test',
    model: 'nai-diffusion-4-5-full',
    protocol: protocol,
    prompt: prompt,
    negativePrompt: negativePrompt,
    width: 832,
    height: 1216,
    scale: 5,
    cfgRescale: 0.25,
    sampler: 'k_euler',
    noiseSchedule: 'native',
    characters: characters,
    status: 'success',
    imagePath: imagePath,
    createdAt: DateTime(2026, 10, 11),
  );
}

({
  Directory directory,
  String imagePath,
  _HistoryActionGeneration generation,
  _RecordingHistoryRepository history,
}) _installHistoryActionServices(WidgetTester tester) {
  _unregisterIfRegistered<SaveImageUseCase>();
  _unregisterIfRegistered<HistoryRepository>();
  _unregisterIfRegistered<GenerationViewModel>();
  final directory = Directory.systemTemp.createTempSync('history-detail-');
  final imagePath = '${directory.path}${Platform.pathSeparator}source.png';
  File(imagePath).writeAsBytesSync(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aWQAAAAASUVORK5CYII=',
    ),
  );
  final generation = _HistoryActionGeneration();
  final history = _RecordingHistoryRepository();
  sl.registerSingleton<GenerationViewModel>(generation);
  sl.registerSingleton<HistoryRepository>(history);
  sl.registerSingleton<SaveImageUseCase>(SaveImageUseCase(history));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache.clearLiveImages();
    PaintingBinding.instance.imageCache.clear();
    _unregisterIfRegistered<SaveImageUseCase>();
    _unregisterIfRegistered<HistoryRepository>(instance: history);
    _unregisterIfRegistered<GenerationViewModel>(instance: generation);
    generation.dispose();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may still hold a decoded image cache handle until test exit.
    }
  });
  return (
    directory: directory,
    imagePath: imagePath,
    generation: generation,
    history: history,
  );
}

void _unregisterIfRegistered<T extends Object>({Object? instance}) {
  if (!sl.isRegistered<T>()) return;
  final result = sl.unregister<T>(instance: instance);
  if (result is Future<void>) unawaited(result);
}

Future<void> _flushFileIo(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
}

class _HistoryActionGeneration extends FrontendGenerationFake {
  String? _sourceImagePath;
  String? _maskImagePath;

  @override
  String? get sourceImagePath => _sourceImagePath;

  @override
  set sourceImagePath(String? value) => _sourceImagePath = value;

  @override
  String? get maskImagePath => _maskImagePath;

  @override
  set maskImagePath(String? value) => _maskImagePath = value;

  GenerationTask? enhanceSource;
  GenerationTask? upscaleSource;
  GenerationTask? loadedHistoryTask;

  @override
  Future<void> loadFromHistory(GenerationTask task) async {
    loadedHistoryTask = task;
    selectedModel = task.model;
  }

  @override
  Future<void> updateInpaintPrompt(String value) async {
    inpaintPrompt = value;
  }

  @override
  Future<void> updateInpaintNegativePrompt(String value) async {
    inpaintNegativePrompt = value;
  }

  @override
  Future<void> importTaskToInpaint(GenerationTask task) async {
    await super.importTaskToInpaint(task);
    sourceImagePath = task.imagePath;
    maskImagePath = null;
  }

  @override
  void setSourceImagePath(String? path) => sourceImagePath = path;

  @override
  void setMaskImagePath(String? path) => maskImagePath = path;

  @override
  Future<bool> enhanceWithOfficial({
    required double scale,
    required double strength,
    double noise = 0,
    bool max = false,
    String? promptOverride,
    GenerationTask? sourceTask,
    void Function(GenerationTask result)? onCompleted,
  }) async {
    final source = sourceTask ?? selectedResult ?? lastCompletedTask;
    if (source == null) return false;
    enhanceSource = source;
    final result = source.copyWith(
      taskId: 'enhanced-history-result',
      imagePath: source.imagePath,
      width: source.width * 2,
      height: source.height * 2,
      completedAt: DateTime.now(),
    );
    sessionResults = [...sessionResults, result];
    selectedResultTaskId = result.taskId;
    lastCompletedTask = result;
    onCompleted?.call(result);
    return true;
  }

  @override
  Future<String> upscaleFileWithOfficial(
    String inputPath,
    int scale, {
    GenerationTask? sourceTask,
  }) async {
    upscaleSource = sourceTask;
    if (sourceTask != null) {
      receive(
        sourceTask.copyWith(
          taskId: 'upscaled-history-result',
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

class _RecordingHistoryRepository implements HistoryRepository {
  final saved = <GenerationTask>[];

  @override
  Future<GenerationTask> saveTask(GenerationTask task) async {
    saved.add(task);
    return task;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
