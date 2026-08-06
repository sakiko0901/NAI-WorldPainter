import 'package:nai_huishi/domain/entities/vibe_encoding.dart';

abstract class VibeEncodingRepository {
  Future<List<VibeEncoding>> getAll();
  Future<VibeEncoding?> getById(int id);
  Future<VibeEncoding?> findBySourceImagePath(String path);
  Future<VibeEncoding> createFromEncoding({
    required String title,
    required String encodedVibe,
    required String sourceImagePath,
    String? encodedModel,
  });
  Future<List<VibeEncoding>> createManyFromEncodings({
    required String titlePrefix,
    required String sourceImagePath,
    required List<String> encodedVibes,
    String? encodedModel,
  });
  Future<VibeEncoding> updateTitle(VibeEncoding encoding, String title);
  Future<void> delete(int id);
}
