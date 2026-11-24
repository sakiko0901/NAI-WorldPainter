import 'dart:convert';

import 'package:uuid/uuid.dart';

enum LlmThinkingLevel {
  automatic('自动'),
  off('关闭'),
  minimal('极低'),
  low('低'),
  medium('中'),
  high('高'),
  xhigh('极高'),
  max('最高');

  const LlmThinkingLevel(this.label);

  final String label;
}

enum LlmApiProtocol {
  openAiCompatible('OpenAI 兼容接口'),
  openAi('OpenAI 官方接口', 'https://api.openai.com/v1'),
  anthropic('Anthropic Claude 官方接口', 'https://api.anthropic.com/v1'),
  gemini('Gemini 官方接口', 'https://generativelanguage.googleapis.com/v1beta');

  const LlmApiProtocol(this.label, [this.defaultBaseUrl = '']);

  final String label;
  final String defaultBaseUrl;

  bool supportsKeyRotation(String baseUrl) {
    final url = Uri.tryParse(baseUrl.trim());
    return this == gemini &&
        url?.scheme == 'https' &&
        url?.host == 'generativelanguage.googleapis.com' &&
        url?.port == 443;
  }

  static LlmApiProtocol fromJson(Object? value) =>
      values.where((protocol) => protocol.name == value).firstOrNull ??
      openAiCompatible;
}

enum LlmProviderPreset {
  gemini('Gemini', LlmApiProtocol.gemini, 'gemini-3.8-flash'),
  chatGpt('ChatGPT', LlmApiProtocol.openAi, 'gpt-6.1-terra'),
  claude('Claude', LlmApiProtocol.anthropic, 'claude-sonnet-5-5'),
  deepSeek('DeepSeek', LlmApiProtocol.openAiCompatible, 'deepseek-flash',
      'https://api.deepseek.com');

  const LlmProviderPreset(this.label, this.protocol, this.model,
      [this._baseUrl]);

  final String label;
  final LlmApiProtocol protocol;
  final String model;
  final String? _baseUrl;

  String get baseUrl => _baseUrl ?? protocol.defaultBaseUrl;
}

/// LLM 供应商：一个 apiKey + baseUrl 下挂多个模型名。
///
/// 角色绑定（main/vision）通过 providerId 引用此供应商，
/// 再选其中一个 model 名作为完整 LlmRoleConfig。
class LlmProvider {
  final String id;
  String name;
  String apiKey;
  String baseUrl;
  final LlmApiProtocol protocol;
  final List<String> backupApiKeys;
  final int geminiKeyIndex;
  List<String> models;
  final int createdAt;
  final Map<String, int> contextWindows;
  final Map<String, bool> streaming;
  final Map<String, LlmThinkingLevel> thinkingLevels;

  LlmProvider({
    required this.id,
    required this.name,
    required this.apiKey,
    required this.baseUrl,
    required this.models,
    required this.createdAt,
    this.protocol = LlmApiProtocol.openAiCompatible,
    this.backupApiKeys = const [],
    this.geminiKeyIndex = 0,
    this.contextWindows = const {},
    this.streaming = const {},
    this.thinkingLevels = const {},
  });

  factory LlmProvider.create({
    String? id,
    required String name,
    String apiKey = '',
    String baseUrl = '',
    LlmApiProtocol protocol = LlmApiProtocol.openAiCompatible,
    List<String> backupApiKeys = const [],
    int geminiKeyIndex = 0,
    List<String>? models,
    Map<String, int>? contextWindows,
    Map<String, bool>? streaming,
  }) {
    return LlmProvider(
      id: id ?? const Uuid().v4(),
      name: name,
      apiKey: apiKey,
      baseUrl: baseUrl,
      protocol: protocol,
      backupApiKeys: backupApiKeys,
      geminiKeyIndex: geminiKeyIndex,
      models: models ?? const [],
      contextWindows: contextWindows ?? const {},
      streaming: streaming ?? const {},
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
        'protocol': protocol.name,
        if (backupApiKeys.isNotEmpty) 'backupApiKeys': backupApiKeys,
        if (geminiKeyIndex != 0) 'geminiKeyIndex': geminiKeyIndex,
        'models': models,
        'createdAt': createdAt,
        'contextWindows': contextWindows,
        'streaming': streaming,
        if (thinkingLevels.isNotEmpty)
          'thinkingLevels':
              thinkingLevels.map((model, level) => MapEntry(model, level.name)),
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
      protocol: LlmApiProtocol.fromJson(json['protocol']),
      backupApiKeys: json['backupApiKeys'] is List
          ? (json['backupApiKeys'] as List).whereType<String>().toList()
          : const [],
      geminiKeyIndex:
          json['geminiKeyIndex'] is int ? json['geminiKeyIndex'] as int : 0,
      models: models,
      contextWindows: {
        if (json['contextWindows'] is Map)
          for (final entry in (json['contextWindows'] as Map).entries)
            if (entry.value is num && entry.value >= 2048)
              entry.key.toString(): (entry.value as num).toInt()
      },
      streaming: {
        if (json['streaming'] is Map)
          for (final entry in (json['streaming'] as Map).entries)
            if (entry.value is bool) entry.key.toString(): entry.value as bool,
      },
      thinkingLevels: {
        if (json['thinkingLevels'] case final Map saved)
          for (final entry in saved.entries)
            for (final level in LlmThinkingLevel.values)
              if (level != LlmThinkingLevel.automatic &&
                  level.name == entry.value)
                entry.key.toString(): level,
      },
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
    LlmApiProtocol? protocol,
    List<String>? backupApiKeys,
    int? geminiKeyIndex,
    List<String>? models,
    Map<String, int>? contextWindows,
    Map<String, bool>? streaming,
    Map<String, LlmThinkingLevel>? thinkingLevels,
  }) =>
      LlmProvider(
        id: id,
        name: name ?? this.name,
        apiKey: apiKey ?? this.apiKey,
        baseUrl: baseUrl ?? this.baseUrl,
        protocol: protocol ?? this.protocol,
        backupApiKeys: backupApiKeys ?? List.of(this.backupApiKeys),
        geminiKeyIndex: geminiKeyIndex ?? this.geminiKeyIndex,
        models: models ?? List<String>.from(this.models),
        contextWindows: contextWindows ?? Map.of(this.contextWindows),
        streaming: streaming ?? Map.of(this.streaming),
        thinkingLevels: thinkingLevels ?? Map.of(this.thinkingLevels),
        createdAt: createdAt,
      );
}
