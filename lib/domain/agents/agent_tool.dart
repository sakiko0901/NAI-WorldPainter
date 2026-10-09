import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nai_huishi/domain/entities/llm_interaction.dart';

/// Agent 工具的执行结果
@immutable
class ToolResult {
  /// 是否成功
  final bool success;

  /// 给 LLM 看的文本（成功时是数据摘要，失败时是错误说明）
  final String text;

  /// 给 UI 看的展示文本（成功时是用户可读的简短描述）
  final String displayText;

  /// 副产物：是否需要 LLM 再次思考（例如生成了新 prompt，可以提示 LLM）
  final String? followUpHint;

  /// 需要用户回答的结构化交互。
  final LlmInteraction? interaction;

  const ToolResult({
    required this.success,
    required this.text,
    required this.displayText,
    this.followUpHint,
    this.interaction,
  });

  factory ToolResult.success(String text,
      {String? displayText,
      String? followUpHint,
      LlmInteraction? interaction}) {
    return ToolResult(
      success: true,
      text: text,
      displayText: displayText ?? text,
      followUpHint: followUpHint,
      interaction: interaction,
    );
  }

  factory ToolResult.failure(String reason) {
    return ToolResult(
      success: false,
      text: '失败：$reason',
      displayText: '失败：$reason',
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'text': text,
        'displayText': displayText,
        if (followUpHint != null) 'followUpHint': followUpHint,
        if (interaction != null) 'interaction': interaction!.toJson(),
      };

  static ToolResult fromJson(Map<String, dynamic> json) {
    return ToolResult(
      success: json['success'] as bool? ?? false,
      text: json['text'] as String? ?? '',
      displayText: json['displayText'] as String? ?? '',
      followUpHint: json['followUpHint'] as String?,
      interaction: json['interaction'] is Map
          ? LlmInteraction.fromJsonString(jsonEncode(json['interaction']))
          : null,
    );
  }
}

/// Agent 工具接口。所有工具实现此接口。
abstract class AgentTool {
  /// 工具名（与 OpenAI function name 一致）
  String get name;

  /// 给 LLM 看的描述
  String get description;

  /// JSON Schema 参数定义
  Map<String, dynamic> get parametersSchema;

  /// 是否需要用户确认才执行（副作用工具置 true）
  bool get requireConfirmation => false;

  /// 执行工具
  Future<ToolResult> call(Map<String, dynamic> arguments);

  /// 转换为 OpenAI tools 字段中的元素
  Map<String, dynamic> toOpenAiTool() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': parametersSchema,
      },
    };
  }
}
