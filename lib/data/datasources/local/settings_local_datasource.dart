import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/llm_profile_role.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_role_binding.dart';

class SettingsLocalDatasource {
  final SharedPreferences _prefs;

  SettingsLocalDatasource(this._prefs);

  // API Key
  Future<String?> getApiKey() async => _prefs.getString(AppConstants.keyApiKey);
  Future<void> setApiKey(String key) async =>
      _prefs.setString(AppConstants.keyApiKey, key);
  Future<void> deleteApiKey() async => _prefs.remove(AppConstants.keyApiKey);

  // Base URL
  String getBaseUrl() =>
      _prefs.getString(AppConstants.keyBaseUrl) ?? ApiConstants.defaultBaseUrl;
  Future<void> setBaseUrl(String url) async =>
      _prefs.setString(AppConstants.keyBaseUrl, url);

  // Default Model
  Future<String?> getDefaultModel() async =>
      _prefs.getString(AppConstants.keyDefaultModel);
  Future<void> setDefaultModel(String model) async =>
      _prefs.setString(AppConstants.keyDefaultModel, model);

  // Default Resolution
  String getDefaultResolution() =>
      _prefs.getString(AppConstants.keyDefaultResolution) ??
      ApiConstants.defaultResolution;
  Future<void> setDefaultResolution(String r) async =>
      _prefs.setString(AppConstants.keyDefaultResolution, r);

  // Default Sampler
  String getDefaultSampler() =>
      _prefs.getString(AppConstants.keyDefaultSampler) ??
      ApiConstants.defaultSampler;
  Future<void> setDefaultSampler(String s) async =>
      _prefs.setString(AppConstants.keyDefaultSampler, s);

  // Default Scale
  double getDefaultScale() =>
      _prefs.getDouble(AppConstants.keyDefaultScale) ??
      ApiConstants.defaultScale;
  Future<void> setDefaultScale(double s) async =>
      _prefs.setDouble(AppConstants.keyDefaultScale, s);

  // Default CFG Rescale
  double getDefaultCfgRescale() =>
      _prefs.getDouble(AppConstants.keyDefaultCfgRescale) ??
      ApiConstants.defaultCfgRescale;
  Future<void> setDefaultCfgRescale(double v) async =>
      _prefs.setDouble(AppConstants.keyDefaultCfgRescale, v);

  // Default Noise Schedule
  String getDefaultNoiseSchedule() =>
      _prefs.getString(AppConstants.keyDefaultNoiseSchedule) ??
      ApiConstants.defaultNoiseSchedule;
  Future<void> setDefaultNoiseSchedule(String s) async =>
      _prefs.setString(AppConstants.keyDefaultNoiseSchedule, s);

  // Default Style Words（每次生图自动拼到 prompt 前面）
  String getDefaultStyleWords() =>
      _prefs.getString(AppConstants.keyDefaultStyleWords) ?? '';
  Future<void> setDefaultStyleWords(String v) async =>
      _prefs.setString(AppConstants.keyDefaultStyleWords, v);

  // Prompt Draft
  String getPromptDraft() =>
      _prefs.getString(AppConstants.keyPromptDraft) ?? '';
  Future<void> setPromptDraft(String value) async =>
      _prefs.setString(AppConstants.keyPromptDraft, value);

  // Negative Prompt Draft
  String getNegativePromptDraft() =>
      _prefs.getString(AppConstants.keyNegativePromptDraft) ?? '';
  Future<void> setNegativePromptDraft(String value) async =>
      _prefs.setString(AppConstants.keyNegativePromptDraft, value);

  String? getSelectedModelDraft() =>
      _prefs.getString(AppConstants.keySelectedModelDraft);
  Future<void> setSelectedModelDraft(String value) async =>
      _prefs.setString(AppConstants.keySelectedModelDraft, value);

  String getSelectedResolutionDraft() =>
      _prefs.getString(AppConstants.keySelectedResolutionDraft) ??
      ApiConstants.defaultResolution;
  Future<void> setSelectedResolutionDraft(String value) async =>
      _prefs.setString(AppConstants.keySelectedResolutionDraft, value);

  String getSelectedSamplerDraft() =>
      _prefs.getString(AppConstants.keySelectedSamplerDraft) ??
      ApiConstants.defaultSampler;
  Future<void> setSelectedSamplerDraft(String value) async =>
      _prefs.setString(AppConstants.keySelectedSamplerDraft, value);

