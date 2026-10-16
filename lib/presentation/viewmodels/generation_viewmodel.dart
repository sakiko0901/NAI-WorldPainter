import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/core/services/background_keepalive_service.dart';
import 'package:nai_huishi/core/utils/official_cost_calculator.dart';
import 'package:nai_huishi/data/datasources/local/daily_stats_local_datasource.dart';
import 'package:nai_huishi/data/datasources/local/official_novelai_token_store.dart';
import 'package:nai_huishi/data/datasources/remote/official_novelai_api_service.dart';
import 'package:nai_huishi/domain/agents/prompt_box_accessor.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/novelai_route.dart';
import 'package:nai_huishi/domain/entities/vibe_encoding.dart';
import 'package:nai_huishi/domain/entities/tiled_img2img.dart';
import 'package:nai_huishi/domain/services/tiled_img2img_service.dart';
import 'package:nai_huishi/domain/entities/nai_model.dart';
import 'package:nai_huishi/domain/entities/preset.dart';
import 'package:nai_huishi/domain/usecases/generate_image.dart';
import 'package:nai_huishi/domain/usecases/manage_settings.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/domain/repositories/generation_repository.dart';
import 'package:uuid/uuid.dart';

/// 生图页模型选项（聚合多供应商）
class ImageModelOption {
  final String modelId;
  final String displayName;
  final ImageProviderType provider;

  /// 该模型属于哪个 endpoint。NovelAI 没有 endpoint 概念时为空。
  final String? endpointId;

  /// endpoint 的展示名（用于在下拉里前缀显示），NovelAI 时为空。
  final String? endpointName;
  final String? protocol;
  final String actualModel;

  const ImageModelOption({
    required this.modelId,
    required this.displayName,
    required this.provider,
    required this.actualModel,
    this.endpointId,
    this.endpointName,
    this.protocol,
  });
}

/// V5 思考（Effort）等级。官方 API 通过切换 model 字段实现。
enum GenerationEffort {
  /// nai-diffusion-5-full（默认）
  high,

  /// nai-diffusion-5-full-medium 蒸馏版，固定 14 steps
  medium,
}

class GenerationViewModel extends ChangeNotifier implements PromptBoxAccessor {
  /// 流式预览：taskId → 最新预览帧（JPEG 字节）。
  /// 每个生成任务在结果区有自己的占位卡，帧只在对应占位卡上显示。
  final Map<String, Uint8List> streamPreviews = {};
  final Map<String, int> streamPreviewSteps = {};
  /// 旧字段保留供页面兼容（当前选中占位的帧）。
  Uint8List? get streamPreviewBytes =>
      _previewTaskId == null ? null : streamPreviews[_previewTaskId];
  int? get streamPreviewStep =>
      _previewTaskId == null ? null : streamPreviewSteps[_previewTaskId];
  StreamSubscription? _previewSub;
  String? _previewTaskId;
  final GenerateImageUseCase _generateImage;
  final ManageSettingsUseCase _manageSettings;
  final SaveImageUseCase _saveImage;
  final GenerationQueue _queue;
  final TiledImg2ImgService _tiledImg2Img;
  final OfficialNovelAiApiService _officialApi;
  final OfficialNovelAiTokenStore _officialTokenStore;
  final DailyStatsLocalDatasource _dailyStats;

  GenerationViewModel({
    required GenerateImageUseCase generateImage,
    required ManageSettingsUseCase manageSettings,
    required SaveImageUseCase saveImage,
    required GenerationQueue queue,
    TiledImg2ImgService? tiledImg2Img,
    required OfficialNovelAiApiService officialApi,
    required OfficialNovelAiTokenStore officialTokenStore,
    required DailyStatsLocalDatasource dailyStats,
  })  : _generateImage = generateImage,
        _manageSettings = manageSettings,
        _saveImage = saveImage,
        _queue = queue,
        _tiledImg2Img = tiledImg2Img ?? TiledImg2ImgService(queue),
        _officialApi = officialApi,
        _officialTokenStore = officialTokenStore,
        _dailyStats = dailyStats {
    _init();
  }

  String prompt = '';
  String negativePrompt = '';
  String inpaintPrompt = '';
  String inpaintNegativePrompt = '';

  /// V5 官方渠道思考等级：High = nai-diffusion-5-full，
  /// Medium = nai-diffusion-5-full-medium（固定 14 steps、k_euler_ancestral、无 rescale）。
  GenerationEffort effort = GenerationEffort.high;

  /// 提示词框版本号。每次 updatePrompt/updateNegativePrompt/updateInpaintPrompt/updateInpaintNegativePrompt 时 +1。
  /// 用于 Agent 检测提示词框内容是否变化（read_current_prompts 返回此字段）。
  int _promptVersion = 0;
  int get promptVersion => _promptVersion;
  String selectedModel = '';
  String selectedResolution = '832x1216';
  String selectedNanoImageSize = '1K';
  String selectedSampler = 'k_euler';
  double scale = 5.0;
  double cfgRescale = 0.0;
  String selectedNoiseSchedule = ApiConstants.defaultNoiseSchedule;
  int? seed;
  int? appliedSeed;
  int steps = ApiConstants.defaultSteps;
  bool isStepsLocked = false;
  List<NaiModel> models = [];

  ImageModelOption? get currentModelOption => imageModelOptions
      .where((option) => option.modelId == selectedModel)
      .firstOrNull;

  NovelAiRoute? get _currentNovelAiRoute {
    final option = currentModelOption;
    if (option != null && option.provider != ImageProviderType.novelAi) {
      return null;
    }

    String? endpointId = option?.endpointId;
    if (endpointId == null || endpointId.isEmpty) {
      if (selectedModel.startsWith('nai:ikun:')) {
        endpointId = AppConstants.novelAiImageGenerationsEndpointId;
      } else if (selectedModel.startsWith('nai:7877:')) {
        endpointId = AppConstants.novelAiChatCompletionsEndpointId;
      } else if (selectedModel.startsWith('nai:official:')) {
        endpointId = AppConstants.novelAiOfficialEndpointId;
      }
    }
    final protocol = option?.protocol;
    if ((endpointId == null || endpointId.isEmpty) &&
        (protocol == null || protocol.isEmpty)) {
      return null;
    }
    return NovelAiRoute.fromIds(endpointId, protocol);
  }

  bool get isIkunEndpoint => _currentNovelAiRoute?.isIkun ?? false;

  bool get is7877Endpoint => _currentNovelAiRoute?.isGateway7877 ?? false;

  bool get isOfficialEndpoint => _currentNovelAiRoute?.isOfficial ?? false;

  bool get isV5Model {
    final model =
        currentModelOption?.actualModel ?? _resolveActualModelId(selectedModel);
    final normalized = model.trim().toLowerCase();
    return normalized.contains('nai-diffusion-5') || normalized.contains('v5');
  }

  /// 官方渠道 V5 Full 模型才支持 Effort 切换（High/Medium）。
  bool get supportsEffortToggle {
    if (!isOfficialEndpoint) return false;
    final model =
        currentModelOption?.actualModel ?? _resolveActualModelId(selectedModel);
    final normalized = model.trim().toLowerCase();
    return normalized == 'nai-diffusion-5-full' ||
        normalized == 'nai-diffusion-5-full-inpainting';
  }

  /// Medium 等级生效中（决定 steps/sampler/rescale 强制约束）。
  bool get isMediumEffort =>
      supportsEffortToggle && effort == GenerationEffort.medium;

  Future<void> updateEffort(GenerationEffort value) async {
    if (effort == value) return;
    effort = value;
    if (isMediumEffort) {
      // Medium 强制约束：14 steps、k_euler_ancestral、无 rescale
      steps = 14;
      await _manageSettings.setStepsDraft(steps);
      selectedSampler = 'k_euler_ancestral';
      await _manageSettings.setSelectedSamplerDraft(selectedSampler);
      cfgRescale = 0.0;
      await _manageSettings.setCfgRescaleDraft(cfgRescale);
    }
    notifyListeners();
  }

  bool get supportsCharacterPrompts => true;

  bool get supportsVibeReferences {
    final model =
        currentModelOption?.actualModel ?? _resolveActualModelId(selectedModel);
    if (_isLimitModel(model)) return false;
    return isIkunEndpoint || !isV5Model;
  }

  int get maxVibeReferences => isIkunEndpoint
      ? AppConstants.maxIkunVibeReferences
      : AppConstants.maxVibeReferences;

  bool get supportsPreciseReferences {
    if (!isIkunEndpoint && !isOfficialEndpoint) return false;
    final model =
        currentModelOption?.actualModel ?? _resolveActualModelId(selectedModel);
    if (_isLimitModel(model)) return false;
    return _supportsPreciseReference(model) ||
        (isIkunEndpoint && _isV5ModelId(model));
  }

  List<ImageModelOption> imageModelOptions = [];

  /// 当前选中模型所属的供应商
  ImageProviderType get currentProvider {
    final opt =
        imageModelOptions.where((o) => o.modelId == selectedModel).toList();
    if (opt.isNotEmpty) return opt.first.provider;
    return ImageProviderType.novelAi;
  }

  bool get isGptProvider => currentProvider == ImageProviderType.gpt;
  bool get isNanoProvider => currentProvider == ImageProviderType.nanoBanana;
  bool get isNonNovelAiProvider => isGptProvider || isNanoProvider;

  List<String> get availableResolutions {
    List<String> presets;
    if (isGptProvider) {
      presets = ApiConstants.gptSupportedSizes;
    } else if (isNanoProvider) {
      presets = ApiConstants.nanoSupportedSizes;
    } else if (isIkunEndpoint) {
      presets = ApiConstants.ikunSupportedResolutions;
    } else if (isOfficialEndpoint) {
      // 官方渠道按像素计费（Opus 免费额度才限制 ≤1MP），全档尺寸可用。
      presets = ApiConstants.officialSupportedResolutions;
    } else if (is7877Endpoint) {
      // 7877 网关：V5 模型要求总像素不超过 1024×1024。
      presets = isV5Model
          ? ApiConstants.officialSupportedResolutions.where((size) {
              final parts = size.split('x');
              final width = int.tryParse(parts.first) ?? 0;
              final height = int.tryParse(parts.last) ?? 0;
              return width * height <= 1024 * 1024;
            }).toList()
          : ApiConstants.officialSupportedResolutions;
    } else if (isV5Model) {
      presets = ApiConstants.supportedResolutions.keys.where((size) {
        final parts = size.split('x');
        final width = int.tryParse(parts.first) ?? 0;
        final height = int.tryParse(parts.last) ?? 0;
        return width * height <= 1024 * 1024;
      }).toList();
    } else {
      presets = ApiConstants.supportedResolutions.keys.toList();
    }
    // 自定义画幅附加在预设之后（预设不变）。
    final merged = [...presets];
    for (final custom in customResolutions) {
      if (!merged.contains(custom)) merged.add(custom);
    }
    return merged;
  }

