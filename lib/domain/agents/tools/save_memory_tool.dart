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
      '例如用户说"记住：纳西妲是青绿眼"，trigger="纳西妲"，content="青绿眼"。'
      '记忆默认标记为 pendingLlmCandidate（待确认），不立即参与检索。'
      'trigger 和 content 都不能为空。type 默认为 other，可选 character_name/character_feature/style/other。';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'trigger': {
            'type': 'string',
            'description': '触发词（用户纠正的对象，如角色名"纳西妲"）',
          },
          'content': {
            'type': 'string',
            'description': '正确内容（如"青绿眼"、"胡桃的宿雪樱红皮肤"）',
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
