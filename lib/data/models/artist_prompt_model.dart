import 'dart:convert';

import 'package:nai_huishi/domain/entities/artist_prompt.dart';

class ArtistPromptModel {
  static Map<String, dynamic> toDb(ArtistPrompt artist) => {
        'id': artist.id,
        'name': artist.name,
        'tag': artist.tag,
        'image_path': artist.imagePath,
        'categories': jsonEncode(artist.categories),
        'danbooru_count': artist.danbooruCount,
        'created_at': artist.createdAt.millisecondsSinceEpoch,
        'updated_at': artist.updatedAt.millisecondsSinceEpoch,
      };

  static ArtistPrompt fromDb(Map<String, dynamic> row) {
    final rawCategories = row['categories'] as String?;
    List<String> categories = const ['未分类'];
    if (rawCategories != null && rawCategories.isNotEmpty) {
      final decoded = jsonDecode(rawCategories);
      if (decoded is List) {
        categories = decoded
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
      }
    }
    if (categories.isEmpty) categories = const ['未分类'];

    return ArtistPrompt(
      id: row['id'] as int?,
      name: row['name'] as String,
      tag: row['tag'] as String,
      imagePath: (row['image_path'] as String?) ?? '',
      categories: categories,
      danbooruCount: (row['danbooru_count'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }
}
