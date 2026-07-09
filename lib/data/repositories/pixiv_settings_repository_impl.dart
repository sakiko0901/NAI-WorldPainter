import 'package:nai_huishi/data/datasources/local/pixiv_settings_local_datasource.dart';
import 'package:nai_huishi/domain/entities/pixiv_settings.dart';
import 'package:nai_huishi/domain/repositories/pixiv_settings_repository.dart';

class PixivSettingsRepositoryImpl implements PixivSettingsRepository {
  final PixivSettingsLocalDatasource _local;

  PixivSettingsRepositoryImpl(this._local);

  @override
  Future<PixivSettings> load() async => _local.load();

  @override
  Future<void> save(PixivSettings s) => _local.save(s);

  @override
  Future<List<Map<String, String>>> loadCustomCharacters() async =>
      _local.loadCustomCharacters();

  @override
  Future<void> saveCustomCharacters(List<Map<String, String>> e) =>
      _local.saveCustomCharacters(e);

  @override
  Future<List<Map<String, String>>> loadCustomSurroundings() async =>
      _local.loadCustomSurroundings();

  @override
  Future<void> saveCustomSurroundings(List<Map<String, String>> e) =>
      _local.saveCustomSurroundings(e);
}