  String getSelectedNoiseScheduleDraft() =>
      _prefs.getString(AppConstants.keySelectedNoiseScheduleDraft) ??
      ApiConstants.defaultNoiseSchedule;
  Future<void> setSelectedNoiseScheduleDraft(String value) async =>
      _prefs.setString(AppConstants.keySelectedNoiseScheduleDraft, value);

  double getScaleDraft() =>
      _prefs.getDouble(AppConstants.keyScaleDraft) ?? ApiConstants.defaultScale;
  Future<void> setScaleDraft(double value) async =>
      _prefs.setDouble(AppConstants.keyScaleDraft, value);

  double getCfgRescaleDraft() =>
      _prefs.getDouble(AppConstants.keyCfgRescaleDraft) ??
      ApiConstants.defaultCfgRescale;
  Future<void> setCfgRescaleDraft(double value) async =>
      _prefs.setDouble(AppConstants.keyCfgRescaleDraft, value);

  int getStepsDraft() => _prefs.getInt(AppConstants.keyStepsDraft) ?? 28;
  Future<void> setStepsDraft(int value) async =>
      _prefs.setInt(AppConstants.keyStepsDraft, value.clamp(1, 50));

  bool getStepsLocked() => _prefs.getBool(AppConstants.keyStepsLocked) ?? false;
  Future<void> setStepsLocked(bool value) async =>
      _prefs.setBool(AppConstants.keyStepsLocked, value);

