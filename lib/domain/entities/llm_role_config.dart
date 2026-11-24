import 'llm_provider.dart';

/// 角色 LLM 配置。
///
/// 这是给 AgentLoop / LlmApiService 用的扁平配置对象，
/// 由 ViewModel 根据 LlmRoleBinding + LlmProvider 解析得出。
class LlmRoleConfig {
  final String apiKey;
  final String baseUrl;
  final String model;
  final LlmApiProtocol protocol;
  final String? providerId;
  final List<String> backupApiKeys;
  final int geminiKeyIndex;
  final LlmThinkingLevel thinkingLevel;
  const LlmRoleConfig({
    this.apiKey = '',
    this.baseUrl = '',
    this.model = '',
    this.protocol = LlmApiProtocol.openAiCompatible,
    this.providerId,
    this.backupApiKeys = const [],
    this.geminiKeyIndex = 0,
    this.thinkingLevel = LlmThinkingLevel.automatic,
  });

  bool get isConfigured =>
      apiKey.trim().isNotEmpty &&
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  LlmRoleConfig copyWith({
    String? apiKey,
    String? baseUrl,
    String? model,
    int? geminiKeyIndex,
  }) =>
      LlmRoleConfig(
        apiKey: apiKey ?? this.apiKey,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        protocol: protocol,
        providerId: providerId,
        backupApiKeys: backupApiKeys,
        geminiKeyIndex: geminiKeyIndex ?? this.geminiKeyIndex,
        thinkingLevel: thinkingLevel,
      );
}
