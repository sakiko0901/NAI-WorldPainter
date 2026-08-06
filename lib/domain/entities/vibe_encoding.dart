import 'package:equatable/equatable.dart';

class VibeEncoding extends Equatable {
  final int? id;
  final String title;
  final String thumbnailPath;
  final String? sourceImagePath;
  final String encodedVibe;
  final String? encodedModel;
  final DateTime createdAt;
  final DateTime updatedAt;

  const VibeEncoding({
    this.id,
    required this.title,
    required this.thumbnailPath,
    this.sourceImagePath,
    required this.encodedVibe,
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
        encodedModel,
        createdAt,
        updatedAt,
      ];
}
