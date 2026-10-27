import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/data/datasources/local/daily_stats_local_datasource.dart';
import 'package:nai_huishi/data/datasources/local/official_novelai_token_store.dart';
import 'package:nai_huishi/data/datasources/local/workspace_image_importer.dart';
import 'package:nai_huishi/data/datasources/remote/official_novelai_api_service.dart';
import 'package:nai_huishi/domain/agents/tools/read_current_prompts_tool.dart';
import 'package:nai_huishi/domain/agents/tools/write_prompt_tool.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/tiled_img2img.dart';
import 'package:nai_huishi/domain/repositories/generation_repository.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/domain/repositories/settings_repository.dart';
import 'package:nai_huishi/domain/usecases/generate_image.dart';
import 'package:nai_huishi/domain/usecases/manage_settings.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'inpaint import replaces all prompts and isolates persistent role drafts',
      () async {
    final directory = await Directory.systemTemp.createTemp('inpaint_drafts_');
    addTearDown(() => directory.delete(recursive: true));
    final source = await _writeTestPng(directory, 'source.png', 16, 16);
    final history = _MemoryHistoryRepository();
    final settings = _SettingsRepository();
    final queue =
        GenerationQueue(_CapturingGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final vm = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(vm.dispose);
    await Future<void>.delayed(Duration.zero);
    vm.characters = const [
      CharacterSpec(prompt: 'untouched text-to-image role')
    ];
    vm.inpaintPrompt = 'stale';
    vm.inpaintNegativePrompt = 'stale negative';
    vm.inpaintCharacters = const [CharacterSpec(prompt: 'stale role')];
    final task = GenerationTask(
      taskId: 'source',
      model: 'nai-diffusion-5-full',
      prompt: '2girls, beach',
      negativePrompt: 'bad quality',
      width: 16,
      height: 16,
      scale: 5,
      cfgRescale: 0,
      sampler: 'k_dpmpp_2m',
      noiseSchedule: 'native',
      status: 'success',
      createdAt: DateTime(2026),
      imagePath: source.path,
      characters: const [
        CharacterSpec(prompt: 'blue hair', uc: 'hat'),
        CharacterSpec(
            prompt: 'red hair', uc: 'glasses', centerX: .7, centerY: .4),
        CharacterSpec(prompt: 'disabled role', enabled: false),
      ],
    );
    await vm.importTaskToInpaint(task);
    expect(vm.generationMode, GenerationMode.inpainting);
    expect(vm.inpaintPrompt, task.prompt);
    expect(vm.inpaintNegativePrompt, 'bad quality');
    expect(vm.characters, task.characters);
    expect(settings.savedInpaintCharacters, task.characters);
    expect(vm.sourceImagePath, source.path);
    expect(vm.maskImagePath, isNull);
    expect(vm.selectedSampler, 'k_euler');

    final built = vm.buildInpaintTask(
      sourcePath: source.path,
      maskPath: source.path,
      prompt: vm.inpaintPrompt,
      negativePrompt: vm.inpaintNegativePrompt,
      strength: .7,
      disabledOriginalImage: false,
      colorCorrect: true,
    );
    expect(built.characters, hasLength(2));
    expect(built.characters!.first.uc, 'hat');
    expect(built.characters!.first.centerX, isNull);
    expect(built.characters!.last.centerX, .7);
    expect(built.useCoords, isTrue);
    vm.setCharacterPositionAuto(1);
    final automatic = vm.buildInpaintTask(
      sourcePath: source.path,
      maskPath: source.path,
      prompt: vm.inpaintPrompt,
      negativePrompt: vm.inpaintNegativePrompt,
      strength: .7,
      disabledOriginalImage: false,
      colorCorrect: true,
    );
    expect(automatic.useCoords, isFalse);
    expect(
        automatic.characters!
            .every((c) => c.centerX == null && c.centerY == null),
        isTrue);
    final written = await WritePromptTool(vm).call({
      'target': 'character_1',
      'content': 'green hair',
      'mode': 'replace',
    });
    expect(written.success, isTrue);
    expect(vm.inpaintCharacters.first.centerX, isNull);
    expect(vm.inpaintCharacters.first.prompt, 'green hair');
    expect(built.characters!.first.prompt, 'blue hair');
    final read = await ReadCurrentPromptsTool(vm).call(const {});
    expect(read.followUpHint, contains('green hair'));
    vm.setGenerationMode(GenerationMode.textToImage);
    expect(vm.characters.single.prompt, 'untouched text-to-image role');
    await vm.importTaskToInpaint(GenerationTask(
      taskId: 'empty',
      model: task.model,
      prompt: '',
      width: 16,
      height: 16,
      scale: 5,
      cfgRescale: 0,
      sampler: 'k_euler',
      noiseSchedule: 'native',
      status: 'success',
      createdAt: DateTime(2026),
      imagePath: source.path,
    ));
    expect(vm.inpaintPrompt, isEmpty);
    expect(vm.inpaintNegativePrompt, isEmpty);
    expect(vm.inpaintCharacters, isEmpty);
    expect(settings.savedInpaintCharacters, isEmpty);
  });

  for (final enhance in [false, true]) {
    test(
        '${enhance ? 'Enhance' : 'Upscale'} binds history input and adds a distinct workspace result',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('processed_result_');
      addTearDown(() => directory.delete(recursive: true));
      final source = await _writeTestPng(directory, 'source.png', 16, 16);
      final output = await _writeTestPng(directory, 'output.png', 32, 32);
      final gate = Completer<void>();
      final service = _TestOfficialNovelAiApiService(
        upscaleOutputPath: output.path,
        enhanceOutputPath: output.path,
        processingGate: gate,
      );
      final history = _MemoryHistoryRepository();
      final queue =
          GenerationQueue(_CapturingGenerationRepository('unused'), history);
      addTearDown(queue.dispose);
      final vm = _createGenerationViewModel(
        generateImage: GenerateImageUseCase(history),
        manageSettings: ManageSettingsUseCase(_SettingsRepository()),
        saveImage: SaveImageUseCase(history),
        queue: queue,
        officialApi: service,
        officialTokenStore: _TestOfficialNovelAiTokenStore('test'),
      );
      addTearDown(vm.dispose);
      await Future<void>.delayed(Duration.zero);
      final task = GenerationTask(
        id: 18,
        taskId: 'history',
        model: 'nai-diffusion-5-full',
        prompt: 'original prompt',
        width: 16,
        height: 16,
        scale: 5,
        cfgRescale: 0,
        sampler: 'k_euler',
        noiseSchedule: 'native',
        status: 'success',
        createdAt: DateTime(2026),
        imagePath: source.path,
        imageUrl: 'https://example.test/original.png',
      );
      final old = task.copyWith(taskId: 'old-workspace');
      vm.displayImportedImage(old);
      GenerationTask? receipt;
      final pending = enhance
          ? vm.enhanceWithOfficial(
              scale: 1.5,
              strength: .3,
              sourceTask: task,
              onCompleted: (result) => receipt = result)
          : vm.upscaleWithOfficial(2, sourceTask: task);
      expect(vm.isProcessingImage, isTrue);
      expect(vm.imageProcessingSourceTaskId, 'history');
      expect(vm.imageProcessingLabel, enhance ? 'Enhance' : 'Upscale');
      await Future<void>.delayed(Duration.zero);
      expect(vm.imageProcessingStatus, contains('test processing'));
      expect(await vm.upscaleWithOfficial(2), isFalse);
      await vm.generate();
      expect(vm.sessionResults, [old]);
      gate.complete();
      expect(await pending, isTrue);
      expect(vm.isProcessingImage, isFalse);
      expect(vm.imageProcessingSourceTaskId, isNull);
      expect(vm.imageProcessingStatus, isNull);
      final result = vm.selectedResult!;
      expect(vm.sessionResults, hasLength(2));
      expect(result.imagePath, output.path);
      expect(result.width, 32);
      expect(result.prompt, 'original prompt');
      expect(result.taskId, isNot(task.taskId));
      expect(result.id, isNull);
      expect(result.imageUrl, isNull);
      if (enhance) expect(receipt, same(result));
      expect(task.imagePath, source.path);
    });
  }

  test('standalone upscale adds its output and clears busy state after failure',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('standalone_upscale_');
    addTearDown(() => directory.delete(recursive: true));
    final source = await _writeTestPng(directory, 'source.png', 16, 16);
    final output = await _writeTestPng(directory, 'output.png', 32, 32);
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_CapturingGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final vm = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
      officialApi:
          _TestOfficialNovelAiApiService(upscaleOutputPath: output.path),
      officialTokenStore: _TestOfficialNovelAiTokenStore('test'),
    );
    addTearDown(vm.dispose);
    await Future<void>.delayed(Duration.zero);
    await vm.upscaleFileWithOfficial(source.path, 2);
    expect(vm.sessionResults.single.imagePath, output.path);
    expect(vm.selectedResult!.model, 'imported-image');
    await output.delete();
    await expectLater(vm.upscaleFileWithOfficial(source.path, 2),
        throwsA(isA<ApiException>()));
    expect(vm.isProcessingImage, isFalse);
    expect(vm.imageProcessingStatus, isNull);
    expect(vm.sessionResults, hasLength(1));
  });

  for (final automaticLayout in [true, false]) {
    test(
        'agent character ${automaticLayout ? 'automatic layout' : 'manual positions'} reaches the generation task',
        () async {
      final image = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'generation_viewmodel_agent_character_positions.png',
      );
      await image.writeAsBytes(const [1, 2, 3]);
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });

      final history = _MemoryHistoryRepository();
      final repository = _CapturingGenerationRepository(image.path);
      final queue = GenerationQueue(repository, history);
      addTearDown(queue.dispose);
      final vm = _createGenerationViewModel(
        generateImage: GenerateImageUseCase(history),
        manageSettings: ManageSettingsUseCase(_SettingsRepository()),
        saveImage: SaveImageUseCase(history),
        queue: queue,
      );
      addTearDown(vm.dispose);
      await Future<void>.delayed(Duration.zero);
      vm.imageModelOptions = const [
        ImageModelOption(
          modelId: 'model',
          displayName: 'model',
          actualModel: 'nai-diffusion-5-full',
          provider: ImageProviderType.novelAi,
          protocol: AppConstants.novelAiImageGenerationsProtocol,
        ),
      ];
      vm.selectedModel = 'model';
      vm.prompt = '2girls';

      final writePrompt = WritePromptTool(vm);
      final firstWrite = await writePrompt.call({
        'target': 'character_1',
        'content': 'blue hair, at the center',
        'mode': 'replace',
        if (!automaticLayout) 'position': {'x': 0.5, 'y': 0.5},
      });
      final secondWrite = await writePrompt.call({
        'target': 'character_2',
        'content': 'red hair, seated on the right',
        'mode': 'replace',
        if (!automaticLayout) 'position': {'x': 0.76, 'y': 0.68},
      });

      expect(firstWrite.success, isTrue);
      expect(secondWrite.success, isTrue);
      expect(firstWrite.text, contains(automaticLayout ? '自动布局' : '0.50'));
      expect(firstWrite.text, isNot(contains('尚未定位')));
      final read = await ReadCurrentPromptsTool(vm).call(const {});
      final readback = jsonDecode(read.followUpHint!) as Map<String, dynamic>;
      final readCharacters = readback['characters'] as List<dynamic>;
      expect(readCharacters[0]['position'],
          automaticLayout ? null : {'x': 0.5, 'y': 0.5});
      expect(readCharacters[1]['position'],
          automaticLayout ? null : {'x': 0.76, 'y': 0.68});

      await vm.generate();

      final task = repository.submitted.single;
      expect(task.useCoords, !automaticLayout);
      expect(task.characters, hasLength(2));
      expect(task.characters![0].centerX, automaticLayout ? null : 0.5);
      expect(task.characters![0].centerY, automaticLayout ? null : 0.5);
      expect(task.characters![1].centerX, automaticLayout ? null : 0.76);
      expect(task.characters![1].centerY, automaticLayout ? null : 0.68);
    });
  }

  test('agent position validation and batch prompt replacement preserve layout',
      () async {
    final history = _MemoryHistoryRepository();
    final queue = GenerationQueue(
      _CapturingGenerationRepository('unused'),
      history,
    );
    addTearDown(queue.dispose);
    final vm = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(vm.dispose);
    await Future<void>.delayed(Duration.zero);
    vm.characters = const [
      CharacterSpec(prompt: 'existing role', centerX: 0.3, centerY: 0.6),
    ];
    final writePrompt = WritePromptTool(vm);
    final versionBeforeInvalidWrite = vm.version;

    final invalidPositionArguments = <Map<String, dynamic>>[
      {
        'target': 'character_1',
        'content': 'changed role',
        'mode': 'replace',
        'position': {'x': 0.5},
      },
      {
        'target': 'character_1',
        'content': 'changed role',
        'mode': 'replace',
        'position': {'x': double.nan, 'y': 0.6},
      },
      {
        'target': 'character_1',
        'content': 'changed role',
        'mode': 'replace',
        'position': {'x': double.infinity, 'y': 0.6},
      },
      {
        'target': 'character_1',
        'content': 'changed role',
        'mode': 'replace',
        'position': {'x': -0.1, 'y': 0.6},
      },
      {
        'target': 'character_1',
        'content': 'changed role',
        'mode': 'replace',
        'position': {'x': 1.1, 'y': 0.6},
      },
      {
        'target': 'positive',
        'content': 'changed main prompt',
        'mode': 'replace',
        'position': {'x': 0.4, 'y': 0.6},
      },
      {
        'target': 'character_1_uc',
        'content': 'bad hands',
        'mode': 'replace',
        'position': {'x': 0.4, 'y': 0.6},
      },
    ];
    for (final arguments in invalidPositionArguments) {
      final currentVersion = vm.version;
      final result = await writePrompt.call(arguments);
      expect(result.success, isFalse);
      expect(vm.version, currentVersion);
      expect(vm.characters, hasLength(1));
      expect(vm.characters.single.prompt, 'existing role');
      expect(vm.characters.single.centerX, 0.3);
      expect(vm.characters.single.centerY, 0.6);
    }
    expect(vm.version, versionBeforeInvalidWrite);
    expect(vm.characters, hasLength(1));
    expect(vm.characters.single.prompt, 'existing role');
    expect(vm.characters.single.centerX, 0.3);
    expect(vm.characters.single.centerY, 0.6);

    final textOnlyEdit = await writePrompt.call({
      'target': 'character_1',
      'content': 'edited role',
      'mode': 'replace',
    });
    expect(textOnlyEdit.success, isTrue);
    expect(vm.characters.single.centerX, 0.3);
    expect(vm.characters.single.centerY, 0.6);

    // Assistant writes also leave new roles unpositioned, without requiring
    // the model to invent coordinates or falling back to an implicit center.
    final automaticRole = await writePrompt.call({
      'target': 'character_2',
      'content': 'new role',
      'mode': 'replace',
    });
    expect(automaticRole.success, isTrue);
    expect(automaticRole.text, contains('自动布局'));
    expect(vm.characters, hasLength(2));
    expect(vm.characters[1].centerX, isNull);
    expect(vm.characters[1].centerY, isNull);

    await vm.replaceAll(characterPrompts: const ['imported role', 'another']);
    expect(vm.characters[0].centerX, 0.3);
    expect(vm.characters[0].centerY, 0.6);
    expect(vm.characters[1].centerX, isNull);
    expect(vm.characters[1].centerY, isNull);

    // Filling an empty, manually positioned card must preserve its layout,
    // including an explicitly selected center.
    for (final position in [(0.3, 0.6), (0.5, 0.5)]) {
      vm.characters = [
        CharacterSpec(
          prompt: '',
          centerX: position.$1,
          centerY: position.$2,
        ),
      ];
      final fillPositionedCard = await writePrompt.call({
        'target': 'character_1',
        'content': 'new role',
        'mode': 'replace',
      });
      expect(fillPositionedCard.success, isTrue);
      expect(vm.characters.single.prompt, 'new role');
      expect(vm.characters.single.centerX, position.$1);
      expect(vm.characters.single.centerY, position.$2);
    }

    // A negative-first role slot uses the same automatic layout default when
    // its positive prompt is filled in later.
    final ucFirstWrite = await writePrompt.call({
      'target': 'character_2_uc',
      'content': 'bad hands',
      'mode': 'replace',
    });
    expect(ucFirstWrite.success, isTrue);
    expect(vm.characters, hasLength(2));
    expect(vm.characters[1].prompt, isEmpty);
    expect(vm.characters[1].uc, 'bad hands');
    final versionBeforeUnpositionedPositive = vm.version;
    final unpositionedPositiveAfterUc = await writePrompt.call({
      'target': 'character_2',
      'content': 'new role',
      'mode': 'replace',
    });
    expect(unpositionedPositiveAfterUc.success, isTrue);
    expect(vm.version, versionBeforeUnpositionedPositive + 1);
    expect(vm.characters, hasLength(2));
    expect(vm.characters[1].prompt, 'new role');
    expect(vm.characters[1].uc, 'bad hands');
    expect(vm.characters[1].centerX, isNull);
    expect(vm.characters[1].centerY, isNull);
  });

  test('batch generation keeps selection on the newest placeholder', () async {
    final image = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'generation_viewmodel_batch.png',
    );
    await image.writeAsBytes(const [1, 2, 3]);
    addTearDown(() => image.deleteSync());

    final history = _MemoryHistoryRepository();
    final queue = GenerationQueue(
      _DelayedGenerationRepository(image.path),
      history,
    );
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    viewModel.prompt = '1girl';
    viewModel.selectedModel = 'model';
    await viewModel.updateBatchCount(3);

    final generateFuture = viewModel.generate();

    // 第 1 张完成后，第 2 张的占位卡应自动成为选中项
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await generateFuture;

    expect(viewModel.sessionResults, hasLength(3));
    expect(
        viewModel.selectedResultTaskId, viewModel.sessionResults.last.taskId);
  });

  test('reselecting the newest placeholder resumes auto-follow mid-batch',
      () async {
    final image = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'generation_viewmodel_reselect.png',
    );
    await image.writeAsBytes(const [1, 2, 3]);
    addTearDown(() => image.deleteSync());

    final history = _MemoryHistoryRepository();
    final queue = GenerationQueue(
      _DelayedGenerationRepository(image.path),
      history,
    );
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    viewModel.prompt = '1girl';
    viewModel.selectedModel = 'model';
    await viewModel.updateBatchCount(4);

    final generateFuture = viewModel.generate();

    // 等到第 2 张完成、第 3 张占位卡选中
    await Future<void>.delayed(const Duration(milliseconds: 420));
    final thirdId = viewModel.sessionResults.last.taskId;
    expect(viewModel.selectedResultTaskId, thirdId);

    // 翻回第 1 张，再转回最后一张（第 3 张，可能仍是占位卡）
    viewModel.selectResult(viewModel.sessionResults.first.taskId);
    viewModel.selectResult(viewModel.sessionResults.last.taskId);

    // 第 3、4 张陆续完成，选中项应继续跟随到最后
    await generateFuture;

    expect(viewModel.sessionResults, hasLength(4));
    expect(viewModel.selectedResultTaskId, viewModel.sessionResults.last.taskId);
  });

  test('imported image displays without submitting a task or replacing drafts',
      () async {
    final history = _MemoryHistoryRepository();
    final repository = _CapturingGenerationRepository('unused');
    final queue = GenerationQueue(repository, history);
    addTearDown(queue.dispose);
    final vm = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(vm.dispose);
    await Future<void>.delayed(Duration.zero);
    vm.prompt = 'unsaved draft';
    vm.seed = 100;
    final image = GenerationTask(
      taskId: 'imported',
      model: 'imported-image',
      prompt: '',
      width: 31,
      height: 17,
      scale: 0,
      cfgRescale: 0,
      sampler: '',
      noiseSchedule: '',
      status: 'success',
      imagePath: 'local.png',
      createdAt: DateTime.now(),
    );
    expect(vm.displayImportedImage(image), isTrue);
    expect(vm.selectedResult, image);
    expect(vm.lastCompletedTask, image);
    expect(vm.prompt, 'unsaved draft');
    expect(vm.seed, 100);
    expect(vm.selectedResult?.seed, isNull);
    expect(repository.submitted, isEmpty);
    vm.queueState =
        const QueueState(isProcessing: true, pendingCount: 0, pendingTasks: []);
    expect(vm.displayImportedImage(image.copyWith(taskId: 'late-import')),
        isFalse);
    expect(vm.selectedResult, image);
  });

  test('generate completes only after successful result is displayable',
      () async {
    final image = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'generation_viewmodel_result.png',
    );
    await image.writeAsBytes(const [1, 2, 3]);
    addTearDown(() => image.deleteSync());

    final history = _MemoryHistoryRepository();
    final queue = GenerationQueue(
      _SuccessfulGenerationRepository(image.path),
      history,
    );
    addTearDown(queue.dispose);
    final saveStarted = Completer<void>();
    final allowSave = Completer<void>();
    final saveImage = _DelayedSaveImageUseCase(
      history,
      saveStarted: saveStarted,
      allowSave: allowSave,
    );
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: saveImage,
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    viewModel.prompt = '1girl';
    viewModel.selectedModel = 'model';

    var generateCompleted = false;
    final generateFuture = viewModel.generate().then((_) {
      generateCompleted = true;
    });

    await saveStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(generateCompleted, isFalse);
    // 新批次开始即清掉上批结果，占位卡入列
    expect(viewModel.sessionResults, hasLength(1));
    expect(viewModel.sessionResults.single.status, 'pending');
    expect(
        viewModel.selectedResultTaskId, viewModel.sessionResults.single.taskId);

    allowSave.complete();
    await generateFuture;

    expect(viewModel.isGenerating, isFalse);
    expect(viewModel.sessionResults, hasLength(1));
    expect(viewModel.sessionResults.single.status, 'success');
    expect(viewModel.lastCompletedTask?.taskId,
        viewModel.sessionResults.single.taskId);
    expect(saveImage.executeCount, 1);
  });

  test('502 failure ends loading even when history update fails', () async {
    final history = _FailingUpdateHistoryRepository();
    final queue = GenerationQueue(_BadGatewayGenerationRepository(), history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    viewModel.prompt = '1girl';
    viewModel.selectedModel = 'model';

    await viewModel.generate().timeout(const Duration(seconds: 2));

    expect(viewModel.isGenerating, isFalse);
    expect(viewModel.errorMessage, contains('All connection attempts failed'));
  });

  test('ikun steps lock forces 28 and unlock restores editing', () async {
    final settings = _SettingsRepository();
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_SuccessfulGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'model',
        displayName: 'model',
        actualModel: 'model',
        provider: ImageProviderType.novelAi,
        protocol: AppConstants.novelAiImageGenerationsProtocol,
      ),
    ];

    await viewModel.updateSteps(40);
    expect(viewModel.steps, 40);
    await viewModel.toggleStepsLock();
    expect(viewModel.isStepsLocked, isTrue);
    expect(viewModel.steps, 28);
    await viewModel.updateSteps(45);
    expect(viewModel.steps, 28);
    await viewModel.toggleStepsLock();
    await viewModel.updateSteps(45);
    expect(viewModel.steps, 45);
    expect(settings.savedStepsLocked, isFalse);
  });

  test('precise reference is replaced, updated, removed and saved', () async {
    final settings = _SettingsRepository();
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_SuccessfulGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'model',
        displayName: 'model',
        actualModel: 'nai-diffusion-4-5-full',
        provider: ImageProviderType.novelAi,
        protocol: AppConstants.novelAiImageGenerationsProtocol,
      ),
    ];

    await viewModel.addPreciseReference('first.png');
    await viewModel.updatePreciseReference(
      0,
      viewModel.preciseReferences.single.copyWith(
        referenceType: 'character',
        strength: 0.8,
      ),
    );
    await viewModel.replacePreciseReference(0, 'second.png');

    final reference = viewModel.preciseReferences.single;
    expect(reference.path, 'second.png');
    expect(reference.referenceType, 'character');
    expect(reference.strength, 0.8);
    expect(settings.savedPreciseReferences, viewModel.preciseReferences);

    await viewModel.removePreciseReference(0);
    expect(viewModel.preciseReferences, isEmpty);
  });

  test('角色精细参考按角色保存且不影响其他角色', () async {
    final settings = _SettingsRepository();
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_SuccessfulGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.characters = const [
      CharacterSpec(prompt: 'first'),
      CharacterSpec(prompt: 'second'),
    ];

    await viewModel.addCharacterReference(0, 'first.png');
    await viewModel.updateCharacterReference(
      0,
      0,
      viewModel.characters.first.referenceImages.single.copyWith(
        strength: 0.7,
        informationExtracted: 0.4,
      ),
    );
    await viewModel.replaceCharacterReference(0, 0, 'replaced.png');

    expect(viewModel.characters[0].referenceImages.single.path, 'replaced.png');
    expect(viewModel.characters[0].referenceImages.single.strength, 0.7);
    expect(
      viewModel.characters[0].referenceImages.single.informationExtracted,
      0.4,
    );
    expect(viewModel.characters[1].referenceImages, isEmpty);
    expect(settings.savedCharacters[0].referenceImages.single.path,
        'replaced.png');

    await viewModel.removeCharacterReference(0, 0);
    expect(viewModel.characters[0].referenceImages, isEmpty);
  });

  test('batch count persists the 1 to 30 range', () async {
    final settings = _SettingsRepository();
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_SuccessfulGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);

    await viewModel.updateBatchCount(31);
    expect(viewModel.batchCount, AppConstants.maxBatchCount);
    expect(settings.savedBatchCount, AppConstants.maxBatchCount);

    await viewModel.updateBatchCount(0);
    expect(viewModel.batchCount, 1);
    expect(settings.savedBatchCount, 1);
  });

  test('switching reference mode clears the other draft and persists choice',
      () async {
    final settings = _SettingsRepository();
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_SuccessfulGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'model',
        displayName: 'model',
        actualModel: 'model',
        provider: ImageProviderType.novelAi,
        protocol: AppConstants.novelAiImageGenerationsProtocol,
      ),
    ];

    await viewModel.setVibeReference('vibe.png');
    await viewModel.switchReferenceMode(ReferenceMode.precise);

    expect(viewModel.referenceMode, ReferenceMode.precise);
    expect(settings.savedReferenceMode, ReferenceMode.precise);
    expect(viewModel.vibeReferences, isEmpty);
    expect(settings.savedVibeReferences, isEmpty);
    expect(viewModel.preciseReferences, isEmpty);
  });

  test('vibe and precise references clear each other', () async {
    final settings = _SettingsRepository();
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_SuccessfulGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'model',
        displayName: 'model',
        actualModel: 'nai-diffusion-4-5-full',
        provider: ImageProviderType.novelAi,
        protocol: AppConstants.novelAiImageGenerationsProtocol,
      ),
    ];

    await viewModel.setVibeReference('vibe.png');
    await viewModel.addPreciseReference('precise.png');
    expect(viewModel.vibeReferences, isEmpty);
    expect(viewModel.referenceMode, ReferenceMode.precise);

    await viewModel.setVibeReference('new-vibe.png');
    expect(viewModel.preciseReferences, isEmpty);
    expect(viewModel.referenceMode, ReferenceMode.vibe);
  });

  test('vibe reference is replaced, updated, removed and saved', () async {
    final settings = _SettingsRepository();
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_SuccessfulGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'model',
        displayName: 'model',
        actualModel: 'model',
        provider: ImageProviderType.novelAi,
        protocol: AppConstants.novelAiImageGenerationsProtocol,
      ),
    ];

    viewModel.setVibeReference('first.png');
    expect(viewModel.vibeReferences, hasLength(1));
    expect(viewModel.vibeReferences.single.path, 'first.png');

    await viewModel.updateVibeReference(
      0,
      viewModel.vibeReferences.single.copyWith(
        strength: 0.8,
        informationExtracted: 0.4,
      ),
    );
    await viewModel.setVibeReference('second.png');

    expect(viewModel.vibeReferences, hasLength(1));
    expect(viewModel.vibeReferences.single.path, 'second.png');
    expect(viewModel.vibeReferences.single.strength, 0.8);
    expect(viewModel.vibeReferences.single.informationExtracted, 0.4);
    expect(settings.savedVibeReferences, viewModel.vibeReferences);

    await viewModel.removeVibeReference();

    expect(viewModel.vibeReferences, isEmpty);
    expect(settings.savedVibeReferences, isEmpty);
  });

  test('Vibe references accept four items and reject a fifth', () async {
    final settings = _SettingsRepository();
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_SuccessfulGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'model',
        displayName: 'model',
        actualModel: 'model',
        provider: ImageProviderType.novelAi,
        protocol: AppConstants.novelAiChatCompletionsProtocol,
      ),
    ];

    final added = await viewModel.addVibeReferences(
      ['one.png', 'two.png', 'three.png', 'four.png', 'five.png'],
    );

    expect(added, AppConstants.maxVibeReferences);
    expect(viewModel.vibeReferences.map((reference) => reference.path), [
      'one.png',
      'two.png',
      'three.png',
      'four.png',
    ]);
    expect(await viewModel.addVibeReferences(['five.png']), 0);
    await viewModel.removeVibeReference(1);
    expect(viewModel.vibeReferences.map((reference) => reference.path), [
      'one.png',
      'three.png',
      'four.png',
    ]);
    expect(settings.savedVibeReferences, viewModel.vibeReferences);
  });

  test('Precise Reference accepts V4 and V4.5 models', () async {
    for (final model in const [
      'nai-v4-curated',
      'nai-diffusion-4-5-full',
    ]) {
      final image = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'precise_model_${model.hashCode}.png',
      );
      await image.writeAsBytes(const [1, 2, 3]);
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });
      final repository = _CapturingGenerationRepository(image.path);
      final history = _MemoryHistoryRepository();
      final queue = GenerationQueue(repository, history);
      addTearDown(queue.dispose);
      final viewModel = _createGenerationViewModel(
        generateImage: GenerateImageUseCase(history),
        manageSettings: ManageSettingsUseCase(_SettingsRepository()),
        saveImage: SaveImageUseCase(history),
        queue: queue,
      );
      addTearDown(viewModel.dispose);
      await Future<void>.delayed(Duration.zero);
      viewModel.imageModelOptions = [
        ImageModelOption(
          modelId: model,
          displayName: model,
          actualModel: model,
          provider: ImageProviderType.novelAi,
          endpointId: 'ikun',
          protocol: AppConstants.novelAiImageGenerationsProtocol,
        ),
      ];
      viewModel.selectedModel = model;
      viewModel.prompt = '1girl';
      await viewModel.addPreciseReference('reference.png');

      await viewModel.generate();

      expect(repository.submitted, hasLength(1));
      expect(repository.submitted.single.preciseReferences, hasLength(1));
      expect(viewModel.errorMessage, isNull);
    }
  });

  test('角色精细参考合并到兼容渠道的精密参考任务', () async {
    final image = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'role_precise_reference.png',
    );
    await image.writeAsBytes(const [1, 2, 3]);
    addTearDown(() async {
      if (await image.exists()) await image.delete();
    });
    final history = _MemoryHistoryRepository();
    final repository = _CapturingGenerationRepository(image.path);
    final queue = GenerationQueue(repository, history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'model',
        displayName: 'model',
        actualModel: 'nai-diffusion-4-5-full',
        provider: ImageProviderType.novelAi,
        protocol: AppConstants.novelAiImageGenerationsProtocol,
      ),
    ];
    viewModel.prompt = '1girl';
    await viewModel.switchReferenceMode(ReferenceMode.precise);
    viewModel.characters = [
      CharacterSpec(
        prompt: 'first',
        referenceImages: [
          CharacterReferenceImage(path: image.path, strength: 0.6),
        ],
      ),
      const CharacterSpec(
        prompt: 'disabled',
        enabled: false,
        referenceImages: [CharacterReferenceImage(path: 'ignored.png')],
      ),
    ];

    await viewModel.generate();

    final task = repository.submitted.single;
    expect(task.characters?.first.referenceImages.single.path, image.path);
    expect(task.preciseReferences, [
      PreciseReferenceImage(
        path: image.path,
        referenceType: 'character',
        strength: 0.6,
      ),
    ]);
  });

  test('Precise Reference is unavailable for unsupported and limit models',
      () async {
    for (final model in const ['nai-v3', 'nai-v4.5-full-limit']) {
      final history = _MemoryHistoryRepository();
      final repository = _CapturingGenerationRepository('unused');
      final queue = GenerationQueue(repository, history);
      addTearDown(queue.dispose);
      final viewModel = _createGenerationViewModel(
        generateImage: GenerateImageUseCase(history),
        manageSettings: ManageSettingsUseCase(_SettingsRepository()),
        saveImage: SaveImageUseCase(history),
        queue: queue,
      );
      addTearDown(viewModel.dispose);
      await Future<void>.delayed(Duration.zero);
      viewModel.imageModelOptions = [
        ImageModelOption(
          modelId: model,
          displayName: model,
          actualModel: model,
          provider: ImageProviderType.novelAi,
          endpointId: 'ikun',
          protocol: AppConstants.novelAiImageGenerationsProtocol,
        ),
      ];
      viewModel.selectedModel = model;
      viewModel.prompt = '1girl';
      await viewModel.addPreciseReference('reference.png');

      await viewModel.generate();

      expect(viewModel.supportsPreciseReferences, isFalse);
      expect(viewModel.preciseReferences, isEmpty);
      expect(repository.submitted, hasLength(1));
      expect(repository.submitted.single.preciseReferences, isEmpty);
    }
  });

  test('7877 仅支持 Vibe，不显示或添加精密参考', () async {
    final settings = _SettingsRepository();
    final history = _MemoryHistoryRepository();
    final repository = _CapturingGenerationRepository('unused');
    final queue = GenerationQueue(repository, history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'model',
        displayName: 'model',
        actualModel: 'model',
        provider: ImageProviderType.novelAi,
        protocol: AppConstants.novelAiChatCompletionsProtocol,
      ),
    ];
    viewModel.selectedModel = 'model';
    viewModel.prompt = '1girl';

    await viewModel.setVibeReference('vibe.png');
    await viewModel.updateVibeReference(
      0,
      viewModel.vibeReferences.single.copyWith(
        strength: 0.8,
        informationExtracted: 0.4,
      ),
    );
    await viewModel.generate();

    expect(viewModel.supportsVibeReferences, isTrue);
    expect(viewModel.supportsPreciseReferences, isFalse);
    expect(settings.savedVibeReferences.single.path, 'vibe.png');
    expect(repository.submitted, hasLength(1));
    expect(repository.submitted.single.vibeReferences, hasLength(1));
    expect(repository.submitted.single.vibeReferences.single.strength, 0.8);
    expect(
      repository.submitted.single.vibeReferences.single.informationExtracted,
      0.4,
    );

    await viewModel.addPreciseReference('precise.png');
    expect(viewModel.vibeReferences, hasLength(1));
    expect(viewModel.preciseReferences, isEmpty);
  });

  test('分块高清重绘使用 0.3 默认强度且保留手动值', () async {
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_SuccessfulGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.img2imgStrength, 0.7);
    viewModel.updateImg2ImgMode(Img2ImgMode.tiled);
    expect(viewModel.img2imgStrength, 0.3);

    viewModel.updateImg2ImgStrength(0.42);
    viewModel.updateImg2ImgMode(Img2ImgMode.normal);
    viewModel.updateImg2ImgMode(Img2ImgMode.tiled);
    expect(viewModel.img2imgStrength, 0.42);

    viewModel.clearImg2ImgData();
    expect(viewModel.img2imgStrength, 0.7);
    viewModel.updateImg2ImgMode(Img2ImgMode.normal);
    viewModel.updateImg2ImgMode(Img2ImgMode.tiled);
    expect(viewModel.img2imgStrength, 0.3);
  });

  test('7877 支持组合图生图与 Vibe 参考', () async {
    final source = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}vibe_img2img.png',
    );
    await source.writeAsBytes(const [1]);
    addTearDown(() async {
      if (await source.exists()) await source.delete();
    });
    final history = _MemoryHistoryRepository();
    final repository = _CapturingGenerationRepository('unused');
    final queue = GenerationQueue(repository, history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'model',
        displayName: 'model',
        actualModel: 'model',
        provider: ImageProviderType.novelAi,
        protocol: AppConstants.novelAiChatCompletionsProtocol,
      ),
    ];
    viewModel.selectedModel = 'model';
    viewModel.prompt = '1girl';
    await viewModel.setVibeReference('vibe.png');
    viewModel.setImg2ImgSourceImagePath(source.path);

    await viewModel.generate();

    expect(repository.submitted, hasLength(1));
    expect(repository.submitted.single.img2imgSourceImagePath, source.path);
    expect(repository.submitted.single.vibeReferences, hasLength(1));
  });

  test('7877 and ikun submit independent img2img state', () async {
    for (final protocol in const [
      AppConstants.novelAiChatCompletionsProtocol,
      AppConstants.novelAiImageGenerationsProtocol,
    ]) {
      final source = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'img2img_${protocol.hashCode}.png',
      );
      await source.writeAsBytes(const [1]);
      addTearDown(() async {
        if (await source.exists()) await source.delete();
      });
      final repository = _CapturingGenerationRepository(source.path);
      final history = _MemoryHistoryRepository();
      final queue = GenerationQueue(repository, history);
      addTearDown(queue.dispose);
      final viewModel = _createGenerationViewModel(
        generateImage: GenerateImageUseCase(history),
        manageSettings: ManageSettingsUseCase(_SettingsRepository()),
        saveImage: SaveImageUseCase(history),
        queue: queue,
      );
      addTearDown(viewModel.dispose);
      await Future<void>.delayed(Duration.zero);
      viewModel.imageModelOptions = [
        ImageModelOption(
          modelId: protocol,
          displayName: protocol,
          actualModel: 'model',
          provider: ImageProviderType.novelAi,
          protocol: protocol,
        ),
      ];
      viewModel.selectedModel = protocol;
      viewModel.prompt = '1girl';
      viewModel.setImg2ImgSourceImagePath(source.path);
      viewModel.updateImg2ImgStrength(0.42);

      await viewModel.generate();

      expect(repository.submitted, hasLength(1));
      expect(repository.submitted.single.img2imgSourceImagePath, source.path);
      expect(repository.submitted.single.img2imgStrength, 0.42);
    }
  });

  test('GPT reference images are batch-added, deduplicated and capped at 16',
      () async {
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_SuccessfulGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.addGptImages(['a.png', 'b.png', 'a.png']), 2);
    expect(viewModel.gptImagePaths, ['a.png', 'b.png']);

    final additional = List.generate(20, (index) => 'image_$index.png');
    expect(viewModel.addGptImages(additional), 14);
    expect(viewModel.gptImagePaths, hasLength(16));
    expect(viewModel.gptImagePaths.toSet(), hasLength(16));
    expect(viewModel.addGptImages(['overflow.png']), 0);
  });

  test('GPT and NanoBanana tasks preserve all selected reference images',
      () async {
    for (final provider in const [
      ImageProviderType.gpt,
      ImageProviderType.nanoBanana,
    ]) {
      final output = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'multi_reference_${provider.name}.png',
      );
      await output.writeAsBytes(const [1]);
      addTearDown(() async {
        if (await output.exists()) await output.delete();
      });
      final history = _MemoryHistoryRepository();
      final repository = _CapturingGenerationRepository(output.path);
      final queue = GenerationQueue(repository, history);
      addTearDown(queue.dispose);
      final viewModel = _createGenerationViewModel(
        generateImage: GenerateImageUseCase(history),
        manageSettings: ManageSettingsUseCase(_SettingsRepository()),
        saveImage: SaveImageUseCase(history),
        queue: queue,
      );
      addTearDown(viewModel.dispose);
      await Future<void>.delayed(Duration.zero);
      viewModel.imageModelOptions = [
        ImageModelOption(
          modelId: provider.name,
          displayName: provider.name,
          actualModel: 'model',
          provider: provider,
        ),
      ];
      viewModel.selectedModel = provider.name;
      viewModel.prompt = 'edit these images';
      viewModel.addGptImages(['first.png', 'second.png', 'third.png']);

      await viewModel.generate();

      expect(repository.submitted, hasLength(1));
      expect(
        repository.submitted.single.gptImagePaths,
        ['first.png', 'second.png', 'third.png'],
      );
    }
  });

  test('loadFromHistory restores Precise Reference and clears Vibe', () async {
    final settings = _SettingsRepository();
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_SuccessfulGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'nai-v4-curated',
        displayName: 'V4',
        actualModel: 'nai-v4-curated',
        provider: ImageProviderType.novelAi,
        protocol: AppConstants.novelAiImageGenerationsProtocol,
      ),
    ];
    await viewModel.setVibeReference('vibe.png');
    final task = GenerationTask(
      taskId: 'history-task',
      model: 'nai-v4-curated',
      protocol: AppConstants.novelAiImageGenerationsProtocol,
      prompt: 'history prompt',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0,
      sampler: 'k_euler',
      noiseSchedule: 'native',
      preciseReferences: const [
        PreciseReferenceImage(path: 'history-reference.png'),
      ],
      status: 'success',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    await viewModel.loadFromHistory(task);

    expect(viewModel.preciseReferences, task.preciseReferences);
    expect(viewModel.vibeReferences, isEmpty);
    expect(viewModel.referenceMode, ReferenceMode.precise);
    expect(settings.savedReferenceMode, ReferenceMode.precise);
    expect(settings.savedPreciseReferences, task.preciseReferences);
    expect(settings.savedVibeReferences, isEmpty);
  });

  test('loadFromHistory restores ikun inpainting source mask and strength',
      () async {
    final settings = _SettingsRepository();
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_SuccessfulGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'nai:ikun:nai-v4.5-full',
        displayName: 'ikun V4.5',
        actualModel: 'nai-v4.5-full',
        provider: ImageProviderType.novelAi,
        endpointId: 'ikun',
        protocol: AppConstants.novelAiImageGenerationsProtocol,
      ),
    ];
    final task = GenerationTask(
      taskId: 'history-inpaint',
      model: 'nai-v4.5-full',
      endpointId: 'ikun',
      protocol: AppConstants.novelAiImageGenerationsProtocol,
      prompt: 'replace sky',
      negativePrompt: 'cloudy',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0,
      sampler: 'k_euler',
      noiseSchedule: 'karras',
      mode: GenerationMode.inpainting,
      sourceImagePath: 'source.png',
      maskImagePath: 'mask.png',
      inpaintStrength: 0.78,
      status: 'success',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    await viewModel.loadFromHistory(task);

    expect(viewModel.generationMode, GenerationMode.inpainting);
    expect(viewModel.inpaintPrompt, 'replace sky');
    expect(viewModel.inpaintNegativePrompt, 'cloudy');
    expect(viewModel.sourceImagePath, 'source.png');
    expect(viewModel.maskImagePath, 'mask.png');
    expect(viewModel.inpaintStrength, 0.78);
    expect(viewModel.img2imgSourceImagePath, isNull);
  });

  test('loadFromHistory restores ikun img2img source and strength', () async {
    final settings = _SettingsRepository();
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_SuccessfulGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'nai:ikun:nai-v4.5-full',
        displayName: 'ikun V4.5',
        actualModel: 'nai-v4.5-full',
        provider: ImageProviderType.novelAi,
        endpointId: 'ikun',
        protocol: AppConstants.novelAiImageGenerationsProtocol,
      ),
    ];
    final task = GenerationTask(
      taskId: 'history-img2img',
      model: 'nai-v4.5-full',
      endpointId: 'ikun',
      protocol: AppConstants.novelAiImageGenerationsProtocol,
      prompt: 'watercolor',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0,
      sampler: 'k_euler',
      noiseSchedule: 'karras',
      img2imgSourceImagePath: 'img2img.png',
      img2imgStrength: 0.42,
      status: 'success',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    await viewModel.loadFromHistory(task);

    expect(viewModel.generationMode, GenerationMode.textToImage);
    expect(viewModel.prompt, 'watercolor');
    expect(viewModel.img2imgSourceImagePath, 'img2img.png');
    expect(viewModel.img2imgStrength, 0.42);
    expect(viewModel.sourceImagePath, isNull);
    expect(viewModel.maskImagePath, isNull);
  });

  const effortChannels = <({String name, String endpointId, String protocol})>[
    (
      name: 'official',
      endpointId: AppConstants.novelAiOfficialEndpointId,
      protocol: AppConstants.novelAiOfficialProtocol,
    ),
    (
      name: 'ikun',
      endpointId: AppConstants.novelAiImageGenerationsEndpointId,
      protocol: AppConstants.novelAiImageGenerationsProtocol,
    ),
    (
      name: '7877',
      endpointId: AppConstants.novelAiChatCompletionsEndpointId,
      protocol: AppConstants.novelAiChatCompletionsProtocol,
    ),
  ];
  const canonicalEffortModels = <({
    String name,
    String highModel,
    String mediumModel,
    GenerationMode mode,
  })>[
    (
      name: 'full',
      highModel: 'nai-diffusion-5-full',
      mediumModel: 'nai-diffusion-5-full-medium',
      mode: GenerationMode.textToImage,
    ),
    (
      name: 'inpainting',
      highModel: 'nai-diffusion-5-full-inpainting',
      mediumModel: 'nai-diffusion-5-full-medium-inpainting',
      mode: GenerationMode.inpainting,
    ),
  ];
  for (final channel in effortChannels) {
    for (final model in canonicalEffortModels) {
      test(
        '${channel.name} V5 Full ${model.name} submits Medium constraints and returns to High',
        () => _expectEffortSubmissionCycle(
          endpointId: channel.endpointId,
          protocol: channel.protocol,
          actualModel: model.highModel,
          expectedHighModel: model.highModel,
          expectedMediumModel: model.mediumModel,
          mode: model.mode,
        ),
      );
    }
  }

  const gatewayAliasEffortModels = <({
    String name,
    String aliasHighModel,
    String aliasMediumModel,
    GenerationMode mode,
  })>[
    (
      name: 'full',
      aliasHighModel: 'nai-v5-full',
      aliasMediumModel: 'nai-v5-full-medium',
      mode: GenerationMode.textToImage,
    ),
    (
      name: 'inpainting',
      aliasHighModel: 'nai-v5-inpaint',
      aliasMediumModel: 'nai-v5-inpaint-medium',
      mode: GenerationMode.inpainting,
    ),
  ];
  for (final channel in effortChannels.skip(1)) {
    for (final model in gatewayAliasEffortModels) {
      test(
        '${channel.name} ${model.name} Effort preserves its model naming contract',
        () => _expectEffortSubmissionCycle(
          endpointId: channel.endpointId,
          protocol: channel.protocol,
          actualModel: model.aliasHighModel,
          expectedHighModel: model.aliasHighModel,
          expectedMediumModel: model.aliasMediumModel,
          mode: model.mode,
        ),
      );
    }
  }

  test(
      '7877 V5 limit High model round-trips through regular Medium model',
      () => _expectEffortSubmissionCycle(
            endpointId: AppConstants.novelAiChatCompletionsEndpointId,
            protocol: AppConstants.novelAiChatCompletionsProtocol,
            actualModel: 'nai-v5-full-limit',
            expectedHighModel: 'nai-v5-full-limit',
            expectedMediumModel: 'nai-v5-full-medium',
            mode: GenerationMode.textToImage,
          ));

  test('selecting a Medium model sets Effort and refresh keeps High override',
      () async {
    final settings = _SettingsRepository()
      ..novelAiEndpoints = const [
        ApiEndpoint(
          id: AppConstants.novelAiChatCompletionsEndpointId,
          name: '7877',
          baseUrl: 'https://7877.example',
          apiKey: 'key',
          models: [
            'nai-diffusion-5-full',
            'nai-diffusion-5-full-medium',
          ],
          protocol: AppConstants.novelAiChatCompletionsProtocol,
        ),
      ];
    final history = _MemoryHistoryRepository();
    final repository = _CapturingGenerationRepository('unused');
    final queue = GenerationQueue(repository, history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    await viewModel.loadModels();
    await viewModel.updateSelectedModel('nai:7877:nai-diffusion-5-full');
    viewModel.prompt = 'a quiet forest';
    viewModel.steps = 23;
    viewModel.selectedSampler = 'k_dpmpp_2m';
    viewModel.cfgRescale = 0.35;

    const mediumModelId = 'nai:7877:nai-diffusion-5-full-medium';
    await viewModel.updateSelectedModel(mediumModelId);
    expect(viewModel.supportsEffortToggle, isTrue);
    expect(viewModel.effort, GenerationEffort.medium);
    await viewModel.generate();
    expect(repository.submitted.single.model, 'nai-diffusion-5-full-medium');
    expect(repository.submitted.single.steps, 14);

    await viewModel.updateEffort(GenerationEffort.high);
    expect(viewModel.effort, GenerationEffort.high);
    await viewModel.loadModels();
    expect(viewModel.selectedModel, mediumModelId);
    expect(viewModel.effort, GenerationEffort.high);
    await viewModel.generate();

    expect(repository.submitted, hasLength(2));
    expect(repository.submitted.last.model, 'nai-diffusion-5-full');
    expect(repository.submitted.last.steps, 23);
    expect(repository.submitted.last.sampler, 'k_dpmpp_2m');
    expect(repository.submitted.last.cfgRescale, 0.35);

    await viewModel.updateSelectedModel(mediumModelId);
    expect(viewModel.steps, 14);
    await viewModel.updateSelectedModel('nai:7877:nai-diffusion-5-full');
    expect(viewModel.effort, GenerationEffort.high);
    expect(viewModel.steps, 23);
    expect(viewModel.selectedSampler, 'k_dpmpp_2m');
    expect(viewModel.cfgRescale, 0.35);
  });

  test('V5 Medium drops third-party negative inputs without erasing drafts',
      () async {
    final history = _MemoryHistoryRepository();
    final repository = _CapturingGenerationRepository('unused');
    final queue = GenerationQueue(repository, history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'nai:ikun:nai-diffusion-5-full',
        displayName: 'ikun V5 Full',
        actualModel: 'nai-diffusion-5-full',
        provider: ImageProviderType.novelAi,
        endpointId: AppConstants.novelAiImageGenerationsEndpointId,
        protocol: AppConstants.novelAiImageGenerationsProtocol,
      ),
    ];
    viewModel.selectedModel = 'nai:ikun:nai-diffusion-5-full';
    viewModel.prompt = 'a quiet forest';
    viewModel.negativePrompt = 'low quality';
    viewModel.characters = const [
      CharacterSpec(prompt: '1girl', uc: 'bad hands'),
    ];
    viewModel.referenceMode = ReferenceMode.vibe;
    viewModel.vibeReferences = const [
      CharacterReferenceImage(path: 'vibe-reference.png'),
    ];

    expect(viewModel.supportsEffortToggle, isTrue);
    await viewModel.updateEffort(GenerationEffort.medium);
    await viewModel.generate();

    final mediumTask = repository.submitted.single;
    expect(mediumTask.model, 'nai-diffusion-5-full-medium');
    expect(mediumTask.negativePrompt, isNull);
    expect(mediumTask.vibeReferences, isEmpty);
    expect(mediumTask.characters!.single.uc, isNull);
    expect(viewModel.negativePrompt, 'low quality');
    expect(viewModel.vibeReferences, hasLength(1));
    expect(viewModel.characters.single.uc, 'bad hands');

    expect(viewModel.supportsVibeReferences, isFalse);
    expect(viewModel.supportsPreciseReferences, isFalse);
    final referenceDirectory =
        await Directory.systemTemp.createTemp('vm_effort_reference_');
    addTearDown(() => referenceDirectory.delete(recursive: true));
    final preciseReference = await _writeTestPng(
      referenceDirectory,
      'precise-reference.png',
      1,
      1,
    );
    viewModel.referenceMode = ReferenceMode.precise;
    viewModel.preciseReferences = [
      PreciseReferenceImage(path: preciseReference.path),
    ];
    await viewModel.generate();
    expect(repository.submitted, hasLength(2));
    expect(repository.submitted.last.preciseReferences, isEmpty);

    await viewModel.updateEffort(GenerationEffort.high);
    await viewModel.generate();

    final highTask = repository.submitted.last;
    expect(highTask.model, 'nai-diffusion-5-full');
    expect(highTask.negativePrompt, 'low quality');
    expect(viewModel.supportsVibeReferences, isTrue);
    expect(viewModel.supportsPreciseReferences, isTrue);
    expect(highTask.preciseReferences, hasLength(1));
    expect(highTask.characters!.single.uc, 'bad hands');
  });

  test('V5 Medium History restores its matching channel model and regenerates',
      () async {
    final history = _MemoryHistoryRepository();
    final repository = _CapturingGenerationRepository('unused');
    final queue = GenerationQueue(repository, history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'nai:7877:nai-diffusion-5-full',
        displayName: '7877 V5 Full',
        actualModel: 'nai-diffusion-5-full',
        provider: ImageProviderType.novelAi,
        endpointId: AppConstants.novelAiChatCompletionsEndpointId,
        protocol: AppConstants.novelAiChatCompletionsProtocol,
      ),
    ];
    final mediumHistoryTask = GenerationTask(
      taskId: 'history-v5-medium',
      model: 'nai-diffusion-5-full-medium',
      endpointId: AppConstants.novelAiChatCompletionsEndpointId,
      protocol: AppConstants.novelAiChatCompletionsProtocol,
      prompt: 'history prompt',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0,
      sampler: 'k_euler_ancestral',
      noiseSchedule: 'native',
      steps: 14,
      status: 'success',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    await viewModel.loadFromHistory(mediumHistoryTask);

    expect(viewModel.selectedModel, 'nai:7877:nai-diffusion-5-full-medium');
    expect(viewModel.supportsEffortToggle, isTrue);
    expect(viewModel.effort, GenerationEffort.medium);
    expect(viewModel.isMediumEffort, isTrue);
    await viewModel.generate();

    final regenerated = repository.submitted.single;
    expect(regenerated.model, 'nai-diffusion-5-full-medium');
    expect(regenerated.steps, 14);
    expect(regenerated.sampler, 'k_euler_ancestral');
    expect(regenerated.cfgRescale, 0);
    await viewModel.updateEffort(GenerationEffort.high);
    expect(viewModel.steps, 28);

    // The same model on another channel must not take over a history task.
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'nai:ikun:nai-diffusion-5-full',
        displayName: 'ikun V5 Full',
        actualModel: 'nai-diffusion-5-full',
        provider: ImageProviderType.novelAi,
        endpointId: AppConstants.novelAiImageGenerationsEndpointId,
        protocol: AppConstants.novelAiImageGenerationsProtocol,
      ),
    ];
    await viewModel.loadFromHistory(mediumHistoryTask);
    expect(viewModel.selectedModel, 'nai:7877:nai-diffusion-5-full-medium');
    await viewModel.generate();
    expect(repository.submitted.last.endpointId,
        AppConstants.novelAiChatCompletionsEndpointId);
    expect(repository.submitted.last.model, 'nai-diffusion-5-full-medium');
  });

  test('Effort stays unavailable for older, curated, GPT and Nano models',
      () async {
    final unsupportedOptions = [
      for (final channel in effortChannels)
        for (final model in const [
          'nai-diffusion-4-5-full',
          'nai-diffusion-5-curated',
        ])
          (
            name: '${channel.name} $model',
            option: _novelAiEffortOption(channel, model),
          ),
      (
        name: 'GPT',
        option: const ImageModelOption(
          modelId: 'gpt:gpt-image-1',
          displayName: 'GPT Image',
          actualModel: 'gpt-image-1',
          provider: ImageProviderType.gpt,
        ),
      ),
      (
        name: 'Nano',
        option: const ImageModelOption(
          modelId: 'nano:gemini-2.5-flash-image',
          displayName: 'Nano Banana',
          actualModel: 'gemini-2.5-flash-image',
          provider: ImageProviderType.nanoBanana,
        ),
      ),
    ];
    final history = _MemoryHistoryRepository();
    final queue = GenerationQueue(
      _SuccessfulGenerationRepository('unused'),
      history,
    );
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);

    for (final candidate in unsupportedOptions) {
      viewModel.imageModelOptions = [candidate.option];
      viewModel.selectedModel = candidate.option.modelId;

      expect(viewModel.supportsEffortToggle, isFalse, reason: candidate.name);
      await viewModel.updateEffort(GenerationEffort.medium);
      expect(viewModel.isMediumEffort, isFalse, reason: candidate.name);
      expect(viewModel.steps, 28, reason: candidate.name);
      expect(viewModel.selectedSampler, 'k_euler', reason: candidate.name);
    }
  });

  test('7877 V5 禁用 Vibe 并限制步数画幅，但保留角色提示词', () async {
    final settings = _SettingsRepository();
    final history = _MemoryHistoryRepository();
    final queue = GenerationQueue(
      _SuccessfulGenerationRepository('unused'),
      history,
    );
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'nai:7877:nai-diffusion-5-full',
        displayName: '7877 V5 Full',
        actualModel: 'nai-diffusion-5-full',
        provider: ImageProviderType.novelAi,
        endpointId: '7877',
        protocol: AppConstants.novelAiChatCompletionsProtocol,
      ),
    ];
    viewModel.selectedModel = 'nai:7877:nai-diffusion-5-full';
    expect(viewModel.supportsVibeReferences, isFalse);
    expect(viewModel.supportsCharacterPrompts, isTrue);
    await viewModel.updateSteps(50);
    expect(viewModel.steps, 28);
    expect(viewModel.availableResolutions, contains('1024x1024'));
    expect(viewModel.availableResolutions, contains('832x1216'));
    expect(viewModel.availableResolutions, isNot(contains('1024x1536')));
  });

  test('loadModels restores active ikun model over stale 7877 selection',
      () async {
    final settings = _SettingsRepository()
      ..activeNovelAiEndpointId = 'ikun'
      ..activeNovelAiModel = 'ikun-custom-model'
      ..novelAiEndpoints = const [
        ApiEndpoint(
          id: '7877',
          name: '7877',
          baseUrl: 'https://7877.example',
          apiKey: 'key',
          models: ['nai-diffusion-4-5-full'],
          protocol: AppConstants.novelAiChatCompletionsProtocol,
        ),
        ApiEndpoint(
          id: 'ikun',
          name: 'ikun',
          baseUrl: 'https://ikun.example',
          apiKey: 'key',
          models: ['ikun-custom-model'],
          protocol: AppConstants.novelAiImageGenerationsProtocol,
        ),
      ];
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_SuccessfulGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.selectedModel = 'stale-model';
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'nai:7877:nai-diffusion-4-5-full',
        displayName: '7877 model',
        actualModel: 'nai-diffusion-4-5-full',
        provider: ImageProviderType.novelAi,
        endpointId: '7877',
        protocol: AppConstants.novelAiChatCompletionsProtocol,
      ),
      ImageModelOption(
        modelId: 'nai:ikun:ikun-custom-model',
        displayName: 'ikun model',
        actualModel: 'ikun-custom-model',
        provider: ImageProviderType.novelAi,
        endpointId: 'ikun',
        protocol: AppConstants.novelAiImageGenerationsProtocol,
      ),
    ];

    await viewModel.loadModels();

    expect(viewModel.selectedModel, 'nai:ikun:ikun-custom-model');
    expect(viewModel.isIkunEndpoint, isTrue);
  });

  test('loadFromHistory keeps iku endpoint for matching model names', () async {
    final settings = _SettingsRepository();
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_SuccessfulGenerationRepository('unused'), history);
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(settings),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'nai:7877:nai-v4.5-full',
        displayName: '7877 V4.5',
        actualModel: 'nai-v4.5-full',
        provider: ImageProviderType.novelAi,
        endpointId: '7877',
        protocol: AppConstants.novelAiChatCompletionsProtocol,
      ),
      ImageModelOption(
        modelId: 'nai:ikun:nai-v4.5-full',
        displayName: 'ikun V4.5',
        actualModel: 'nai-v4.5-full',
        provider: ImageProviderType.novelAi,
        endpointId: 'ikun',
        protocol: AppConstants.novelAiImageGenerationsProtocol,
      ),
    ];
    final task = GenerationTask(
      taskId: 'history-ikun',
      model: 'nai-v4.5-full',
      endpointId: 'ikun',
      protocol: AppConstants.novelAiImageGenerationsProtocol,
      prompt: 'history prompt',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0,
      sampler: 'k_euler',
      noiseSchedule: 'native',
      preciseReferences: const [
        PreciseReferenceImage(path: 'history-reference.png'),
      ],
      status: 'success',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    await viewModel.loadFromHistory(task);

    expect(viewModel.selectedModel, 'nai:ikun:nai-v4.5-full');
    expect(viewModel.isIkunEndpoint, isTrue);
    expect(viewModel.supportsPreciseReferences, isTrue);
    expect(viewModel.preciseReferences, task.preciseReferences);
  });

  test('official upscale records dimensions from the returned PNG', () async {
    final directory = await Directory.systemTemp.createTemp('vm_upscale_');
    addTearDown(() => directory.delete(recursive: true));
    final source = await _writeTestPng(directory, 'source.png', 3, 4);
    final output = await _writeTestPng(directory, 'upscaled.png', 12, 16);
    final api = _TestOfficialNovelAiApiService(
      upscaleOutputPath: output.path,
    );
    final history = _MemoryHistoryRepository();
    final queue = GenerationQueue(
      _SuccessfulGenerationRepository(source.path),
      history,
    );
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
      officialApi: api,
      officialTokenStore: _TestOfficialNovelAiTokenStore('test-token'),
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    final sourceTask = _successfulImageTask(
      taskId: 'source-upscale',
      imagePath: source.path,
      width: 3,
      height: 4,
    );
    viewModel.sessionResults = [sourceTask];
    viewModel.selectedResultTaskId = sourceTask.taskId;

    expect(await viewModel.upscaleWithOfficial(4), isTrue);

    final result = viewModel.selectedResult!;
    expect(api.upscaleRequests.single, (
      imagePath: source.path,
      token: 'test-token',
      scale: 4,
    ));
    expect(result.imagePath, output.path);
    expect(result.width, 12);
    expect(result.height, 16);
    expect(result.size, '12x16');
  });

  test('official enhance uses source settings and preserves the current draft',
      () async {
    final directory = await Directory.systemTemp.createTemp('vm_enhance_');
    addTearDown(() => directory.delete(recursive: true));
    final source = await _writeTestPng(directory, 'source.png', 5, 7);
    final output = await _writeTestPng(directory, 'enhanced.png', 17, 9);
    final api = _TestOfficialNovelAiApiService(
      enhanceOutputPath: output.path,
    );
    final history = _MemoryHistoryRepository();
    final queue = GenerationQueue(
      _SuccessfulGenerationRepository(source.path),
      history,
    );
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
      officialApi: api,
      officialTokenStore: _TestOfficialNovelAiTokenStore('test-token'),
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    final sourceTask = _successfulImageTask(
      taskId: 'official-source',
      imagePath: source.path,
      width: 5,
      height: 7,
      model: 'nai-diffusion-5-curated',
      steps: 21,
      scale: 7.25,
      prompt: 'source prompt',
      negativePrompt: 'source negative',
    );
    viewModel.sessionResults = [sourceTask];
    viewModel.selectedResultTaskId = sourceTask.taskId;
    viewModel.imageModelOptions = const [
      ImageModelOption(
        modelId: 'gpt:gpt-image-1',
        displayName: 'GPT Image',
        actualModel: 'gpt-image-1',
        provider: ImageProviderType.gpt,
      ),
    ];
    viewModel.selectedModel = 'gpt:gpt-image-1';
    viewModel.selectedResolution = '1024x1024';
    viewModel.steps = 8;
    viewModel.scale = 4.5;
    viewModel.prompt = 'draft prompt';
    viewModel.negativePrompt = 'draft negative';

    expect(
      await viewModel.enhanceWithOfficial(scale: 1.5, strength: 0.42),
      isTrue,
    );

    final request = api.enhanceRequests.single;
    expect(request.imagePath, source.path);
    expect(request.token, 'test-token');
    expect(request.model, 'nai-diffusion-5-curated');
    expect(request.steps, 21);
    expect(request.prompt, 'source prompt');
    expect(request.scale, 1.5);
    expect(request.scaleValue, 7.25);
    expect(viewModel.selectedModel, 'gpt:gpt-image-1');
    expect(viewModel.selectedResolution, '1024x1024');
    expect(viewModel.steps, 8);
    expect(viewModel.scale, 4.5);
    expect(viewModel.prompt, 'draft prompt');
    expect(viewModel.negativePrompt, 'draft negative');

    final result = viewModel.selectedResult!;
    expect(result.imagePath, output.path);
    expect(result.width, 17);
    expect(result.height, 9);
    expect(result.size, '17x9');
  });

  test(
      'plain imported image Enhance uses active model without invented source settings',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('vm_import_enhance_');
    addTearDown(() => directory.delete(recursive: true));
    final source = await _writeTestPng(directory, 'source.png', 5, 7);
    final output = await _writeTestPng(directory, 'enhanced.png', 17, 9);
    final api = _TestOfficialNovelAiApiService(enhanceOutputPath: output.path);
    final history = _MemoryHistoryRepository();
    final queue =
        GenerationQueue(_SuccessfulGenerationRepository(source.path), history);
    addTearDown(queue.dispose);
    final vm = _createGenerationViewModel(
        generateImage: GenerateImageUseCase(history),
        manageSettings: ManageSettingsUseCase(_SettingsRepository()),
        saveImage: SaveImageUseCase(history),
        queue: queue,
        officialApi: api,
        officialTokenStore: _TestOfficialNovelAiTokenStore('test-token'));
    addTearDown(vm.dispose);
    await Future<void>.delayed(Duration.zero);
    vm.selectedModel = 'nai-diffusion-5';
    vm.steps = 28;
    vm.scale = 5;
    vm.prompt = 'current prompt';
    vm.displayImportedImage(await WorkspaceImageImporter.read(source.path));
    expect(await vm.enhanceWithOfficial(scale: 1.5, strength: .3), isTrue);
    expect(api.enhanceRequests.single.model, 'nai-diffusion-5');
    expect(api.enhanceRequests.single.steps, 28);
    expect(api.enhanceRequests.single.scaleValue, 5);
    expect(vm.selectedResult!.steps, 28);
    expect(vm.selectedResult!.scale, 5);
    expect(vm.selectedModel, 'nai-diffusion-5');
    expect(vm.prompt, 'current prompt');
  });

  test('inpaint handler completion resets cancellation for the next run',
      () async {
    final history = _MemoryHistoryRepository();
    final queue = GenerationQueue(
      _SuccessfulGenerationRepository('unused'),
      history,
    );
    addTearDown(queue.dispose);
    final viewModel = _createGenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    await Future<void>.delayed(Duration.zero);
    final handlerStarted = Completer<void>();
    final finishFirstHandler = Completer<void>();
    var firstHandlerEntered = false;
    var generatedRuns = 0;
    viewModel.generationMode = GenerationMode.inpainting;
    viewModel.inpaintWorkspaceHandler = () async {
      if (!firstHandlerEntered) {
        firstHandlerEntered = true;
        handlerStarted.complete();
        await finishFirstHandler.future;
        generatedRuns++;
        return true;
      }
      if (viewModel.isBatchCancelling) return false;
      generatedRuns++;
      return true;
    };

    final firstRun = viewModel.generate();
    await handlerStarted.future;
    viewModel.cancelBatch();
    expect(viewModel.isBatchCancelling, isTrue);
    finishFirstHandler.complete();
    await firstRun;

    expect(viewModel.isGenerating, isFalse);
    expect(viewModel.isBatchCancelling, isFalse);
    expect(generatedRuns, 1);
    await viewModel.generate();
    expect(generatedRuns, 2);
  });
}

