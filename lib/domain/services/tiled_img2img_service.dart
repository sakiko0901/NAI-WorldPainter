import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/tiled_img2img.dart';

class TiledImg2ImgService {
  final GenerationQueue _queue;

  TiledImg2ImgService(this._queue);

  Future<String> execute({
    required GenerationTask baseTask,
    required String sourcePath,
    required double strength,
    required bool Function() isCancelled,
    void Function(TiledImg2ImgProgress progress)? onProgress,
  }) async {
    final source = img.decodeImage(await File(sourcePath).readAsBytes());
    if (source == null) {
      throw const FormatException('无法读取分块重绘原图');
    }
    if (source.width > TiledImg2ImgConfig.maxCanvasDimension ||
        source.height > TiledImg2ImgConfig.maxCanvasDimension ||
        source.width * source.height > TiledImg2ImgConfig.maxCanvasPixels) {
      throw ArgumentError('图片尺寸超过分块重绘上限');
    }

    final tiles = buildTiles(source.width, source.height);
    final dir = Directory(p.join(
      (await getTemporaryDirectory()).path,
      'tiled_img2img',
      baseTask.taskId,
    ));
    await dir.create(recursive: true);
    try {
      final results = <Img2ImgTile, img.Image>{};
      onProgress?.call(TiledImg2ImgProgress(0, tiles.length));
      for (var i = 0; i < tiles.length; i++) {
        if (isCancelled()) throw const TiledImg2ImgCancelled();
        final tile = tiles[i];
        final tileImage = encodeTile(source, tile);
        final tileFile = File(p.join(dir.path, 'tile_${tile.index}.png'));
        await tileFile.writeAsBytes(tileImage);
        final task = baseTask.copyWith(
          taskId: const Uuid().v4(),
          width: tile.requestWidth,
          height: tile.requestHeight,
          img2imgSourceImagePath: tileFile.path,
          img2imgStrength: strength,
          sourceImagePath: null,
          maskImagePath: null,
          mode: GenerationMode.textToImage,
          isInternal: true,
          seed: baseTask.seed == null ? null : _tileSeed(baseTask.seed!, tile),
        );
        final wait = _queue.taskStream.firstWhere((item) =>
            item.taskId == task.taskId &&
            (item.status == AppConstants.taskSuccess ||
                item.status == AppConstants.taskFailed));
        await _queue.enqueueTransient(task);
        final completed = await wait;
        if (completed.status != AppConstants.taskSuccess ||
            completed.imagePath == null) {
          throw StateError(
              '第 ${i + 1}/${tiles.length} 个分块重绘失败：${completed.errorMessage ?? '未知错误'}');
        }
        final result =
            img.decodeImage(await File(completed.imagePath!).readAsBytes());
        if (result == null) {
          throw StateError('第 ${i + 1} 个分块结果无法读取');
        }
        results[tile] = result;
        try {
          await tileFile.delete();
        } catch (_) {}
        onProgress?.call(TiledImg2ImgProgress(i + 1, tiles.length));
      }
      final merged = _stitch(source, results);
      final imageDir = await ImageUtils.getImageDirectory();
      final persistent =
          File(p.join(imageDir.path, ImageUtils.generateFilename()));
      await persistent.writeAsBytes(img.encodePng(merged));
      return persistent.path;
    } finally {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }

  List<Img2ImgTile> buildTiles(int width, int height) {
    final tiles = <Img2ImgTile>[];
    var index = 0;
    var row = 0;
    for (var y = 0; y < height; y += TiledImg2ImgConfig.stride) {
      var column = 0;
      for (var x = 0; x < width; x += TiledImg2ImgConfig.stride) {
        tiles.add(Img2ImgTile(
          index: index++,
          row: row,
          column: column++,
          cropX: x,
          cropY: y,
          cropWidth: math.min(TiledImg2ImgConfig.tileSize, width - x),
          cropHeight: math.min(TiledImg2ImgConfig.tileSize, height - y),
          requestWidth: TiledImg2ImgConfig.requestSize,
          requestHeight: TiledImg2ImgConfig.requestSize,
        ));
      }
      row++;
    }
    if (tiles.length > TiledImg2ImgConfig.maxTiles) {
      throw ArgumentError('分块数量超过 ${TiledImg2ImgConfig.maxTiles} 块');
    }
    return tiles;
  }

  List<int> encodeTile(img.Image source, Img2ImgTile tile) {
    final output = img.Image(
      width: TiledImg2ImgConfig.tileSize,
      height: TiledImg2ImgConfig.tileSize,
      numChannels: 3,
    );
    for (var y = 0; y < TiledImg2ImgConfig.tileSize; y++) {
      final sourceY = (tile.cropY + y).clamp(0, source.height - 1);
      for (var x = 0; x < TiledImg2ImgConfig.tileSize; x++) {
        final sourceX = (tile.cropX + x).clamp(0, source.width - 1);
        final pixel = source.getPixel(sourceX, sourceY);
        output.setPixelRgb(x, y, pixel.r, pixel.g, pixel.b);
      }
    }
    return img.encodePng(output);
  }

  int _tileSeed(int seed, Img2ImgTile tile) {
    var value = seed & 0x7fffffff;
    value = (value * 31 + tile.row) & 0x7fffffff;
    value = (value * 31 + tile.column) & 0x7fffffff;
    return value;
  }

  img.Image _stitch(
    img.Image source,
    Map<Img2ImgTile, img.Image> results,
  ) {
    final outW = (source.width * TiledImg2ImgConfig.outputScale).round();
    final outH = (source.height * TiledImg2ImgConfig.outputScale).round();
    final sums = List<double>.filled(outW * outH * 3, 0);
    final weights = List<double>.filled(outW * outH, 0);
    for (final entry in results.entries) {
      final tile = entry.key;
      final result = entry.value;
      final scaleX = result.width / tile.requestWidth;
      final scaleY = result.height / tile.requestHeight;
      final outCropW =
          (tile.cropWidth * TiledImg2ImgConfig.outputScale).round();
      final outCropH =
          (tile.cropHeight * TiledImg2ImgConfig.outputScale).round();
      final outCropX = (tile.cropX * TiledImg2ImgConfig.outputScale).round();
      final outCropY = (tile.cropY * TiledImg2ImgConfig.outputScale).round();
      for (var y = 0; y < outCropH; y++) {
        for (var x = 0; x < outCropW; x++) {
          final canvasX = outCropX + x;
          final canvasY = outCropY + y;
          if (canvasX >= outW || canvasY >= outH) continue;
          final localX = math.min(result.width - 1, (x / scaleX).round());
          final localY = math.min(result.height - 1, (y / scaleY).round());
          final edgeX = math.min(x, outCropW - 1 - x);
          final edgeY = math.min(y, outCropH - 1 - y);
          final feather = math.min(1.0, math.min(edgeX, edgeY) / 64.0);
          final weight = math.max(0.05, feather);
          final pixel = result.getPixel(localX, localY);
          final index = canvasY * outW + canvasX;
          sums[index * 3] += pixel.r * weight;
          sums[index * 3 + 1] += pixel.g * weight;
          sums[index * 3 + 2] += pixel.b * weight;
          weights[index] += weight;
        }
      }
    }
    final output = img.Image(width: outW, height: outH, numChannels: 3);
    const srcScale = TiledImg2ImgConfig.outputScale;
    for (var y = 0; y < outH; y++) {
      for (var x = 0; x < outW; x++) {
        final index = y * outW + x;
        if (weights[index] <= 0) {
          final sx = (x / srcScale).floor().clamp(0, source.width - 1);
          final sy = (y / srcScale).floor().clamp(0, source.height - 1);
          final pixel = source.getPixel(sx, sy);
          output.setPixelRgb(x, y, pixel.r, pixel.g, pixel.b);
        } else {
          output.setPixelRgb(
            x,
            y,
            (sums[index * 3] / weights[index]).round().clamp(0, 255),
            (sums[index * 3 + 1] / weights[index]).round().clamp(0, 255),
            (sums[index * 3 + 2] / weights[index]).round().clamp(0, 255),
          );
        }
      }
    }
    return output;
  }
}

class TiledImg2ImgCancelled implements Exception {
  const TiledImg2ImgCancelled();
}
