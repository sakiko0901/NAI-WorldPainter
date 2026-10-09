import 'dart:io';

import 'package:nai_huishi/domain/entities/comic_project.dart';

/// 本地文字区域识别的扩展点。
///
/// 当前版本不上传图片，也不在没有可靠离线模型时猜测文字位置。覆盖替换
/// 始终创建可编辑的白色覆盖层，用户可通过白色笔精确擦除残留文字。
class ComicTextRecognitionService {
  Future<List<ComicRect>> recognizeTextAreas(
    String imagePath,
    ComicRect within,
  ) async {
    if (!await File(imagePath).exists()) return const [];
    return const [];
  }
}