  List<CharacterSpec> getCharactersDraft() {
    final raw = _prefs.getString(AppConstants.keyCharactersDraft);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => CharacterSpec.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setCharactersDraft(List<CharacterSpec> value) async {
    await _prefs.setString(
      AppConstants.keyCharactersDraft,
      jsonEncode(value.map((c) => c.toJson()).toList()),
    );
  }

  List<CharacterReferenceImage> getVibeReferencesDraft() {
    final raw = _prefs.getString(AppConstants.keyVibeReferencesDraft);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((item) => CharacterReferenceImage.fromJson(
              item as Map<String, dynamic>,
            ))
        .toList();
  }

  Future<void> setVibeReferencesDraft(
    List<CharacterReferenceImage> value,
  ) async {
    await _prefs.setString(
      AppConstants.keyVibeReferencesDraft,
      jsonEncode(value.map((reference) => reference.toJson()).toList()),
    );
  }

  // Inpaint Prompt Draft
  String getInpaintPromptDraft() =>
      _prefs.getString(AppConstants.keyInpaintPromptDraft) ?? '';
  Future<void> setInpaintPromptDraft(String value) async =>
      _prefs.setString(AppConstants.keyInpaintPromptDraft, value);

  // Inpaint Negative Prompt Draft
  String getInpaintNegativePromptDraft() =>
      _prefs.getString(AppConstants.keyInpaintNegativePromptDraft) ?? '';
  Future<void> setInpaintNegativePromptDraft(String value) async =>
      _prefs.setString(AppConstants.keyInpaintNegativePromptDraft, value);

  // LLM 配置
  String? getLlmApiKey() => _prefs.getString(AppConstants.keyLlmApiKey);
  Future<void> setLlmApiKey(String value) async =>
      _prefs.setString(AppConstants.keyLlmApiKey, value);

  String getLlmBaseUrl() => _prefs.getString(AppConstants.keyLlmBaseUrl) ?? '';
  Future<void> setLlmBaseUrl(String value) async =>
      _prefs.setString(AppConstants.keyLlmBaseUrl, value);

  String getLlmModel() => _prefs.getString(AppConstants.keyLlmModel) ?? '';
  Future<void> setLlmModel(String value) async =>
      _prefs.setString(AppConstants.keyLlmModel, value);

  String getLlmSystemPrompt() =>
      _prefs.getString(AppConstants.keyLlmSystemPrompt) ??
      AppConstants.defaultLlmSystemPrompt;
  Future<void> setLlmSystemPrompt(String value) async =>
      _prefs.setString(AppConstants.keyLlmSystemPrompt, value);

  String? getLlmActiveSessionId() =>
      _prefs.getString(AppConstants.keyLlmActiveSessionId);
  Future<void> setLlmActiveSessionId(String? value) async {
    if (value == null) {
      await _prefs.remove(AppConstants.keyLlmActiveSessionId);
    } else {
      await _prefs.setString(AppConstants.keyLlmActiveSessionId, value);
    }
  }

  // LLM 上下文条数
  int getLlmContextLimit() =>
      _prefs.getInt(AppConstants.keyLlmContextLimit) ??
      AppConstants.defaultLlmContextLimit;
  Future<void> setLlmContextLimit(int value) async =>
      _prefs.setInt(AppConstants.keyLlmContextLimit, value);

  // LLM 供应商列表（JSON 字符串，存 List<LlmProvider>）
  List<LlmProvider> getLlmProviders() => LlmProvider.listFromJsonString(
      _prefs.getString(AppConstants.keyLlmProviders));
  Future<void> setLlmProviders(List<LlmProvider> providers) async =>
      _prefs.setString(AppConstants.keyLlmProviders,
          LlmProvider.listToJsonString(providers));

  // LLM 角色绑定（main/vision 各存 LlmRoleBinding JSON）
  LlmRoleBinding getLlmRoleBindingMain() => LlmRoleBinding.fromJsonString(
      _prefs.getString(AppConstants.keyLlmRoleBindingMain));
  Future<void> setLlmRoleBindingMain(LlmRoleBinding b) async =>
      _prefs.setString(AppConstants.keyLlmRoleBindingMain, b.toJsonString());

  LlmRoleBinding getLlmRoleBindingVision() => LlmRoleBinding.fromJsonString(
      _prefs.getString(AppConstants.keyLlmRoleBindingVision));
  Future<void> setLlmRoleBindingVision(LlmRoleBinding b) async =>
      _prefs.setString(AppConstants.keyLlmRoleBindingVision, b.toJsonString());

  /// 旧数据迁移：把旧 3 角色 9 key 配置 + 旧单配置迁成 LlmProvider + LlmRoleBinding。
  /// 幂等，用 llm_provider_migrated_v3 标记位防重复。
  /// 优先迁 2 角色（main/vision），若 2 角色全空则把旧单配置 keyLlmApiKey 迁为 main。
  /// 旧 embedding 角色数据已被弃用，迁移时忽略（不再写入 embedding binding）。
  bool migrateLegacyLlm3RoleToProvider() {
    if (_prefs.getBool('llm_provider_migrated_v3') ?? false) return false;

    final providers = <LlmProvider>[];
    LlmRoleBinding? mainBinding;
    LlmRoleBinding? visionBinding;

    // 旧 3 角色 9 key（注意：3 角色常量已删除，但 SP 中可能仍有旧值，用字符串直接读）
    // embedding 角色已删除，迁移时跳过其旧 key
    const legacyKeys = <(String, String, String, LlmProfileRole)>[
      (
        'llm_main_api_key',
        'llm_main_base_url',
        'llm_main_model',
        LlmProfileRole.main
      ),
      (
        'llm_vision_api_key',
        'llm_vision_base_url',
        'llm_vision_model',
        LlmProfileRole.vision
      ),
    ];

    for (final (apiKeyKey, baseUrlKey, modelKey, role) in legacyKeys) {
      final apiKey = _prefs.getString(apiKeyKey);
      final baseUrl = _prefs.getString(baseUrlKey) ?? '';
      final model = _prefs.getString(modelKey) ?? '';
      if (apiKey == null || apiKey.isEmpty || baseUrl.isEmpty || model.isEmpty)
        continue;

      final provider = LlmProvider.create(
        name: '导入的${role.label}供应商',
        apiKey: apiKey,
        baseUrl: baseUrl,
        models: [model],
      );
      providers.add(provider);
      final binding = LlmRoleBinding(providerId: provider.id, model: model);
      switch (role) {
        case LlmProfileRole.main:
          mainBinding = binding;
          break;
        case LlmProfileRole.vision:
          visionBinding = binding;
          break;
        case LlmProfileRole.aux:
          break;
      }
    }

    // 2) 若 2 角色全空，尝试旧单配置 keyLlmApiKey 迁为 main
    if (providers.isEmpty) {
      final apiKey = _prefs.getString(AppConstants.keyLlmApiKey);
      final baseUrl = _prefs.getString(AppConstants.keyLlmBaseUrl) ?? '';
      final model = _prefs.getString(AppConstants.keyLlmModel) ?? '';
      if (apiKey != null &&
          apiKey.isNotEmpty &&
          baseUrl.isNotEmpty &&
          model.isNotEmpty) {
        final provider = LlmProvider.create(
          name: '导入的主模型供应商',
          apiKey: apiKey,
          baseUrl: baseUrl,
          models: [model],
        );
        providers.add(provider);
        mainBinding = LlmRoleBinding(providerId: provider.id, model: model);
      }
    }

    if (providers.isNotEmpty) {
      _prefs.setString(AppConstants.keyLlmProviders,
          LlmProvider.listToJsonString(providers));
      if (mainBinding != null) {
        _prefs.setString(
            AppConstants.keyLlmRoleBindingMain, mainBinding.toJsonString());
      }
      if (visionBinding != null) {
        _prefs.setString(
            AppConstants.keyLlmRoleBindingVision, visionBinding.toJsonString());
      }
    }

    _prefs.setBool('llm_provider_migrated_v3', true);
    return true;
  }

  // 知识库
  String? getNsfwBookPath() => _prefs.getString(AppConstants.keyNsfwBookPath);
  Future<void> setNsfwBookPath(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(AppConstants.keyNsfwBookPath);
    } else {
      await _prefs.setString(AppConstants.keyNsfwBookPath, value);
    }
  }

