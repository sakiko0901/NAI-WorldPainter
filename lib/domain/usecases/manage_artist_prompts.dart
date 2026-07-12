import 'package:nai_huishi/domain/entities/artist_prompt.dart';
import 'package:nai_huishi/domain/repositories/artist_prompt_repository.dart';

class ManageArtistPromptsUseCase {
  final ArtistPromptRepository _repo;

  ManageArtistPromptsUseCase(this._repo);

  Future<List<ArtistPrompt>> getAll() => _repo.getAll();
  Future<List<String>> getCategories() => _repo.getCategories();
  Future<ArtistPrompt> create({
    required String name,
    required String tag,
    required String imagePath,
    required List<String> categories,
    required int danbooruCount,
  }) =>
      _repo.create(
        name: name,
        tag: tag,
        imagePath: imagePath,
        categories: categories,
        danbooruCount: danbooruCount,
      );
  Future<ArtistPrompt> update(ArtistPrompt artist) => _repo.update(artist);
  Future<void> delete(int id) => _repo.delete(id);
  Future<void> addCategory(String category) => _repo.addCategory(category);
  Future<void> deleteCategory(String category) =>
      _repo.deleteCategory(category);
  Future<Map<String, dynamic>> exportData() => _repo.exportData();
  Future<int> importData(Map<String, dynamic> data) => _repo.importData(data);
}
