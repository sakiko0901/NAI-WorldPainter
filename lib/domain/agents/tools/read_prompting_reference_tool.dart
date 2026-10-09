import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/services/prompting_skill_loader.dart';

class ReadPromptingReferenceTool extends AgentTool {
  final PromptingSkillLoader _loader;

  ReadPromptingReferenceTool(this._loader);

  @override
  String get name => 'read_prompting_reference';

  @override
  String get description =>
      '读取 NovelAI Diffusion V5 提示词 Skill 的参考规则。用户需求模糊、需要构思画面或多个方向时先读 ideation；'
      '准备编排、修改或写入 V5 提示词时必须读 writing，并在写完后按其中检查表自检。只供 V5 普通提示词会话使用。';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'reference': {
            'type': 'string',
            'enum': ['ideation', 'writing'],
            'description': 'ideation=通用构思，writing=通用写法',
          },
        },
        'required': ['reference'],
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final raw = (arguments['reference'] as String?)?.trim() ?? '';
    final reference = switch (raw) {
      'ideation' => PromptingReference.ideation,
      'writing' => PromptingReference.writing,
      _ => null,
    };
    if (reference == null) {
      return ToolResult.failure('reference 只能是 ideation 或 writing');
    }
    try {
      final content = await _loader.loadReference(reference);
      return ToolResult.success(
        content,
        displayText: reference == PromptingReference.ideation
            ? '已读取 V5 构思规则'
            : '已读取 V5 写法规则',
      );
    } catch (e) {
      return ToolResult.failure('读取 V5 提示词参考失败：$e');
    }
  }
}
