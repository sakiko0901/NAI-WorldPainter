import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/llm_profile_role.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_role_binding.dart';
import 'package:nai_huishi/domain/repositories/settings_repository.dart';

class ManageSettingsUseCase {
  final SettingsRepository _repo;

  ManageSettingsUseCase(this._repo);

  Future<String?> getApiKey() => _repo.getApiKey();
  Future<void> setApiKey(String key) => _repo.setApiKey(key);
  Future<void> deleteApiKey() => _repo.deleteApiKey();

  Future<String> getBaseUrl() => _repo.getBaseUrl();
  Future<void> setBaseUrl(String url) => _repo.setBaseUrl(url);

  Future<String?> getDefaultModel() => _repo.getDefaultModel();
  Future<void> setDefaultModel(String model) => _repo.setDefaultModel(model);

  Future<String> getDefaultResolution() => _repo.getDefaultResolution();
  Future<void> setDefaultResolution(String r) => _repo.setDefaultResolution(r);

  Future<String> getDefaultSampler() => _repo.getDefaultSampler();
  Future<void> setDefaultSampler(String s) => _repo.setDefaultSampler(s);

  Future<double> getDefaultScale() => _repo.getDefaultScale();
  Future<void> setDefaultScale(double s) => _repo.setDefaultScale(s);

  Future<double> getDefaultCfgRescale() => _repo.getDefaultCfgRescale();
  Future<void> setDefaultCfgRescale(double v) => _repo.setDefaultCfgRescale(v);

  Future<String> getDefaultNoiseSchedule() => _repo.getDefaultNoiseSchedule();
  Future<void> setDefaultNoiseSchedule(String s) =>
      _repo.setDefaultNoiseSchedule(s);

  Future<String> getDefaultStyleWords() => _repo.getDefaultStyleWords();
  Future<void> setDefaultStyleWords(String v) => _repo.setDefaultStyleWords(v);

  Future<String> getPromptDraft() => _repo.getPromptDraft();
  Future<void> setPromptDraft(String value) => _repo.setPromptDraft(value);

  Future<String> getNegativePromptDraft() => _repo.getNegativePromptDraft();
  Future<void> setNegativePromptDraft(String value) =>
      _repo.setNegativePromptDraft(value);

  Future<String?> getSelectedModelDraft() => _repo.getSelectedModelDraft();
  Future<void> setSelectedModelDraft(String value) =>
      _repo.setSelectedModelDraft(value);

  Future<String> getSelectedResolutionDraft() =>
      _repo.getSelectedResolutionDraft();
  Future<void> setSelectedResolutionDraft(String value) =>
      _repo.setSelectedResolutionDraft(value);

  Future<String> getSelectedSamplerDraft() => _repo.getSelectedSamplerDraft();
  Future<void> setSelectedSamplerDraft(String value) =>
      _repo.setSelectedSamplerDraft(value);

  Future<String> getSelectedNoiseScheduleDraft() =>
      _repo.getSelectedNoiseScheduleDraft();
  Future<void> setSelectedNoiseScheduleDraft(String value) =>
      _repo.setSelectedNoiseScheduleDraft(value);

  Future<double> getScaleDraft() => _repo.getScaleDraft();
  Future<void> setScaleDraft(double value) => _repo.setScaleDraft(value);

  Future<double> getCfgRescaleDraft() => _repo.getCfgRescaleDraft();
  Future<void> setCfgRescaleDraft(double value) =>
      _repo.setCfgRescaleDraft(value);

  Future<int> getStepsDraft() => _repo.getStepsDraft();
  Future<void> setStepsDraft(int value) => _repo.setStepsDraft(value);

  Future<bool> getStepsLocked() => _repo.getStepsLocked();
  Future<void> setStepsLocked(bool value) => _repo.setStepsLocked(value);

  Future<List<CharacterSpec>> getCharactersDraft() =>
      _repo.getCharactersDraft();
  Future<void> setCharactersDraft(List<CharacterSpec> value) =>
      _repo.setCharactersDraft(value);
  Future<List<CharacterReferenceImage>> getVibeReferencesDraft() =>
      _repo.getVibeReferencesDraft();
  Future<void> setVibeReferencesDraft(List<CharacterReferenceImage> value) =>
      _repo.setVibeReferencesDraft(value);

  Future<String> getInpaintPromptDraft() => _repo.getInpaintPromptDraft();
  Future<void> setInpaintPromptDraft(String value) =>
      _repo.setInpaintPromptDraft(value);

  Future<String> getInpaintNegativePromptDraft() =>
      _repo.getInpaintNegativePromptDraft();
  Future<void> setInpaintNegativePromptDraft(String value) =>
      _repo.setInpaintNegativePromptDraft(value);

  Future<String?> getLlmApiKey() => _repo.getLlmApiKey();
  Future<void> setLlmApiKey(String value) => _repo.setLlmApiKey(value);

  Future<String> getLlmBaseUrl() => _repo.getLlmBaseUrl();
  Future<void> setLlmBaseUrl(String value) => _repo.setLlmBaseUrl(value);

  Future<String> getLlmModel() => _repo.getLlmModel();
  Future<void> setLlmModel(String value) => _repo.setLlmModel(value);

  Future<String> getLlmSystemPrompt() => _repo.getLlmSystemPrompt();
  Future<void> setLlmSystemPrompt(String value) =>
      _repo.setLlmSystemPrompt(value);

