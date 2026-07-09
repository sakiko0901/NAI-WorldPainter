import 'dart:convert';

/// 角色绑定：把 main/vision 两角色映射到 [LlmProvider.id] + 模型名。
class LlmRoleBinding {
  final String? providerId;
  final String model;

  const LlmRoleBinding({this.providerId, this.model = ''});

  bool get isConfigured =>
      providerId != null && providerId!.isNotEmpty && model.isNotEmpty;

  static const empty = LlmRoleBinding();

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'model': model,
      };

  String toJsonString() => jsonEncode(toJson());

  factory LlmRoleBinding.fromJson(Map<String, dynamic> json) {
    final pid = json['providerId'];
    return LlmRoleBinding(
      providerId: pid == null ? null : pid.toString(),
      model: json['model']?.toString() ?? '',
    );
  }

  static LlmRoleBinding fromJsonString(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return const LlmRoleBinding();
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return LlmRoleBinding.fromJson(decoded);
      } else if (decoded is Map) {
        return LlmRoleBinding.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return const LlmRoleBinding();
  }

  LlmRoleBinding copyWith({String? providerId, String? model}) =>
      LlmRoleBinding(
        providerId: providerId ?? this.providerId,
        model: model ?? this.model,
      );
}
