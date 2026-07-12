import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';

/// 保存图片到本地相册。副作用工具，需用户确认。
/// image_path 是本地文件路径，或 task_id 用于从历史记录中查。
class SaveImageTool extends AgentTool {
  final SaveImageUseCase _useCase;
  final HistoryRepository _historyRepo;
  SaveImageTool(this._useCase, this._historyRepo);

  @override
  String get name => 'save_image';

  @override
  String get description => '把图片保存到系统相册。副作用工具，需用户确认。'
      'image_path 是本地图片文件路径（绝对路径）。'
      '保存成功返回保存后的本地路径。';

  @override
  bool get requireConfirmation => true;

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'image_path': {
            'type': 'string',
            'description': '本地图片文件绝对路径',
          },
        },
        'required': ['image_path'],
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final imagePath = (arguments['image_path'] as String?)?.trim() ?? '';
    if (imagePath.isEmpty) {
      return ToolResult.failure('image_path 不能为空');
    }
    try {
      // 构造一个轻量 GenerationTask 用于 SaveImageUseCase
      final task = GenerationTask(
        taskId: 'save_${DateTime.now().millisecondsSinceEpoch}',
        model: '',
        prompt: '',
        width: 0,
        height: 0,
        scale: 0,
        cfgRescale: 0,
        sampler: '',
        noiseSchedule: '',
        status: 'success',
        imagePath: imagePath,
        createdAt: DateTime.now(),
      );
      final savedPath = await _useCase.execute(task);
      final galleryOk = await _useCase.saveToGallery(savedPath);
      return ToolResult.success(
        galleryOk ? '已保存到本地相册。路径：$savedPath' : '已保存到本地目录：$savedPath（保存到相册失败）',
        displayText: galleryOk ? '已保存到相册' : '已保存到本地',
        followUpHint: '{"saved_path":"$savedPath","gallery_saved":$galleryOk}',
      );
    } catch (e) {
      return ToolResult.failure('保存图片失败：$e');
    }
  }
}
