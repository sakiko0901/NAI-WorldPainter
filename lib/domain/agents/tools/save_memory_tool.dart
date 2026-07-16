import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_memories.dart';

/// 保存记忆到本地学习记忆库。
class SaveMemoryTool extends AgentTool {
  final ManagePromptMemoriesUseCase _memories;
  SaveMemoryTool(this._memories);

  @override
  String get name => 'save_memory';

  @override
  String get description => '把一条"触发词→正确内容"映射保存到本地学习记忆库。当用户明确纠正人名、角色特征、画风知识时调用。'
      'trigger 可保留用户使用的中文或英文别名；character_name、character_feature、style 的 content 必须是经 search_danbooru 确认存在的英文 Danbooru canonical tag，使用 lowercase 和 underscore，多个 tag 用半角逗号分隔。'
      'other 类型可保存普通事实文本。记忆默认标记为 pendingLlmCandidate（待确认），不立即参与检索。'
      'trigger 和 content 都不能为空。type 默认为 other，可选 character_name/character_feature/style/other。';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'trigger': {
            'type': 'string',
            'description': '触发词或别名（可保留用户使用的中文，如"纳西妲"）',
          },
          'content': {
            'type': 'string',
            'description':
                '正确内容。tag 类型必须是英文 Danbooru canonical tag，如 green_eyes, long_hair',
          },
          'type': {
            'type': 'string',
            'enum': ['character_name', 'character_feature', 'style', 'other'],
            'description': '记忆类型，默认 other',
          },
        },
        'required': ['trigger', 'content'],
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final trigger = (arguments['trigger'] as String?)?.trim() ?? '';
    final content = (arguments['content'] as String?)?.trim() ?? '';
    final typeStr = (arguments['type'] as String?)?.trim() ?? 'other';
    if (trigger.isEmpty) return ToolResult.failure('trigger 不能为空');
    if (content.isEmpty) return ToolResult.failure('content 不能为空');

    final type = _parseType(typeStr);
    final now = DateTime.now();
    try {
      await _memories.save(PromptMemory(
        trigger: trigger,
        content: content,
        type: type,
        source: PromptMemorySource.pendingLlmCandidate,
        createdAt: now,
        updatedAt: now,
      ));
      return ToolResult.success(
        '已保存记忆：$trigger → $content（待用户在记忆管理页确认后生效）。',
        displayText: '已保存记忆：$trigger',
      );
    } catch (e) {
      return ToolResult.failure('保存记忆失败：$e');
    }
  }

  PromptMemoryType _parseType(String s) {
    switch (s) {
      case 'character_name':
        return PromptMemoryType.characterName;
      case 'character_feature':
        return PromptMemoryType.characterFeature;
      case 'style':
        return PromptMemoryType.style;
      default:
        return PromptMemoryType.other;
    }
  }
}
