import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/data/datasources/local/daily_stats_local_datasource.dart';
import 'package:nai_huishi/data/datasources/local/official_novelai_token_store.dart';
import 'package:nai_huishi/data/datasources/remote/official_novelai_api_service.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/nai_model.dart';
import 'package:nai_huishi/domain/entities/preset.dart';
import 'package:nai_huishi/domain/entities/image_tag_result.dart';
import 'package:nai_huishi/domain/repositories/generation_repository.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/domain/repositories/settings_repository.dart';
import 'package:nai_huishi/domain/usecases/generate_image.dart';
import 'package:nai_huishi/domain/usecases/manage_settings.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'seed and selected metadata persist without changing unselected settings',
      () async {
    final settings = _MemorySettings(
        selectedModel: _modelId(
            AppConstants.novelAiOfficialEndpointId, 'nai-diffusion-5-full'),
        sampler: 'k_dpm_2',
        steps: 23);
    final vm = _createViewModel(settings);
    await vm.loadModels();
    vm.updateSeed(123);
    await vm.importReferenceMetadata(
        const ImageTagResult(source: TagSource.naiMetadata, metadata: {
          'seed': 456,
          'steps': 12,
          'sampler': 'k_euler',
          'cfg_rescale': 0.6
        }),
        {'seed', 'cfg_rescale'});
    final restored = _createViewModel(settings);
    await restored.loadModels();
    expect(restored.seed, 456);
    expect(restored.steps, 23);
    expect(restored.selectedSampler, 'k_dpm_2');
    expect(restored.cfgRescale, 0.6);
    restored.updateSeed(null);
    final random = _createViewModel(settings);
    await random.loadModels();
    expect(random.seed, isNull);
  });

  for (final endpoint in [
    AppConstants.novelAiOfficialEndpointId,
    AppConstants.novelAiImageGenerationsEndpointId,
    AppConstants.novelAiChatCompletionsEndpointId
  ]) {
    test('V5 accepts and restores 50 steps on $endpoint', () async {
      final settings = _MemorySettings(
          selectedModel: _modelId(endpoint, 'nai-diffusion-5-full'),
          sampler: 'k_euler');
      final vm = _createViewModel(settings);
      await vm.loadModels();
      await vm.updateSteps(50);
      expect(vm.steps, 50);
      final task = vm.buildInpaintTask(
          sourcePath: 'source.png',
          maskPath: 'mask.png',
          prompt: 'test',
          negativePrompt: '',
          strength: 1,
          disabledOriginalImage: false,
          colorCorrect: true);
      expect(task.steps, 50);
      final restored = _createViewModel(settings);
      await restored.loadModels();
      expect(restored.steps, 50);
      await restored.updateSteps(0);
      expect(restored.steps, 1);
      await restored.updateSteps(99);
      expect(restored.steps, 50);
    });
  }

  test('zero estimate includes 1024 square and still requires under 28 steps',
      () async {
    final settings = _MemorySettings(
        selectedModel: _modelId(
            AppConstants.novelAiOfficialEndpointId, 'nai-diffusion-5-full'),
        sampler: 'k_euler',
        steps: 27);
    final vm = _createViewModel(settings);
    await vm.loadModels();
    await vm.updateSelectedResolution('832x1216');
    expect(vm.officialCostPerImage, 0);
    await vm.updateSteps(28);
    expect(vm.officialCostPerImage, greaterThan(0));
    await vm.updateSteps(27);
    await vm.updateSelectedResolution('1024x1024');
    expect(vm.officialCostPerImage, 0);
    await vm.updateSteps(28);
    expect(vm.officialCostPerImage, greaterThan(0));
    await vm.updateSteps(27);
    await vm.updateSelectedResolution('1024x1536');
    expect(vm.officialCostPerImage, greaterThan(0));
    await vm.updateSelectedResolution('1216x832');
    expect(vm.officialCostPerImage, 0);
  });

  test('custom resolutions can be deleted without removing built-in presets',
      () async {
    final settings = _MemorySettings(
        selectedModel: _modelId(
            AppConstants.novelAiOfficialEndpointId, 'nai-diffusion-5-full'),
        sampler: 'k_euler');
    final vm = _createViewModel(settings);
    await vm.loadModels();
    final presets = List.of(vm.availableResolutions);
    expect(await vm.addCustomResolution(704, 960), isNull);
    final restored = _createViewModel(settings);
    await restored.loadModels();
    expect(restored.availableResolutions, contains('704x960'));
    await restored.removeCustomResolution('704x960');
    expect(restored.availableResolutions, containsAll(presets));
    expect(restored.availableResolutions, isNot(contains('704x960')));
    expect(restored.selectedResolution, isNot('704x960'));
    final deleted = _createViewModel(settings);
    await deleted.loadModels();
    expect(deleted.availableResolutions, isNot(contains('704x960')));
  });

  test('Medium runtime constraints preserve High settings across restart',
      () async {
    final settings = _MemorySettings(
      selectedModel: _modelId(
          AppConstants.novelAiOfficialEndpointId, 'nai-diffusion-5-full'),
      sampler: 'k_dpm_2',
      steps: 23,
      cfgRescale: 0.35,
    );
    final first = _createViewModel(settings);
    await first.loadModels();

    await first.updateSelectedModel(_modelId(
      AppConstants.novelAiOfficialEndpointId,
      'nai-diffusion-5-full-medium',
    ));

    expect(first.isMediumEffort, isTrue);
    expect(first.steps, 14);
    expect(first.selectedSampler, 'k_euler_ancestral');
    expect(first.cfgRescale, 0);
    expect(settings.sampler, 'k_dpm_2');
    expect(settings.steps, 23);
    expect(settings.cfgRescale, 0.35);

    final restarted = _createViewModel(settings);
    await restarted.loadModels();

    expect(restarted.isMediumEffort, isTrue);
    expect(restarted.steps, 14);
    expect(restarted.selectedSampler, 'k_euler_ancestral');
    expect(restarted.cfgRescale, 0);
    expect(settings.sampler, 'k_dpm_2');
    expect(settings.steps, 23);
    expect(settings.cfgRescale, 0.35);

    await restarted.updateSelectedModel(_modelId(
      AppConstants.novelAiOfficialEndpointId,
      'nai-diffusion-5-full',
    ));
    expect(restarted.isMediumEffort, isFalse);
    expect(restarted.selectedSampler, 'k_dpm_2');
    expect(restarted.steps, 23);
    expect(restarted.cfgRescale, 0.35);
  });

  test('unsupported sampler fallback does not replace preference across routes',
      () async {
    final settings = _MemorySettings(
      selectedModel: _modelId(
          AppConstants.novelAiOfficialEndpointId, 'nai-diffusion-5-full'),
      sampler: 'k_dpm_2', // supported by official/7877, unavailable on IKUN
    );
    final first = _createViewModel(settings);
    await first.loadModels();

    await first.updateSelectedModel(_modelId(
      AppConstants.novelAiImageGenerationsEndpointId,
      'nai-diffusion-5-full',
    ));
    expect(first.selectedSampler, ApiConstants.defaultSampler);
    expect(settings.sampler, 'k_dpm_2');

    // The selected IKUN route and the original High preference both survive
    // a fresh view-model instance.
    final restarted = _createViewModel(settings);
    await restarted.loadModels();
    expect(restarted.selectedSampler, ApiConstants.defaultSampler);
    expect(settings.sampler, 'k_dpm_2');

    await restarted.updateSelectedModel(_modelId(
      AppConstants.novelAiOfficialEndpointId,
      'nai-diffusion-5-full',
    ));
    expect(restarted.selectedSampler, 'k_dpm_2');
    expect(settings.sampler, 'k_dpm_2');

    await restarted.updateSelectedModel(_modelId(
      AppConstants.novelAiImageGenerationsEndpointId,
      'nai-diffusion-5-full',
    ));
    await restarted.updateSelectedSampler('k_euler');
    await restarted.updateSelectedModel(_modelId(
      AppConstants.novelAiOfficialEndpointId,
      'nai-diffusion-5-full',
    ));
    expect(restarted.selectedSampler, 'k_euler');
    expect(settings.sampler, 'k_euler');
  });

  test('loadModels restores the preference after resolving a new route',
      () async {
    final settings = _MemorySettings(
      selectedModel: _modelId(AppConstants.novelAiImageGenerationsEndpointId,
          'nai-diffusion-5-full'),
      sampler: 'k_dpm_2',
    )
      ..activeEndpointId = AppConstants.novelAiChatCompletionsEndpointId
      ..activeModel = 'nai-diffusion-5-full';
    final vm = _createViewModel(settings);

    await vm.loadModels();

    expect(
      vm.selectedModel,
      _modelId(AppConstants.novelAiChatCompletionsEndpointId,
          'nai-diffusion-5-full'),
    );
    expect(vm.selectedSampler, 'k_dpm_2');
    expect(settings.sampler, 'k_dpm_2');
  });

  test('sampler edits wait for asynchronous defaults before saving', () async {
    final samplerRead = Completer<String>();
    final samplerReadStarted = Completer<void>();
    final settings = _MemorySettings(
      selectedModel: _modelId(
          AppConstants.novelAiOfficialEndpointId, 'nai-diffusion-5-full'),
      sampler: 'k_euler',
      samplerRead: samplerRead,
      samplerReadStarted: samplerReadStarted,
    );
    final vm = _createViewModel(settings);
    await samplerReadStarted.future;

    final edit = vm.updateSelectedSampler('k_dpmpp_2m');
    expect(settings.sampler, 'k_euler');
    samplerRead.complete('k_euler');
    await edit;

    expect(vm.selectedSampler, 'k_dpmpp_2m');
    expect(settings.sampler, 'k_dpmpp_2m');
  });

  test('Medium history keeps High preference while High history imports it',
      () async {
    final settings = _MemorySettings(
      selectedModel: _modelId(
          AppConstants.novelAiOfficialEndpointId, 'nai-diffusion-5-full'),
      sampler: 'k_dpmpp_2m',
      steps: 20,
      cfgRescale: 0.4,
    )
      ..activeEndpointId = AppConstants.novelAiOfficialEndpointId
      ..activeModel = 'nai-diffusion-5-full';
    // The endpoint advertises only High. Importing a Medium history entry must
    // persist its exact model so loadModels can restore it as an active model.
    settings.endpoints[0] =
        settings.endpoints[0].copyWith(models: const ['nai-diffusion-5-full']);
    final vm = _createViewModel(settings);
    await vm.loadModels();

    await vm.loadFromHistory(GenerationTask(
      taskId: 'history-medium',
      model: 'nai-diffusion-5-full-medium',
      endpointId: AppConstants.novelAiOfficialEndpointId,
      protocol: AppConstants.novelAiOfficialProtocol,
      prompt: 'history prompt',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0,
      sampler: 'k_euler_ancestral',
      noiseSchedule: 'karras',
      steps: 14,
      status: 'success',
      createdAt: DateTime(2026),
    ));

    expect(vm.isMediumEffort, isTrue);
    expect(vm.selectedSampler, 'k_euler_ancestral');
    expect(settings.sampler, 'k_dpmpp_2m');
    expect(settings.steps, 20);
    expect(settings.cfgRescale, 0.4);
    expect(settings.activeEndpointId, AppConstants.novelAiOfficialEndpointId);
    expect(settings.activeModel, 'nai-diffusion-5-full-medium');

    final restarted = _createViewModel(settings);
    await restarted.loadModels();
    expect(restarted.isMediumEffort, isTrue);
    expect(
      restarted.selectedModel,
      _modelId(AppConstants.novelAiOfficialEndpointId,
          'nai-diffusion-5-full-medium'),
    );
    expect(restarted.selectedSampler, 'k_euler_ancestral');
    expect(restarted.steps, 14);
    expect(settings.sampler, 'k_dpmpp_2m');
    expect(settings.steps, 20);
    expect(settings.cfgRescale, 0.4);
    await restarted.updateEffort(GenerationEffort.high);
    expect(restarted.selectedSampler, 'k_dpmpp_2m');
    expect(restarted.steps, 20);
    expect(restarted.cfgRescale, 0.4);

    await restarted.loadFromHistory(GenerationTask(
      taskId: 'history-high',
      model: 'nai-diffusion-5-full',
      endpointId: AppConstants.novelAiOfficialEndpointId,
      protocol: AppConstants.novelAiOfficialProtocol,
      prompt: 'high history prompt',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0.5,
      sampler: 'k_euler',
      noiseSchedule: 'karras',
      steps: 25,
      status: 'success',
      createdAt: DateTime(2026),
    ));

    expect(restarted.isMediumEffort, isFalse);
    expect(restarted.selectedSampler, 'k_euler');
    expect(restarted.steps, 25);
    expect(restarted.cfgRescale, 0.5);
    expect(settings.sampler, 'k_euler');
    expect(settings.steps, 25);
    expect(settings.cfgRescale, 0.5);
  });

  test('preset sampling replaces High preference and survives restart',
      () async {
    final settings = _MemorySettings(
      selectedModel: _modelId(AppConstants.novelAiImageGenerationsEndpointId,
          'nai-diffusion-5-full'),
      sampler: 'k_dpm_2',
      steps: 23,
      cfgRescale: 0.35,
    )
      ..activeEndpointId = AppConstants.novelAiImageGenerationsEndpointId
      ..activeModel = 'nai-diffusion-5-full';
    final vm = _createViewModel(settings);
    await vm.loadModels();
    await vm.updateEffort(GenerationEffort.medium);

    await vm.loadFromPreset(Preset(
      name: 'Imported sampling',
      category: 'test',
      model: _modelId(
        AppConstants.novelAiOfficialEndpointId,
        'nai-diffusion-5-full',
      ),
      prompt: 'preset prompt',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0.5,
      sampler: 'k_euler',
      noiseSchedule: 'karras',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ));

    expect(vm.isMediumEffort, isFalse);
    expect(vm.selectedSampler, 'k_euler');
    expect(vm.steps, 23);
    expect(vm.cfgRescale, 0.5);
    expect(settings.sampler, 'k_euler');
    expect(settings.steps, 23);
    expect(settings.cfgRescale, 0.5);
    expect(
        settings.selectedModel,
        _modelId(
          AppConstants.novelAiOfficialEndpointId,
          'nai-diffusion-5-full',
        ));
    expect(settings.activeEndpointId, AppConstants.novelAiOfficialEndpointId);
    expect(settings.activeModel, 'nai-diffusion-5-full');

    final restarted = _createViewModel(settings);
    await restarted.loadModels();
    expect(
      restarted.selectedModel,
      _modelId(AppConstants.novelAiOfficialEndpointId, 'nai-diffusion-5-full'),
    );
    expect(restarted.selectedSampler, 'k_euler');
    expect(restarted.steps, 23);
    expect(restarted.cfgRescale, 0.5);
  });
}

