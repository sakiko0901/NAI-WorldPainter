import 'dart:typed_data';

import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/nai_model.dart';

/// 生成结果：成功返回 task，失败抛出 ApiException
abstract class GenerationRepository {
  /// 提交单个生成任务（直接调用 API，不走队列）
  Future<GenerationTask> submitGeneration(GenerationTask task);

  /// 流式预览回调（仅官方渠道 V4/V4.5/V5 生效）。
  /// key 为 taskId；value 在任务完成后由仓库清除。
  void setStreamPreviewHandler(
      String taskId, void Function(Uint8List bytes, int? step)? onFrame);

  /// 获取模型列表
  Future<List<NaiModel>> fetchModels();

  /// 取消任务
  Future<void> cancelTask(String taskId);
}