  String resolutionLabel(String value) {
    if (isGptProvider) return ApiConstants.gptSizeLabels[value] ?? value;
    if (isNanoProvider) return ApiConstants.nanoSizeLabels[value] ?? value;
    if (isIkunEndpoint) return ApiConstants.ikunSizeLabels[value] ?? value;
    if (isOfficialEndpoint || is7877Endpoint) {
      return ApiConstants.officialSizeLabels[value] ?? value;
    }
    switch (value) {
      case '832x1216':
        return '纵向 832×1216';
      case '1216x832':
        return '横向 1216×832';
      case '1024x1024':
        return '方形 1024×1024';
      case '768x1344':
        return '小图 · 纵向 768×1344';
      case '1344x768':
        return '小图 · 横向 1344×768';
      default:
        // 自定义画幅：宽高相同时显示 自定义 · 方形，否则显示 自定义。
        final parts = value.split('x');
        final width = int.tryParse(parts.first);
        final height = int.tryParse(parts.last);
        if (width != null && height != null) {
          return width == height
              ? '自定义 · 方形 $width×$height'
              : '自定义 · $width×$height';
        }
        return value;
    }
  }

  String nanoImageSizeLabel(String value) =>
      ApiConstants.nanoImageSizeLabels[value] ?? value;

  String get _defaultResolutionForCurrentProvider {
    if (isGptProvider) return ApiConstants.gptSupportedSizes.first;
    if (isNanoProvider) return ApiConstants.nanoSupportedSizes.first;
    return ApiConstants.defaultResolution;
  }

  QueueState? queueState;
  GenerationTask? lastCompletedTask;
  bool get isGenerating =>
      _generateInFlight || (queueState?.isProcessing ?? false);
  int get pendingCount => queueState?.pendingCount ?? 0;
  String? errorMessage;

  // ── 官方渠道 Anlas 消耗预估 ──
  bool _officialAccountLoading = false;
  OfficialNovelAiAccount? _officialAccount;

  /// 当前官方渠道单张预计消耗（仅官方渠道时计算），供生成页显示。
  int? get officialCostPerImage {
    if (!isOfficialEndpoint) return null;
    final model =
        currentModelOption?.actualModel ?? _resolveActualModelId(selectedModel);
    final res = _parseResolution(selectedResolution);
    return OfficialCostCalculator.calculateCost(
      width: res.$1,
      height: res.$2,
      steps: isV5Model ? steps.clamp(1, 28) : steps.clamp(1, 50),
      model: model,
      strength: img2imgSourceImagePath != null ? img2imgStrength : 1.0,
    );
  }

  /// 官方剩余总点数（Anlas）。
  int? get officialTotalAnlas => _officialAccount?.totalTrainingSteps;

  bool get officialAccountLoading => _officialAccountLoading;

  /// 刷新官方账户点数（Anlas），静默失败。
  Future<void> refreshOfficialAccount() async {
    if (!isOfficialEndpoint || _officialAccountLoading) return;
    _officialAccountLoading = true;
    notifyListeners();
    try {
      final token = await _officialTokenStore.read();
      if (token == null || token.trim().isEmpty) return;
      _officialAccount = await _officialApi.verifyToken(token);
    } catch (_) {
      // 静默失败：点数显示不影响生成流程。
    } finally {
      _officialAccountLoading = false;
      notifyListeners();
    }
  }

  // 批量生成
  int batchCount = 1; // 1-30
  List<GenerationTask> sessionResults = [];
  String? selectedResultTaskId;
  GenerationTask? get selectedResult {
    if (selectedResultTaskId == null) return null;
    for (final t in sessionResults) {
      if (t.taskId == selectedResultTaskId) return t;
    }
    return null;
  }

  // 当前批次还需要发送的任务数（用于"批量生成中"提示）
  int _batchRemaining = 0;
  int get batchRemaining => _batchRemaining;

  /// 用户是否在缩略图条上手动选过某张。手动选过后，新到达的结果不再自动跟随。
  bool _userPickedResult = false;

  /// 当前是否正查看结果区最后一张（含生成中的占位卡）。
  /// 查看最新时新结果自动跟随；用户翻看旧图时不打断。
  bool get isViewingLatestResult =>
      sessionResults.isEmpty ||
      selectedResultTaskId == null ||
      selectedResultTaskId == sessionResults.last.taskId;

  void _followLatestResult(String taskId) {
    if (!_userPickedResult || isViewingLatestResult) {
      selectedResultTaskId = taskId;
    }
  }

  /// generate() 重入守卫：从按下"生成"到批次全部完成期间一直为 true，
  /// 比 queueState.isProcessing 更早置位、更晚置位，杜绝任何并发批次。
  bool _generateInFlight = false;

  /// 批量取消标志：用户在生成中再次点击"生成"按钮时设为 true，
  /// 当前正在生成的图跑完后，循环 break，剩余张数不再生成。
  bool _cancelBatch = false;
  bool get isBatchCancelling => _cancelBatch;

  GenerationMode generationMode = GenerationMode.textToImage;
  Img2ImgMode img2ImgMode = Img2ImgMode.normal;
  int _tiledCompleted = 0;
  int _tiledTotal = 0;
  bool _cancelTiled = false;
  bool _img2imgStrengthUserEdited = false;
  String? sourceImagePath;
  String? maskImagePath;
  double inpaintStrength = 0.96;
  bool disabledOriginalImage = false;
  bool colorCorrect = true;
  String? img2imgSourceImagePath;
  double img2imgStrength = 0.7;
  List<String> gptImagePaths = []; // GPT 图生图参考图列表（最多16张）
  ReferenceMode referenceMode = ReferenceMode.vibe;
  List<CharacterReferenceImage> vibeReferences = [];
  List<PreciseReferenceImage> preciseReferences = [];

  StreamSubscription? _queueSub;
  StreamSubscription? _taskSub;
  final Map<String, Future<void>> _taskProcessing = {};
  final Set<String> _processedTaskIds = {};

  /// 已计入每日统计的 taskId，防止同一任务重复计数。
  final Set<String> _recordedStatTaskIds = {};

  void _init() {
    _loadDefaults();
    _listenQueue();
  }

  Future<void> _loadDefaults() async {
    selectedModel = await _manageSettings.getSelectedModelDraft() ??
        await _manageSettings.getDefaultModel() ??
        '';
    selectedResolution = await _manageSettings.getSelectedResolutionDraft();
    selectedSampler = await _manageSettings.getSelectedSamplerDraft();
    scale = await _manageSettings.getScaleDraft();
    cfgRescale = await _manageSettings.getCfgRescaleDraft();
    steps = await _manageSettings.getStepsDraft();
    isStepsLocked = await _manageSettings.getStepsLocked();
    if (isStepsLocked && steps != ApiConstants.defaultSteps) {
      steps = ApiConstants.defaultSteps;
      await _manageSettings.setStepsDraft(steps);
    }
    selectedNoiseSchedule =
        await _manageSettings.getSelectedNoiseScheduleDraft();
    prompt = await _manageSettings.getPromptDraft();
    negativePrompt = await _manageSettings.getNegativePromptDraft();
    inpaintPrompt = await _manageSettings.getInpaintPromptDraft();
    inpaintNegativePrompt =
        await _manageSettings.getInpaintNegativePromptDraft();
    characters = await _manageSettings.getCharactersDraft();
    preciseReferences = await _manageSettings.getPreciseReferencesDraft();
    final savedVibeReferences = await _manageSettings.getVibeReferencesDraft();
    vibeReferences = savedVibeReferences;
    referenceMode = await _manageSettings.getReferenceModeDraft();
    await _normalizeReferenceDrafts();
    batchCount = await _manageSettings.getBatchCount();
    await _loadCustomResolutions();

    notifyListeners();
  }

  Future<void> _normalizeReferenceDrafts() async {
    final savedMode = referenceMode;
    final savedVibeReferences = vibeReferences;
    final savedPreciseReferences = preciseReferences;
    if (vibeReferences.length > maxVibeReferences) {
      vibeReferences = vibeReferences.take(maxVibeReferences).toList();
    }
    if (vibeReferences.isNotEmpty && preciseReferences.isEmpty) {
      referenceMode = ReferenceMode.vibe;
    } else if (preciseReferences.isNotEmpty && vibeReferences.isEmpty) {
      referenceMode = ReferenceMode.precise;
    } else if (vibeReferences.isNotEmpty && preciseReferences.isNotEmpty) {
      if (referenceMode == ReferenceMode.vibe) {
        preciseReferences = const [];
      } else {
        vibeReferences = const [];
      }
    }
    await Future.wait([
      if (referenceMode != savedMode)
        _manageSettings.setReferenceModeDraft(referenceMode),
      if (!listEquals(vibeReferences, savedVibeReferences))
        _manageSettings.setVibeReferencesDraft(vibeReferences),
      if (!listEquals(preciseReferences, savedPreciseReferences))
        _manageSettings.setPreciseReferencesDraft(preciseReferences),
    ]);
  }

  void _listenQueue() {
    _queueSub = _queue.queueStream.listen((state) {
      queueState = state;
      notifyListeners();
    });

    _taskSub = _queue.taskStream.listen(_onQueueTask);
    _previewSub = _queue.previewStream.listen((frame) {
      final (taskId, bytes, step) = frame;
      // 每个任务持有自己的预览帧，多张并行/串行生成互不覆盖
      streamPreviews[taskId] = bytes;
      if (step != null) streamPreviewSteps[taskId] = step;
      _previewTaskId = taskId;
      notifyListeners();
    });
  }

  Future<void> _onQueueTask(GenerationTask task) async {
    if (task.isInternal || !_isFinalTask(task)) return;
    // 任务终态：清掉该任务的流式帧
    streamPreviews.remove(task.taskId);
    streamPreviewSteps.remove(task.taskId);
    if (_previewTaskId == task.taskId) {
      _previewTaskId = null;
    }
    await _applyCompletedTask(task);
  }

  bool _isFinalTask(GenerationTask task) =>
      task.status == AppConstants.taskSuccess ||
      task.status == AppConstants.taskFailed;

  Future<void> _applyCompletedTask(GenerationTask task) {
    if (_processedTaskIds.contains(task.taskId)) return Future.value();
    return _taskProcessing.putIfAbsent(task.taskId, () async {
      await Future<void>.value();
      if (_processedTaskIds.contains(task.taskId)) return;
      try {
        if (task.status == AppConstants.taskSuccess) {
          GenerationTask completed;
          try {
            final filePath = await _saveImage.execute(task);
            completed = task.copyWith(imagePath: filePath);
          } catch (_) {
            completed = task;
          }
          _recordDailyStat(task.taskId, task.completedAt ?? task.createdAt);
          lastCompletedTask = completed;
          final existingIndex =
              sessionResults.indexWhere((result) => result.taskId == task.taskId);
          if (existingIndex >= 0) {
            // 占位卡升级为完成结果（原位替换，不打乱顺序）
            final updated = [...sessionResults];
            updated[existingIndex] = completed;
            sessionResults = updated;
          } else {
            sessionResults = [...sessionResults, completed];
          }
          // 自动跟随到最新结果，除非用户已翻回旧图
          _followLatestResult(completed.taskId);
          errorMessage = null;
        } else {
          errorMessage = task.errorMessage;
        }
        _processedTaskIds.add(task.taskId);
        notifyListeners();
      } finally {
        _taskProcessing.remove(task.taskId);
      }
    });
  }

  /// 记录每日生成成功统计（幂等；持久化失败不影响主流程）。
  void _recordDailyStat(String taskId, DateTime? time) {
    if (_recordedStatTaskIds.contains(taskId)) return;
    _recordedStatTaskIds.add(taskId);
    try {
      _dailyStats.recordSuccess(time ?? DateTime.now());
    } catch (_) {
      // 统计失败不影响生成流程。
    }
  }

