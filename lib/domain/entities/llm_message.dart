import 'package:equatable/equatable.dart';
import 'package:nai_huishi/domain/agents/agent_event.dart';
import 'package:nai_huishi/domain/entities/llm_interaction.dart';

enum LlmMessageRole { user, assistant }

class LlmMessage extends Equatable {
  final int? id;
  final String sessionId;
  final LlmMessageRole role;
  final String content;
  final DateTime createdAt;

  /// 图片 base64（仅内存，不持久化到 DB）。tentative 阶段用于即时显示。
  final String? imageBase64;

  /// 图片本地文件路径（持久化到 DB）。落库后通过此字段渲染。
  final String? imagePath;

  /// Agent 工具调用历史 JSON（持久化到 DB）。
  final String? toolCallsJson;

  /// Agent 工具执行时间线（内存对象，由 toolCallsJson 反序列化得来）。
  final List<AgentEvent>? agentTimeline;

  /// assistant 向用户提出的结构化单选问题。
  final LlmInteraction? interaction;

  const LlmMessage({
    this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.imageBase64,
    this.imagePath,
    this.toolCallsJson,
    this.agentTimeline,
    this.interaction,
  });

  String get roleString => role == LlmMessageRole.user ? 'user' : 'assistant';

  static LlmMessageRole roleFromString(String s) =>
      s == 'user' ? LlmMessageRole.user : LlmMessageRole.assistant;

  LlmMessage copyWith({
    int? id,
    String? sessionId,
    LlmMessageRole? role,
    String? content,
    DateTime? createdAt,
    String? imageBase64,
    String? imagePath,
    String? toolCallsJson,
    List<AgentEvent>? agentTimeline,
    LlmInteraction? interaction,
  }) {
    return LlmMessage(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      imageBase64: imageBase64 ?? this.imageBase64,
      imagePath: imagePath ?? this.imagePath,
      toolCallsJson: toolCallsJson ?? this.toolCallsJson,
      agentTimeline: agentTimeline ?? this.agentTimeline,
      interaction: interaction ?? this.interaction,
    );
  }

  @override
  List<Object?> get props =>
      [id, sessionId, role, content, createdAt, imagePath, interaction];
}