ImageModelOption _novelAiEffortOption(
  ({String name, String endpointId, String protocol}) channel,
  String model,
) =>
    ImageModelOption(
      modelId: 'nai:${channel.endpointId}:$model',
      displayName: model,
      actualModel: model,
      provider: ImageProviderType.novelAi,
      endpointId: channel.endpointId,
      protocol: channel.protocol,
    );

Future<void> _expectEffortSubmissionCycle({
  required String endpointId,
  required String protocol,
  required String actualModel,
  required String expectedHighModel,
  required String expectedMediumModel,
  required GenerationMode mode,
}) async {
  final history = _MemoryHistoryRepository();
  final repository = _CapturingGenerationRepository('unused');
  final queue = GenerationQueue(repository, history);
  addTearDown(queue.dispose);
  final viewModel = _createGenerationViewModel(
    generateImage: GenerateImageUseCase(history),
    manageSettings: ManageSettingsUseCase(_SettingsRepository()),
    saveImage: SaveImageUseCase(history),
    queue: queue,
  );
  addTearDown(viewModel.dispose);
  await Future<void>.delayed(Duration.zero);

  final modelId = 'nai:$endpointId:$actualModel';
  viewModel.imageModelOptions = [
    ImageModelOption(
      modelId: modelId,
      displayName: actualModel,
      actualModel: actualModel,
      provider: ImageProviderType.novelAi,
      endpointId: endpointId,
      protocol: protocol,
    ),
  ];
  viewModel.selectedModel = modelId;
  viewModel.generationMode = mode;
  if (mode == GenerationMode.textToImage) {
    viewModel.prompt = 'a quiet forest';
    viewModel.negativePrompt = 'low quality';
    viewModel.characters = [
      CharacterSpec(
        prompt: '1girl',
        uc: 'bad hands',
        centerX: 0.5,
        centerY: 0.5,
        referenceImages:
            endpointId == AppConstants.novelAiImageGenerationsEndpointId
                ? const [CharacterReferenceImage(path: 'role-reference.png')]
                : const [],
      ),
    ];
    if (endpointId == AppConstants.novelAiImageGenerationsEndpointId) {
      viewModel.referenceMode = ReferenceMode.vibe;
      viewModel.vibeReferences = const [
        CharacterReferenceImage(path: 'vibe-reference.png'),
      ];
    }
  } else {
    viewModel.inpaintPrompt = 'repair the cloudy sky';
    viewModel.inpaintNegativePrompt = 'low quality';
    viewModel.inpaintCharacters = const [
      CharacterSpec(prompt: 'blue hair', uc: 'hat'),
    ];
  }
  viewModel.steps = 23;
  viewModel.selectedSampler = 'k_euler';
  viewModel.cfgRescale = 0.35;

  expect(viewModel.supportsEffortToggle, isTrue);
  await viewModel.updateEffort(GenerationEffort.medium);
  await _submitEffortTestTask(viewModel, queue, mode);

  final mediumTask = repository.submitted.single;
  expect(mediumTask.model, expectedMediumModel);
  expect(mediumTask.steps, 14);
  expect(mediumTask.sampler, 'k_euler_ancestral');
  expect(mediumTask.cfgRescale, 0);
  expect(mediumTask.mode, mode);
  final isThirdParty = endpointId != AppConstants.novelAiOfficialEndpointId;
  if (mode == GenerationMode.textToImage) {
    expect(mediumTask.negativePrompt, isThirdParty ? isNull : 'low quality');
    expect(mediumTask.characters, hasLength(1));
    expect(mediumTask.characters!.single.prompt, '1girl');
    expect(
        mediumTask.characters!.single.uc, isThirdParty ? isNull : 'bad hands');
    if (endpointId == AppConstants.novelAiImageGenerationsEndpointId) {
      expect(mediumTask.characters!.single.referenceImages, isEmpty);
      expect(viewModel.characters.single.referenceImages, hasLength(1));
    }
    if (endpointId == AppConstants.novelAiImageGenerationsEndpointId) {
      expect(mediumTask.vibeReferences, isEmpty);
      expect(viewModel.vibeReferences, hasLength(1));
    }
  } else {
    expect(mediumTask.sourceImagePath, 'source.png');
    expect(mediumTask.maskImagePath, 'mask.png');
    expect(mediumTask.negativePrompt, isThirdParty ? isNull : 'low quality');
    expect(mediumTask.characters!.single.prompt, 'blue hair');
    expect(mediumTask.characters!.single.uc, isThirdParty ? isNull : 'hat');
    expect(mediumTask.useCoords, isFalse);
    expect(viewModel.inpaintCharacters.single.uc, 'hat');
  }

  await viewModel.updateEffort(GenerationEffort.high);
  await _submitEffortTestTask(viewModel, queue, mode);

  expect(repository.submitted, hasLength(2));
  final highTask = repository.submitted.last;
  expect(highTask.model, expectedHighModel);
  expect(highTask.steps, 23);
  expect(highTask.sampler, 'k_euler');
  expect(highTask.cfgRescale, 0.35);
  if (mode == GenerationMode.textToImage) {
    expect(highTask.negativePrompt, 'low quality');
    expect(highTask.characters!.single.uc, 'bad hands');
    if (endpointId == AppConstants.novelAiImageGenerationsEndpointId) {
      expect(highTask.characters!.single.referenceImages, hasLength(1));
    }
    if (endpointId == AppConstants.novelAiImageGenerationsEndpointId) {
      expect(highTask.vibeReferences, hasLength(1));
    }
  } else {
    expect(highTask.sourceImagePath, 'source.png');
    expect(highTask.maskImagePath, 'mask.png');
    expect(highTask.characters!.single.uc, 'hat');
    expect(highTask.useCoords, isFalse);
    expect(highTask.negativePrompt, 'low quality');
  }
}