  ImageModelOption _endpointModelOption({
    required String prefix,
    required ApiEndpoint endpoint,
    required String model,
    required ImageProviderType provider,
  }) {
    return ImageModelOption(
      modelId: '$prefix:${endpoint.id}:$model',
      displayName: model,
      provider: provider,
      actualModel: model,
      endpointId: endpoint.id,
      endpointName: endpoint.name,
      protocol: endpoint.protocol,
    );
  }

  Future<void> loadModels() async {
    final options = <ImageModelOption>[];

    // NovelAI — 聚合全部固定槽位，每个选项保留 endpoint、协议和真实模型。
    final novelEndpoints =
        await _manageSettings.getEndpoints(ImageProviderType.novelAi);
    final activeNovelAiEndpointId =
        await _manageSettings.getActiveEndpointId(ImageProviderType.novelAi);
    final activeNovelAiModel =
        await _manageSettings.getActiveModel(ImageProviderType.novelAi);
    for (final ep in novelEndpoints) {
      final endpointModels = <String>{...ep.models};
      if (ep.id == activeNovelAiEndpointId &&
          activeNovelAiModel != null &&
          activeNovelAiModel.isNotEmpty) {
        endpointModels.add(activeNovelAiModel);
      }
      for (final model in endpointModels) {
        options.add(_endpointModelOption(
          prefix: 'nai',
          endpoint: ep,
          model: model,
          provider: ImageProviderType.novelAi,
        ));
      }
    }
    if (novelEndpoints.isEmpty) {
      try {
        models = await sl<GenerationRepository>().fetchModels();
        for (final model in models) {
          options.add(ImageModelOption(
            modelId: model.id,
            displayName: model.name,
            provider: ImageProviderType.novelAi,
            actualModel: model.id,
          ));
        }
      } catch (_) {
        // NovelAI 未配置或拉取失败，跳过。
      }
    }

    // GPT — 列出所有已配置 endpoint 的所有模型，每条带上 endpointId
    final gptEndpoints =
        await _manageSettings.getEndpoints(ImageProviderType.gpt);
    for (final ep in gptEndpoints) {
      for (final m in ep.models) {
        options.add(ImageModelOption(
          modelId: 'gpt:${ep.id}:$m',
          displayName: m,
          provider: ImageProviderType.gpt,
          actualModel: m,
          endpointId: ep.id,
          endpointName: ep.name,
        ));
      }
    }
    // 旧版兼容：没有任何 endpoint 时退回 legacy 单值
    if (gptEndpoints.isEmpty) {
      final legacy = await _manageSettings.getImageProviderGptModel();
      if (legacy.isNotEmpty) {
        options.add(ImageModelOption(
          modelId: 'gpt:$legacy',
          displayName: legacy,
          provider: ImageProviderType.gpt,
          actualModel: legacy,
        ));
      }
    }

    // Nano Banana — 同上
    final nanoEndpoints =
        await _manageSettings.getEndpoints(ImageProviderType.nanoBanana);
    for (final ep in nanoEndpoints) {
      for (final m in ep.models) {
        options.add(ImageModelOption(
          modelId: 'nano:${ep.id}:$m',
          displayName: m,
          provider: ImageProviderType.nanoBanana,
          actualModel: m,
          endpointId: ep.id,
          endpointName: ep.name,
        ));
      }
    }
    if (nanoEndpoints.isEmpty) {
      final legacy = await _manageSettings.getImageProviderNanoModel();
      if (legacy.isNotEmpty) {
        options.add(ImageModelOption(
          modelId: 'nano:$legacy',
          displayName: legacy,
          provider: ImageProviderType.nanoBanana,
          actualModel: legacy,
        ));
      }
    }

    imageModelOptions = options;
    // 去重：DropdownButton 要求 value 唯一
    final seen = <String>{};
    imageModelOptions =
        imageModelOptions.where((opt) => seen.add(opt.modelId)).toList();

    final activeEndpointId =
        await _manageSettings.getActiveEndpointId(ImageProviderType.novelAi);
    final activeModel =
        await _manageSettings.getActiveModel(ImageProviderType.novelAi);
    final activeOption = imageModelOptions
        .where((option) =>
            option.provider == ImageProviderType.novelAi &&
            option.endpointId == activeEndpointId &&
            option.actualModel == activeModel)
        .firstOrNull;
    final selectedOption = imageModelOptions
        .where((option) => option.modelId == selectedModel)
        .firstOrNull;
    final shouldUseActiveNovelAi = activeOption != null &&
        (selectedOption == null ||
            selectedOption.provider == ImageProviderType.novelAi);
    if (shouldUseActiveNovelAi && selectedModel != activeOption.modelId) {
      selectedModel = activeOption.modelId;
      await _manageSettings.setSelectedModelDraft(selectedModel);
    } else if (selectedModel.isEmpty && options.isNotEmpty) {
      selectedModel = options.first.modelId;
      await _manageSettings.setSelectedModelDraft(selectedModel);
    }
    await _ensureResolutionForCurrentProvider();
    await _ensureSamplingForCurrentProvider();
    // Nano Banana 不支持局部重绘，自动回退至文生图
    if (isNanoProvider && generationMode == GenerationMode.inpainting) {
      generationMode = GenerationMode.textToImage;
    }
    notifyListeners();
  }

  Future<void> updatePrompt(String value) async {
    prompt = value;
    _promptVersion++;
    await _manageSettings.setPromptDraft(value);
    notifyListeners();
  }

  Future<void> updateNegativePrompt(String value) async {
    negativePrompt = value;
    _promptVersion++;
    await _manageSettings.setNegativePromptDraft(value);
    notifyListeners();
  }

  Future<void> updateInpaintPrompt(String value) async {
    inpaintPrompt = value;
    _promptVersion++;
    await _manageSettings.setInpaintPromptDraft(value);
    notifyListeners();
  }

  Future<void> updateInpaintNegativePrompt(String value) async {
    inpaintNegativePrompt = value;
    _promptVersion++;
    await _manageSettings.setInpaintNegativePromptDraft(value);
    notifyListeners();
  }

  // ───── PromptBoxAccessor 实现 ─────
  @override
  String get positive => prompt;
  @override
  String get negative => negativePrompt;
  @override
  String get inpaintPositive => inpaintPrompt;
  @override
  String get inpaintNegative => inpaintNegativePrompt;
  @override
  int get version => _promptVersion;

  @override
  bool get isInpaintingMode => generationMode == GenerationMode.inpainting;

  @override
  List<CharacterSpec> get characters => _characters;
  set characters(List<CharacterSpec> v) {
    _characters = v;
  }

  List<CharacterSpec> _characters = const [];

  @override
  Future<int> writePrompt({
    required String target,
    required String content,
    required bool append,
  }) async {
    final trimmed = content.trim();
    // 局部重绘框守卫：非重绘模式下禁止写入 inpaint 框
    if ((target == 'inpaint_positive' || target == 'inpaint_negative') &&
        !isInpaintingMode) {
      throw InpaintModeGuardError(target);
    }

    // 多角色框：character_N（prompt）或 character_N_uc（负向）
    final charMatch = RegExp(r'^character_(\d+)(_uc)?$').firstMatch(target);
    if (charMatch != null) {
      final idx = int.parse(charMatch.group(1)!) - 1; // 用户视角 1-based
      final isUc = charMatch.group(2) == '_uc';
      if (idx < 0 || idx >= 6) {
        throw ArgumentError('角色序号超出范围（1-6）：$target');
      }
      // 补齐角色列表到 idx+1 个
      while (_characters.length <= idx) {
        _characters = [
          ..._characters,
          const CharacterSpec(
            prompt: '',
            uc: null,
            centerX: 0.5,
            centerY: 0.5,
          )
        ];
      }
      if (isUc) {
        final current = _characters[idx].uc ?? '';
        final newUc = append && current.isNotEmpty
            ? _mergePrompt(current, trimmed)
            : trimmed;
        replaceCharacterNegative(idx, newUc);
      } else {
        final current = _characters[idx].prompt;
        final newPrompt = append && current.isNotEmpty
            ? _mergePrompt(current, trimmed)
            : trimmed;
        replaceCharacterPrompt(idx, newPrompt);
      }
      _promptVersion++;
      await _saveCharactersDraft();
      notifyListeners();
      return _promptVersion;
    }

    switch (target) {
      case 'positive':
        await updatePrompt(append && prompt.isNotEmpty
            ? _mergePrompt(prompt, trimmed)
            : trimmed);
        break;
      case 'negative':
        await updateNegativePrompt(append && negativePrompt.isNotEmpty
            ? _mergePrompt(negativePrompt, trimmed)
            : trimmed);
        break;
      case 'inpaint_positive':
        await updateInpaintPrompt(append && inpaintPrompt.isNotEmpty
            ? _mergePrompt(inpaintPrompt, trimmed)
            : trimmed);
        break;
      case 'inpaint_negative':
        await updateInpaintNegativePrompt(
            append && inpaintNegativePrompt.isNotEmpty
                ? _mergePrompt(inpaintNegativePrompt, trimmed)
                : trimmed);
        break;
      default:
        throw ArgumentError('unknown target: $target');
    }
    return _promptVersion;
  }

  Future<void> appendToPrompt(String value) async {
    final text = value.trim();
    if (text.isEmpty) return;
    if (generationMode == GenerationMode.inpainting) {
      final merged = _mergePrompt(inpaintPrompt, text);
      await updateInpaintPrompt(merged);
    } else {
      final merged = _mergePrompt(prompt, text);
      await updatePrompt(merged);
    }
  }

  Future<void> replacePrompt(String value) async {
    final text = value.trim();
    if (generationMode == GenerationMode.inpainting) {
      await updateInpaintPrompt(text);
    } else {
      await updatePrompt(text);
    }
  }

  Future<void> appendToNegativePrompt(String value) async {
    final text = value.trim();
    if (text.isEmpty) return;
    if (generationMode == GenerationMode.inpainting) {
      final merged = _mergePrompt(inpaintNegativePrompt, text);
      await updateInpaintNegativePrompt(merged);
    } else {
      final merged = _mergePrompt(negativePrompt, text);
      await updateNegativePrompt(merged);
    }
  }

  Future<void> replaceNegativePrompt(String value) async {
    final text = value.trim();
    if (generationMode == GenerationMode.inpainting) {
      await updateInpaintNegativePrompt(text);
    } else {
      await updateNegativePrompt(text);
    }
  }

  /// 追加到指定角色的 prompt
  void appendToCharacterPrompt(int index, String value) {
    if (index < 0 || index >= characters.length) return;
    final text = value.trim();
    if (text.isEmpty) return;
    final merged = _mergePrompt(characters[index].prompt, text);
    updateCharacter(index, characters[index].copyWith(prompt: merged));
  }

  /// 替换指定角色的 prompt
  void replaceCharacterPrompt(int index, String value) {
    if (index < 0) return;
    while (characters.length <= index) {
      characters = [
        ...characters,
        const CharacterSpec(
          prompt: '',
          uc: null,
          centerX: 0.5,
          centerY: 0.5,
        )
      ];
    }
    updateCharacter(index, characters[index].copyWith(prompt: value.trim()));
  }

  /// 替换指定角色的负向（uc）
  void replaceCharacterNegative(int index, String value) {
    if (index < 0) return;
    while (characters.length <= index) {
      characters = [
        ...characters,
        const CharacterSpec(
          prompt: '',
          uc: null,
          centerX: 0.5,
          centerY: 0.5,
        )
      ];
    }
    updateCharacter(index, characters[index].copyWith(uc: value.trim()));
  }