  Future<String?> getLlmActiveSessionId() => _repo.getLlmActiveSessionId();
  Future<void> setLlmActiveSessionId(String? value) =>
      _repo.setLlmActiveSessionId(value);

  Future<int> getLlmContextLimit() => _repo.getLlmContextLimit();
  Future<void> setLlmContextLimit(int value) => _repo.setLlmContextLimit(value);

  // 供应商列表
  Future<List<LlmProvider>> getLlmProviders() => _repo.getLlmProviders();
  Future<void> saveLlmProviders(List<LlmProvider> providers) =>
      _repo.saveLlmProviders(providers);

  // 3 角色绑定
  Future<LlmRoleBinding> getLlmRoleBinding(LlmProfileRole role) =>
      _repo.getLlmRoleBinding(role);
  Future<void> setLlmRoleBinding(LlmProfileRole role, LlmRoleBinding binding) =>
      _repo.setLlmRoleBinding(role, binding);

  bool migrateLegacyLlm3RoleToProvider() =>
      _repo.migrateLegacyLlm3RoleToProvider();

  Future<bool> testConnection() => _repo.testConnection();

  // 知识库
  Future<String?> getNsfwBookPath() => _repo.getNsfwBookPath();
  Future<void> setNsfwBookPath(String? value) => _repo.setNsfwBookPath(value);

  // 联网搜索开关
  Future<bool> getWebSearchEnabled() => _repo.getWebSearchEnabled();
  Future<void> setWebSearchEnabled(bool value) =>
      _repo.setWebSearchEnabled(value);

  // Danbooru 智能校准
  Future<bool> getDanbooruCalibrationEnabled() =>
      _repo.getDanbooruCalibrationEnabled();
  Future<void> setDanbooruCalibrationEnabled(bool value) =>
      _repo.setDanbooruCalibrationEnabled(value);
  Future<String> getDanbooruBaseUrl() => _repo.getDanbooruBaseUrl();
  Future<void> setDanbooruBaseUrl(String value) =>
      _repo.setDanbooruBaseUrl(value);

  // 图像 API 供应商配置 — NovelAI
  Future<String> getImageProviderNovelAiBaseUrl() =>
      _repo.getImageProviderNovelAiBaseUrl();
  Future<void> setImageProviderNovelAiBaseUrl(String value) =>
      _repo.setImageProviderNovelAiBaseUrl(value);
  Future<String?> getImageProviderNovelAiApiKey() =>
      _repo.getImageProviderNovelAiApiKey();
  Future<void> setImageProviderNovelAiApiKey(String value) =>
      _repo.setImageProviderNovelAiApiKey(value);
  Future<String> getImageProviderNovelAiModel() =>
      _repo.getImageProviderNovelAiModel();
  Future<void> setImageProviderNovelAiModel(String value) =>
      _repo.setImageProviderNovelAiModel(value);

  // 图像 API 供应商配置 — GPT
  Future<String> getImageProviderGptBaseUrl() =>
      _repo.getImageProviderGptBaseUrl();
  Future<void> setImageProviderGptBaseUrl(String value) =>
      _repo.setImageProviderGptBaseUrl(value);
  Future<String?> getImageProviderGptApiKey() =>
      _repo.getImageProviderGptApiKey();
  Future<void> setImageProviderGptApiKey(String value) =>
      _repo.setImageProviderGptApiKey(value);
  Future<String> getImageProviderGptModel() => _repo.getImageProviderGptModel();
  Future<void> setImageProviderGptModel(String value) =>
      _repo.setImageProviderGptModel(value);

  // 图像 API 供应商配置 — Nano Banana
  Future<String> getImageProviderNanoBaseUrl() =>
      _repo.getImageProviderNanoBaseUrl();
  Future<void> setImageProviderNanoBaseUrl(String value) =>
      _repo.setImageProviderNanoBaseUrl(value);
  Future<String?> getImageProviderNanoApiKey() =>
      _repo.getImageProviderNanoApiKey();
  Future<void> setImageProviderNanoApiKey(String value) =>
      _repo.setImageProviderNanoApiKey(value);
  Future<String> getImageProviderNanoModel() =>
      _repo.getImageProviderNanoModel();
  Future<void> setImageProviderNanoModel(String value) =>
      _repo.setImageProviderNanoModel(value);

  // 图像 API 供应商 v2 多中转站
  Future<List<ApiEndpoint>> getEndpoints(ImageProviderType p) =>
      _repo.getEndpoints(p);
  Future<void> setEndpoints(ImageProviderType p, List<ApiEndpoint> list) =>
      _repo.setEndpoints(p, list);
  Future<String?> getActiveEndpointId(ImageProviderType p) =>
      _repo.getActiveEndpointId(p);
  Future<void> setActiveEndpointId(ImageProviderType p, String? id) =>
      _repo.setActiveEndpointId(p, id);
  Future<String?> getActiveModel(ImageProviderType p) =>
      _repo.getActiveModel(p);
  Future<void> setActiveModel(ImageProviderType p, String? model) =>
      _repo.setActiveModel(p, model);
  Future<ApiEndpoint?> getActiveEndpoint(ImageProviderType p) =>
      _repo.getActiveEndpoint(p);

  // 批量生成
  Future<int> getBatchCount() => _repo.getBatchCount();
  Future<void> setBatchCount(int value) => _repo.setBatchCount(value);
}