  // 联网搜索开关（持久化，避免每次离开聊天关闭）
  bool getWebSearchEnabled() =>
      _prefs.getBool(AppConstants.keyWebSearchEnabled) ?? false;
  Future<void> setWebSearchEnabled(bool value) async =>
      _prefs.setBool(AppConstants.keyWebSearchEnabled, value);

  // Danbooru 校准（默认启用）
  bool getDanbooruCalibrationEnabled() =>
      _prefs.getBool(AppConstants.keyDanbooruCalibrationEnabled) ?? true;
  Future<void> setDanbooruCalibrationEnabled(bool value) async =>
      _prefs.setBool(AppConstants.keyDanbooruCalibrationEnabled, value);

  String getDanbooruBaseUrl() =>
      _prefs.getString(AppConstants.keyDanbooruBaseUrl) ?? '';
  Future<void> setDanbooruBaseUrl(String value) async {
    if (value.trim().isEmpty) {
      await _prefs.remove(AppConstants.keyDanbooruBaseUrl);
    } else {
      await _prefs.setString(AppConstants.keyDanbooruBaseUrl, value.trim());
    }
  }

  // 图像 API 供应商配置 — NovelAI
  String getImageProviderNovelAiBaseUrl() =>
      _prefs.getString(AppConstants.keyImageProviderNovelAiBaseUrl) ?? '';
  Future<void> setImageProviderNovelAiBaseUrl(String value) async =>
      _prefs.setString(AppConstants.keyImageProviderNovelAiBaseUrl, value);

  String? getImageProviderNovelAiApiKey() =>
      _prefs.getString(AppConstants.keyImageProviderNovelAiApiKey);
  Future<void> setImageProviderNovelAiApiKey(String value) async =>
      _prefs.setString(AppConstants.keyImageProviderNovelAiApiKey, value);

  String getImageProviderNovelAiModel() =>
      _prefs.getString(AppConstants.keyImageProviderNovelAiModel) ?? '';
  Future<void> setImageProviderNovelAiModel(String value) async =>
      _prefs.setString(AppConstants.keyImageProviderNovelAiModel, value);

  // 图像 API 供应商配置 — GPT
  String getImageProviderGptBaseUrl() =>
      _prefs.getString(AppConstants.keyImageProviderGptBaseUrl) ?? '';
  Future<void> setImageProviderGptBaseUrl(String value) async =>
      _prefs.setString(AppConstants.keyImageProviderGptBaseUrl, value);

  String? getImageProviderGptApiKey() =>
      _prefs.getString(AppConstants.keyImageProviderGptApiKey);
  Future<void> setImageProviderGptApiKey(String value) async =>
      _prefs.setString(AppConstants.keyImageProviderGptApiKey, value);

