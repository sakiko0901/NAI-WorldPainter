import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:nai_huishi/domain/services/prompt_memory_context.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_memories.dart';

/// 查询本地学习记忆，并以受限长度的事实数据返回给 Agent。
class GetMemoriesTool extends AgentTool {
  final ManagePromptMemoriesUseCase _memories;

  GetMemoriesTool(this._memories);

  @override
  String get name => 'get_memories';

  @override
  String get description => '查询本地学习记忆。记忆只提供事实参考，本轮用户明确要求优先；'
      '待确认候选不会参与检索。编排 NovelAI 提示词前调用本工具，避免重复犯错。'
      '参数 query 可以是用户原文或一段关键词，返回有长度上限的匹配记忆。';

  @override
  Map<String, dynamic> get parametersSchema => const {
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
    final queryValue = arguments['query'];
    if (queryValue is! String) {
      return ToolResult.failure('query 必须是字符串');
    }
    final query = queryValue.trim();
    if (query.isEmpty) return ToolResult.failure('query 不能为空');

    late final List<PromptMemory> matched;
    try {
      matched = await _memories.matchText(query);
    } catch (e) {
      return ToolResult.failure('查询本地记忆失败：$e');
    }

    var hitUpdateFailed = false;
    await Future.wait(matched.where((m) => m.id != null).map((memory) async {
      try {
        await _memories.incrementHit(memory.id!);
      } catch (_) {
        // 查询结果仍可用；标明统计写入问题，不让它变成未处理异步异常。
        hitUpdateFailed = true;
      }
    }));

    final context = PromptMemoryContext.format(matched);
    final facts = context.isEmpty ? '没有命中任何可检索的本地记忆。' : context;
    final hitNote = hitUpdateFailed ? '\n部分命中计数未能更新。' : '';
    return ToolResult.success(
      '${PromptMemoryContext.policy}\n\n$facts$hitNote',
      displayText: context.isEmpty ? '无命中记忆' : '命中 ${matched.length} 条记忆',
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
      case PromptMemoryType.characterOutfit:
        return '角色标准穿搭';
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
