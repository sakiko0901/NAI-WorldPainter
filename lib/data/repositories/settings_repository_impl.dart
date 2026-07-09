import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/llm_profile_role.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_role_binding.dart';
import 'package:nai_huishi/domain/repositories/settings_repository.dart';
import 'package:nai_huishi/data/datasources/local/settings_local_datasource.dart';
import 'package:nai_huishi/data/datasources/remote/novelai_api_service.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SettingsLocalDatasource _local;
  NovelAiApiService? _apiService;

  SettingsRepositoryImpl(this._local);

  void setApiService(NovelAiApiService service) {
    _apiService = service;
  }

  @override
  Future<String?> getApiKey() => _local.getApiKey();

  @override
  Future<void> setApiKey(String key) => _local.setApiKey(key);

  @override
  Future<void> deleteApiKey() => _local.deleteApiKey();

  @override
  Future<String> getBaseUrl() async => _local.getBaseUrl();

  @override
  Future<void> setBaseUrl(String url) => _local.setBaseUrl(url);

  @override
  Future<String?> getDefaultModel() => _local.getDefaultModel();

  @override
  Future<void> setDefaultModel(String model) => _local.setDefaultModel(model);

  @override
  Future<String> getDefaultResolution() async => _local.getDefaultResolution();

  @override
  Future<void> setDefaultResolution(String r) => _local.setDefaultResolution(r);

  @override
  Future<String> getDefaultSampler() async => _local.getDefaultSampler();

  @override
  Future<void> setDefaultSampler(String s) => _local.setDefaultSampler(s);

  @override
  Future<double> getDefaultScale() async => _local.getDefaultScale();

  @override
  Future<void> setDefaultScale(double s) => _local.setDefaultScale(s);

  @override
  Future<double> getDefaultCfgRescale() async => _local.getDefaultCfgRescale();

  @override
  Future<void> setDefaultCfgRescale(double v) => _local.setDefaultCfgRescale(v);

  @override
  Future<String> getDefaultNoiseSchedule() async => _local.getDefaultNoiseSchedule();

  @override
  Future<void> setDefaultNoiseSchedule(String s) => _local.setDefaultNoiseSchedule(s);

  @override
  Future<String> getDefaultStyleWords() async => _local.getDefaultStyleWords();

  @override
  Future<void> setDefaultStyleWords(String v) => _local.setDefaultStyleWords(v);

  @override
  Future<String> getPromptDraft() async => _local.getPromptDraft();

  @override
  Future<void> setPromptDraft(String value) => _local.setPromptDraft(value);

  @override
  Future<String> getNegativePromptDraft() async => _local.getNegativePromptDraft();

  @override
  Future<void> setNegativePromptDraft(String value) => _local.setNegativePromptDraft(value);

  @override
  Future<String?> getSelectedModelDraft() async => _local.getSelectedModelDraft();

  @override
  Future<void> setSelectedModelDraft(String value) => _local.setSelectedModelDraft(value);

  @override
  Future<String> getSelectedResolutionDraft() async => _local.getSelectedResolutionDraft();

  @override
  Future<void> setSelectedResolutionDraft(String value) => _local.setSelectedResolutionDraft(value);

  @override
  Future<String> getSelectedSamplerDraft() async => _local.getSelectedSamplerDraft();

  @override
  Future<void> setSelectedSamplerDraft(String value) => _local.setSelectedSamplerDraft(value);

  @override
  Future<String> getSelectedNoiseScheduleDraft() async => _local.getSelectedNoiseScheduleDraft();

  @override
  Future<void> setSelectedNoiseScheduleDraft(String value) => _local.setSelectedNoiseScheduleDraft(value);

  @override
  Future<double> getScaleDraft() async => _local.getScaleDraft();

  @override
  Future<void> setScaleDraft(double value) => _local.setScaleDraft(value);

  @override
  Future<double> getCfgRescaleDraft() async => _local.getCfgRescaleDraft();

  @override
  Future<void> setCfgRescaleDraft(double value) => _local.setCfgRescaleDraft(value);

  @override
  Future<List<CharacterSpec>> getCharactersDraft() async => _local.getCharactersDraft();

  @override
  Future<void> setCharactersDraft(List<CharacterSpec> value) => _local.setCharactersDraft(value);

  @override
  Future<String> getInpaintPromptDraft() async => _local.getInpaintPromptDraft();

  @override
  Future<void> setInpaintPromptDraft(String value) => _local.setInpaintPromptDraft(value);

  @override
  Future<String> getInpaintNegativePromptDraft() async => _local.getInpaintNegativePromptDraft();

  @override
  Future<void> setInpaintNegativePromptDraft(String value) => _local.setInpaintNegativePromptDraft(value);

  @override
  Future<String?> getLlmApiKey() async => _local.getLlmApiKey();

  @override
  Future<void> setLlmApiKey(String value) => _local.setLlmApiKey(value);

  @override
  Future<String> getLlmBaseUrl() async => _local.getLlmBaseUrl();

  @override
  Future<void> setLlmBaseUrl(String value) => _local.setLlmBaseUrl(value);

  @override
  Future<String> getLlmModel() async => _local.getLlmModel();

  @override
  Future<void> setLlmModel(String value) => _local.setLlmModel(value);

  @override
  Future<String> getLlmSystemPrompt() async => _local.getLlmSystemPrompt();

  @override
  Future<void> setLlmSystemPrompt(String value) => _local.setLlmSystemPrompt(value);

  @override
  Future<String?> getLlmActiveSessionId() async => _local.getLlmActiveSessionId();

  @override
  Future<void> setLlmActiveSessionId(String? value) => _local.setLlmActiveSessionId(value);

  // LLM 上下文条数
  @override
  Future<int> getLlmContextLimit() async => _local.getLlmContextLimit();

  @override
  Future<void> setLlmContextLimit(int value) => _local.setLlmContextLimit(value);

  // LLM 供应商列表
  @override
  Future<List<LlmProvider>> getLlmProviders() async => _local.getLlmProviders();

  @override
  Future<void> saveLlmProviders(List<LlmProvider> providers) =>
      _local.setLlmProviders(providers);

  // LLM 角色绑定
  @override
  Future<LlmRoleBinding> getLlmRoleBinding(LlmProfileRole role) async {
    switch (role) {
      case LlmProfileRole.main:
        return _local.getLlmRoleBindingMain();
      case LlmProfileRole.vision:
        return _local.getLlmRoleBindingVision();
      case LlmProfileRole.aux:
        return const LlmRoleBinding();
    }
  }

  @override
  Future<void> setLlmRoleBinding(LlmProfileRole role, LlmRoleBinding binding) async {
    switch (role) {
      case LlmProfileRole.main:
        await _local.setLlmRoleBindingMain(binding);
        break;
      case LlmProfileRole.vision:
        await _local.setLlmRoleBindingVision(binding);
        break;
      case LlmProfileRole.aux:
        break;
    }
  }

  @override
  bool migrateLegacyLlm3RoleToProvider() => _local.migrateLegacyLlm3RoleToProvider();

  @override
  Future<bool> testConnection() async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) return false;
    final baseUrl = await getBaseUrl();
    if (_apiService == null) return false;
    return _apiService!.testConnection(apiKey, baseUrl);
  }

  // 知识库
  @override
  Future<String?> getNsfwBookPath() async => _local.getNsfwBookPath();
  @override
  Future<void> setNsfwBookPath(String? value) => _local.setNsfwBookPath(value);

  // 联网搜索开关
  @override
  Future<bool> getWebSearchEnabled() async => _local.getWebSearchEnabled();
  @override
  Future<void> setWebSearchEnabled(bool value) => _local.setWebSearchEnabled(value);

  // Danbooru 智能校准
  @override
  Future<bool> getDanbooruCalibrationEnabled() async =>
      _local.getDanbooruCalibrationEnabled();
  @override
  Future<void> setDanbooruCalibrationEnabled(bool value) =>
      _local.setDanbooruCalibrationEnabled(value);

  @override
  Future<String> getDanbooruBaseUrl() async => _local.getDanbooruBaseUrl();
  @override
  Future<void> setDanbooruBaseUrl(String value) => _local.setDanbooruBaseUrl(value);

  // 图像 API 供应商配置 — NovelAI
  @override
  Future<String> getImageProviderNovelAiBaseUrl() async => _local.getImageProviderNovelAiBaseUrl();
  @override
  Future<void> setImageProviderNovelAiBaseUrl(String value) => _local.setImageProviderNovelAiBaseUrl(value);
  @override
  Future<String?> getImageProviderNovelAiApiKey() async => _local.getImageProviderNovelAiApiKey();
  @override
  Future<void> setImageProviderNovelAiApiKey(String value) => _local.setImageProviderNovelAiApiKey(value);
  @override
  Future<String> getImageProviderNovelAiModel() async => _local.getImageProviderNovelAiModel();
  @override
  Future<void> setImageProviderNovelAiModel(String value) => _local.setImageProviderNovelAiModel(value);

  // 图像 API 供应商配置 — GPT
  @override
  Future<String> getImageProviderGptBaseUrl() async => _local.getImageProviderGptBaseUrl();
  @override
  Future<void> setImageProviderGptBaseUrl(String value) => _local.setImageProviderGptBaseUrl(value);
  @override
  Future<String?> getImageProviderGptApiKey() async => _local.getImageProviderGptApiKey();
  @override
  Future<void> setImageProviderGptApiKey(String value) => _local.setImageProviderGptApiKey(value);
  @override
  Future<String> getImageProviderGptModel() async => _local.getImageProviderGptModel();
  @override
  Future<void> setImageProviderGptModel(String value) => _local.setImageProviderGptModel(value);

  // 图像 API 供应商配置 — Nano Banana
  @override
  Future<String> getImageProviderNanoBaseUrl() async => _local.getImageProviderNanoBaseUrl();
  @override
  Future<void> setImageProviderNanoBaseUrl(String value) => _local.setImageProviderNanoBaseUrl(value);
  @override
  Future<String?> getImageProviderNanoApiKey() async => _local.getImageProviderNanoApiKey();
  @override
  Future<void> setImageProviderNanoApiKey(String value) => _local.setImageProviderNanoApiKey(value);
  @override
  Future<String> getImageProviderNanoModel() async => _local.getImageProviderNanoModel();
  @override
  Future<void> setImageProviderNanoModel(String value) => _local.setImageProviderNanoModel(value);

  // ===== 图像 API 供应商 v2 多中转站 =====
  @override
  Future<List<ApiEndpoint>> getEndpoints(ImageProviderType p) async => _local.getEndpoints(p);
  @override
  Future<void> setEndpoints(ImageProviderType p, List<ApiEndpoint> list) =>
      _local.setEndpoints(p, list);
  @override
  Future<String?> getActiveEndpointId(ImageProviderType p) async => _local.getActiveEndpointId(p);
  @override
  Future<void> setActiveEndpointId(ImageProviderType p, String? id) =>
      _local.setActiveEndpointId(p, id);
  @override
  Future<String?> getActiveModel(ImageProviderType p) async => _local.getActiveModel(p);
  @override
  Future<void> setActiveModel(ImageProviderType p, String? model) =>
      _local.setActiveModel(p, model);
  @override
  Future<ApiEndpoint?> getActiveEndpoint(ImageProviderType p) async =>
      _local.getActiveEndpoint(p);

  // ===== 批量生成 =====
  @override
  Future<int> getBatchCount() async => _local.getBatchCount();
  @override
  Future<void> setBatchCount(int value) => _local.setBatchCount(value);
}
