import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/data/datasources/local/nai_metadata_parser.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';

class WorkspaceImageImporter {
  /// Runs in an isolate so decoding and optional PNG metadata do not block gestures.
  static Future<GenerationTask> read(String path) async {
    final bytes = await File(path).readAsBytes();
    final isPng = bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50;
    img.Image? image;
    img.DecodeInfo? info;
    try {
      if (isPng) {
        info = img.PngDecoder().startDecode(bytes);
      } else {
        image = img.decodeImage(bytes);
      }
    } catch (_) {
      throw const FormatException('无法读取图片');
    }
    final width = info?.width ?? image?.width;
    final height = info?.height ?? image?.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      throw const FormatException('无法读取图片');
    }
    // Large PNGs retain their full image and text metadata without allocating
    // another RGBA image and alpha buffer for optional stealth inspection.
    final tags = isPng
        ? NaiMetadataParser.parseBytes(bytes,
            allowStealth: width * height <= 4 * 1024 * 1024)
        : null;
    final orientation = image?.exif.imageIfd.orientation ?? 1;
    final swapAxes = orientation >= 5 && orientation <= 8;
    final metadata = tags?.metadata ?? const <String, dynamic>{};
    num? number(String key) => metadata[key] is num
        ? metadata[key] as num
        : num.tryParse('${metadata[key]}');
    final now = DateTime.now();
    return GenerationTask(
      taskId: 'import-${const Uuid().v4()}',
      model: 'imported-image',
      prompt: tags?.selectedGeneralTags ?? '',
      negativePrompt: tags?.negativePrompt,
      width: swapAxes ? height : width,
      height: swapAxes ? width : height,
      seed: number('seed')?.toInt(),
      scale: number('scale')?.toDouble() ?? 0,
      cfgRescale: number('cfg_rescale')?.toDouble() ?? 0,
      steps: number('steps')?.toInt() ?? 0,
      sampler: metadata['sampler']?.toString() ?? '',
      noiseSchedule: metadata['noise_schedule']?.toString() ?? '',
      characters: tags?.characters,
      imagePath: path,
      status: AppConstants.taskSuccess,
      createdAt: now,
      completedAt: now,
    );
  }
}
