import 'package:nai_huishi/domain/entities/pixiv_settings.dart';
import 'package:nai_huishi/domain/repositories/pixiv_settings_repository.dart';

class ManagePixivSettingsUseCase {
  final PixivSettingsRepository _repo;

  ManagePixivSettingsUseCase(this._repo);

  Future<PixivSettings> load() => _repo.load();
  Future<void> save(PixivSettings s) => _repo.save(s);

  Future<List<Map<String, String>>> loadCustomCharacters() =>
      _repo.loadCustomCharacters();
  Future<void> saveCustomCharacters(List<Map<String, String>> e) =>
      _repo.saveCustomCharacters(e);

  Future<List<Map<String, String>>> loadCustomSurroundings() =>
      _repo.loadCustomSurroundings();
  Future<void> saveCustomSurroundings(List<Map<String, String>> e) =>
      _repo.saveCustomSurroundings(e);
}
