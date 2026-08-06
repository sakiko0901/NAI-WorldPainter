import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';

/// 调用生图队列生成图像。副作用工具，需用户确认。
/// 复用 GenerationViewModel 当前配置（model/resolution/sampler/scale 等），
/// 工具可覆盖 prompt / negativePrompt / batchCount。
class GenerateImageTool extends AgentTool {
  final GenerationViewModel _genVm;
  GenerateImageTool(this._genVm);

  @override
  String get name => 'generate_image';

  @override
  String get description => '调用生图队列生成图像（需用户确认）。'
      '默认使用 GenerationViewModel 当前配置（model/resolution/sampler/scale/seed 等）。'
      '可通过 prompt 参数临时覆盖正向提示词，通过 negative_prompt 覆盖负向，通过 batch_count 指定批量。'
      '生成完成后图像会显示在生图区，用户可继续操作。';

  @override
  bool get requireConfirmation => true;

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'prompt': {
            'type': 'string',
            'description': '正向提示词。不传则使用当前提示词框内容',
          },
          'negative_prompt': {
            'type': 'string',
            'description': '负向提示词。不传则使用当前负向框内容',
          },
          'batch_count': {
            'type': 'integer',
            'minimum': 1,
            'maximum': AppConstants.maxBatchCount,
            'description': '批量张数，1-30；不传则使用当前批量设置',
          },
        },
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final prompt = (arguments['prompt'] as String?)?.trim();
    final negative = (arguments['negative_prompt'] as String?)?.trim();
    final batchRaw = arguments['batch_count'];
    int? batch;
    if (batchRaw is int) {
      batch = batchRaw;
    } else if (batchRaw is String) {
      batch = int.tryParse(batchRaw);
    }
    if (prompt != null && prompt.isNotEmpty) {
      await _genVm.updatePrompt(prompt);
    }
    if (negative != null && negative.isNotEmpty) {
      await _genVm.updateNegativePrompt(negative);
    }
    if (batch != null) {
      await _genVm.updateBatchCount(batch.clamp(1, AppConstants.maxBatchCount));
    }
    try {
      final previousTaskId = _genVm.lastCompletedTask?.taskId;
      await _genVm.generate();
      final error = _genVm.errorMessage?.trim();
      if (error != null && error.isNotEmpty) {
        return ToolResult.failure('生图失败：$error');
      }
      if (_genVm.lastCompletedTask?.taskId == previousTaskId) {
        return ToolResult.failure('生图未产生新结果，请检查当前模型、渠道和提示词配置');
      }
      return ToolResult.success(
        '已完成生图任务（batch_count=${_genVm.batchCount}）。结果已显示在生图区。',
        displayText: '生图已完成',
      );
    } catch (e) {
      return ToolResult.failure('生图失败：$e');
    }
  }
}