Future<void> _submitEffortTestTask(
  GenerationViewModel viewModel,
  GenerationQueue queue,
  GenerationMode mode,
) async {
  if (mode == GenerationMode.textToImage) {
    await viewModel.generate();
    return;
  }
  final task = viewModel.buildInpaintTask(
    sourcePath: 'source.png',
    maskPath: 'mask.png',
    prompt: viewModel.inpaintPrompt,
    negativePrompt: viewModel.inpaintNegativePrompt,
    strength: 0.72,
    disabledOriginalImage: false,
    colorCorrect: true,
  );
  await queue.enqueueTransientAndWait(task);
}

GenerationViewModel _createGenerationViewModel({
  required GenerateImageUseCase generateImage,
  required ManageSettingsUseCase manageSettings,
  required SaveImageUseCase saveImage,
  required GenerationQueue queue,
  OfficialNovelAiApiService? officialApi,
  OfficialNovelAiTokenStore? officialTokenStore,
}) =>
    GenerationViewModel(
      generateImage: generateImage,
      manageSettings: manageSettings,
      saveImage: saveImage,
      queue: queue,
      officialApi: officialApi ?? _TestOfficialNovelAiApiService(),
      officialTokenStore:
          officialTokenStore ?? _TestOfficialNovelAiTokenStore(),
      dailyStats: _TestDailyStatsLocalDatasource(),
    );

