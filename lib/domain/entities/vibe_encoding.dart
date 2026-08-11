import 'package:equatable/equatable.dart';

class VibeEncoding extends Equatable {
  final int? id;
  final String title;
  final String thumbnailPath;
  final String? sourceImagePath;

  /// 编码正文仅在生成前按需从 App 私有文件读取；列表加载时为空。
  final String encodedVibe;
  final String? encodedVibePath;
  final String? encodedModel;
  final DateTime createdAt;
  final DateTime updatedAt;

  const VibeEncoding({
    this.id,
    required this.title,
    required this.thumbnailPath,
    this.sourceImagePath,
    this.encodedVibe = '',
    this.encodedVibePath,
    this.encodedModel,
    required this.createdAt,
    required this.updatedAt,
  });

  VibeEncoding copyWith({
    int? id,
    String? title,
    String? thumbnailPath,
    String? sourceImagePath,
    String? encodedVibe,
    String? encodedVibePath,
    String? encodedModel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      VibeEncoding(
        id: id ?? this.id,
        title: title ?? this.title,
        thumbnailPath: thumbnailPath ?? this.thumbnailPath,
        sourceImagePath: sourceImagePath ?? this.sourceImagePath,
        encodedVibe: encodedVibe ?? this.encodedVibe,
        encodedVibePath: encodedVibePath ?? this.encodedVibePath,
        encodedModel: encodedModel ?? this.encodedModel,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  List<Object?> get props => [
        id,
        title,
        thumbnailPath,
        sourceImagePath,
        encodedVibe,
        encodedVibePath,
        encodedModel,
        createdAt,
        updatedAt,
      ];
}
