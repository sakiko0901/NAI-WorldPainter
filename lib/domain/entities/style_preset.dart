import 'package:equatable/equatable.dart';

class StylePreset extends Equatable {
  final int? id;
  final String title;
  final String prompt;
  final String imagePath;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StylePreset({
    this.id,
    required this.title,
    required this.prompt,
    required this.imagePath,
    required this.createdAt,
    required this.updatedAt,
  });

  StylePreset copyWith({
    int? id,
    String? title,
    String? prompt,
    String? imagePath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StylePreset(
      id: id ?? this.id,
      title: title ?? this.title,
      prompt: prompt ?? this.prompt,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props =>
      [id, title, prompt, imagePath, createdAt, updatedAt];
}
