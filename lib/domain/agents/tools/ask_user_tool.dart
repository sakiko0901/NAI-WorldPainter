import 'dart:math';

import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/entities/llm_interaction.dart';

class AskUserTool extends AgentTool {
  @override
  String get name => 'ask_user';

  @override
  String get description =>
      '当缺少会实质影响结果的关键信息时，向用户提出一个单选问题。必须提供清晰、简短、互斥的选项；不要猜测用户未说明的偏好。用户选择后会自动继续当前任务。';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'question': {'type': 'string', 'description': '要询问用户的问题'},
          'options': {
            'type': 'array',
            'minItems': 2,
            'maxItems': 6,
            'items': {
              'type': 'object',
              'properties': {
                'id': {'type': 'string'},
                'label': {'type': 'string'},
                'value': {'type': 'string'},
              },
              'required': ['id', 'label'],
            },
          },
          'allow_custom': {
            'type': 'boolean',
            'description': '是否显示自定义回答入口，默认 true',
          },
          'custom_placeholder': {'type': 'string'},
        },
        'required': ['question', 'options'],
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final question = arguments['question']?.toString().trim() ?? '';
    final rawOptions = arguments['options'];
    if (question.isEmpty || rawOptions is! List || rawOptions.length < 2) {
      return ToolResult.failure('问题必须非空，且至少提供两个选项');
    }
    if (rawOptions.length > 6) {
      return ToolResult.failure('选项不能超过六个');
    }

    final options = rawOptions
        .map(LlmInteractionOption.fromJson)
        .whereType<LlmInteractionOption>()
        .toList();
    final ids = options.map((option) => option.id).toSet();
    if (options.length != rawOptions.length || ids.length != options.length) {
      return ToolResult.failure('每个选项都必须包含唯一的 id 和 label');
    }

    final interaction = LlmInteraction(
      id: 'interaction-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1000)}',
      question: question,
      options: List.unmodifiable(options),
      allowCustom: arguments['allow_custom'] as bool? ?? true,
      customPlaceholder: arguments['custom_placeholder']?.toString().trim(),
      createdAt: DateTime.now(),
    );
    return ToolResult.success(
      '已向用户提出问题：$question',
      displayText: '等待用户选择',
      interaction: interaction,
    );
  }
}
