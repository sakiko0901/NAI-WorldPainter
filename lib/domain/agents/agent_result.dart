import 'package:flutter/foundation.dart';
import 'package:nai_huishi/domain/agents/agent_event.dart';

/// Agent 循环的最终输出
@immutable
class AgentResult {
  /// 最终给用户看的 assistant 文本回复
  final String finalContent;

  /// 工具执行时间线（用于 UI 渲染）
  final List<AgentEvent> timeline;

  /// 是否因迭代上限而中止
  final bool hitMaxIterations;

  /// 是否因致命错误中止
  final bool failed;

  /// 错误信息（failed=true 时有值）
  final String? error;

  const AgentResult({
    required this.finalContent,
    required this.timeline,
    this.hitMaxIterations = false,
    this.failed = false,
    this.error,
  });

  factory AgentResult.success(String content, List<AgentEvent> timeline) {
    return AgentResult(
      finalContent: content,
      timeline: List.unmodifiable(timeline),
    );
  }

  factory AgentResult.failure(String error, List<AgentEvent> timeline) {
    return AgentResult(
      finalContent: '',
      timeline: List.unmodifiable(timeline),
      failed: true,
      error: error,
    );
  }

  factory AgentResult.maxIterations(String partial, List<AgentEvent> timeline) {
    return AgentResult(
      finalContent: partial,
      timeline: List.unmodifiable(timeline),
      hitMaxIterations: true,
    );
  }
}
