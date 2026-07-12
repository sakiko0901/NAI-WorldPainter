import 'package:equatable/equatable.dart';

/// 单个中转站配置（API 端点）
class ApiEndpoint extends Equatable {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final List<String> models;
  final String protocol;

  const ApiEndpoint({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.models,
    this.protocol = 'openaiChat',
  });

  ApiEndpoint copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    List<String>? models,
    String? protocol,
  }) {
    return ApiEndpoint(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      models: models ?? this.models,
      protocol: protocol ?? this.protocol,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'base_url': baseUrl,
        'api_key': apiKey,
        'models': models,
        'protocol': protocol,
      };

  factory ApiEndpoint.fromJson(Map<String, dynamic> json) => ApiEndpoint(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        baseUrl: json['base_url'] as String? ?? '',
        apiKey: json['api_key'] as String? ?? '',
        models: (json['models'] as List?)?.map((e) => e as String).toList() ??
            const [],
        protocol: json['protocol'] as String? ?? 'openaiChat',
      );

  @override
  List<Object?> get props => [id, name, baseUrl, apiKey, models, protocol];
}
