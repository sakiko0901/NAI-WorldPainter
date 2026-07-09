import 'package:nai_huishi/data/datasources/local/pixiv_settings_local_datasource.dart';
import 'package:nai_huishi/data/datasources/remote/pixiv_api_service.dart';
import 'package:nai_huishi/domain/entities/pixiv_upload_task.dart';
import 'package:nai_huishi/domain/repositories/pixiv_upload_repository.dart';

class PixivUploadRepositoryImpl implements PixivUploadRepository {
  final PixivApiService _api;
  final PixivSettingsLocalDatasource _settings;

  PixivUploadRepositoryImpl(this._api, this._settings);

  @override
  Future<List<String>> suggestTags(String imagePath) async {
    final settings = _settings.load();
    return _api.suggestTags(settings: settings, imagePath: imagePath);
  }

  @override
  Future<PixivUploadTask> uploadOnce(PixivUploadTask task) async {
    final settings = _settings.load();
    final illustId = await _api.uploadIllustration(
      settings: settings,
      task: task,
    );
    return task.copyWith(
      status: PixivUploadStatus.completed,
      illustId: illustId,
      completedAt: DateTime.now(),
      clearError: true,
    );
  }
}