class _TestOfficialNovelAiApiService extends OfficialNovelAiApiService {
  _TestOfficialNovelAiApiService({
    this.upscaleOutputPath,
    this.enhanceOutputPath,
    this.processingGate,
  });

  final String? upscaleOutputPath;
  final String? enhanceOutputPath;
  final Completer<void>? processingGate;
  final upscaleRequests = <({String imagePath, String token, int scale})>[];
  final enhanceRequests = <({
    String imagePath,
    String token,
    String model,
    String prompt,
    int steps,
    double scale,
    double scaleValue,
  })>[];

  @override
  Future<OfficialNovelAiAccount> verifyToken(String token) async =>
      const OfficialNovelAiAccount();

  @override
  Future<OfficialNovelAiV5Usage?> fetchV5Usage(String token) async => null;

  @override
  Future<String> upscaleImage({
    required String imagePath,
    required String token,
    int scale = 2,
    void Function(String status)? onStatus,
  }) async {
    upscaleRequests.add((imagePath: imagePath, token: token, scale: scale));
    onStatus?.call('test processing Upscale');
    if (processingGate != null) await processingGate!.future;
    final outputPath = upscaleOutputPath;
    if (outputPath == null) {
      throw StateError('No upscale output was configured for this test');
    }
    return outputPath;
  }

