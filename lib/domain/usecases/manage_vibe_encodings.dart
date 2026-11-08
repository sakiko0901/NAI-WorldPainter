import 'package:nai_huishi/domain/entities/vibe_encoding.dart';
import 'package:nai_huishi/domain/repositories/vibe_encoding_repository.dart';

class ManageVibeEncodingsUseCase {
  final VibeEncodingRepository _repository;

  ManageVibeEncodingsUseCase(this._repository);

  Future<List<VibeEncoding>> getAll() => _repository.getAll();
  Future<VibeEncoding?> getById(int id) => _repository.getById(id);
  Future<VibeEncoding?> findBySourceImagePath(String path) =>
      _repository.findBySourceImagePath(path);

  Future<VibeEncoding> createFromEncoding({
    required String title,
    required String encodedVibe,
    required String sourceImagePath,
    String? encodedModel,
    double informationExtracted = 1.0,
    String? sourceHash,
  }) =>
      _repository.createFromEncoding(
        title: title,
        encodedVibe: encodedVibe,
        sourceImagePath: sourceImagePath,
        encodedModel: encodedModel,
        informationExtracted: informationExtracted,
        sourceHash: sourceHash,
      );

  Future<List<VibeEncoding>> createManyFromEncodings({
    required String titlePrefix,
    required String sourceImagePath,
    required List<String> encodedVibes,
    String? encodedModel,
    double informationExtracted = 1.0,
    String? sourceHash,
  }) =>
      _repository.createManyFromEncodings(
        titlePrefix: titlePrefix,
        sourceImagePath: sourceImagePath,
        encodedVibes: encodedVibes,
        encodedModel: encodedModel,
        informationExtracted: informationExtracted,
        sourceHash: sourceHash,
      );

  Future<VibeEncoding> updateTitle(VibeEncoding encoding, String title) =>
      _repository.updateTitle(encoding, title);

  Future<void> delete(int id) => _repository.delete(id);
}
