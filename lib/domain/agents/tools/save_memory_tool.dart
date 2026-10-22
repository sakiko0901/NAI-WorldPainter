import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:nai_huishi/domain/services/prompt_memory_context.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_memories.dart';

/// 保存记忆到本地学习记忆库。所有由 Agent 创建的记忆都需要用户确认。
class SaveMemoryTool extends AgentTool {
  final ManagePromptMemoriesUseCase _memories;
  SaveMemoryTool(this._memories);

  @override
  String get name => 'save_memory';

  @override
  String get description => '把一条“触发词→正确内容”保存为待确认的本地记忆。'
      '支持 character_name、character_feature、style、character_outfit 及普通事实类型。'
      'character_name、character_feature、style 的内容必须是经 search_danbooru 核实存在的英文 Danbooru canonical tag，使用 lowercase 和 underscore，多个 tag 用半角逗号分隔；'
      'character_outfit 应保留完整自然语言服装描述，也可保存已向用户说明的参考图识别描述，不强制转换为 Danbooru tag。'
      '只有用户明确要求记住或更新某角色的标准穿搭时才保存 character_outfit；临时换装不能覆盖标准穿搭。'
      'trigger 填角色名或主要触发词，其他称呼放入可选 aliases。保存后仍为待确认，不会立即参与检索；'
      '必须告知用户在记忆管理页检查并确认后才会生效。';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'trigger': {
            'type': 'string',
            'maxLength': 512,
            'description': '主要触发词，例如角色名；可保留用户使用的中文或英文',
          },
          'aliases': {
            'type': 'array',
            'maxItems': 12,
            'items': {'type': 'string', 'maxLength': 512},
            'description': '可选别名字符串数组，例如该角色的其他称呼',
          },
          'content': {
            'type': 'string',
            'maxLength': 6000,
            'description': '正确内容；标准穿搭可用完整自然语言，或使用已经向用户说明的不确定项的参考图识别描述',
          },
          'type': {
            'type': 'string',
            'enum': [
              'character_name',
              'character_feature',
              'character_outfit',
              'style',
              'other',
              'fact',
              'preference',
              'observation',
              'decision',
            ],
            'description': '记忆类型，默认 other',
          },
        },
        'required': ['trigger', 'content'],
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final triggerValue = arguments['trigger'];
    if (triggerValue is! String) {
      return ToolResult.failure('trigger 必须是字符串');
    }
    final trigger = triggerValue.trim();
    if (trigger.isEmpty) return ToolResult.failure('trigger 不能为空');
    if (trigger.runes.length > 512) {
      return ToolResult.failure('trigger 不能超过 512 个字符');
    }

    final contentValue = arguments['content'];
    if (contentValue is! String) {
      return ToolResult.failure('content 必须是字符串');
    }
    final content = contentValue.trim();
    if (content.isEmpty) return ToolResult.failure('content 不能为空');
    if (content.runes.length > 6000) {
      return ToolResult.failure('content 不能超过 6000 个字符');
    }

    final aliasesValue = arguments['aliases'];
    final aliases = <String>[];
    if (arguments.containsKey('aliases')) {
      if (aliasesValue is! List) {
        return ToolResult.failure('aliases 必须是字符串数组');
      }
      if (aliasesValue.length > 12) {
        return ToolResult.failure('aliases 最多包含 12 项');
      }
      for (final value in aliasesValue) {
        if (value is! String) {
          return ToolResult.failure('aliases 中的每一项都必须是字符串');
        }
        if (value.trim().isEmpty) {
          return ToolResult.failure('aliases 不能包含空字符串');
        }
        aliases.add(value.trim());
      }
    }

    final typeValue = arguments['type'];
    if (arguments.containsKey('type') && typeValue is! String) {
      return ToolResult.failure('type 必须是字符串');
    }
    final typeString = typeValue is String ? typeValue.trim() : 'other';
    final type = _parseType(typeString);
    if (type == null) {
      return ToolResult.failure('未知记忆类型：$typeValue');
    }

    final combinedTrigger = PromptMemoryTriggers.encode([trigger, ...aliases]);
    if (combinedTrigger.isEmpty) {
      return ToolResult.failure('trigger 不能为空');
    }
    if (PromptMemoryTriggers.parse(combinedTrigger).length > 13) {
      return ToolResult.failure('trigger 加 aliases 最多支持 12 个别名');
    }
    if (combinedTrigger.runes.length > 512) {
      return ToolResult.failure('trigger 与 aliases 合计不能超过 512 个字符');
    }
    final now = DateTime.now();
    try {
      await _memories.save(PromptMemory(
        trigger: combinedTrigger,
        content: content,
        type: type,
        source: PromptMemorySource.pendingLlmCandidate,
        createdAt: now,
        updatedAt: now,
      ));
      final outfitNote = type == PromptMemoryType.characterOutfit
          ? '这是一条角色标准穿搭候选；临时换装不会覆盖它。'
          : '';
      return ToolResult.success(
        '已创建待确认记忆：$combinedTrigger → $content。$outfitNote'
        '目前尚未生效、不会参与检索；请告知用户到记忆管理页检查并确认后，才会跨聊天生效。',
        displayText: '已创建待确认记忆：$trigger',
      );
    } catch (e) {
      return ToolResult.failure('保存记忆失败：$e');
    }
  }

  PromptMemoryType? _parseType(String value) {
    switch (value) {
      case 'character_name':
        return PromptMemoryType.characterName;
      case 'character_feature':
        return PromptMemoryType.characterFeature;
      case 'character_outfit':
        return PromptMemoryType.characterOutfit;
      case 'style':
        return PromptMemoryType.style;
      case 'other':
        return PromptMemoryType.other;
      case 'fact':
        return PromptMemoryType.fact;
      case 'preference':
        return PromptMemoryType.preference;
      case 'observation':
        return PromptMemoryType.observation;
      case 'decision':
        return PromptMemoryType.decision;
      default:
        return null;
    }
  }
}
