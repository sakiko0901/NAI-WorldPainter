import 'package:equatable/equatable.dart';

/// 单个中转站配置（API 端点）
class ApiEndpoint extends Equatable {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final List<String> models;
  final String protocol;

  /// Null preserves the channel default for configurations saved before this
  /// setting existed (official on, custom relay off).
  final bool? streamEnabled;

  const ApiEndpoint({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.models,
    this.protocol = 'openaiChat',
    this.streamEnabled,
  });

  ApiEndpoint copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    List<String>? models,
    String? protocol,
    bool? streamEnabled,
  }) {
    return ApiEndpoint(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      models: models ?? this.models,
      protocol: protocol ?? this.protocol,
      streamEnabled: streamEnabled ?? this.streamEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'base_url': baseUrl,
        'api_key': apiKey,
        'models': models,
        'protocol': protocol,
        if (streamEnabled != null) 'stream_enabled': streamEnabled,
      };

  factory ApiEndpoint.fromJson(Map<String, dynamic> json) => ApiEndpoint(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        baseUrl: json['base_url'] as String? ?? '',
        apiKey: json['api_key'] as String? ?? '',
        models: (json['models'] as List?)?.map((e) => e as String).toList() ??
            const [],
        protocol: json['protocol'] as String? ?? 'openaiChat',
        streamEnabled: json['stream_enabled'] as bool?,
      );

  @override
  List<Object?> get props =>
      [id, name, baseUrl, apiKey, models, protocol, streamEnabled];
}
