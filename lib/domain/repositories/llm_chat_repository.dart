import 'package:nai_huishi/domain/agents/agent_event.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/domain/entities/llm_session.dart';

abstract class LlmChatRepository {
  Future<List<LlmSession>> listSessions();
  Future<LlmSession> createSession({String? initialTitle});
  Future<void> renameSession(String id, String title);
  Future<void> deleteSession(String id);
  Future<void> deleteAllSessions();
  Future<List<LlmMessage>> listMessages(String sessionId);

  /// 仅落库用户消息（不调 LLM，不落 assistant）。
  /// Agent 化后由 ViewModel 调用：先落 user → 跑 AgentLoop → 再调 [saveAgentRunResult] 落 assistant。
  /// 返回 user 消息在 DB 中的 id。
  Future<int> saveUserMessage({
    required String sessionId,
    required String userText,
    String? imageBase64,
  });

  /// 落库 assistant 消息（含 tool_calls JSON 时间线）。
  /// 返回 assistant 消息（带 id 和反序列化的 agentTimeline）。
  Future<LlmMessage> saveAgentRunResult({
    required String sessionId,
    required String assistantText,
    String? toolCallsJson,
    List<AgentEvent>? agentTimeline,
  });

  /// 仅落库用户消息 + assistant 消息（不调 LLM，用于无 tool 调用的单次回复场景）
  /// 返回 assistant 消息（带 id）
  Future<LlmMessage> saveUserAndAssistantMessages({
    required String sessionId,
    required String userText,
    String? imageBase64,
    String? imagePath,
    required String assistantText,
  });

  /// 删除指定消息及其之后的所有消息
  Future<void> deleteMessagesFrom(int messageId, String sessionId);

  /// 不落库的轻量调用：直接调 LLM chat completions，返回 assistant 文本。
  /// 用于"关键词抽取"等不需要进入会话历史的中间步骤。
  Future<String> chatCompletionsRaw({
    required String apiKey,
    required String baseUrl,
    required String model,
    required String systemPrompt,
    required String userText,
  });
}
