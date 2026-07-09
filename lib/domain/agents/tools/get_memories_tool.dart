import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_memories.dart';

/// 查询本地学习记忆。Agent 用它取回用户曾经纠正过的 trigger→content 映射。
class GetMemoriesTool extends AgentTool {
  final ManagePromptMemoriesUseCase _memories;

  GetMemoriesTool(this._memories);

  @override
  String get name => 'get_memories';

  @override
  String get description =>
      '查询本地学习记忆库。当用户文本中出现某些关键词、人名、画风名时，可能存在用户曾经纠正过的"触发词→正确内容"映射。'
      '在编排 NovelAI 提示词前调用本工具，可避免重复犯错。'
      '参数 query 可以是用户原文或一段关键词，返回匹配到的记忆列表。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '要查询的文本，建议直接传用户最新一条消息的原文',
          },
        },
        'required': ['query'],
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final query = (arguments['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) {
      return ToolResult.failure('query 不能为空');
    }
    final matched = await _memories.matchText(query);
    if (matched.isEmpty) {
      return ToolResult.success(
        '没有命中任何本地记忆。',
        displayText: '无命中记忆',
      );
    }
    // 命中后异步更新 hit_count
    for (final m in matched) {
      final id = m.id;
      if (id != null) {
        // fire-and-forget
        _memories.incrementHit(id);
      }
    }
    final buf = StringBuffer();
    buf.writeln('命中 ${matched.length} 条本地记忆：');
    for (int i = 0; i < matched.length; i++) {
      final m = matched[i];
      buf.writeln('${i + 1}. 触发词：${m.trigger}');
      buf.writeln('   内容：${m.content}');
      buf.writeln('   来源：${m.source.label}，类型：${m.type.label}');
    }
    buf.writeln('这些记忆的优先级高于 Danbooru 与模型常识，必须遵循。');
    return ToolResult.success(
      buf.toString(),
      displayText: '命中 ${matched.length} 条记忆',
    );
  }
}

/// 给 PromptMemory 的枚举加 label 辅助方法（避免在 entity 里加，保留 entity 简洁）
extension PromptMemoryTypeLabel on PromptMemoryType {
  String get label {
    switch (this) {
      case PromptMemoryType.characterName:
        return '角色名';
      case PromptMemoryType.characterFeature:
        return '角色特征';
      case PromptMemoryType.style:
        return '画风';
      case PromptMemoryType.other:
        return '其他';
      case PromptMemoryType.fact:
        return '事实';
      case PromptMemoryType.preference:
        return '偏好';
      case PromptMemoryType.observation:
        return '观察';
      case PromptMemoryType.decision:
        return '决策';
    }
  }
}

extension PromptMemorySourceLabel on PromptMemorySource {
  String get label {
    switch (this) {
      case PromptMemorySource.manual:
        return '手动';
      case PromptMemorySource.userInstruction:
        return '用户指令';
      case PromptMemorySource.llmCandidate:
        return 'LLM 候选';
      case PromptMemorySource.pendingLlmCandidate:
        return 'LLM 候选（待确认）';
    }
  }
}
