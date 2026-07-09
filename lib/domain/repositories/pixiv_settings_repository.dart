import 'package:nai_huishi/domain/entities/pixiv_settings.dart';

abstract class PixivSettingsRepository {
  Future<PixivSettings> load();
  Future<void> save(PixivSettings settings);

  Future<List<Map<String, String>>> loadCustomCharacters();
  Future<void> saveCustomCharacters(List<Map<String, String>> entries);

  Future<List<Map<String, String>>> loadCustomSurroundings();
  Future<void> saveCustomSurroundings(List<Map<String, String>> entries);
}
