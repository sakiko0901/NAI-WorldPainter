import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
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
    final viewModel = GenerationViewModel(
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
    expect(viewModel.sessionResults, isEmpty);

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
    final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
      final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
      final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
      final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
      final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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

  test('7877 V5 禁用 Vibe 并限制步数画幅，但保留角色提示词', () async {
    final settings = _SettingsRepository();
    final history = _MemoryHistoryRepository();
    final queue = GenerationQueue(
      _SuccessfulGenerationRepository('unused'),
      history,
    );
    addTearDown(queue.dispose);
    final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
    final viewModel = GenerationViewModel(
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
