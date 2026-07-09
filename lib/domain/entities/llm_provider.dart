import 'dart:convert';

import 'package:uuid/uuid.dart';

/// LLM 供应商：一个 apiKey + baseUrl 下挂多个模型名。
///
/// 角色绑定（main/vision）通过 providerId 引用此供应商，
/// 再选其中一个 model 名作为完整 LlmRoleConfig。
class LlmProvider {
  final String id;
  String name;
  String apiKey;
  String baseUrl;
  List<String> models;
  final int createdAt;

  LlmProvider({
    required this.id,
    required this.name,
    required this.apiKey,
    required this.baseUrl,
    required this.models,
    required this.createdAt,
  });

  factory LlmProvider.create({
    String? id,
    required String name,
    String apiKey = '',
    String baseUrl = '',
    List<String>? models,
  }) {
    return LlmProvider(
      id: id ?? const Uuid().v4(),
      name: name,
      apiKey: apiKey,
      baseUrl: baseUrl,
      models: models ?? const [],
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  bool get isConfigured =>
      apiKey.trim().isNotEmpty && baseUrl.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'models': models,
        'createdAt': createdAt,
      };

  static List<Map<String, dynamic>> listToJson(List<LlmProvider> list) =>
      list.map((p) => p.toJson()).toList();

  static String listToJsonString(List<LlmProvider> list) =>
      jsonEncode(listToJson(list));

  factory LlmProvider.fromJson(Map<String, dynamic> json) {
    final rawModels = json['models'];
    List<String> models;
    if (rawModels is List) {
      models = rawModels.map((e) => e.toString()).toList();
    } else {
      models = const [];
    }
    return LlmProvider(
      id: json['id']?.toString() ?? const Uuid().v4(),
      name: json['name']?.toString() ?? '',
      apiKey: json['apiKey']?.toString() ?? '',
      baseUrl: json['baseUrl']?.toString() ?? '',
      models: models,
      createdAt: (json['createdAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  static List<LlmProvider> listFromJsonString(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return const [];
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! List) return const [];
      final result = <LlmProvider>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          result.add(LlmProvider.fromJson(item));
        } else if (item is Map) {
          result.add(LlmProvider.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  LlmProvider copyWith({
    String? name,
    String? apiKey,
    String? baseUrl,
    List<String>? models,
  }) =>
      LlmProvider(
        id: id,
        name: name ?? this.name,
        apiKey: apiKey ?? this.apiKey,
        baseUrl: baseUrl ?? this.baseUrl,
        models: models ?? List<String>.from(this.models),
        createdAt: createdAt,
      );
}
