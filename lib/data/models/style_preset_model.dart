import 'package:nai_huishi/domain/entities/style_preset.dart';

class StylePresetModel {
  static Map<String, dynamic> toDb(StylePreset preset) => {
        'id': preset.id,
        'title': preset.title,
        'prompt': preset.prompt,
        'image_path': preset.imagePath,
        'created_at': preset.createdAt.millisecondsSinceEpoch,
        'updated_at': preset.updatedAt.millisecondsSinceEpoch,
      };

  static StylePreset fromDb(Map<String, dynamic> row) => StylePreset(
        id: row['id'] as int?,
        title: row['title'] as String,
        prompt: row['prompt'] as String,
        imagePath: row['image_path'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      );
}