  String getImageProviderGptModel() =>
      _prefs.getString(AppConstants.keyImageProviderGptModel) ?? '';
  Future<void> setImageProviderGptModel(String value) async =>
      _prefs.setString(AppConstants.keyImageProviderGptModel, value);

  // 图像 API 供应商配置 — Nano Banana
  String getImageProviderNanoBaseUrl() =>
      _prefs.getString(AppConstants.keyImageProviderNanoBaseUrl) ?? '';
  Future<void> setImageProviderNanoBaseUrl(String value) async =>
      _prefs.setString(AppConstants.keyImageProviderNanoBaseUrl, value);

  String? getImageProviderNanoApiKey() =>
      _prefs.getString(AppConstants.keyImageProviderNanoApiKey);
  Future<void> setImageProviderNanoApiKey(String value) async =>
      _prefs.setString(AppConstants.keyImageProviderNanoApiKey, value);

  String getImageProviderNanoModel() =>
      _prefs.getString(AppConstants.keyImageProviderNanoModel) ?? '';
  Future<void> setImageProviderNanoModel(String value) async =>
      _prefs.setString(AppConstants.keyImageProviderNanoModel, value);

  // ===== 图像 API 供应商 v2 多中转站结构 =====
  ({String endpoints, String activeId, String activeModel}) _keysFor(
      ImageProviderType p) {
    switch (p) {
      case ImageProviderType.novelAi:
        return (
          endpoints: AppConstants.keyImageProviderNovelAiEndpoints,
          activeId: AppConstants.keyImageProviderNovelAiActiveEndpointId,
          activeModel: AppConstants.keyImageProviderNovelAiActiveModel,
        );
      case ImageProviderType.gpt:
        return (
          endpoints: AppConstants.keyImageProviderGptEndpoints,
          activeId: AppConstants.keyImageProviderGptActiveEndpointId,
          activeModel: AppConstants.keyImageProviderGptActiveModel,
        );
      case ImageProviderType.nanoBanana:
        return (
          endpoints: AppConstants.keyImageProviderNanoEndpoints,
          activeId: AppConstants.keyImageProviderNanoActiveEndpointId,
          activeModel: AppConstants.keyImageProviderNanoActiveModel,
        );
    }
  }

  /// 读取某个 provider 的中转站列表。
  /// NovelAI 固定保留 7877 与 ikun 两个槽位，并将既有 active（或首个）端点迁入 7877。
  /// 其他 provider 保持旧有的可变中转站行为。
  List<ApiEndpoint> getEndpoints(ImageProviderType p) {
    final keys = _keysFor(p);
    final raw = _prefs.getString(keys.endpoints);
    List<ApiEndpoint> endpoints = const [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        endpoints = list
            .map((e) => ApiEndpoint.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        endpoints = const [];
      }
    }

    if (p == ImageProviderType.novelAi) {
      final fixedEndpoints = _normalizeNovelAiEndpoints(endpoints);
      if (!_sameEndpoints(endpoints, fixedEndpoints)) {
        _prefs.setString(
          keys.endpoints,
          jsonEncode(fixedEndpoints.map((e) => e.toJson()).toList()),
        );
        _prefs.setString(
            keys.activeId, AppConstants.novelAiChatCompletionsEndpointId);
        final chatEndpoint = fixedEndpoints.first;
        if (chatEndpoint.models.isNotEmpty) {
          _prefs.setString(keys.activeModel, chatEndpoint.models.first);
        } else {
          _prefs.remove(keys.activeModel);
        }
      }
      return fixedEndpoints;
    }

    if (endpoints.isNotEmpty) return endpoints;

    final migrated = _migrateLegacy(p);
    if (migrated != null) {
      _prefs.setString(keys.endpoints, jsonEncode([migrated.toJson()]));
      _prefs.setString(keys.activeId, migrated.id);
      if (migrated.models.isNotEmpty) {
        _prefs.setString(keys.activeModel, migrated.models.first);
      }
      return [migrated];
    }
    return [];
  }

