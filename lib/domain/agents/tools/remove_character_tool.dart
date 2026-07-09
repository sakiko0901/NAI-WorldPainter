import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';

/// 删除指定多角色格子（character_N）。
/// 当不需要那么多角色格时，agent 可调用此工具清理多余格子。
class RemoveCharacterTool extends AgentTool {
  final GenerationViewModel _genVm;
  RemoveCharacterTool(this._genVm);

  @override
  String get name => 'remove_character';

  @override
  String get description =>
      '删除指定的多角色格子。当用户不需要那么多角色、或某个角色不再需要时调用。'
      'index 是 1-based 角色序号（1-6），对应 write_prompt 的 character_N。'
      '\n\n使用场景：'
      '\n- 用户原本要 3 角色生图，临时改成 2 角色 → 删除第 3 个角色格'
      '\n- 用户取消多角色设定，改成单角色 → 依次删除所有角色格（或调 clear_characters）'
      '\n- 多角色格过多导致生图失败时，删除多余格'
      '\n\n注意：删除会清空该格的 prompt 和 uc。'
      '如果 index 超出当前角色数，工具返回错误（不会自动补齐）。';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'index': {
            'type': 'integer',
            'description': '要删除的角色序号（1-based，1-6）',
          },
        },
        'required': ['index'],
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final raw = arguments['index'];
    if (raw == null) {
      return ToolResult.failure('index 不能为空');
    }
    final index = (raw is int) ? raw : int.tryParse(raw.toString());
    if (index == null || index < 1 || index > 6) {
      return ToolResult.failure('index 必须是 1-6 的整数');
    }
    final chars = _genVm.characters;
    if (index > chars.length) {
      return ToolResult.failure(
          '当前只有 ${chars.length} 个角色格，无法删除第 $index 个');
    }
    _genVm.removeCharacter(index - 1);
    return ToolResult.success(
      '已删除角色 $index。当前剩余 ${_genVm.characters.length} 个角色格。',
      displayText: '已删除角色 $index 格',
    );
  }
}

/// 清空所有多角色格子（保留 positive/negative 不动）。
class ClearCharactersTool extends AgentTool {
  final GenerationViewModel _genVm;
  ClearCharactersTool(this._genVm);

  @override
  String get name => 'clear_characters';

  @override
  String get description =>
      '清空所有多角色格子（character_1 到 character_N）。'
      '当用户从多角色场景切换到单角色场景、或要重新编排所有角色时调用。'
      '只清角色格，不影响 positive / negative / inpaint 框。';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {},
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final count = _genVm.characters.length;
    // 逐个从后往前删，避免索引错乱
    for (int i = _genVm.characters.length - 1; i >= 0; i--) {
      _genVm.removeCharacter(i);
    }
    return ToolResult.success(
      '已清空全部 $count 个角色格。',
      displayText: '已清空全部角色格',
    );
  }
}
