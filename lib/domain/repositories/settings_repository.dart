import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/llm_profile_role.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_role_binding.dart';

abstract class SettingsRepository {
  Future<String?> getApiKey();
  Future<void> setApiKey(String key);
  Future<void> deleteApiKey();

  Future<String> getBaseUrl();
  Future<void> setBaseUrl(String url);

  Future<String?> getDefaultModel();
  Future<void> setDefaultModel(String model);

  Future<String> getDefaultResolution();
  Future<void> setDefaultResolution(String resolution);

  Future<String> getDefaultSampler();
  Future<void> setDefaultSampler(String sampler);

  Future<double> getDefaultScale();
  Future<void> setDefaultScale(double scale);

  Future<double> getDefaultCfgRescale();
  Future<void> setDefaultCfgRescale(double value);

  Future<String> getDefaultNoiseSchedule();
  Future<void> setDefaultNoiseSchedule(String schedule);

  Future<String> getDefaultStyleWords();
  Future<void> setDefaultStyleWords(String value);
  Future<String> getDefaultStyleWordsV5();
  Future<void> setDefaultStyleWordsV5(String value);
  Future<String> getDefaultStyleWordsV45();
  Future<void> setDefaultStyleWordsV45(String value);

  Future<String> getPromptDraft();
  Future<void> setPromptDraft(String value);

  Future<String> getNegativePromptDraft();
  Future<void> setNegativePromptDraft(String value);

  Future<String?> getSelectedModelDraft();
  Future<void> setSelectedModelDraft(String value);

  Future<String> getSelectedResolutionDraft();
  Future<void> setSelectedResolutionDraft(String value);

  Future<List<String>> getCustomResolutions();
  Future<void> setCustomResolutions(List<String> value);

  Future<String> getSelectedSamplerDraft();
  Future<void> setSelectedSamplerDraft(String value);

  Future<String> getSelectedNoiseScheduleDraft();
  Future<void> setSelectedNoiseScheduleDraft(String value);

  Future<double> getScaleDraft();
  Future<void> setScaleDraft(double value);

  Future<double> getCfgRescaleDraft();
  Future<void> setCfgRescaleDraft(double value);

  Future<int> getStepsDraft();
  Future<void> setStepsDraft(int value);

  Future<bool> getStepsLocked();
  Future<void> setStepsLocked(bool value);

  Future<List<CharacterSpec>> getCharactersDraft();
  Future<void> setCharactersDraft(List<CharacterSpec> value);
  Future<List<CharacterReferenceImage>> getVibeReferencesDraft();
  Future<void> setVibeReferencesDraft(List<CharacterReferenceImage> value);
  Future<ReferenceMode> getReferenceModeDraft();
  Future<void> setReferenceModeDraft(ReferenceMode value);
  Future<List<PreciseReferenceImage>> getPreciseReferencesDraft();
  Future<void> setPreciseReferencesDraft(List<PreciseReferenceImage> value);

  Future<String> getInpaintPromptDraft();
  Future<void> setInpaintPromptDraft(String value);

  Future<String> getInpaintNegativePromptDraft();
  Future<void> setInpaintNegativePromptDraft(String value);

  // LLM 提示词辅助
  Future<String?> getLlmApiKey();
  Future<void> setLlmApiKey(String value);

  Future<String> getLlmBaseUrl();
  Future<void> setLlmBaseUrl(String value);

  Future<String> getLlmModel();
  Future<void> setLlmModel(String value);

  Future<String> getLlmSystemPrompt();
  Future<void> setLlmSystemPrompt(String value);

  Future<String?> getLlmActiveSessionId();
  Future<void> setLlmActiveSessionId(String? value);

  // LLM 上下文条数
  Future<int> getLlmContextLimit();
  Future<void> setLlmContextLimit(int value);

  // LLM 供应商列表
  Future<List<LlmProvider>> getLlmProviders();
  Future<void> saveLlmProviders(List<LlmProvider> providers);

  // LLM 3 角色绑定
  Future<LlmRoleBinding> getLlmRoleBinding(LlmProfileRole role);
  Future<void> setLlmRoleBinding(LlmProfileRole role, LlmRoleBinding binding);

  /// 旧 3 角色 9 key + 旧单配置数据迁移到供应商+绑定结构
  bool migrateLegacyLlm3RoleToProvider();

  /// 测试 API 连通性
  Future<bool> testConnection();

  // 知识库
  Future<String?> getNsfwBookPath();
  Future<void> setNsfwBookPath(String? value);

  // Danbooru 智能校准
  Future<bool> getDanbooruCalibrationEnabled();
  Future<void> setDanbooruCalibrationEnabled(bool value);
  Future<String> getDanbooruBaseUrl();
  Future<void> setDanbooruBaseUrl(String value);

  // 图像 API 供应商配置 — NovelAI
  Future<String> getImageProviderNovelAiBaseUrl();
  Future<void> setImageProviderNovelAiBaseUrl(String value);
  Future<String?> getImageProviderNovelAiApiKey();
  Future<void> setImageProviderNovelAiApiKey(String value);
  Future<String> getImageProviderNovelAiModel();
  Future<void> setImageProviderNovelAiModel(String value);

  // 图像 API 供应商配置 — GPT
  Future<String> getImageProviderGptBaseUrl();
  Future<void> setImageProviderGptBaseUrl(String value);
  Future<String?> getImageProviderGptApiKey();
  Future<void> setImageProviderGptApiKey(String value);
  Future<String> getImageProviderGptModel();
  Future<void> setImageProviderGptModel(String value);

  // 图像 API 供应商配置 — Nano Banana
  Future<String> getImageProviderNanoBaseUrl();
  Future<void> setImageProviderNanoBaseUrl(String value);
  Future<String?> getImageProviderNanoApiKey();
  Future<void> setImageProviderNanoApiKey(String value);
  Future<String> getImageProviderNanoModel();
  Future<void> setImageProviderNanoModel(String value);

  // 图像 API 供应商 v2 多中转站
  Future<List<ApiEndpoint>> getEndpoints(ImageProviderType p);
  Future<void> setEndpoints(ImageProviderType p, List<ApiEndpoint> list);
  Future<String?> getActiveEndpointId(ImageProviderType p);
  Future<void> setActiveEndpointId(ImageProviderType p, String? id);
  Future<String?> getActiveModel(ImageProviderType p);
  Future<void> setActiveModel(ImageProviderType p, String? model);
  Future<ApiEndpoint?> getActiveEndpoint(ImageProviderType p);

  // 批量生成
  Future<int> getBatchCount();
  Future<void> setBatchCount(int value);
}