String _modelId(String endpointId, String model) => 'nai:$endpointId:$model';

GenerationViewModel _createViewModel(_MemorySettings settings) {
  final history = _MemoryHistory();
  final queue = GenerationQueue(_MemoryGenerationRepository(), history);
  final vm = GenerationViewModel(
    generateImage: GenerateImageUseCase(history),
    manageSettings: ManageSettingsUseCase(settings),
    saveImage: SaveImageUseCase(history),
    queue: queue,
    officialApi: OfficialNovelAiApiService(),
    officialTokenStore: _EmptyTokenStore(),
    dailyStats: _UnusedDailyStats(),
  );
  addTearDown(() {
    vm.dispose();
    queue.dispose();
  });
  return vm;
}

class _MemorySettings implements SettingsRepository {
  _MemorySettings({
    required this.selectedModel,
    required this.sampler,
    this.steps = 28,
    this.cfgRescale = 0,
    this.samplerRead,
    this.samplerReadStarted,
  });

  int? seed;
  List<String> customResolutions = [];
  String? selectedModel;
  String sampler;
  int steps;
  double cfgRescale;
  final Completer<String>? samplerRead;
  final Completer<void>? samplerReadStarted;
  String selectedResolution = '832x1216';
  String noiseSchedule = 'karras';
  String? activeEndpointId;
  String? activeModel;

