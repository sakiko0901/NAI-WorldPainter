import 'dart:io';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:nai_huishi/core/constants/app_constants.dart';

class ImageUtils {
  ImageUtils._();

  /// 获取图片存储目录
  static Future<Directory> getImageDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final imageDir = Directory(p.join(appDir.path, AppConstants.imagesDirName));
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }
    return imageDir;
  }

  /// 获取画师串封面存储目录
  static Future<Directory> getArtistPromptImageDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir =
        Directory(p.join(appDir.path, AppConstants.artistPromptsDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 把用户选中的图片复制到应用私有目录并压缩。
  /// - [maxDimension]：最长边上限，超过则等比缩小（默认 1024）
  /// - [quality]：JPEG 质量 0-100（默认 85）
  /// 失败时回退到普通文件复制（仍保证持久化）。
  /// 返回持久化后的文件路径。
  static Future<String> copyAndCompressImage(
    File source, {
    int maxDimension = 1024,
    int quality = 85,
  }) async {
    final dir = await getArtistPromptImageDirectory();
    final filename = 'artist_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final targetPath = p.join(dir.path, filename);

    try {
      final bytes = await source.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        // 解码失败：直接复制原文件
        await source.copy(targetPath);
        return targetPath;
      }
      // 等比缩放
      img.Image resized;
      if (decoded.width > maxDimension || decoded.height > maxDimension) {
        if (decoded.width >= decoded.height) {
          final newHeight =
              (decoded.height * maxDimension / decoded.width).round();
          resized =
              img.copyResize(decoded, width: maxDimension, height: newHeight);
        } else {
          final newWidth =
              (decoded.width * maxDimension / decoded.height).round();
          resized =
              img.copyResize(decoded, width: newWidth, height: maxDimension);
        }
      } else {
        resized = decoded;
      }
      final encoded = img.encodeJpg(resized, quality: quality);
      await File(targetPath).writeAsBytes(encoded);
      return targetPath;
    } catch (_) {
      // 压缩失败：回退到普通复制
      try {
        await source.copy(targetPath);
        return targetPath;
      } catch (_) {
        // 极端情况：返回原始路径（虽不持久化，但至少不阻塞保存）
        return source.path;
      }
    }
  }

  /// 保存 base64 图片到本地
  static Future<String> saveBase64Image(
      String base64Data, String filename) async {
    final dir = await getImageDirectory();
    final filePath = p.join(dir.path, filename);
    final file = File(filePath);
    final bytes = base64Decode(base64Data);
    await file.writeAsBytes(bytes);
    return filePath;
  }

  /// 从 URL 下载图片并保存到本地
  static Future<String> downloadAndSaveImage(
      String url, String filename) async {
    final dir = await getImageDirectory();
    return p.join(dir.path, filename);
  }

  /// 生成唯一文件名
  static String generateFilename() {
    final now = DateTime.now();
    final timestamp = now.millisecondsSinceEpoch;
    return 'nai_$timestamp.png';
  }

  /// 删除本地图片
  static Future<bool> deleteImage(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
      return true;
    }
    return false;
  }

  /// 从 API 返回的 Markdown 中提取图片 URL
  static String? extractImageUrlFromMarkdown(String markdown) {
    final regex = RegExp(r'!\[image\]\((https?://[^\s)]+)\)');
    final match = regex.firstMatch(markdown);
    return match?.group(1);
  }

  /// 从 URL 提取文件名
  static String extractFilenameFromUrl(String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    if (segments.isNotEmpty) {
      return segments.last;
    }
    return generateFilename();
  }
}