  List<ApiEndpoint> _normalizeNovelAiEndpoints(List<ApiEndpoint> endpoints) {
    ApiEndpoint? oldChat;
    if (endpoints.isNotEmpty) {
      final activeId = _prefs
          .getString(AppConstants.keyImageProviderNovelAiActiveEndpointId);
      final active = endpoints.where((endpoint) => endpoint.id == activeId);
      oldChat = active.isNotEmpty ? active.first : endpoints.first;
    } else {
      oldChat = _migrateLegacy(ImageProviderType.novelAi);
    }

    final chats = endpoints.where((endpoint) =>
        endpoint.id == AppConstants.novelAiChatCompletionsEndpointId);
    final images = endpoints.where((endpoint) =>
        endpoint.id == AppConstants.novelAiImageGenerationsEndpointId);
    final existingChat = chats.isNotEmpty ? chats.first : null;
    final existingImage = images.isNotEmpty ? images.first : null;
    final chatSource = existingChat ?? oldChat;

    return [
      ApiEndpoint(
        id: AppConstants.novelAiChatCompletionsEndpointId,
        name: chatSource?.name.isNotEmpty == true ? chatSource!.name : '7877',
        protocol: AppConstants.novelAiChatCompletionsProtocol,
        baseUrl: chatSource?.baseUrl ?? '',
        apiKey: chatSource?.apiKey ?? '',
        models: chatSource?.models ?? const [],
      ),
      ApiEndpoint(
        id: AppConstants.novelAiImageGenerationsEndpointId,
        name: existingImage?.name.isNotEmpty == true
            ? existingImage!.name
            : 'ikun',
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        baseUrl: existingImage?.baseUrl ?? '',
        apiKey: existingImage?.apiKey ?? '',
        models: existingImage?.models ?? const [],
      ),
    ];
  }

  bool _sameEndpoints(List<ApiEndpoint> a, List<ApiEndpoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  ApiEndpoint? _migrateLegacy(ImageProviderType p) {
    String oldUrl;
    String? oldKey;
    String oldModel;
    switch (p) {
      case ImageProviderType.novelAi:
        oldUrl = getImageProviderNovelAiBaseUrl();
        oldKey = getImageProviderNovelAiApiKey();
        oldModel = getImageProviderNovelAiModel();
        break;
      case ImageProviderType.gpt:
        oldUrl = getImageProviderGptBaseUrl();
        oldKey = getImageProviderGptApiKey();
        oldModel = getImageProviderGptModel();
        break;
      case ImageProviderType.nanoBanana:
        oldUrl = getImageProviderNanoBaseUrl();
        oldKey = getImageProviderNanoApiKey();
        oldModel = getImageProviderNanoModel();
        break;
    }
    if (oldUrl.isEmpty &&
        (oldKey == null || oldKey.isEmpty) &&
        oldModel.isEmpty) {
      return null;
    }
    return ApiEndpoint(
      id: 'legacy_${p.name}_${DateTime.now().millisecondsSinceEpoch}',
      name: '默认',
      baseUrl: oldUrl,
      apiKey: oldKey ?? '',
      models: oldModel.isEmpty ? const [] : [oldModel],
    );
  }

  Future<void> setEndpoints(ImageProviderType p, List<ApiEndpoint> list) async {
    final keys = _keysFor(p);
    await _prefs.setString(
      keys.endpoints,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  String? getActiveEndpointId(ImageProviderType p) =>
      _prefs.getString(_keysFor(p).activeId);
  Future<void> setActiveEndpointId(ImageProviderType p, String? id) async {
    final key = _keysFor(p).activeId;
    if (id == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, id);
    }
  }

  String? getActiveModel(ImageProviderType p) =>
      _prefs.getString(_keysFor(p).activeModel);
  Future<void> setActiveModel(ImageProviderType p, String? model) async {
    final key = _keysFor(p).activeModel;
    if (model == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, model);
    }
  }

  /// 取当前 active 中转站；若没有 active，回退到列表第一个；都没有返回 null
  ApiEndpoint? getActiveEndpoint(ImageProviderType p) {
    final list = getEndpoints(p);
    if (list.isEmpty) return null;
    final activeId = getActiveEndpointId(p);
    if (activeId != null) {
      try {
        return list.firstWhere((e) => e.id == activeId);
      } catch (_) {/* fall through */}
    }
    return list.first;
  }

  // 批量生成数量
  int getBatchCount() => _prefs.getInt(AppConstants.keyBatchCount) ?? 1;
  Future<void> setBatchCount(int value) async {
    final clamped = value.clamp(1, 15);
    await _prefs.setInt(AppConstants.keyBatchCount, clamped);
  }
}
