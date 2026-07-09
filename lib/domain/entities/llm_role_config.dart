/// 3 角色 LLM 配置（apiKey + baseUrl + model 的组合）。
///
/// 这是给 AgentLoop / LlmApiService 用的扁平配置对象，
/// 由 ViewModel 根据 LlmRoleBinding + LlmProvider 解析得出。
class LlmRoleConfig {
  final String apiKey;
  final String baseUrl;
  final String model;
  const LlmRoleConfig({this.apiKey = '', this.baseUrl = '', this.model = ''});

  bool get isConfigured =>
      apiKey.trim().isNotEmpty &&
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  LlmRoleConfig copyWith({String? apiKey, String? baseUrl, String? model}) =>
      LlmRoleConfig(
        apiKey: apiKey ?? this.apiKey,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
      );
}
