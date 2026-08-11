import 'package:nai_huishi/domain/entities/vibe_encoding.dart';

class VibeEncodingModel {
  static VibeEncoding fromDb(Map<String, dynamic> row) => VibeEncoding(
        id: row['id'] as int?,
        title: row['title'] as String,
        thumbnailPath: row['thumbnail_path'] as String,
        sourceImagePath: row['source_image_path'] as String?,
        encodedVibe: row['encoded_vibe'] as String? ?? '',
        encodedVibePath: row['encoded_vibe_path'] as String?,
        encodedModel: row['encoded_model'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      );

  static Map<String, dynamic> toDb(VibeEncoding value) => {
        if (value.id != null) 'id': value.id,
        'title': value.title,
        'thumbnail_path': value.thumbnailPath,
        'source_image_path': value.sourceImagePath,
        'encoded_vibe': value.encodedVibe,
        'encoded_vibe_path': value.encodedVibePath,
        'encoded_model': value.encodedModel,
        'created_at': value.createdAt.millisecondsSinceEpoch,
        'updated_at': value.updatedAt.millisecondsSinceEpoch,
      };
}
