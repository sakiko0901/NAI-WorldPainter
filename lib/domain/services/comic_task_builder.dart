import 'package:uuid/uuid.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/domain/entities/comic_project.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';

class ComicTaskBuilder {
  static const _uuid = Uuid();

  GenerationTask build({
    required ComicProject project,
    required ComicPanel panel,
    String? taskId,
  }) {
    final size = _parseSize(project.resolution);
    final textLines = panel.dialogues
        .where((dialogue) =>
            dialogue.generateText && dialogue.text.trim().isNotEmpty)
        .map((dialogue) => 'TEXT: ${dialogue.text.trim()}');
    final basePrompt = [
      if (project.globalPrompt.trim().isNotEmpty) project.globalPrompt.trim(),
      panel.prompt.trim(),
    ].join(', ');
    final prompt = textLines.isEmpty
        ? basePrompt
        : '$basePrompt\n\n${textLines.join('\n')}';
    if (prompt.trim().isEmpty) throw ArgumentError('分镜提示词不能为空');
    return GenerationTask(
      taskId: taskId ?? _uuid.v4(),
      model: project.model,
      endpointId: project.endpointId,
      protocol: project.protocol.isEmpty
          ? AppConstants.novelAiChatCompletionsProtocol
          : project.protocol,
      prompt: prompt,
      negativePrompt: project.negativePrompt.trim().isEmpty
          ? null
          : project.negativePrompt.trim(),
      width: size.$1,
      height: size.$2,
      size: project.resolution,
      scale: project.scale,
      cfgRescale: project.cfgRescale,
      sampler: project.sampler,
      noiseSchedule: project.noiseSchedule,
      steps: project.steps,
      seed: project.seed,
      status: AppConstants.taskPending,
      createdAt: DateTime.now(),
      providerType: ImageProviderType.novelAi,
    );
  }

  (int, int) _parseSize(String value) {
    final parts = value.split('x');
    if (parts.length != 2) throw ArgumentError('漫画分镜尺寸无效');
    final width = int.tryParse(parts[0]);
    final height = int.tryParse(parts[1]);
    if (width == null || height == null || width <= 0 || height <= 0) {
      throw ArgumentError('漫画分镜尺寸无效');
    }
    return (width, height);
  }
}
