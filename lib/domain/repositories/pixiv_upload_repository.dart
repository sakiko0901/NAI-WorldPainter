import 'package:nai_huishi/domain/entities/pixiv_upload_task.dart';

/// Pixiv 上传仓库接口
abstract class PixivUploadRepository {
  /// 根据图片调用 Pixiv 官方推荐 tag 接口
  Future<List<String>> suggestTags(String imagePath);

  /// 把任务真正上传到 Pixiv，返回带 illustId 的更新后任务
  Future<PixivUploadTask> uploadOnce(PixivUploadTask task);
}