  /// 清空所有提示词（正向、负向、角色）
  Future<void> clearAllPrompts() async {
    if (generationMode == GenerationMode.inpainting) {
      await updateInpaintPrompt('');
      await updateInpaintNegativePrompt('');
    } else {
      await updatePrompt('');
      await updateNegativePrompt('');
    }
    characters = [];
    await _saveCharactersDraft();
    notifyListeners();
  }

  /// 一键替换全部：先清空再写入新值
  /// [characterPrompts] 顺序对应角色 1、角色 2 ...
  /// [characterNegatives] 与 characterPrompts 等长，可为空字符串
  Future<void> replaceAll({
    String? positive,
    String? negative,
    List<String>? characterPrompts,
    List<String>? characterNegatives,
  }) async {
    await clearAllPrompts();
    if (positive != null && positive.trim().isNotEmpty) {
      if (generationMode == GenerationMode.inpainting) {
        await updateInpaintPrompt(positive.trim());
      } else {
        await updatePrompt(positive.trim());
      }
    }
    if (negative != null && negative.trim().isNotEmpty) {
      if (generationMode == GenerationMode.inpainting) {
        await updateInpaintNegativePrompt(negative.trim());
      } else {
        await updateNegativePrompt(negative.trim());
      }
    }
    if (characterPrompts != null && characterPrompts.isNotEmpty) {
      final newChars = <CharacterSpec>[];
      for (int i = 0; i < characterPrompts.length && i < 6; i++) {
        final p = characterPrompts[i].trim();
        final uc = (characterNegatives != null && i < characterNegatives.length)
            ? characterNegatives[i].trim()
            : '';
        newChars.add(CharacterSpec(
          prompt: p,
          uc: uc.isEmpty ? null : uc,
          centerX: 0.5,
          centerY: 0.5,
        ));
      }
      characters = newChars;
      await _saveCharactersDraft();
    }
    notifyListeners();
  }