  @override
  Future<String> enhanceImage({
    required String imagePath,
    required String token,
    required String model,
    required String prompt,
    String? negativePrompt,
    int? seed,
    int steps = 23,
    double scaleValue = 5.0,
    required double strength,
    double noise = 0.0,
    double scale = 1.5,
    bool upscaledEnhance = false,
    void Function(String status)? onStatus,
  }) async {
    enhanceRequests.add((
      imagePath: imagePath,
      token: token,
      model: model,
      prompt: prompt,
      steps: steps,
      scale: scale,
      scaleValue: scaleValue,
    ));
    onStatus?.call('test processing Enhance');
    if (processingGate != null) await processingGate!.future;
    final outputPath = enhanceOutputPath;
    if (outputPath == null) {
      throw StateError('No enhance output was configured for this test');
    }
    return outputPath;
  }
}

class _TestOfficialNovelAiTokenStore extends OfficialNovelAiTokenStore {
  _TestOfficialNovelAiTokenStore([this.token]);

  final String? token;

  @override
  Future<String?> read() async => token;
}

class _TestDailyStatsLocalDatasource implements DailyStatsLocalDatasource {
  @override
  Future<void> recordSuccess(DateTime time) async {}

  @override
  Future<int> getSuccessCount(DateTime time) async => 0;