  final endpoints = <ApiEndpoint>[
    const ApiEndpoint(
      id: AppConstants.novelAiOfficialEndpointId,
      name: 'Official',
      baseUrl: '',
      apiKey: '',
      protocol: AppConstants.novelAiOfficialProtocol,
      models: ['nai-diffusion-5-full', 'nai-diffusion-5-full-medium'],
    ),
    const ApiEndpoint(
      id: AppConstants.novelAiImageGenerationsEndpointId,
      name: 'IKUN',
      baseUrl: '',
      apiKey: '',
      protocol: AppConstants.novelAiImageGenerationsProtocol,
      models: ['nai-diffusion-5-full', 'nai-diffusion-5-full-medium'],
    ),
    const ApiEndpoint(
      id: AppConstants.novelAiChatCompletionsEndpointId,
      name: '7877',
      baseUrl: '',
      apiKey: '',
      protocol: AppConstants.novelAiChatCompletionsProtocol,
      models: ['nai-diffusion-5-full', 'nai-diffusion-5-full-medium'],
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName
        .toString()
        .replaceAll('Symbol("', '')
        .replaceAll('")', '');
    final args = invocation.positionalArguments;
    switch (name) {
      case 'getSelectedModelDraft':
        return Future<String?>.value(selectedModel);
      case 'setSelectedModelDraft':
        selectedModel = args[0] as String;
        return Future<void>.value();
      case 'getDefaultModel':
        return Future<String?>.value(null);
      case 'getSelectedResolutionDraft':
        return Future<String>.value(selectedResolution);
      case 'setSelectedResolutionDraft':
        selectedResolution = args[0] as String;
        return Future<void>.value();
      case 'getSelectedSamplerDraft':
        samplerReadStarted?.complete();
        return samplerRead?.future ?? Future<String>.value(sampler);
      case 'setSelectedSamplerDraft':
        sampler = args[0] as String;
        return Future<void>.value();
      case 'getScaleDraft':
        return Future<double>.value(5);
      case 'getCfgRescaleDraft':
        return Future<double>.value(cfgRescale);
      case 'setCfgRescaleDraft':
        cfgRescale = args[0] as double;
        return Future<void>.value();
      case 'getSeedDraft':
        return Future<int?>.value(seed);
      case 'setSeedDraft':
        seed = args[0] as int?;
        return Future<void>.value();
      case 'getStepsDraft':
        return Future<int>.value(steps);
      case 'setStepsDraft':
        steps = args[0] as int;
        return Future<void>.value();
      case 'getStepsLocked':
        return Future<bool>.value(false);
      case 'getSelectedNoiseScheduleDraft':
        return Future<String>.value(noiseSchedule);
      case 'setSelectedNoiseScheduleDraft':
        noiseSchedule = args[0] as String;
        return Future<void>.value();
      case 'getPromptDraft':
      case 'getNegativePromptDraft':
      case 'getInpaintPromptDraft':
      case 'getInpaintNegativePromptDraft':
        return Future<String>.value('');
      case 'getCharactersDraft':
      case 'getInpaintCharactersDraft':
        return Future<List<CharacterSpec>>.value(const []);
      case 'getPreciseReferencesDraft':
        return Future<List<PreciseReferenceImage>>.value(const []);
      case 'getVibeReferencesDraft':
        return Future<List<CharacterReferenceImage>>.value(const []);
      case 'getReferenceModeDraft':
        return Future<ReferenceMode>.value(ReferenceMode.vibe);
      case 'getBatchCount':
        return Future<int>.value(1);
      case 'getCustomResolutions':
        return Future<List<String>>.value(customResolutions);
      case 'setCustomResolutions':
        customResolutions = List.of(args[0] as List<String>);
        return Future<void>.value();
      case 'getEndpoints':
        return Future<List<ApiEndpoint>>.value(
          args[0] == ImageProviderType.novelAi ? endpoints : const [],
        );
      case 'getImageProviderGptModel':
      case 'getImageProviderNanoModel':
        return Future<String>.value('');
      case 'getActiveEndpointId':
        return Future<String?>.value(activeEndpointId);
      case 'getActiveModel':
        return Future<String?>.value(activeModel);
      case 'setActiveEndpointId':
        activeEndpointId = args[1] as String?;
        return Future<void>.value();
      case 'setActiveModel':
        activeModel = args[1] as String?;
        return Future<void>.value();
      default:
        if (name.startsWith('set')) return Future<void>.value();
        return super.noSuchMethod(invocation);
    }
  }
}

class _MemoryGenerationRepository implements GenerationRepository {
  @override
  Future<GenerationTask> submitGeneration(GenerationTask task) async => task;

  @override
  Future<List<NaiModel>> fetchModels() async => const [];

  @override
  Future<void> cancelTask(String taskId) async {}

  @override
  void setStreamPreviewHandler(
    String taskId,
    void Function(Uint8List bytes, int? step)? onFrame,
  ) {}
}

class _MemoryHistory implements HistoryRepository {
  @override
  Future<GenerationTask> saveTask(GenerationTask task) async => task;

  @override
  Future<GenerationTask> updateTask(GenerationTask task) async => task;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyTokenStore extends OfficialNovelAiTokenStore {
  @override
  Future<String?> read() async => null;
}

class _UnusedDailyStats extends DailyStatsLocalDatasource {
  _UnusedDailyStats() : super(_UnusedDatabase());
}

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
