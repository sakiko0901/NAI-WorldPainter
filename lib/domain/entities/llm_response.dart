import 'package:nai_huishi/domain/entities/tool_call.dart';

/// LLM 一次返回的封装
class LlmResponse {
  /// assistant 文本回复（可能为空字符串，当只调 tool 时）
  final String content;

  /// assistant 触发的工具调用列表（无则为空）
  final List<ToolCall> toolCalls;

  /// 'stop' / 'tool_calls' / 'length' / ...
  final String finishReason;

  final int? promptTokens;
  final int? completionTokens;

  const LlmResponse({
    this.promptTokens,
    this.completionTokens,
    required this.content,
    required this.toolCalls,
    required this.finishReason,
  });

  bool get hasToolCalls => toolCalls.isNotEmpty;
}
