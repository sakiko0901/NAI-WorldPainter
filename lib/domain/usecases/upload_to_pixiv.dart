import 'package:nai_huishi/domain/entities/pixiv_upload_task.dart';
import 'package:nai_huishi/domain/repositories/pixiv_upload_repository.dart';

/// 调用一次 Pixiv 上传
class UploadToPixivUseCase {
  final PixivUploadRepository _repo;

  UploadToPixivUseCase(this._repo);

  Future<PixivUploadTask> call(PixivUploadTask task) => _repo.uploadOnce(task);
}
