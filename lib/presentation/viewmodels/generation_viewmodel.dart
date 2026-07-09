import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/core/services/background_keepalive_service.dart';
import 'package:nai_huishi/domain/agents/prompt_box_accessor.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
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

  const ImageModelOption({
    required this.modelId,
    required this.displayName,
    required this.provider,
    this.endpointId,
    this.endpointName,
  });
}

class GenerationViewModel extends ChangeNotifier implements PromptBoxAccessor {
  final GenerateImageUseCase _generateImage;
  final ManageSettingsUseCase _manageSettings;
  final SaveImageUseCase _saveImage;
  final GenerationQueue _queue;

  GenerationViewModel({
    required GenerateImageUseCase generateImage,
    required ManageSettingsUseCase manageSettings,
    required SaveImageUseCase saveImage,
    required GenerationQueue queue,
  })  : _generateImage = generateImage,
        _manageSettings = manageSettings,
        _saveImage = saveImage,
        _queue = queue {
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
  List<NaiModel> models = [];
  List<ImageModelOption> imageModelOptions = [];

  /// 当前选中模型所属的供应商
  ImageProviderType get currentProvider {
    final opt = imageModelOptions.where((o) => o.modelId == selectedModel).toList();
    if (opt.isNotEmpty) return opt.first.provider;
    return ImageProviderType.novelAi;
  }

  bool get isGptProvider => currentProvider == ImageProviderType.gpt;
  bool get isNanoProvider => currentProvider == ImageProviderType.nanoBanana;
  bool get isNonNovelAiProvider => isGptProvider || isNanoProvider;

  List<String> get availableResolutions {
    if (isGptProvider) return ApiConstants.gptSupportedSizes;
    if (isNanoProvider) return ApiConstants.nanoSupportedSizes;
    return ApiConstants.supportedResolutions.keys.toList();
  }

  String resolutionLabel(String value) {
    if (isGptProvider) return ApiConstants.gptSizeLabels[value] ?? value;
    if (isNanoProvider) return ApiConstants.nanoSizeLabels[value] ?? value;
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

  String nanoImageSizeLabel(String value) => ApiConstants.nanoImageSizeLabels[value] ?? value;

  String get _defaultResolutionForCurrentProvider {
    if (isGptProvider) return ApiConstants.gptSupportedSizes.first;
    if (isNanoProvider) return ApiConstants.nanoSupportedSizes.first;
    return ApiConstants.defaultResolution;
  }
  QueueState? queueState;
  GenerationTask? lastCompletedTask;
  bool get isGenerating => _generateInFlight || (queueState?.isProcessing ?? false);
  int get pendingCount => queueState?.pendingCount ?? 0;
  String? errorMessage;

  // 批量生成
  int batchCount = 1; // 1-15
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
  String? sourceImagePath;
  String? maskImagePath;
  double inpaintStrength = 1.0;
  List<String> gptImagePaths = []; // GPT 图生图参考图列表（最多16张）

  StreamSubscription? _queueSub;
  StreamSubscription? _taskSub;

  void _init() {
    _loadDefaults();
    _listenQueue();
  }

  Future<void> _loadDefaults() async {
    selectedModel = await _manageSettings.getSelectedModelDraft() ?? await _manageSettings.getDefaultModel() ?? '';
    selectedResolution = await _manageSettings.getSelectedResolutionDraft();
    selectedSampler = await _manageSettings.getSelectedSamplerDraft();
    scale = await _manageSettings.getScaleDraft();
    cfgRescale = await _manageSettings.getCfgRescaleDraft();
    selectedNoiseSchedule = await _manageSettings.getSelectedNoiseScheduleDraft();
    prompt = await _manageSettings.getPromptDraft();
    negativePrompt = await _manageSettings.getNegativePromptDraft();
    inpaintPrompt = await _manageSettings.getInpaintPromptDraft();
    inpaintNegativePrompt = await _manageSettings.getInpaintNegativePromptDraft();
    characters = await _manageSettings.getCharactersDraft();
    batchCount = await _manageSettings.getBatchCount();

    notifyListeners();
  }

  void _listenQueue() {
    _queueSub = _queue.queueStream.listen((state) {
      queueState = state;
      notifyListeners();
    });

    _taskSub = _queue.taskStream.listen((task) async {
      if (task.status == 'success') {
        try {
          final filePath = await _saveImage.execute(task);
          final completed = task.copyWith(imagePath: filePath);
          lastCompletedTask = completed;
          sessionResults = [...sessionResults, completed];
          // 自动跟随到最新结果，除非用户已手动锁定某张
          if (!_userPickedResult) {
            selectedResultTaskId = completed.taskId;
          }
        } catch (_) {
          lastCompletedTask = task;
          sessionResults = [...sessionResults, task];
          if (!_userPickedResult) {
            selectedResultTaskId = task.taskId;
          }
        }
        errorMessage = null;
      } else if (task.status == 'failed') {
        errorMessage = task.errorMessage;
      }
      notifyListeners();
    });
  }

  Future<void> loadModels() async {
    final options = <ImageModelOption>[];

    // NovelAI — 优先用 active endpoint 中维护的模型列表；
    // 若无，再尝试远程 fetchModels（现有 NovelAI 网关行为）
    final novelEndpoint = await _manageSettings.getActiveEndpoint(ImageProviderType.novelAi);
    final naiManualModels = novelEndpoint?.models ?? const <String>[];
    if (naiManualModels.isNotEmpty) {
      for (final m in naiManualModels) {
        options.add(ImageModelOption(
          modelId: m,
          displayName: m,
          provider: ImageProviderType.novelAi,
        ));
      }
    } else {
      try {
        models = await sl<GenerationRepository>().fetchModels();
        for (final m in models) {
          options.add(ImageModelOption(
            modelId: m.id,
            displayName: m.name,
            provider: ImageProviderType.novelAi,
          ));
        }
      } catch (_) {
        // NovelAI 未配置或拉取失败，跳过
      }
    }

    // GPT — 列出所有已配置 endpoint 的所有模型，每条带上 endpointId
    final gptEndpoints = await _manageSettings.getEndpoints(ImageProviderType.gpt);
    for (final ep in gptEndpoints) {
      for (final m in ep.models) {
        options.add(ImageModelOption(
          modelId: 'gpt:${ep.id}:$m',
          displayName: m,
          provider: ImageProviderType.gpt,
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
        ));
      }
    }

    // Nano Banana — 同上
    final nanoEndpoints = await _manageSettings.getEndpoints(ImageProviderType.nanoBanana);
    for (final ep in nanoEndpoints) {
      for (final m in ep.models) {
        options.add(ImageModelOption(
          modelId: 'nano:${ep.id}:$m',
          displayName: m,
          provider: ImageProviderType.nanoBanana,
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
        ));
      }
    }

    imageModelOptions = options;
    // 去重：DropdownButton 要求 value 唯一
    final seen = <String>{};
    imageModelOptions = imageModelOptions.where((opt) => seen.add(opt.modelId)).toList();

    if (selectedModel.isNotEmpty && !imageModelOptions.any((opt) => opt.modelId == selectedModel)) {
      selectedModel = imageModelOptions.isNotEmpty ? imageModelOptions.first.modelId : '';
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
        _characters = [..._characters, const CharacterSpec(
          prompt: '', uc: null, centerX: 0.5, centerY: 0.5,
        )];
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
        await updateInpaintNegativePrompt(append && inpaintNegativePrompt.isNotEmpty
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
      characters = [...characters, const CharacterSpec(
        prompt: '', uc: null, centerX: 0.5, centerY: 0.5,
      )];
    }
    updateCharacter(index, characters[index].copyWith(prompt: value.trim()));
  }

  /// 替换指定角色的负向（uc）
  void replaceCharacterNegative(int index, String value) {
    if (index < 0) return;
    while (characters.length <= index) {
      characters = [...characters, const CharacterSpec(
        prompt: '', uc: null, centerX: 0.5, centerY: 0.5,
      )];
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
    final opt = imageModelOptions
        .where((o) => o.modelId == value)
        .toList();
    if (opt.isNotEmpty && opt.first.endpointId != null) {
      await _manageSettings.setActiveEndpointId(opt.first.provider, opt.first.endpointId);
    }
    await _ensureResolutionForCurrentProvider();
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
    await _manageSettings.setSelectedSamplerDraft(value);
    notifyListeners();
  }

  Future<void> updateSelectedNoiseSchedule(String value) async {
    selectedNoiseSchedule = value;
    await _manageSettings.setSelectedNoiseScheduleDraft(value);
    notifyListeners();
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
    if (gptImagePaths.length >= 16) return;
    gptImagePaths = [...gptImagePaths, path];
    notifyListeners();
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

  void updateInpaintStrength(double value) {
    inpaintStrength = value;
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
    } finally {
      _generateInFlight = false;
      _batchRemaining = 0;
      _cancelBatch = false;
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
    final effectivePrompt = generationMode == GenerationMode.inpainting ? inpaintPrompt : prompt;
    final effectiveNegativePrompt = generationMode == GenerationMode.inpainting ? inpaintNegativePrompt : negativePrompt;

    if (effectivePrompt.isEmpty) {
      errorMessage = '请输入提示词';
      notifyListeners();
      return;
    }

    final res = _parseResolution(selectedResolution);
    final enabledCharacters = characters.where((c) => c.enabled).toList();

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
    final actualModelId = _resolveActualModelId(selectedModel);
    final provider = currentProvider;

    final task = GenerationTask(
      taskId: const Uuid().v4(),
      model: actualModelId,
      prompt: effectivePrompt,
      negativePrompt: (provider == ImageProviderType.gpt || provider == ImageProviderType.nanoBanana || effectiveNegativePrompt.isEmpty) ? null : effectiveNegativePrompt,
      width: res.$1,
      height: res.$2,
      size: selectedResolution,
      scale: scale,
      cfgRescale: cfgRescale,
      sampler: selectedSampler,
      noiseSchedule: selectedNoiseSchedule,
      seed: seed,
      characters: generationMode == GenerationMode.textToImage && enabledCharacters.isNotEmpty ? enabledCharacters : null,
      status: 'pending',
      createdAt: DateTime.now(),
      mode: generationMode,
      sourceImagePath: generationMode == GenerationMode.inpainting
          ? sourceImagePath
          : null,
      maskImagePath: maskImagePath,
      gptImagePaths: (provider == ImageProviderType.gpt || provider == ImageProviderType.nanoBanana) && gptImagePaths.isNotEmpty
          ? gptImagePaths
          : null,
      nanoImageSize: provider == ImageProviderType.nanoBanana ? selectedNanoImageSize : null,
      inpaintStrength: generationMode == GenerationMode.inpainting ? inpaintStrength : null,
      responseFormat: generationMode == GenerationMode.inpainting ? 'url' : null,
      providerType: provider,
    );

    errorMessage = null;
    // 重置批次结果区
    sessionResults = [];
    selectedResultTaskId = null;
    _userPickedResult = false;
    final count = batchCount.clamp(1, 15);
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
          await BackgroundKeepAliveService.instance.updateNotification('批量生成 ${i + 1}/$count');
        }
        // 先订阅再 enqueue，避免任务完成事件早于订阅丢失
        final waitFuture = _awaitTaskComplete(taskI.taskId);
        await _generateImage.execute(_queue, taskI);
        await waitFuture;
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

  /// 监听队列直到指定 taskId 进入 success/failed
  Future<void> _awaitTaskComplete(String taskId) async {
    final completer = Completer<void>();
    StreamSubscription? sub;
    sub = _queue.taskStream.listen((t) {
      if (t.taskId != taskId) return;
      if (t.status == AppConstants.taskSuccess || t.status == AppConstants.taskFailed) {
        if (!completer.isCompleted) completer.complete();
        sub?.cancel();
      }
    });
    return completer.future;
  }

  Future<void> updateBatchCount(int value) async {
    final v = value.clamp(1, 15);
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

  Future<void> _saveCharactersDraft() => _manageSettings.setCharactersDraft(characters);

  void addCharacter() {
    if (characters.length >= 6) {
      errorMessage = '最多支持 6 个角色';
      notifyListeners();
      return;
    }

    characters = [...characters, const CharacterSpec(
      prompt: '',
      centerX: 0.5,
      centerY: 0.5,
    )];
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
    updateCharacter(index, characters[index].copyWith(enabled: !characters[index].enabled));
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
    // 优先在已加载的 imageModelOptions 中找匹配的 endpoint+model 组合
    String? matched;
    for (final opt in imageModelOptions) {
      if (opt.provider != task.providerType) continue;
      if (_resolveActualModelId(opt.modelId) == task.model) {
        matched = opt.modelId;
        break;
      }
    }
    selectedModel = matched ?? switch (task.providerType) {
      ImageProviderType.gpt => 'gpt:${task.model}',
      ImageProviderType.nanoBanana => 'nano:${task.model}',
      ImageProviderType.novelAi => task.model,
    };
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
      await _manageSettings.setInpaintNegativePromptDraft(inpaintNegativePrompt);
    } else {
      generationMode = GenerationMode.textToImage;
      prompt = task.prompt;
      negativePrompt = task.negativePrompt ?? '';
      characters = task.characters ?? [];
      await _manageSettings.setPromptDraft(prompt);
      await _manageSettings.setNegativePromptDraft(negativePrompt);
      await _saveCharactersDraft();
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
    return selectedModelId;
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _taskSub?.cancel();
    super.dispose();
  }
}
