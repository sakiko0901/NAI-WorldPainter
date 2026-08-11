import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/core/services/background_keepalive_service.dart';
import 'package:nai_huishi/domain/agents/prompt_box_accessor.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
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

class GenerationViewModel extends ChangeNotifier implements PromptBoxAccessor {
  final GenerateImageUseCase _generateImage;
  final ManageSettingsUseCase _manageSettings;
  final SaveImageUseCase _saveImage;
  final GenerationQueue _queue;
  final TiledImg2ImgService _tiledImg2Img;

  GenerationViewModel({
    required GenerateImageUseCase generateImage,
    required ManageSettingsUseCase manageSettings,
    required SaveImageUseCase saveImage,
    required GenerationQueue queue,
    TiledImg2ImgService? tiledImg2Img,
  })  : _generateImage = generateImage,
        _manageSettings = manageSettings,
        _saveImage = saveImage,
        _queue = queue,
        _tiledImg2Img = tiledImg2Img ?? TiledImg2ImgService(queue) {
    _init();
  }

  String prompt = '';
  String negativePrompt = '';
  String inpaintPrompt = '';
  String inpaintNegativePrompt = '';

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
  String selectedNoiseSchedule = 'native';
  int? seed;
  int? appliedSeed;
  int steps = ApiConstants.defaultSteps;
  bool isStepsLocked = false;
  List<NaiModel> models = [];

  ImageModelOption? get currentModelOption => imageModelOptions
      .where((option) => option.modelId == selectedModel)
      .firstOrNull;

  bool get isIkunEndpoint =>
      currentModelOption?.protocol ==
          AppConstants.novelAiImageGenerationsProtocol ||
      selectedModel.startsWith('nai:ikun:');

  bool get is7877Endpoint =>
      currentModelOption?.protocol ==
          AppConstants.novelAiChatCompletionsProtocol ||
      selectedModel.startsWith('nai:7877:');

  bool get supportsVibeReferences => is7877Endpoint || isIkunEndpoint;

  int get maxVibeReferences => isIkunEndpoint
      ? AppConstants.maxIkunVibeReferences
      : AppConstants.maxVibeReferences;

  bool get supportsPreciseReferences {
    if (!isIkunEndpoint) return false;
    final model =
        currentModelOption?.actualModel ?? _resolveActualModelId(selectedModel);
    return !_isLimitModel(model) && _supportsPreciseReference(model);
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
    if (isGptProvider) return ApiConstants.gptSupportedSizes;
    if (isNanoProvider) return ApiConstants.nanoSupportedSizes;
    if (isIkunEndpoint) return ApiConstants.ikunSupportedResolutions;
    return ApiConstants.supportedResolutions.keys.toList();
  }

