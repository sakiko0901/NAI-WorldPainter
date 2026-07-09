/// OpenAI 兼容的 tool_call 实体
class ToolCall {
  /// 服务端返回的 id（用于回传 tool_call_id）
  final String id;

  /// 工具名（与 AgentTool.name 一致）
  final String name;

  /// 已解析的参数对象（JSON 反序列化后的 Map）
  final Map<String, dynamic> arguments;

  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  @override
  String toString() => 'ToolCall($name, args=$arguments)';
}
