import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:nai_huishi/domain/entities/tool_call.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';

/// Agent 循环中的事件，用于 UI 时间线展示
@immutable
class AgentEvent {
  /// 触发的工具名
  final String toolName;

  /// 工具调用的 id（关联 LLM tool_call_id）
  final String toolCallId;

  /// 调用参数（用于展示）
  final Map<String, dynamic> arguments;

  /// 状态：pending / running / done / error / awaiting_confirm / cancelled
  final String status;

  /// 执行结果（done / error 时有值）
  final ToolResult? result;

  /// 时间戳
  final DateTime createdAt;

  const AgentEvent({
    required this.toolName,
    required this.toolCallId,
    required this.arguments,
    required this.status,
    this.result,
    required this.createdAt,
  });

  AgentEvent copyWith({
    String? status,
    ToolResult? result,
  }) {
    return AgentEvent(
      toolName: toolName,
      toolCallId: toolCallId,
      arguments: arguments,
      status: status ?? this.status,
      result: result ?? this.result,
      createdAt: createdAt,
    );
  }

  static AgentEvent fromToolCall(ToolCall call, {String status = 'pending'}) {
    return AgentEvent(
      toolName: call.name,
      toolCallId: call.id,
      arguments: call.arguments,
      status: status,
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'toolName': toolName,
        'toolCallId': toolCallId,
        'arguments': arguments,
        'status': status,
        if (result != null) 'result': result!.toJson(),
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  static AgentEvent fromJson(Map<String, dynamic> json) {
    return AgentEvent(
      toolName: json['toolName'] as String? ?? '',
      toolCallId: json['toolCallId'] as String? ?? '',
      arguments: (json['arguments'] as Map?)?.cast<String, dynamic>() ?? const {},
      status: json['status'] as String? ?? 'done',
      result: json['result'] is Map
          ? ToolResult.fromJson(json['result'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  static List<AgentEvent> fromJsonList(String? json) {
    if (json == null || json.trim().isEmpty) return const [];
    try {
      final list = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
      return list.map(AgentEvent.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  static String toJsonList(List<AgentEvent> events) {
    try {
      return jsonEncode(events.map((e) => e.toJson()).toList());
    } catch (_) {
      return '[]';
    }
  }
}