  String resolutionLabel(String value) {
    if (isGptProvider) return ApiConstants.gptSizeLabels[value] ?? value;
    if (isNanoProvider) return ApiConstants.nanoSizeLabels[value] ?? value;
    if (isIkunEndpoint) return ApiConstants.ikunSizeLabels[value] ?? value;
    switch (value) {
      case '832x1216':
        return '纵向 832×1216';
      case '1216x832':
        return '横向 1216×832';
      case '1024x1024':
        return '方形 1024×1024';
      default:
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
  String? sourceImagePath;
  String? maskImagePath;
  double inpaintStrength = 1.0;
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
    final savedCharacters = await _manageSettings.getCharactersDraft();
    preciseReferences = await _manageSettings.getPreciseReferencesDraft();
    characters = savedCharacters
        .map((character) => character.copyWith(referenceImages: const []))
        .toList();
    if (savedCharacters
        .any((character) => character.referenceImages.isNotEmpty)) {
      await _saveCharactersDraft();
    }
    final savedVibeReferences = await _manageSettings.getVibeReferencesDraft();
    vibeReferences = savedVibeReferences;
    referenceMode = await _manageSettings.getReferenceModeDraft();
    await _normalizeReferenceDrafts();
    batchCount = await _manageSettings.getBatchCount();

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
  }

  Future<void> _onQueueTask(GenerationTask task) async {
    if (task.isInternal || !_isFinalTask(task)) return;
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
          lastCompletedTask = completed;
          if (!sessionResults.any((result) => result.taskId == task.taskId)) {
            sessionResults = [...sessionResults, completed];
          }
          // 自动跟随到最新结果，除非用户已手动锁定某张
          if (!_userPickedResult) {
            selectedResultTaskId = completed.taskId;
          }
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
    for (final ep in novelEndpoints) {
      for (final model in ep.models) {
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

    if (selectedModel.isNotEmpty &&
        !imageModelOptions.any((opt) => opt.modelId == selectedModel)) {
      selectedModel =
          imageModelOptions.isNotEmpty ? imageModelOptions.first.modelId : '';
      await _manageSettings.setSelectedModelDraft(selectedModel);
    }
    if (selectedModel.isEmpty && options.isNotEmpty) {
      selectedModel = options.first.modelId;
    }
    await _ensureResolutionForCurrentProvider();
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
    }
    if (isIkunEndpoint && isStepsLocked) {
      steps = ApiConstants.defaultSteps;
      await _manageSettings.setStepsDraft(steps);
    }
    await _ensureResolutionForCurrentProvider();
    if (vibeReferences.length > maxVibeReferences) {
      vibeReferences = vibeReferences.take(maxVibeReferences).toList();
      await _manageSettings.setVibeReferencesDraft(vibeReferences);
    }
    // Nano Banana 不支持局部重绘，自动回退至文生图
    if (isNanoProvider && generationMode == GenerationMode.inpainting) {
      generationMode = GenerationMode.textToImage;
    }
    notifyListeners();
  }

  Future<void> _ensureResolutionForCurrentProvider() async {
    final supported = availableResolutions;
    if (!supported.contains(selectedResolution)) {
      selectedResolution = _defaultResolutionForCurrentProvider;
      await _manageSettings.setSelectedResolutionDraft(selectedResolution);
    }
  }

  Future<void> updateSelectedResolution(String value) async {
    selectedResolution = value;
    await _manageSettings.setSelectedResolutionDraft(value);
    notifyListeners();
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
    steps = isIkunEndpoint && isStepsLocked
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

  void setImg2ImgSourceImagePath(String? path) {
    img2imgSourceImagePath = path;
    errorMessage = null;
    notifyListeners();
  }

  void updateImg2ImgStrength(double value) {
    img2imgStrength = value.clamp(0.01, 1.0);
    notifyListeners();
  }

  void clearImg2ImgData() {
    img2imgSourceImagePath = null;
    img2imgStrength = 0.7;
    notifyListeners();
  }

  void clearInpaintingData() {
    sourceImagePath = null;
    maskImagePath = null;
    inpaintStrength = 1.0;
    notifyListeners();
  }

  Future<void> generate() async {
    // 重入守卫：批量生成中再次按下"生成"按钮（或被并发触发）直接忽略，
    // 避免两套 for 循环并行入队导致超过设定张数。
    if (_generateInFlight) return;
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
    final enabledCharacters = characters.where((c) => c.enabled).toList();
    final supportsImg2Img = is7877Endpoint || isIkunEndpoint;
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
    final selectedOption = imageModelOptions
        .where((option) => option.modelId == selectedModel)
        .firstOrNull;
    final actualModelId =
        selectedOption?.actualModel ?? _resolveActualModelId(selectedModel);
    final provider = selectedOption?.provider ?? currentProvider;
    if (supportsPreciseReferences && preciseReferences.isNotEmpty) {
      if (_isLimitModel(actualModelId)) {
        errorMessage = '精密参照图像不能使用 -limit 模型，请选择无 -limit 后缀的 V4/V4.5 模型';
        notifyListeners();
        return;
      }
      if (!_supportsPreciseReference(actualModelId)) {
        errorMessage = '精密参照图像仅支持 NovelAI V4/V4.5 模型';
        notifyListeners();
        return;
      }
    }

    final taskSampler = selectedSampler;
    final taskNoiseSchedule = selectedNoiseSchedule;

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
      cfgRescale: cfgRescale,
      sampler: taskSampler,
      noiseSchedule: taskNoiseSchedule,
      steps: isIkunEndpoint && isStepsLocked
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
      preciseReferences: supportsPreciseReferences &&
              generationMode == GenerationMode.textToImage &&
              referenceMode == ReferenceMode.precise
          ? preciseReferences
          : const [],
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
      img2imgSourceImagePath: effectiveImg2ImgPath,
      img2imgStrength: effectiveImg2ImgPath == null ? null : img2imgStrength,
      responseFormat:
          generationMode == GenerationMode.inpainting ? 'url' : null,
      providerType: provider,
    );

    if (effectiveImg2ImgPath != null && img2ImgMode == Img2ImgMode.tiled) {
      await _generateTiledImg2Img(task, effectiveImg2ImgPath);
      return;
    }

    errorMessage = null;
    // 重置批次结果区
    sessionResults = [];
    selectedResultTaskId = null;
    _userPickedResult = false;
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

    sessionResults = [];
    selectedResultTaskId = null;
    _userPickedResult = false;
    _cancelTiled = false;
    errorMessage = null;
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

  Future<void> _saveCharactersDraft() =>
      _manageSettings.setCharactersDraft(characters);

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

  bool _supportsPreciseReference(String model) {
    final normalized = model.trim().toLowerCase();
    return normalized.startsWith('nai-v4-') ||
        normalized.startsWith('nai-v4.') ||
        normalized.contains('nai-diffusion-4-') ||
        normalized.contains('nai-diffusion-4.');
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
    super.dispose();
  }
}
