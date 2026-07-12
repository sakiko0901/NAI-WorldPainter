import 'package:equatable/equatable.dart';

class ArtistPrompt extends Equatable {
  final int? id;
  final String name;
  final String tag;
  final String imagePath;
  final List<String> categories;
  final int danbooruCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ArtistPrompt({
    this.id,
    required this.name,
    required this.tag,
    required this.imagePath,
    required this.categories,
    required this.danbooruCount,
    required this.createdAt,
    required this.updatedAt,
  });

  ArtistPrompt copyWith({
    int? id,
    String? name,
    String? tag,
    String? imagePath,
    List<String>? categories,
    int? danbooruCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ArtistPrompt(
      id: id ?? this.id,
      name: name ?? this.name,
      tag: tag ?? this.tag,
      imagePath: imagePath ?? this.imagePath,
      categories: categories ?? this.categories,
      danbooruCount: danbooruCount ?? this.danbooruCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        tag,
        imagePath,
        categories,
        danbooruCount,
        createdAt,
        updatedAt
      ];
}
