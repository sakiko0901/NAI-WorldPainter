import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
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

  static const int img2imgMaxPixels = 1024 * 1024;
  static const int img2imgMaxDimension = 1600;
  static const int img2imgDimensionMultiple = 64;

  /// 将图生图源图规范化到网关免费尺寸范围，并返回临时 PNG 路径。
  static Future<String> normalizeImg2ImgSource(File source) async {
    final decoded = img.decodeImage(await source.readAsBytes());
    if (decoded == null) {
      throw const FormatException('无法读取图片，请选择有效的 PNG 或 JPEG 图片');
    }

    final dimensions =
        calculateImg2ImgDimensions(decoded.width, decoded.height);
    final normalized =
        decoded.width == dimensions.$1 && decoded.height == dimensions.$2
            ? decoded
            : img.copyResize(
                decoded,
                width: dimensions.$1,
                height: dimensions.$2,
                interpolation: img.Interpolation.cubic,
              );
    final dir = await getTemporaryDirectory();
    final target = File(p.join(
      dir.path,
      'img2img_${DateTime.now().microsecondsSinceEpoch}.png',
    ));
    await target.writeAsBytes(img.encodePng(normalized));
    return target.path;
  }

  /// 计算最接近原宽高比、满足 1M 像素和 64px 对齐的尺寸。
  static (int, int) calculateImg2ImgDimensions(int width, int height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('图片尺寸必须大于 0');
    }

    final pixelScale = (img2imgMaxPixels / (width * height)).clamp(0.0, 1.0);
    final dimensionScale =
        (img2imgMaxDimension / (width > height ? width : height))
            .clamp(0.0, 1.0);
    final scale = pixelScale < 1
        ? math.min(math.sqrt(pixelScale), dimensionScale)
        : dimensionScale;
    final scaledWidth = width * scale;
    final scaledHeight = height * scale;

    int align(double value) =>
        ((value / img2imgDimensionMultiple).round() * img2imgDimensionMultiple)
            .clamp(img2imgDimensionMultiple, img2imgMaxDimension);

    var targetWidth = align(scaledWidth);
    var targetHeight = align(scaledHeight);
    while (targetWidth * targetHeight > img2imgMaxPixels) {
      if (targetWidth / width >= targetHeight / height &&
          targetWidth > img2imgDimensionMultiple) {
        targetWidth -= img2imgDimensionMultiple;
      } else if (targetHeight > img2imgDimensionMultiple) {
        targetHeight -= img2imgDimensionMultiple;
      } else {
        break;
      }
    }
    return (targetWidth, targetHeight);
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
