import 'package:nai_huishi/domain/repositories/pixiv_upload_repository.dart';

/// 调用 Pixiv 的 suggest_tags_by_image 接口
class SuggestPixivTagsUseCase {
  final PixivUploadRepository _repo;

  SuggestPixivTagsUseCase(this._repo);

  Future<List<String>> call(String imagePath) => _repo.suggestTags(imagePath);
}
