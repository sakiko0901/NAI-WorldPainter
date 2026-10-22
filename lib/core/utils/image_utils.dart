import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data' as typed_data;
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

  /// 将裁剪框内当前可见区域换算成原图像素坐标。
  /// 返回值依次为 x、y、width、height，并保证与目标画幅严格同宽高比。
  static (int, int, int, int) calculateImg2ImgCropRect({
    required int imageWidth,
    required int imageHeight,
    required double viewportWidth,
    required double viewportHeight,
    required double displayScale,
    required double offsetX,
    required double offsetY,
    required int targetWidth,
    required int targetHeight,
  }) {
    if (imageWidth <= 0 ||
        imageHeight <= 0 ||
        viewportWidth <= 0 ||
        viewportHeight <= 0 ||
        displayScale <= 0 ||
        targetWidth <= 0 ||
        targetHeight <= 0) {
      throw ArgumentError('图片、裁剪框和目标尺寸必须大于 0');
    }

    final displayedWidth = imageWidth * displayScale;
    final displayedHeight = imageHeight * displayScale;
    final imageLeft = (viewportWidth - displayedWidth) / 2 + offsetX;
    final imageTop = (viewportHeight - displayedHeight) / 2 + offsetY;
    final visibleWidth = viewportWidth / displayScale;
    final visibleHeight = viewportHeight / displayScale;
    final divisor =
        math.max(1, _greatestCommonDivisor(targetWidth, targetHeight));
    final ratioWidth = targetWidth ~/ divisor;
    final ratioHeight = targetHeight ~/ divisor;
    final units = math
        .min(
          visibleWidth / ratioWidth,
          visibleHeight / ratioHeight,
        )
        .floor();
    if (units < 1) {
      throw ArgumentError('原图尺寸不足以按目标比例裁剪');
    }

    final cropWidth = units * ratioWidth;
    final cropHeight = units * ratioHeight;
    if (cropWidth > imageWidth || cropHeight > imageHeight) {
      throw ArgumentError('裁剪区域超出图片范围');
    }
    final centerX = (-imageLeft + viewportWidth / 2) / displayScale;
    final centerY = (-imageTop + viewportHeight / 2) / displayScale;
    final x =
        (centerX - cropWidth / 2).round().clamp(0, imageWidth - cropWidth);
    final y =
        (centerY - cropHeight / 2).round().clamp(0, imageHeight - cropHeight);
    return (x, y, cropWidth, cropHeight);
  }

  static int _greatestCommonDivisor(int a, int b) {
    while (b != 0) {
      final remainder = a % b;
      a = b;
      b = remainder;
    }
    return a.abs();
  }

  /// 先按原图像素坐标裁切选区，再仅缩放裁切结果。
  static Future<String> cropImg2ImgSource(
    File source, {
    required int cropX,
    required int cropY,
    required int cropWidth,
    required int cropHeight,
    required int targetWidth,
    required int targetHeight,
  }) async {
    final encoded = cropImg2ImgBytes(
      await source.readAsBytes(),
      cropX: cropX,
      cropY: cropY,
      cropWidth: cropWidth,
      cropHeight: cropHeight,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final dir = await getTemporaryDirectory();
    final target = File(p.join(
      dir.path,
      'img2img_${DateTime.now().microsecondsSinceEpoch}.png',
    ));
    await target.writeAsBytes(encoded);
    return target.path;
  }

  static typed_data.Uint8List cropImg2ImgBytes(
    typed_data.Uint8List sourceBytes, {
    required int cropX,
    required int cropY,
    required int cropWidth,
    required int cropHeight,
    required int targetWidth,
    required int targetHeight,
  }) {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      throw const FormatException('无法读取图片，请选择有效的 PNG 或 JPEG 图片');
    }
    if (cropWidth <= 0 ||
        cropHeight <= 0 ||
        cropX < 0 ||
        cropY < 0 ||
        cropX + cropWidth > decoded.width ||
        cropY + cropHeight > decoded.height) {
      throw ArgumentError('裁剪区域超出图片范围');
    }
    if (targetWidth <= 0 ||
        targetHeight <= 0 ||
        cropWidth * targetHeight != cropHeight * targetWidth) {
      throw ArgumentError('裁剪区域与目标画幅比例不一致');
    }

    final cropped = img.copyCrop(
      decoded,
      x: cropX,
      y: cropY,
      width: cropWidth,
      height: cropHeight,
    );
    final normalized = img.copyResize(
      cropped,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.cubic,
    );
    return typed_data.Uint8List.fromList(img.encodePng(normalized));
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

  /// NAI 局部重绘遮罩的 latent 对齐单元（8×8 像素对应一个 latent）。
  static const int naiLatentCell = 8;

  /// 将画板生成的 RGBA 遮罩编码为 NovelAI 局部重绘专用的单通道灰度 PNG。
  ///
  /// - 输入：`numChannels=4` 的 RGBA 遮罩，约定 NovelAI 语义（白色=重绘，黑色=保留）。
  /// - 输出：单通道灰度 PNG（`numChannels=1`），每个 8×8 latent 单元内取同一值（0 或 255），
  ///   通过最近邻降采样到 width/8 × height/8 后再最近邻升采样回原尺寸实现。
  ///
  /// 这样可对齐 NovelAI V4 latent 网格，并匹配成熟客户端（Aedial、ComfyUI_NAIDGenerator 等）
  /// 发送的单通道掩码格式，避免服务端把 RGBA alpha 解读成额外掩码导致灰块。
  static typed_data.Uint8List encodeNovelAiMask(img.Image rgbaMask) {
    return typed_data.Uint8List.fromList(
      img.encodePng(alignNovelAiMask(rgbaMask)),
    );
  }

  /// Shares the exact latent alignment with previews without a PNG round trip.
  static img.Image alignNovelAiMask(img.Image rgbaMask) {
    if (rgbaMask.width <= 0 || rgbaMask.height <= 0) {
      throw ArgumentError('遮罩尺寸必须大于 0');
    }

    // 1) 先把 RGBA 折叠为单通道灰度（白色=重绘→255，黑色=保留→0）。
    //    以 R 通道为基准（画板写入的 R 已经包含 0 或 255）。
    final gray = img.Image(
      width: rgbaMask.width,
      height: rgbaMask.height,
      numChannels: 1,
    );
    for (final pixel in rgbaMask) {
      // 对 NovelAI 语义：r==255 为重绘区域。
      gray.setPixelR(pixel.x, pixel.y, pixel.r);
    }

    // 2) 聚合到 latent 网格（ceil(width/8) × ceil(height/8)）。
    // 单元内任一像素被画为白色，就保留整个重绘单元，避免细笔迹因
    // 左上角像素恰好为黑色而被静默丢弃。
    final latentW = (gray.width + naiLatentCell - 1) ~/ naiLatentCell;
    final latentH = (gray.height + naiLatentCell - 1) ~/ naiLatentCell;
    final latent = img.Image(
      width: latentW,
      height: latentH,
      numChannels: 1,
    );
    for (var ly = 0; ly < latentH; ly++) {
      for (var lx = 0; lx < latentW; lx++) {
        final xStart = lx * naiLatentCell;
        final yStart = ly * naiLatentCell;
        final xEnd = (xStart + naiLatentCell).clamp(0, gray.width);
        final yEnd = (yStart + naiLatentCell).clamp(0, gray.height);
        var repaint = false;
        for (var y = yStart; y < yEnd && !repaint; y++) {
          for (var x = xStart; x < xEnd; x++) {
            if (gray.getPixel(x, y).r >= 128) {
              repaint = true;
              break;
            }
          }
        }
        latent.setPixelR(lx, ly, repaint ? 255 : 0);
      }
    }

    // 3) 最近邻升采样回原尺寸，保证每个 8×8 单元内值一致。
    final aligned = img.Image(
      width: gray.width,
      height: gray.height,
      numChannels: 1,
    );
    for (var y = 0; y < gray.height; y++) {
      final ly = (y ~/ naiLatentCell).clamp(0, latentH - 1);
      for (var x = 0; x < gray.width; x++) {
        final lx = (x ~/ naiLatentCell).clamp(0, latentW - 1);
        aligned.setPixelR(x, y, latent.getPixel(lx, ly).r);
      }
    }

    return aligned;
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