  @override
  Future<Map<String, int>> getRecentCounts({int days = 7}) async => const {};
}

GenerationTask _successfulImageTask({
  required String taskId,
  required String imagePath,
  required int width,
  required int height,
  String model = 'nai-diffusion-4-5-full',
  int steps = 23,
  double scale = 5,
  String prompt = 'source prompt',
  String? negativePrompt,
}) =>
    GenerationTask(
      taskId: taskId,
      model: model,
      endpointId: AppConstants.novelAiOfficialEndpointId,
      protocol: AppConstants.novelAiOfficialProtocol,
      prompt: prompt,
      negativePrompt: negativePrompt,
      width: width,
      height: height,
      size: '${width}x$height',
      scale: scale,
      cfgRescale: 0,
      sampler: 'k_euler',
      noiseSchedule: 'native',
      steps: steps,
      status: 'success',
      imagePath: imagePath,
      createdAt: DateTime(2026),
    );

Future<File> _writeTestPng(
  Directory directory,
  String name,
  int width,
  int height,
) async {
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  final image = img.Image(width: width, height: height);
  await file.writeAsBytes(img.encodePng(image));
  return file;
}

class _DelayedSaveImageUseCase extends SaveImageUseCase {
  _DelayedSaveImageUseCase(
    super.historyRepo, {
    required this.saveStarted,
    required this.allowSave,
  });

