import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/nai_model.dart';
import 'package:nai_huishi/domain/repositories/generation_repository.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/domain/services/tiled_img2img_service.dart';

void main() {
  final service = TiledImg2ImgService(
    GenerationQueue(_GenerationRepository(), _HistoryRepository()),
  );

  test('builds 640px tiles with 320px stride and 1024px requests', () {
    final tiles = service.buildTiles(1024, 1024);
    expect(tiles, hasLength(16));
    expect(tiles.first.cropX, 0);
    expect(tiles.first.cropY, 0);
    expect(tiles.first.cropWidth, 640);
    expect(tiles.first.cropHeight, 640);
    expect(tiles.first.requestWidth, 1024);
    expect(tiles.first.requestHeight, 1024);
    expect(tiles[1].cropX, 320);
    expect(tiles[4].cropY, 320);
  });

  test('pads edge tiles with opaque edge pixels', () {
    final source = img.Image(width: 700, height: 700, numChannels: 3);
    img.fill(source, color: img.ColorRgb8(10, 20, 30));
    source.setPixelRgb(699, 699, 90, 100, 110);
    final tile = service.buildTiles(700, 700).last;
    final encoded = service.encodeTile(source, tile);
    final decoded = img.decodePng(Uint8List.fromList(encoded))!;

    expect(decoded.width, 640);
    expect(decoded.height, 640);
    expect(decoded.numChannels, 3);
    final corner = decoded.getPixel(639, 639);
    expect((corner.r, corner.g, corner.b), (90, 100, 110));
  });
}

class _GenerationRepository implements GenerationRepository {
  @override
  Future<void> cancelTask(String taskId) async {}

  @override
  Future<List<NaiModel>> fetchModels() async => [];

  @override
  Future<GenerationTask> submitGeneration(GenerationTask task) async => task;

  @override
  void setStreamPreviewHandler(
      String taskId, void Function(Uint8List bytes, int? step)? onFrame) {}
}

class _HistoryRepository implements HistoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
