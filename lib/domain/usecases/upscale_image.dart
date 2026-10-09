import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:nai_huishi/domain/entities/sr_model.dart';
import 'package:nai_huishi/domain/repositories/super_resolution_repository.dart';

/// 图片超分用例。负责准备输入/输出路径并调用仓库执行超分。
class UpscaleImageUseCase {
  final SuperResolutionRepository _repo;

  UpscaleImageUseCase(this._repo);

  /// 首次使用前释放模型（幂等）。
  Future<void> prepare() => _repo.prepareModels();

  /// 对 [inputPath] 执行超分，输出到应用临时目录，返回输出文件路径。
  Future<String> execute({
    required String inputPath,
    required SrModel model,
    void Function(String line)? onProgress,
  }) async {
    final tmpDir = await getTemporaryDirectory();
    final outDir = Directory(p.join(tmpDir.path, 'sr_out'));
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final outputPath = p.join(outDir.path, 'sr_${ts}_x${model.scale}.png');

    return _repo.upscale(
      inputPath: inputPath,
      outputPath: outputPath,
      model: model,
      onProgress: onProgress,
    );
  }

  Future<void> cancel() => _repo.cancel();
}