  final Completer<void> saveStarted;
  final Completer<void> allowSave;
  int executeCount = 0;

  @override
  Future<String> execute(GenerationTask task) async {
    executeCount++;
    if (!saveStarted.isCompleted) saveStarted.complete();
    await allowSave.future;
    return task.imagePath!;
  }
}

class _SuccessfulGenerationRepository implements GenerationRepository {
  _SuccessfulGenerationRepository(this.imagePath);

  final String imagePath;

  @override
  Future<GenerationTask> submitGeneration(GenerationTask task) async =>
      task.copyWith(
        status: 'success',
        imagePath: imagePath,
        completedAt: DateTime.now(),
      );

  @override
  void setStreamPreviewHandler(
      String taskId, void Function(Uint8List bytes, int? step)? onFrame) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 每次提交延迟片刻再返回成功，模拟真实生成耗时，让批量循环可观察。
class _DelayedGenerationRepository extends _SuccessfulGenerationRepository {
  _DelayedGenerationRepository(super.imagePath);

  @override
  Future<GenerationTask> submitGeneration(GenerationTask task) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return super.submitGeneration(task);
  }
}

class _CapturingGenerationRepository implements GenerationRepository {
  _CapturingGenerationRepository(this.imagePath);

  final String imagePath;
  final List<GenerationTask> submitted = [];