  /// 拆分 NovelAI 提示词字符串为 tag 列表。
  /// 按逗号切分，去除首尾空白，丢弃空片段。
  /// 不处理权重语法内部结构，保留 `1.5::tag::` 这类原始片段。
  static List<String> _splitTags(String s) {
    if (s.trim().isEmpty) return const [];
    return s
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  /// 提取 tag 的"基础名"用于去重比较。
  /// 去除权重前缀 `1.5::` 和闭合 `::`、去除包裹的 `{{}}` `[]`，
  /// 转小写，仅用于比较，不影响实际写入的 tag 形态。
  static String _tagKey(String tag) {
    var t = tag.trim();
    // 数字权重：`1.5::tag::` → `tag`
    final weighted = RegExp(r'^(\d+(?:\.\d+)?)::(.*)::$').firstMatch(t);
    if (weighted != null) {
      t = weighted.group(2)!;
    }
    // 去掉包裹的 {{...}}、[[...]]、(...)
    while (t.startsWith('{{') && t.endsWith('}}')) {
      t = t.substring(2, t.length - 2);
    }
    while (t.startsWith('[') && t.endsWith(']')) {
      t = t.substring(1, t.length - 1);
    }
    while (t.startsWith('(') && t.endsWith(')')) {
      t = t.substring(1, t.length - 1);
    }
    return t.toLowerCase().trim();
  }

  String _mergePrompt(String current, String incoming) {
    if (current.trim().isEmpty) return incoming;
    if (incoming.trim().isEmpty) return current;

    final existingTags = _splitTags(current);
    final incomingTags = _splitTags(incoming);
    final existingKeys = existingTags.map(_tagKey).toSet();

    final dedupedIncoming = incomingTags.where((t) {
      final key = _tagKey(t);
      // 空 key（如纯逗号）跳过；已存在的 key 跳过
      if (key.isEmpty) return false;
      return !existingKeys.contains(key);
    }).toList();

    if (dedupedIncoming.isEmpty) {
      // 新内容全部已存在，原样返回 current
      return existingTags.join(', ');
    }
    return '${existingTags.join(', ')}, ${dedupedIncoming.join(', ')}';
  }

  Future<void> updateSelectedModel(String value) async {
    selectedModel = value;
    await _manageSettings.setSelectedModelDraft(value);
    // 切换到选中模型对应的 endpoint，提交时 _resolveCreds 会读 active endpoint
    final opt = imageModelOptions.where((o) => o.modelId == value).toList();
    if (opt.isNotEmpty && opt.first.endpointId != null) {
      await _manageSettings.setActiveEndpointId(
          opt.first.provider, opt.first.endpointId);
      await _manageSettings.setActiveModel(
        opt.first.provider,
        opt.first.actualModel,
      );
    }
    if (isIkunEndpoint && isStepsLocked) {
      steps = ApiConstants.defaultSteps;
      await _manageSettings.setStepsDraft(steps);
    }
    await _ensureResolutionForCurrentProvider();
    await _ensureSamplingForCurrentProvider();
    if (vibeReferences.length > maxVibeReferences) {
      vibeReferences = vibeReferences.take(maxVibeReferences).toList();
      await _manageSettings.setVibeReferencesDraft(vibeReferences);
    }
    // Nano Banana 不支持局部重绘，自动回退至文生图
    if (isNanoProvider && generationMode == GenerationMode.inpainting) {
      generationMode = GenerationMode.textToImage;
    }
    if (isOfficialEndpoint) refreshOfficialAccount();
    notifyListeners();
  }

  Future<void> _ensureResolutionForCurrentProvider() async {
    final supported = availableResolutions;
    if (!supported.contains(selectedResolution)) {
      selectedResolution = _defaultResolutionForCurrentProvider;
      await _manageSettings.setSelectedResolutionDraft(selectedResolution);
    }
  }

  Future<void> _ensureSamplingForCurrentProvider() async {
    if (isNonNovelAiProvider) return;

    final samplers = isIkunEndpoint
        ? ApiConstants.ikunSupportedSamplers
        : ApiConstants.supportedSamplers;
    final noiseSchedules = isIkunEndpoint
        ? ApiConstants.ikunSupportedNoiseSchedules
        : ApiConstants.supportedNoiseSchedules;
    final normalizedSampler = selectedSampler.trim().toLowerCase();
    final normalizedNoiseSchedule = selectedNoiseSchedule.trim().toLowerCase();
    final nextSampler = samplers.contains(normalizedSampler)
        ? normalizedSampler
        : ApiConstants.defaultSampler;
    final nextNoiseSchedule = noiseSchedules.contains(normalizedNoiseSchedule)
        ? normalizedNoiseSchedule
        : ApiConstants.defaultNoiseSchedule;

    if (selectedSampler != nextSampler) {
      selectedSampler = nextSampler;
      await _manageSettings.setSelectedSamplerDraft(nextSampler);
    }
    if (selectedNoiseSchedule != nextNoiseSchedule) {
      selectedNoiseSchedule = nextNoiseSchedule;
      await _manageSettings.setSelectedNoiseScheduleDraft(nextNoiseSchedule);
    }
  }

  Future<void> updateSelectedResolution(String value) async {
    selectedResolution = value;
    await _manageSettings.setSelectedResolutionDraft(value);
    notifyListeners();
  }

  // ── 自定义画幅 ──
  List<String> customResolutions = [];

  /// NovelAI 支持的边长范围与步进：边长须为 64 的倍数。
  static const int _resolutionStep = 64;
  static const int _minResolutionSide = 64;
  static const int _maxResolutionSide = 1920;

  /// 校验并添加自定义画幅，成功后选中之。返回错误信息，null 表示成功。
  Future<String?> addCustomResolution(int width, int height) async {
    if (width < _minResolutionSide ||
        height < _minResolutionSide ||
        width > _maxResolutionSide ||
        height > _maxResolutionSide) {
      return '边长需在 $_minResolutionSide 到 $_maxResolutionSide 之间';
    }
    if (width % _resolutionStep != 0 || height % _resolutionStep != 0) {
      return '边长需为 $_resolutionStep 的倍数';
    }
    final key = '${width}x$height';
    if (!customResolutions.contains(key)) {
      customResolutions = [...customResolutions, key];
      await _manageSettings.setCustomResolutions(customResolutions);
    }
    await updateSelectedResolution(key);
    return null;
  }

  Future<void> _loadCustomResolutions() async {
    customResolutions = await _manageSettings.getCustomResolutions();
  }

  void updateSelectedNanoImageSize(String value) {
    selectedNanoImageSize = value;
    notifyListeners();
  }

  Future<void> updateSelectedSampler(String value) async {
    selectedSampler = value;
    notifyListeners();
    await _manageSettings.setSelectedSamplerDraft(selectedSampler);
  }

  Future<void> updateSelectedNoiseSchedule(String value) async {
    selectedNoiseSchedule = value;
    notifyListeners();
    await _manageSettings.setSelectedNoiseScheduleDraft(selectedNoiseSchedule);
  }

  Future<void> updateScale(double value) async {
    scale = value;
    await _manageSettings.setScaleDraft(value);
    notifyListeners();
  }

  Future<void> updateCfgRescale(double value) async {
    cfgRescale = value;
    await _manageSettings.setCfgRescaleDraft(value);
    notifyListeners();
  }

  Future<void> updateSteps(int value) async {
    steps = isV5Model
        ? value.clamp(1, 28)
        : isIkunEndpoint && isStepsLocked
            ? ApiConstants.defaultSteps
            : value.clamp(1, 50);
    await _manageSettings.setStepsDraft(steps);
    notifyListeners();
  }

  Future<void> toggleStepsLock() async {
    isStepsLocked = !isStepsLocked;
    if (isStepsLocked && isIkunEndpoint) {
      steps = ApiConstants.defaultSteps;
      await _manageSettings.setStepsDraft(steps);
    }
    await _manageSettings.setStepsLocked(isStepsLocked);
    notifyListeners();
  }

  Future<void> switchReferenceMode(ReferenceMode mode) async {
    if (referenceMode == mode) return;
    referenceMode = mode;
    if (mode == ReferenceMode.vibe) {
      preciseReferences = const [];
    } else {
      vibeReferences = const [];
    }
    await Future.wait([
      _manageSettings.setReferenceModeDraft(referenceMode),
      _manageSettings.setVibeReferencesDraft(vibeReferences),
      _manageSettings.setPreciseReferencesDraft(preciseReferences),
    ]);
    notifyListeners();
  }

  Future<void> setVibeReference(String path) async {
    if (vibeReferences.isEmpty) {
      await addVibeReferences([path]);
    } else {
      await replaceVibeReferenceWithPath(0, path);
    }
  }

  Future<void> selectVibeEncoding(VibeEncoding encoding) async {
    if (vibeReferences.isEmpty) {
      await addVibeEncodings([encoding]);
    } else {
      await replaceVibeReferenceWithEncoding(0, encoding);
    }
  }

  Future<int> addVibeReferences(Iterable<String> paths) async {
    if (!supportsVibeReferences || vibeReferences.length >= maxVibeReferences) {
      return 0;
    }
    final existingPaths =
        vibeReferences.map((reference) => reference.path).toSet();
    final additions = <CharacterReferenceImage>[];
    for (final path in paths) {
      if (vibeReferences.length + additions.length >= maxVibeReferences) {
        break;
      }
      if (path.isEmpty || existingPaths.contains(path)) continue;
      existingPaths.add(path);
      additions.add(CharacterReferenceImage(path: path));
    }
    return _appendVibeReferences(additions);
  }

  Future<int> addVibeEncodings(Iterable<VibeEncoding> encodings) async {
    if (!supportsVibeReferences || vibeReferences.length >= maxVibeReferences) {
      return 0;
    }
    final existingIds = vibeReferences
        .map((reference) => reference.vibeLibraryId)
        .whereType<int>()
        .toSet();
    final additions = <CharacterReferenceImage>[];
    for (final encoding in encodings) {
      if (vibeReferences.length + additions.length >= maxVibeReferences) {
        break;
      }
      final id = encoding.id;
      if (id == null || existingIds.contains(id)) continue;
      existingIds.add(id);
      additions.add(CharacterReferenceImage(
        path: encoding.sourceImagePath ?? '',
        vibeLibraryId: id,
        thumbnailPath: encoding.thumbnailPath,
        title: encoding.title,
      ));
    }
    return _appendVibeReferences(additions);
  }

  Future<int> _appendVibeReferences(
    List<CharacterReferenceImage> additions,
  ) async {
    if (additions.isEmpty) return 0;
    referenceMode = ReferenceMode.vibe;
    vibeReferences = [...vibeReferences, ...additions];
    preciseReferences = const [];
    await Future.wait([
      _manageSettings.setReferenceModeDraft(referenceMode),
      _manageSettings.setVibeReferencesDraft(vibeReferences),
      _manageSettings.setPreciseReferencesDraft(preciseReferences),
    ]);
    notifyListeners();
    return additions.length;
  }

  Future<void> replaceVibeReferenceWithPath(int index, String path) async {
    if (index < 0 || index >= vibeReferences.length || path.isEmpty) return;
    final current = vibeReferences[index];
    await updateVibeReference(
      index,
      CharacterReferenceImage(
        path: path,
        strength: current.strength,
        informationExtracted: current.informationExtracted,
      ),
    );
  }

  Future<void> replaceVibeReferenceWithEncoding(
    int index,
    VibeEncoding encoding,
  ) async {
    if (index < 0 || index >= vibeReferences.length || encoding.id == null)
      return;
    final current = vibeReferences[index];
    await updateVibeReference(
      index,
      CharacterReferenceImage(
        path: encoding.sourceImagePath ?? '',
        strength: current.strength,
        informationExtracted: current.informationExtracted,
        vibeLibraryId: encoding.id,
        thumbnailPath: encoding.thumbnailPath,
        title: encoding.title,
      ),
    );
  }

  Future<void> addPreciseReference(String path) async {
    if (!supportsPreciseReferences) return;
    referenceMode = ReferenceMode.precise;
    preciseReferences = [
      ...preciseReferences,
      PreciseReferenceImage(path: path),
    ];
    vibeReferences = const [];
    await Future.wait([
      _manageSettings.setReferenceModeDraft(referenceMode),
      _manageSettings.setVibeReferencesDraft(vibeReferences),
      _manageSettings.setPreciseReferencesDraft(preciseReferences),
    ]);
    notifyListeners();
  }

  Future<void> replacePreciseReference(int index, String path) async {
    if (index < 0 || index >= preciseReferences.length) return;
    final list = [...preciseReferences];
    list[index] = list[index].copyWith(path: path);
    preciseReferences = list;
    await _manageSettings.setPreciseReferencesDraft(preciseReferences);
    notifyListeners();
  }

  Future<void> updatePreciseReference(
    int index,
    PreciseReferenceImage reference,
  ) async {
    if (index < 0 || index >= preciseReferences.length) return;
    final list = [...preciseReferences];
    list[index] = reference;
    preciseReferences = list;
    await _manageSettings.setPreciseReferencesDraft(preciseReferences);
    notifyListeners();
  }

  Future<void> removePreciseReference(int index) async {
    if (index < 0 || index >= preciseReferences.length) return;
    final list = [...preciseReferences]..removeAt(index);
    preciseReferences = list;
    await _manageSettings.setPreciseReferencesDraft(preciseReferences);
    notifyListeners();
  }

  Future<void> updateVibeReference(
    int index,
    CharacterReferenceImage reference,
  ) async {
    if (index < 0 || index >= vibeReferences.length) return;
    final references = [...vibeReferences];
    references[index] = reference;
    vibeReferences = references;
    await _manageSettings.setVibeReferencesDraft(vibeReferences);
    notifyListeners();
  }

  Future<void> removeVibeReference([int index = 0]) async {
    if (index < 0 || index >= vibeReferences.length) return;
    final references = [...vibeReferences]..removeAt(index);
    vibeReferences = references;
    await _manageSettings.setVibeReferencesDraft(vibeReferences);
    notifyListeners();
  }

  void updateSeed(int? value) {
    seed = value;
    notifyListeners();
  }

  void applySeed(int? value) {
    appliedSeed = value;
    seed = value;
    notifyListeners();
  }

  void setGenerationMode(GenerationMode mode) {
    generationMode = mode;
    notifyListeners();
  }

  void addGptImage(String path) {
    addGptImages([path]);
  }

  int addGptImages(Iterable<String> paths) {
    final available = 16 - gptImagePaths.length;
    if (available <= 0) return 0;

    final existing = gptImagePaths.toSet();
    final additions = <String>[];
    for (final path in paths) {
      if (path.isEmpty || existing.contains(path)) continue;
      existing.add(path);
      additions.add(path);
      if (additions.length >= available) break;
    }
    if (additions.isEmpty) return 0;

    gptImagePaths = [...gptImagePaths, ...additions];
    notifyListeners();
    return additions.length;
  }

  void removeGptImage(int index) {
    if (index < 0 || index >= gptImagePaths.length) return;
    final list = [...gptImagePaths];
    list.removeAt(index);
    gptImagePaths = list;
    notifyListeners();
  }

  void clearGptImages() {
    gptImagePaths = [];
    notifyListeners();
  }

  void setSourceImagePath(String? path) {
    sourceImagePath = path;
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) {
        errorMessage = null;
      }
    }
    notifyListeners();
  }

  void setMaskImagePath(String? path) {
    maskImagePath = path;
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) {
        errorMessage = null;
      }
    }
    notifyListeners();
  }

  bool get isTiledImg2Img =>
      img2ImgMode == Img2ImgMode.tiled && img2imgSourceImagePath != null;
  int get tiledCompleted => _tiledCompleted;
  int get tiledTotal => _tiledTotal;
  bool get isTiledCancelling => _cancelTiled;

  void updateImg2ImgMode(Img2ImgMode mode) {
    if (mode == Img2ImgMode.tiled &&
        img2ImgMode != Img2ImgMode.tiled &&
        !_img2imgStrengthUserEdited) {
      img2imgStrength = 0.3;
    }
    img2ImgMode = mode;
    notifyListeners();
  }

  void cancelTiledImg2Img() {
    if (isTiledImg2Img && _generateInFlight) {
      _cancelTiled = true;
      notifyListeners();
    }
  }

  void updateInpaintStrength(double value) {
    inpaintStrength = value;
    notifyListeners();
  }

  void updateInpaintOptions({
    bool? disabledOriginalImage,
    bool? colorCorrect,
  }) {
    this.disabledOriginalImage =
        disabledOriginalImage ?? this.disabledOriginalImage;
    this.colorCorrect = colorCorrect ?? this.colorCorrect;
    notifyListeners();
  }

  GenerationTask buildInpaintTask({
    required String sourcePath,
    required String maskPath,
    required String prompt,
    required String negativePrompt,
    required double strength,
    required bool disabledOriginalImage,
    required bool colorCorrect,
    int? seed,
    String? taskId,
  }) {
    final option = currentModelOption;
    final resolutionParts = selectedResolution.split('x');
    final width = int.tryParse(resolutionParts.first) ?? 832;
    final height = int.tryParse(resolutionParts.last) ?? 1216;
    final actualModel = option?.actualModel ?? selectedModel;
    return GenerationTask(
      taskId: taskId ?? const Uuid().v4(),
      model: actualModel,
      endpointId: option?.endpointId,
      protocol: option?.protocol,
      prompt: prompt.trim(),
      negativePrompt:
          negativePrompt.trim().isEmpty ? null : negativePrompt.trim(),
      width: width,
      height: height,
      size: selectedResolution,
      scale: scale,
      cfgRescale: cfgRescale,
      sampler: selectedSampler,
      noiseSchedule: selectedNoiseSchedule,
      steps: steps,
      seed: seed,
      status: AppConstants.taskPending,
      createdAt: DateTime.now(),
      mode: GenerationMode.inpainting,
      sourceImagePath: sourcePath,
      maskImagePath: maskPath,
      inpaintStrength: strength.clamp(0.01, 1.0),
      responseFormat: 'b64_json',
      providerType: option?.provider ?? currentProvider,
      disabledOriginalImage: disabledOriginalImage,
      colorCorrect: colorCorrect,
      isInternal: true,
    );
  }

  void setImg2ImgSourceImagePath(String? path) {
    img2imgSourceImagePath = path;
    errorMessage = null;
    notifyListeners();
  }

  void updateImg2ImgStrength(double value) {
    img2imgStrength = value.clamp(0.01, 1.0);
    _img2imgStrengthUserEdited = true;
    notifyListeners();
  }

  void clearImg2ImgData() {
    img2imgSourceImagePath = null;
    img2imgStrength = 0.7;
    _img2imgStrengthUserEdited = false;
    notifyListeners();
  }

  void clearInpaintingData() {
    sourceImagePath = null;
    maskImagePath = null;
    inpaintStrength = 0.96;
    notifyListeners();
  }

  /// 局部重绘工作区钩子：局部重绘模式下，页面底部生成按钮触发时
  /// 交给工作区执行完整生成（光栅化 → 队列 → 候选），不走通用生图管线。
  /// 返回 true 表示已由工作区处理（generate 直接返回）；null/false 走通用管线。
  Future<bool?> Function()? inpaintWorkspaceHandler;

  Future<void> generate() async {
    // 重入守卫：批量生成中再次按下"生成"按钮（或被并发触发）直接忽略，
    // 避免两套 for 循环并行入队导致超过设定张数。
    if (_generateInFlight) return;
    // 局部重绘模式且工作区在场：整轮生成由工作区内部管线完成。
    if (generationMode == GenerationMode.inpainting &&
        inpaintWorkspaceHandler != null) {
      _generateInFlight = true;
      notifyListeners();
      try {
        await inpaintWorkspaceHandler!();
      } finally {
        _generateInFlight = false;
        _cancelBatch = false;
        _batchRemaining = 0;
        notifyListeners();
      }
      return;
    }
    _generateInFlight = true;
    try {
      await _generateInner();
    } catch (e) {
      errorMessage = '生成失败: $e';
      notifyListeners();
    } finally {
      _generateInFlight = false;
      _batchRemaining = 0;
      _cancelBatch = false;
      _cancelTiled = false;
      _tiledCompleted = 0;
      _tiledTotal = 0;
      notifyListeners();
    }
  }

  /// 取消批量生成：当前正在生成的图跑完后停止后续张数。
  /// 仅在批量生成中调用有效。
  void cancelBatch() {
    if (!_generateInFlight) return;
    _cancelBatch = true;
    notifyListeners();
  }

  Future<void> _generateInner() async {
    // 局部重绘使用独立提示词
    final effectivePrompt =
        generationMode == GenerationMode.inpainting ? inpaintPrompt : prompt;
    final effectiveNegativePrompt = generationMode == GenerationMode.inpainting
        ? inpaintNegativePrompt
        : negativePrompt;

    if (effectivePrompt.isEmpty) {
      errorMessage = '请输入提示词';
      notifyListeners();
      return;
    }

    final res = _parseResolution(selectedResolution);
    if (isIkunEndpoint && (res.$1 > 1600 || res.$2 > 1600)) {
      errorMessage =
          'ikun 服务端限制单边最大 1600，当前尺寸 ${res.$1}×${res.$2} 无法提交；API 文档不支持 1920 壁纸尺寸。';
      notifyListeners();
      return;
    }
    // 官方渠道无 1MP 硬限制（按像素计费），仅 7877 网关与非官方渠道限制 V5。
    if (!isOfficialEndpoint && isV5Model && res.$1 * res.$2 > 1024 * 1024) {
      errorMessage = 'V5 模型要求总像素不超过 1024×1024，请选择较小画幅';
      notifyListeners();
      return;
    }
    final enabledCharacters = supportsCharacterPrompts
        ? characters.where((c) => c.enabled).toList()
        : const <CharacterSpec>[];
    final supportsImg2Img =
        is7877Endpoint || isIkunEndpoint || isOfficialEndpoint;
    final effectiveImg2ImgPath =
        generationMode == GenerationMode.textToImage && supportsImg2Img
            ? img2imgSourceImagePath
            : null;
    if (effectiveImg2ImgPath != null &&
        !File(effectiveImg2ImgPath).existsSync()) {
      errorMessage = '图生图源图已失效，请重新选择';
      notifyListeners();
      return;
    }
    if (generationMode == GenerationMode.inpainting) {
      if (sourceImagePath == null || sourceImagePath!.isEmpty) {
        errorMessage = '请选择原图';
        notifyListeners();
        return;
      }
      if (maskImagePath == null || maskImagePath!.isEmpty) {
        errorMessage = '请选择遮罩图';
        notifyListeners();
        return;
      }
    }

    // 解析实际模型 ID（去掉 gpt: / nano: 前缀）
    var selectedOption = imageModelOptions
        .where((option) => option.modelId == selectedModel)
        .firstOrNull;
    if (selectedOption?.provider == ImageProviderType.novelAi ||
        selectedOption == null) {
      final activeEndpointId =
          await _manageSettings.getActiveEndpointId(ImageProviderType.novelAi);
      final activeModel =
          await _manageSettings.getActiveModel(ImageProviderType.novelAi);
      final activeOption = imageModelOptions
          .where((option) =>
              option.provider == ImageProviderType.novelAi &&
              option.endpointId == activeEndpointId &&
              option.actualModel == activeModel)
          .firstOrNull;
      if (activeOption != null &&
          (selectedOption == null ||
              selectedOption.endpointId != activeOption.endpointId)) {
        selectedModel = activeOption.modelId;
        selectedOption = activeOption;
        await _manageSettings.setSelectedModelDraft(selectedModel);
      }
    }
    final actualModelId = _applyEffortToModel(
      selectedOption?.actualModel ?? _resolveActualModelId(selectedModel),
    );
    final provider = selectedOption?.provider ?? currentProvider;
    final rolePreciseReferences =
        generationMode == GenerationMode.textToImage &&
                referenceMode == ReferenceMode.precise
            ? _rolePreciseReferences(enabledCharacters)
            : const <PreciseReferenceImage>[];
    final globalPreciseReferences = referenceMode == ReferenceMode.precise
        ? preciseReferences
        : const <PreciseReferenceImage>[];
    final taskPreciseReferences = supportsPreciseReferences &&
            generationMode == GenerationMode.textToImage
        ? _mergePreciseReferences(
            globalPreciseReferences,
            rolePreciseReferences,
          )
        : const <PreciseReferenceImage>[];
    if (taskPreciseReferences.isNotEmpty) {
      if (_isLimitModel(actualModelId)) {
        errorMessage = '精密参照图像不能使用 -limit 模型，请选择无 -limit 后缀的 V4/V4.5 模型';
        notifyListeners();
        return;
      }
      if (!_supportsPreciseReference(actualModelId) &&
          !(isIkunEndpoint && _isV5ModelId(actualModelId))) {
        errorMessage = '精密参照图像仅支持 NovelAI V4/V4.5 模型，ikun 渠道也支持 V5 模型';
        notifyListeners();
        return;
      }
      for (final reference in rolePreciseReferences) {
        if (reference.path.isEmpty || !File(reference.path).existsSync()) {
          errorMessage = '角色精细参考图像不可用，请重新选择';
          notifyListeners();
          return;
        }
      }
    }

    final samplerOptions = selectedOption?.endpointId ==
                AppConstants.novelAiImageGenerationsEndpointId ||
            selectedOption?.protocol ==
                AppConstants.novelAiImageGenerationsProtocol
        ? ApiConstants.ikunSupportedSamplers
        : ApiConstants.supportedSamplers;
    final noiseScheduleOptions = selectedOption?.endpointId ==
                AppConstants.novelAiImageGenerationsEndpointId ||
            selectedOption?.protocol ==
                AppConstants.novelAiImageGenerationsProtocol
        ? ApiConstants.ikunSupportedNoiseSchedules
        : ApiConstants.supportedNoiseSchedules;
    final taskSampler = isMediumEffort
        ? 'k_euler_ancestral'
        : samplerOptions.contains(selectedSampler)
            ? selectedSampler
            : ApiConstants.defaultSampler;
    final taskNoiseSchedule =
        noiseScheduleOptions.contains(selectedNoiseSchedule)
            ? selectedNoiseSchedule
            : ApiConstants.defaultNoiseSchedule;

    final task = GenerationTask(
      taskId: const Uuid().v4(),
      model: actualModelId,
      endpointId: selectedOption?.endpointId,
      protocol: selectedOption?.protocol,
      prompt: effectivePrompt,
      negativePrompt: (provider == ImageProviderType.gpt ||
              provider == ImageProviderType.nanoBanana ||
              effectiveNegativePrompt.isEmpty)
          ? null
          : effectiveNegativePrompt,
      width: res.$1,
      height: res.$2,
      size: selectedResolution,
      scale: scale,
      cfgRescale: isMediumEffort ? 0.0 : cfgRescale,
      sampler: taskSampler,
      noiseSchedule: taskNoiseSchedule,
      steps: isMediumEffort
          ? 14
          : isV5Model
              ? steps.clamp(1, 28)
              : isIkunEndpoint && isStepsLocked
                  ? ApiConstants.defaultSteps
                  : steps.clamp(1, 50),
      useCoords: enabledCharacters.any(
        (character) => character.centerX != null && character.centerY != null,
      ),
      seed: seed,
      characters: generationMode == GenerationMode.textToImage &&
              enabledCharacters.isNotEmpty
          ? enabledCharacters
          : null,
      vibeReferences: supportsVibeReferences &&
              generationMode == GenerationMode.textToImage &&
              referenceMode == ReferenceMode.vibe
          ? vibeReferences
          : const [],
      preciseReferences: taskPreciseReferences,
      status: 'pending',
      createdAt: DateTime.now(),
      mode: generationMode,
      sourceImagePath:
          generationMode == GenerationMode.inpainting ? sourceImagePath : null,
      maskImagePath:
          generationMode == GenerationMode.inpainting ? maskImagePath : null,
      gptImagePaths: (provider == ImageProviderType.gpt ||
                  provider == ImageProviderType.nanoBanana) &&
              gptImagePaths.isNotEmpty
          ? gptImagePaths
          : null,
      nanoImageSize: provider == ImageProviderType.nanoBanana
          ? selectedNanoImageSize
          : null,
      inpaintStrength:
          generationMode == GenerationMode.inpainting ? inpaintStrength : null,
      disabledOriginalImage: generationMode == GenerationMode.inpainting
          ? disabledOriginalImage
          : false,
      colorCorrect:
          generationMode == GenerationMode.inpainting ? colorCorrect : true,
      img2imgSourceImagePath: effectiveImg2ImgPath,
      img2imgStrength: effectiveImg2ImgPath == null ? null : img2imgStrength,
      responseFormat:
          generationMode == GenerationMode.inpainting ? 'b64_json' : null,
      providerType: provider,
    );

    if (effectiveImg2ImgPath != null && img2ImgMode == Img2ImgMode.tiled) {
      await _generateTiledImg2Img(task, effectiveImg2ImgPath);
      return;
    }

    errorMessage = null;
    // 保留之前的结果，新批次追加占位卡（用户仍可回看旧图）
    final count = batchCount.clamp(1, AppConstants.maxBatchCount);
    _batchRemaining = count;
    notifyListeners();

    // 批量：循环 enqueue。每张完成后冷却 1s 再发下一张。
    // GenerationQueue 是串行执行的，所以多次入队即可保证按序执行。
    await BackgroundKeepAliveService.instance.acquire(
      notificationText: count > 1 ? '批量生成 0/$count' : '正在生成图像…',
    );
    try {
      int? sharedSeed = seed;
      for (int i = 0; i < count; i++) {
        // 用户在生成中点击了取消按钮：当前张跑完后停止后续张数
        if (_cancelBatch && i > 0) break;
        // 后续每张换一个 seed，避免完全相同的图（除非用户固定了 seed）
        final useSeed = (i == 0) ? sharedSeed : null;
        final taskI = task.copyWith(
          taskId: const Uuid().v4(),
          seed: useSeed,
        );
        if (count > 1) {
          await BackgroundKeepAliveService.instance
              .updateNotification('批量生成 ${i + 1}/$count');
        }
        // 发请求前先在结果区建占位卡：流式帧显示在对应占位上。
        // 用户正在翻看旧图时不打断。
        final placeholder = taskI.copyWith(status: 'pending');
        if (!sessionResults.any((item) => item.taskId == taskI.taskId)) {
          sessionResults = [...sessionResults, placeholder];
        }
        _followLatestResult(taskI.taskId);
        notifyListeners();
        // 先订阅再 enqueue，避免任务完成事件早于订阅丢失。
        // 主流程直接接收最终任务，不依赖长期监听器的调度顺序。
        final waitFuture = _awaitTaskComplete(taskI.taskId);
        try {
          await _generateImage.execute(_queue, taskI);
        } catch (_) {
          waitFuture.ignore();
          rethrow;
        }
        final completedTask = await waitFuture;
        await _applyCompletedTask(completedTask);
        _batchRemaining = count - i - 1;
        notifyListeners();
        if (i < count - 1) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    } finally {
      await BackgroundKeepAliveService.instance.release();
    }
  }

  Future<void> _generateTiledImg2Img(
      GenerationTask task, String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      errorMessage = '图生图源图已失效，请重新选择';
      notifyListeners();
      return;
    }

    // 保留之前的结果，分块重绘完成后追加新图
    _userPickedResult = false;
    _cancelTiled = false;    errorMessage = null;
    await BackgroundKeepAliveService.instance.acquire(
      notificationText: '准备分块重绘…',
    );
    try {
      final outputPath = await _tiledImg2Img.execute(
        baseTask: task,
        sourcePath: sourcePath,
        strength: img2imgStrength,
        isCancelled: () => _cancelTiled,
        onProgress: (progress) async {
          _tiledCompleted = progress.completed;
          _tiledTotal = progress.total;
          await BackgroundKeepAliveService.instance.updateNotification(
            '分块重绘 ${progress.completed}/${progress.total}',
          );
          notifyListeners();
        },
      );
      final completed = task.copyWith(
        taskId: const Uuid().v4(),
        status: AppConstants.taskSuccess,
        imagePath: outputPath,
        completedAt: DateTime.now(),
      );
      await _applyCompletedTask(completed);
    } on TiledImg2ImgCancelled {
      errorMessage = '已取消分块重绘';
      notifyListeners();
    } finally {
      await BackgroundKeepAliveService.instance.release();
    }
  }

  /// 独立订阅队列，返回指定 taskId 的最终成功/失败任务。
  Future<GenerationTask> _awaitTaskComplete(String taskId) => _queue.taskStream
      .firstWhere((task) => task.taskId == taskId && _isFinalTask(task));

  Future<void> updateBatchCount(int value) async {
    final v = value.clamp(1, AppConstants.maxBatchCount);
    if (v == batchCount) return;
    batchCount = v;
    await _manageSettings.setBatchCount(v);
    notifyListeners();
  }

  void selectResult(String taskId) {
    if (selectedResultTaskId == taskId) return;
    selectedResultTaskId = taskId;
    _userPickedResult = true;
    notifyListeners();
  }

  /// Adds a local image to this workspace without submitting a generation task.
  bool displayImportedImage(GenerationTask image) {
    if (isGenerating) return false;
    sessionResults = [...sessionResults, image];
    selectedResultTaskId = image.taskId;
    lastCompletedTask = image;
    _userPickedResult = true;
    errorMessage = null;
    notifyListeners();
    return true;
  }

  /// 从当前结果区移除一张图片（仅工作区显示，不删除历史记录）。
  void removeSessionResult(String taskId) {
    if (isGenerating) return;
    sessionResults =
        sessionResults.where((item) => item.taskId != taskId).toList();
    if (selectedResultTaskId == taskId) {
      selectedResultTaskId = null;
      _userPickedResult = false;
    }
    if (lastCompletedTask?.taskId == taskId) {
      lastCompletedTask = sessionResults.isEmpty ? null : sessionResults.last;
      selectedResultTaskId = lastCompletedTask?.taskId;
    }
    notifyListeners();
  }

  // ── 官方超分 ──
  bool _officialUpscaling = false;
  bool get isOfficialUpscaling => _officialUpscaling;
  String? officialUpscaleStatus;

  /// 对工作台当前图片执行 NovelAI 官方超分，成功后把结果加入当前结果区。
  Future<bool> upscaleWithOfficial(int scale) async {
    final task = selectedResult ?? lastCompletedTask;
    final path = task?.imagePath;
    if (path == null || !File(path).existsSync()) {
      errorMessage = '当前图片不可用，无法超分';
      notifyListeners();
      return false;
    }
    if (_officialUpscaling) return false;
    _officialUpscaling = true;
    officialUpscaleStatus = '准备超分…';
    errorMessage = null;
    notifyListeners();
    try {
      final token = await _officialTokenStore.read();
      if (token == null || token.trim().isEmpty) {
        throw ApiException(
          message: '请先在 API 配置中填写 NovelAI 官方 Token',
          code: 'NO_OFFICIAL_TOKEN',
        );
      }
      final outputPath = await _officialApi.upscaleImage(
        imagePath: path,
        token: token,
        scale: scale,
        onStatus: (status) {
          officialUpscaleStatus = status;
          notifyListeners();
        },
      );
      final dimensions = await compute(_processedImageDimensions, outputPath);
      officialUpscaleStatus = null;
      final newTask = task!.copyWith(
        width: dimensions.$1,
        height: dimensions.$2,
        size: '${dimensions.$1}x${dimensions.$2}',
        taskId: const Uuid().v4(),
        imagePath: outputPath,
        imageUrl: null,
        status: 'success',
        completedAt: DateTime.now(),
      );
      sessionResults = [...sessionResults, newTask];
      selectedResultTaskId = newTask.taskId;
      lastCompletedTask = newTask;
      return true;
    } on ApiException catch (error) {
      officialUpscaleStatus = null;
      errorMessage = error.message;
      return false;
    } catch (error) {
      officialUpscaleStatus = null;
      errorMessage = '官方超分失败：$error';
      return false;
    } finally {
      _officialUpscaling = false;
      notifyListeners();
    }
  }

  // ── 官方 Enhance（图生图放大重绘）──
  bool _officialEnhancing = false;
  bool get isOfficialEnhancing => _officialEnhancing;
  String? officialEnhanceStatus;

  /// 对工作台当前图片执行官方 Enhance（按提示词重绘放大），结果加入结果区。
  Future<bool> enhanceWithOfficial({
    required double scale,
    required double strength,
    double noise = 0.0,
    bool max = false,
    String? promptOverride,
  }) async {
    final task = selectedResult ?? lastCompletedTask;
    final path = task?.imagePath;
    if (path == null || !File(path).existsSync()) {
      errorMessage = '当前图片不可用，无法 Enhance';
      notifyListeners();
      return false;
    }
    if (_officialEnhancing) return false;
    _officialEnhancing = true;
    officialEnhanceStatus = '准备 Enhance…';
    errorMessage = null;
    notifyListeners();
    try {
      final token = await _officialTokenStore.read();
      if (token == null || token.trim().isEmpty) {
        throw ApiException(
          message: '请先在 API 配置中填写 NovelAI 官方 Token',
          code: 'NO_OFFICIAL_TOKEN',
        );
      }
      final sourceTask = task!;
      final imported = sourceTask.model == 'imported-image';
      final model =
          _resolveActualModelId(imported ? selectedModel : sourceTask.model);
      final effectiveSteps =
          (imported && sourceTask.steps <= 0 ? steps : sourceTask.steps)
              .clamp(1, _isV5ModelId(model) ? 28 : 50);
      final effectiveScale =
          imported && sourceTask.scale <= 0 ? this.scale : sourceTask.scale;
      final effectiveNegative = sourceTask.negativePrompt ?? negativePrompt;
      final promptText =
          (promptOverride != null && promptOverride.trim().isNotEmpty)
              ? promptOverride.trim()
              : (sourceTask.prompt.trim().isNotEmpty
                  ? sourceTask.prompt.trim()
                  : prompt);
      final outputPath = await _officialApi.enhanceImage(
        imagePath: path,
        token: token,
        model: model,
        prompt: promptText,
        negativePrompt: effectiveNegative,
        seed: sourceTask.seed,
        steps: effectiveSteps,
        scaleValue: effectiveScale,
        scale: scale,
        strength: strength,
        noise: noise,
        upscaledEnhance: max,
        onStatus: (status) {
          officialEnhanceStatus = status;
          notifyListeners();
        },
      );
      final dimensions = await compute(_processedImageDimensions, outputPath);
      officialEnhanceStatus = null;
      final newTask = sourceTask.copyWith(
        model: model,
        prompt: promptText,
        negativePrompt: effectiveNegative,
        steps: effectiveSteps,
        scale: effectiveScale,
        width: dimensions.$1,
        height: dimensions.$2,
        size: '${dimensions.$1}x${dimensions.$2}',
        taskId: const Uuid().v4(),
        imagePath: outputPath,
        imageUrl: null,
        status: 'success',
        completedAt: DateTime.now(),
      );
      sessionResults = [...sessionResults, newTask];
      selectedResultTaskId = newTask.taskId;
      lastCompletedTask = newTask;
      return true;
    } on ApiException catch (error) {
      officialEnhanceStatus = null;
      errorMessage = error.message;
      return false;
    } catch (error) {
      officialEnhanceStatus = null;
      errorMessage = '官方 Enhance 失败：$error';
      return false;
    } finally {
      _officialEnhancing = false;
      notifyListeners();
    }
  }

  /// 对任意本地图片执行 NovelAI 官方超分，返回输出文件路径。
  Future<String> upscaleFileWithOfficial(
    String inputPath,
    int scale,
  ) async {
    if (_officialUpscaling) {
      throw ApiException(message: '已有超分任务进行中', code: 'UPSCALE_BUSY');
    }
    if (!File(inputPath).existsSync()) {
      throw ApiException(message: '图片不存在，无法超分', code: 'FILE_MISSING');
    }
    _officialUpscaling = true;
    officialUpscaleStatus = '准备超分…';
    errorMessage = null;
    notifyListeners();
    try {
      final token = await _officialTokenStore.read();
      if (token == null || token.trim().isEmpty) {
        throw ApiException(
          message: '请先在 API 配置中填写 NovelAI 官方 Token',
          code: 'NO_OFFICIAL_TOKEN',
        );
      }
      final outputPath = await _officialApi.upscaleImage(
        imagePath: inputPath,
        token: token,
        scale: scale,
        onStatus: (status) {
          officialUpscaleStatus = status;
          notifyListeners();
        },
      );
      officialUpscaleStatus = null;
      return outputPath;
    } on ApiException {
      officialUpscaleStatus = null;
      rethrow;
    } catch (error) {
      officialUpscaleStatus = null;
      throw ApiException(
        message: '官方超分失败：$error',
        code: 'UPSCALE_FAILED',
      );
    } finally {
      _officialUpscaling = false;
      notifyListeners();
    }
  }

  Future<String?> saveImage(GenerationTask task) async {
    try {
      final filePath = await _saveImage.execute(task);
      final saved = await _saveImage.saveToGallery(filePath);
      if (!saved) {
        throw Exception('保存到系统相册失败');
      }
      if (lastCompletedTask?.taskId == task.taskId) {
        lastCompletedTask = task.copyWith(imagePath: filePath);
      }
      notifyListeners();
      return filePath;
    } catch (e) {
      errorMessage = '保存失败: $e';
      notifyListeners();
      return null;
    }
  }

  List<PreciseReferenceImage> _rolePreciseReferences(
    List<CharacterSpec> enabledCharacters,
  ) =>
      [
        for (final character in enabledCharacters)
          for (final reference in character.referenceImages)
            PreciseReferenceImage(
              path: reference.path,
              referenceType: 'character',
              strength: reference.strength,
            ),
      ];

  List<PreciseReferenceImage> _mergePreciseReferences(
    List<PreciseReferenceImage> globalReferences,
    List<PreciseReferenceImage> roleReferences,
  ) {
    final paths = <String>{};
    return [
      ...globalReferences,
      ...roleReferences,
    ]
        .where((reference) =>
            reference.path.isNotEmpty && paths.add(reference.path))
        .toList();
  }

  Future<void> _saveCharactersDraft() =>
      _manageSettings.setCharactersDraft(characters);

  Future<void> addCharacterReference(int characterIndex, String path) async {
    if (path.isEmpty ||
        characterIndex < 0 ||
        characterIndex >= characters.length) {
      return;
    }
    final character = characters[characterIndex];
    if (character.referenceImages.any((reference) => reference.path == path)) {
      return;
    }
    updateCharacter(
      characterIndex,
      character.copyWith(
        referenceImages: [
          ...character.referenceImages,
          CharacterReferenceImage(path: path),
        ],
      ),
    );
  }

  Future<void> replaceCharacterReference(
    int characterIndex,
    int referenceIndex,
    String path,
  ) async {
    if (path.isEmpty ||
        characterIndex < 0 ||
        characterIndex >= characters.length) {
      return;
    }
    final character = characters[characterIndex];
    if (referenceIndex < 0 ||
        referenceIndex >= character.referenceImages.length) {
      return;
    }
    final current = character.referenceImages[referenceIndex];
    final references = [...character.referenceImages];
    references[referenceIndex] = CharacterReferenceImage(
      path: path,
      strength: current.strength,
      informationExtracted: current.informationExtracted,
    );
    updateCharacter(
      characterIndex,
      character.copyWith(referenceImages: references),
    );
  }

  Future<void> updateCharacterReference(
    int characterIndex,
    int referenceIndex,
    CharacterReferenceImage reference,
  ) async {
    if (characterIndex < 0 || characterIndex >= characters.length) return;
    final character = characters[characterIndex];
    if (referenceIndex < 0 ||
        referenceIndex >= character.referenceImages.length) {
      return;
    }
    final references = [...character.referenceImages];
    references[referenceIndex] = reference;
    updateCharacter(
      characterIndex,
      character.copyWith(referenceImages: references),
    );
  }

  Future<void> removeCharacterReference(
    int characterIndex,
    int referenceIndex,
  ) async {
    if (characterIndex < 0 || characterIndex >= characters.length) return;
    final character = characters[characterIndex];
    if (referenceIndex < 0 ||
        referenceIndex >= character.referenceImages.length) {
      return;
    }
    final references = [...character.referenceImages]..removeAt(referenceIndex);
    updateCharacter(
      characterIndex,
      character.copyWith(referenceImages: references),
    );
  }

  void addCharacter() {
    if (characters.length >= 6) {
      errorMessage = '最多支持 6 个角色';
      notifyListeners();
      return;
    }

    characters = [
      ...characters,
      const CharacterSpec(
        prompt: '',
        centerX: 0.5,
        centerY: 0.5,
      )
    ];
    errorMessage = null;
    _saveCharactersDraft();
    notifyListeners();
  }

  void removeCharacter(int index) {
    final list = [...characters];
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      characters = list;
      _saveCharactersDraft();
      notifyListeners();
    }
  }

  void updateCharacter(int index, CharacterSpec char) {
    final list = [...characters];
    if (index >= 0 && index < list.length) {
      list[index] = char;
      characters = list;
      _saveCharactersDraft();
      notifyListeners();
    }
  }

  void moveCharacterUp(int index) {
    if (index <= 0 || index >= characters.length) return;
    final list = [...characters];
    final current = list.removeAt(index);
    list.insert(index - 1, current);
    characters = list;
    _saveCharactersDraft();
    notifyListeners();
  }

  void moveCharacterDown(int index) {
    if (index < 0 || index >= characters.length - 1) return;
    final list = [...characters];
    final current = list.removeAt(index);
    list.insert(index + 1, current);
    characters = list;
    _saveCharactersDraft();
    notifyListeners();
  }

  void toggleCharacterEnabled(int index) {
    if (index < 0 || index >= characters.length) return;
    updateCharacter(
        index, characters[index].copyWith(enabled: !characters[index].enabled));
  }

  void setCharacterPositionAuto(int index) {
    if (index < 0 || index >= characters.length) return;
    updateCharacter(index, characters[index].copyWith(clearCenter: true));
  }

  void setCharacterGridPosition(int index, int row, int col) {
    if (index < 0 || index >= characters.length) return;
    final x = 0.1 + col * 0.2;
    final y = 0.1 + row * 0.2;
    updateCharacter(index, characters[index].copyWith(centerX: x, centerY: y));
  }

  Future<void> loadFromHistory(GenerationTask task) async {
    // 历史任务保存了 endpointId 时，必须先恢复同一渠道，避免同名模型落到另一个 NovelAI 协议。
    final candidates = imageModelOptions.where(
      (option) =>
          option.provider == task.providerType &&
          option.actualModel == task.model,
    );
    final matched = task.endpointId == null
        ? candidates.firstOrNull
        : candidates
                .where((option) => option.endpointId == task.endpointId)
                .firstOrNull ??
            candidates.firstOrNull;
    selectedModel = matched?.modelId ??
        switch (task.providerType) {
          ImageProviderType.gpt => 'gpt:${task.model}',
          ImageProviderType.nanoBanana => 'nano:${task.model}',
          ImageProviderType.novelAi => task.model,
        };
    if (matched?.endpointId != null) {
      await _manageSettings.setActiveEndpointId(
        matched!.provider,
        matched.endpointId,
      );
    }
    selectedResolution = task.size ?? '${task.width}x${task.height}';
    scale = task.scale;
    cfgRescale = task.cfgRescale;
    selectedSampler = task.sampler;
    selectedNoiseSchedule = task.noiseSchedule;
    seed = task.seed;
    appliedSeed = task.seed;
    sourceImagePath =
        task.mode == GenerationMode.inpainting ? task.sourceImagePath : null;
    maskImagePath =
        task.mode == GenerationMode.inpainting ? task.maskImagePath : null;
    inpaintStrength = task.inpaintStrength ?? 1.0;
    img2imgSourceImagePath = task.mode == GenerationMode.textToImage
        ? task.img2imgSourceImagePath
        : null;
    img2imgStrength = task.img2imgStrength ?? 0.7;
    _img2imgStrengthUserEdited = task.img2imgStrength != null;
    errorMessage = null;

    await _manageSettings.setSelectedModelDraft(selectedModel);
    await _manageSettings.setSelectedResolutionDraft(selectedResolution);
    await _manageSettings.setScaleDraft(scale);
    await _manageSettings.setCfgRescaleDraft(cfgRescale);
    await _manageSettings.setSelectedSamplerDraft(selectedSampler);
    await _manageSettings.setSelectedNoiseScheduleDraft(selectedNoiseSchedule);

    if (task.mode == GenerationMode.inpainting && !isNanoProvider) {
      generationMode = GenerationMode.inpainting;
      inpaintPrompt = task.prompt;
      inpaintNegativePrompt = task.negativePrompt ?? '';
      await _manageSettings.setInpaintPromptDraft(inpaintPrompt);
      await _manageSettings
          .setInpaintNegativePromptDraft(inpaintNegativePrompt);
    } else {
      generationMode = GenerationMode.textToImage;
      prompt = task.prompt;
      negativePrompt = task.negativePrompt ?? '';
      characters = task.characters ?? [];
      if (task.preciseReferences.isNotEmpty) {
        referenceMode = ReferenceMode.precise;
        preciseReferences = [...task.preciseReferences];
        vibeReferences = const [];
      } else if (task.vibeReferences.isNotEmpty) {
        referenceMode = ReferenceMode.vibe;
        vibeReferences = [...task.vibeReferences];
        preciseReferences = const [];
      } else {
        vibeReferences = const [];
        preciseReferences = const [];
      }
      await Future.wait([
        _manageSettings.setPromptDraft(prompt),
        _manageSettings.setNegativePromptDraft(negativePrompt),
        _manageSettings.setReferenceModeDraft(referenceMode),
        _manageSettings.setPreciseReferencesDraft(preciseReferences),
        _manageSettings.setVibeReferencesDraft(vibeReferences),
        _saveCharactersDraft(),
      ]);
    }

    notifyListeners();
  }

  void loadFromPreset(Preset preset) {
    prompt = preset.prompt;
    negativePrompt = preset.negativePrompt ?? '';
    selectedModel = preset.model;
    scale = preset.scale;
    cfgRescale = preset.cfgRescale;
    selectedSampler = preset.sampler;
    selectedNoiseSchedule = preset.noiseSchedule;
    characters = preset.characters ?? [];
    selectedResolution = '${preset.width}x${preset.height}';
    _manageSettings.setPromptDraft(prompt);
    _manageSettings.setNegativePromptDraft(negativePrompt);
    _saveCharactersDraft();
    notifyListeners();
  }

  void clearForm() {
    prompt = '';
    negativePrompt = '';
    inpaintPrompt = '';
    inpaintNegativePrompt = '';
    characters = [];
    errorMessage = null;
    clearInpaintingData();
    clearImg2ImgData();
    gptImagePaths = [];
    _manageSettings.setPromptDraft('');
    _manageSettings.setNegativePromptDraft('');
    _manageSettings.setInpaintPromptDraft('');
    _manageSettings.setInpaintNegativePromptDraft('');
    _saveCharactersDraft();
    notifyListeners();
  }

  (int, int) _parseResolution(String key) {
    if (key == 'auto') return (1024, 1024);
    final parts = key.split('x');
    if (parts.length == 2) {
      final width = int.tryParse(parts[0]);
      final height = int.tryParse(parts[1]);
      if (width != null && height != null) return (width, height);
    }
    return (832, 1216);
  }

  /// 解析实际模型 ID。新格式 `gpt:<endpointId>:<model>` / `nano:<endpointId>:<model>`，
  /// 兼容旧格式 `gpt:<model>` / `nano:<model>`。
  bool _isLimitModel(String model) =>
      model.trim().toLowerCase().endsWith('-limit');

  bool _isV5ModelId(String model) {
    final normalized = model.trim().toLowerCase();
    return normalized.contains('nai-diffusion-5') || normalized.contains('v5');
  }

  bool _supportsPreciseReference(String model) {
    final normalized = model.trim().toLowerCase();
    return normalized.startsWith('nai-v4-') ||
        normalized.startsWith('nai-v4.') ||
        normalized.contains('nai-diffusion-4-') ||
        normalized.contains('nai-diffusion-4.');
  }

  /// Effort=Medium 时把官方 V5 Full 模型切换为对应 medium 蒸馏版
  /// （inpainting 模型映射到 nai-diffusion-5-full-medium-inpainting）。
  String _applyEffortToModel(String model) {
    if (!isMediumEffort) return model;
    final normalized = model.trim();
    if (normalized == 'nai-diffusion-5-full-inpainting') {
      return 'nai-diffusion-5-full-medium-inpainting';
    }
    if (normalized == 'nai-diffusion-5-full') {
      return 'nai-diffusion-5-full-medium';
    }
    return model;
  }

  String _resolveActualModelId(String selectedModelId) {
    String stripPrefix(String prefix) {
      var rest = selectedModelId.substring(prefix.length);
      // 找到对应 option，确认它有 endpointId 才按新格式 split
      final opt = imageModelOptions.firstWhere(
        (o) => o.modelId == selectedModelId,
        orElse: () => const ImageModelOption(
          modelId: '',
          displayName: '',
          provider: ImageProviderType.novelAi,
          actualModel: '',
        ),
      );
      if (opt.endpointId != null && opt.endpointId!.isNotEmpty) {
        final marker = '${opt.endpointId}:';
        if (rest.startsWith(marker)) {
          rest = rest.substring(marker.length);
        }
      }
      return rest;
    }

    if (selectedModelId.startsWith('gpt:')) {
      return stripPrefix('gpt:');
    }
    if (selectedModelId.startsWith('nano:')) {
      return stripPrefix('nano:');
    }
    if (selectedModelId.startsWith('nai:')) {
      final parts = selectedModelId.split(':');
      if (parts.length >= 3 &&
          (parts[1] == AppConstants.novelAiImageGenerationsEndpointId ||
              parts[1] == AppConstants.novelAiChatCompletionsEndpointId)) {
        return parts.sublist(2).join(':');
      }
    }
    return selectedModelId;
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _taskSub?.cancel();
    _previewSub?.cancel();
    super.dispose();
  }
}

(int, int) _processedImageDimensions(String path) {
  final image = img.decodeImage(File(path).readAsBytesSync());
  if (image == null) throw const FormatException('无法读取处理后的图片');
  return (image.width, image.height);
}
