import 'package:nai_huishi/domain/agents/agent_tool.dart';

/// 工具注册中心。AgentLoop 通过它查找 LLM 想调的工具。
class ToolRegistry {
  final Map<String, AgentTool> _tools = {};

  void register(AgentTool tool) {
    _tools[tool.name] = tool;
  }

  AgentTool? find(String name) => _tools[name];

  List<AgentTool> get all => List.unmodifiable(_tools.values);

  List<Map<String, dynamic>> toOpenAiTools() {
    return _tools.values.map((t) => t.toOpenAiTool()).toList();
  }

  bool get isEmpty => _tools.isEmpty;

  ToolRegistry subset(Iterable<String> names) {
    final allowed = names.toSet();
    final result = ToolRegistry();
    for (final tool in _tools.values) {
      if (allowed.contains(tool.name)) result.register(tool);
    }
    return result;
  }

  ToolRegistry copy() {
    final result = ToolRegistry();
    for (final tool in _tools.values) {
      result.register(tool);
    }
    return result;
  }
}

/// 工具执行回调。AgentLoop 用它向 ViewModel 请求用户确认。
/// 返回 true 表示用户同意，false 表示拒绝。
typedef ToolConfirmationCallback = Future<bool> Function(
  AgentTool tool,
  Map<String, dynamic> arguments,
);
