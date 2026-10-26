import 'dart:io';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:dio/dio.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SaveImageUseCase {
  final HistoryRepository _historyRepo;

  SaveImageUseCase(this._historyRepo);

  Future<String> execute(GenerationTask task) async {
    if (task.imageUrl == null && task.imagePath == null) {
      throw Exception('没有可保存的图片');
    }

    if (task.imagePath != null) {
      final file = File(task.imagePath!);
      if (await file.exists()) {
        return task.imagePath!;
      }
    }

    if (task.imageUrl != null) {
      final filename = ImageUtils.generateFilename();
      final dir = await ImageUtils.getImageDirectory();
      final filePath = p.join(dir.path, filename);

      final dio = Dio();
      await dio.download(task.imageUrl!, filePath);

      final updated = task.copyWith(imagePath: filePath);
      await _historyRepo.updateTask(updated);

      return filePath;
    }

    throw Exception('图片下载失败');
  }

  Future<String> saveTransient(GenerationTask task) async {
    if (task.imagePath != null && await File(task.imagePath!).exists()) {
      return task.imagePath!;
    }
    if (task.imageUrl == null || task.imageUrl!.isEmpty) {
      throw Exception('没有可保存的图片');
    }
    final filename = ImageUtils.generateFilename();
    final dir = await ImageUtils.getImageDirectory();
    final filePath = p.join(dir.path, filename);
    await Dio().download(task.imageUrl!, filePath);
    return filePath;
  }

  Future<bool> saveToGallery(String filePath) async {
    final result = await ImageGallerySaverPlus.saveFile(filePath);
    if (result is Map) {
      final isSuccess = result['isSuccess'];
      final success = result['success'];
      return isSuccess == true || success == true;
    }
    return false;
  }

  /// 将 PNG 字节原样写入相册，避免 `saveImage` 在 Android 上转成 JPEG。
  ///
  /// 插件的 `saveFile` 会复制文件内容，因此此方法只接受 PNG 字节；
  /// 临时文件放在应用临时目录的独立唯一目录中，并在调用完成后清理。
  Future<bool> savePngBytesToGallery(List<int> pngBytes) async {
    Directory? exportDirectory;
    try {
      final temporaryDirectory = await getTemporaryDirectory();
      exportDirectory = await temporaryDirectory.createTemp('nai_edit_png_');

      // createTemp 保证目录名唯一，用它同时构造相册文件名，避免并发导出重名。
      final name = p.basename(exportDirectory.path);
      final fileName = '$name.png';
      final exportFile = File(p.join(exportDirectory.path, fileName));
      await exportFile.writeAsBytes(pngBytes, flush: true);

      final result = await ImageGallerySaverPlus.saveFile(
        exportFile.path,
        // Android 9 及以下会自行附加原文件扩展名。
        name: name,
      );
      if (result is Map) {
        final isSuccess = result['isSuccess'];
        final success = result['success'];
        return isSuccess == true || success == true;
      }
      return false;
    } finally {
      final directory = exportDirectory;
      if (directory != null) {
        try {
          await directory.delete(recursive: true);
        } on FileSystemException {
          // 清理失败不应覆盖相册保存结果；只处理本次创建的独立目录。
        }
      }
    }
  }
}