  @override
  Future<GenerationTask> submitGeneration(GenerationTask task) async {
    submitted.add(task);
    return task.copyWith(
      status: 'success',
      imagePath: imagePath,
      completedAt: DateTime.now(),
    );
  }

  @override
  void setStreamPreviewHandler(
      String taskId, void Function(Uint8List bytes, int? step)? onFrame) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingHistoryRepository implements HistoryRepository {
  _ThrowingHistoryRepository(this.message);

  final String message;

  @override
  Future<GenerationTask> saveTask(GenerationTask task) async =>
      throw Exception(message);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BadGatewayGenerationRepository implements GenerationRepository {
  @override
  Future<GenerationTask> submitGeneration(GenerationTask task) async =>
      throw ApiException(
        message: '服务器错误 (502)：上游请求失败: All connection attempts failed',
        statusCode: 502,
      );

  @override
  void setStreamPreviewHandler(
      String taskId, void Function(Uint8List bytes, int? step)? onFrame) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingUpdateHistoryRepository extends _MemoryHistoryRepository {
  @override
  Future<GenerationTask> updateTask(GenerationTask task) async {
    if (task.status == 'failed') {
      throw Exception('history update failed');
    }
    return super.updateTask(task);
  }
}

class _MemoryHistoryRepository implements HistoryRepository {
  final Map<String, GenerationTask> tasks = {};

  @override
  Future<GenerationTask> saveTask(GenerationTask task) async {
    tasks[task.taskId] = task;
    return task;
  }

  @override
  Future<GenerationTask> updateTask(GenerationTask task) async {
    tasks[task.taskId] = task;
    return task;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SettingsRepository implements SettingsRepository {
  List<CharacterReferenceImage> savedVibeReferences = const [];
  List<PreciseReferenceImage> savedPreciseReferences = const [];
  ReferenceMode savedReferenceMode = ReferenceMode.vibe;
  List<CharacterSpec> savedCharacters = const [];
  List<CharacterSpec> savedInpaintCharacters = const [];
  List<ApiEndpoint> novelAiEndpoints = const [];
  String? activeNovelAiEndpointId;
  String? activeNovelAiModel;
  int savedBatchCount = 1;
  int savedSteps = 28;
  bool savedStepsLocked = false;

  @override
  Future<void> setStepsDraft(int value) async => savedSteps = value;

  @override
  Future<void> setStepsLocked(bool value) async => savedStepsLocked = value;

  @override
  Future<void> setSelectedModelDraft(String value) async {}

  @override
  Future<void> setSelectedResolutionDraft(String value) async {}

  @override
  Future<void> setScaleDraft(double value) async {}

  @override
  Future<void> setCfgRescaleDraft(double value) async {}

  @override
  Future<void> setSelectedSamplerDraft(String value) async {}

  @override
  Future<void> setSelectedNoiseScheduleDraft(String value) async {}

  @override
  Future<void> setPromptDraft(String value) async {}

  @override
  Future<void> setNegativePromptDraft(String value) async {}

  @override
  Future<void> setVibeReferencesDraft(
    List<CharacterReferenceImage> value,
  ) async {
    savedVibeReferences = [...value];
  }

  @override
  Future<ReferenceMode> getReferenceModeDraft() async => savedReferenceMode;

  @override
  Future<void> setReferenceModeDraft(ReferenceMode value) async {
    savedReferenceMode = value;
  }

  @override
  Future<void> setPreciseReferencesDraft(
    List<PreciseReferenceImage> value,
  ) async {
    savedPreciseReferences = [...value];
  }

  @override
  Future<void> setCharactersDraft(List<CharacterSpec> value) async {
    savedCharacters = [...value];
  }

  @override
  Future<void> setInpaintCharactersDraft(List<CharacterSpec> value) async {
    savedInpaintCharacters = [...value];
  }

  @override
  Future<List<CharacterSpec>> getInpaintCharactersDraft() async =>
      savedInpaintCharacters;

  @override
  Future<String?> getSelectedModelDraft() async => 'model';

  @override
  Future<String> getImageProviderGptModel() async => '';

  @override
  Future<String> getImageProviderNanoModel() async => '';

  @override
  Future<String?> getDefaultModel() async => 'model';

  @override
  Future<String> getSelectedResolutionDraft() async => '832x1216';

  @override
  Future<String> getSelectedSamplerDraft() async => 'k_euler';

  @override
  Future<double> getScaleDraft() async => 5;

  @override
  Future<double> getCfgRescaleDraft() async => 0;

  @override
  Future<int> getStepsDraft() async => 28;

  @override
  Future<bool> getStepsLocked() async => false;

  @override
  Future<String> getSelectedNoiseScheduleDraft() async => 'native';

  @override
  Future<String> getPromptDraft() async => '';

  @override
  Future<String> getNegativePromptDraft() async => '';

  @override
  Future<String> getInpaintPromptDraft() async => '';

  @override
  Future<void> setInpaintPromptDraft(String value) async {}

  @override
  Future<String> getInpaintNegativePromptDraft() async => '';

  @override
  Future<void> setInpaintNegativePromptDraft(String value) async {}

  @override
  Future<List<CharacterSpec>> getCharactersDraft() async => const [];

  @override
  Future<List<ApiEndpoint>> getEndpoints(ImageProviderType provider) async =>
      provider == ImageProviderType.novelAi ? novelAiEndpoints : const [];

  @override
  Future<List<CharacterReferenceImage>> getVibeReferencesDraft() async =>
      const [];

  @override
  Future<List<PreciseReferenceImage>> getPreciseReferencesDraft() async =>
      const [];

  @override
  Future<List<String>> getCustomResolutions() async => const [];

  @override
  Future<void> setCustomResolutions(List<String> value) async {}

  @override
  Future<int> getBatchCount() async => savedBatchCount;

  @override
  Future<void> setBatchCount(int value) async => savedBatchCount = value;

  @override
  Future<void> setActiveEndpointId(
      ImageProviderType provider, String? id) async {
    if (provider == ImageProviderType.novelAi) {
      activeNovelAiEndpointId = id;
    }
  }

  @override
  Future<void> setActiveModel(ImageProviderType provider, String? model) async {
    if (provider == ImageProviderType.novelAi) {
      activeNovelAiModel = model;
    }
  }

  @override
  Future<String?> getActiveEndpointId(ImageProviderType provider) async =>
      provider == ImageProviderType.novelAi ? activeNovelAiEndpointId : null;

  @override
  Future<String?> getActiveModel(ImageProviderType provider) async =>
      provider == ImageProviderType.novelAi ? activeNovelAiModel : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
