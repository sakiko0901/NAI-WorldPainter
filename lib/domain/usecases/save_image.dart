import 'dart:io';
import 'dart:typed_data';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:dio/dio.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path/path.dart' as p;

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

  /// 将内存中的图片字节直接保存到相册（不落盘到应用目录）。
  Future<bool> saveBytesToGallery(List<int> bytes) async {
    final result = await ImageGallerySaverPlus.saveImage(
      Uint8List.fromList(bytes),
      quality: 100,
      name: 'nai_edit_${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
    );
    if (result is Map) {
      final isSuccess = result['isSuccess'];
      final success = result['success'];
      return isSuccess == true || success == true;
    }
    return false;
  }
}
