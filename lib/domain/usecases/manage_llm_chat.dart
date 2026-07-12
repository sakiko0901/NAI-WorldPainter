import 'package:nai_huishi/domain/agents/agent_event.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/domain/entities/llm_session.dart';
import 'package:nai_huishi/domain/repositories/llm_chat_repository.dart';

class ManageLlmChatUseCase {
  final LlmChatRepository _repo;

  ManageLlmChatUseCase(this._repo);

  Future<List<LlmSession>> listSessions() => _repo.listSessions();
  Future<LlmSession> createSession({String? initialTitle}) =>
      _repo.createSession(initialTitle: initialTitle);
  Future<void> renameSession(String id, String title) =>
      _repo.renameSession(id, title);
  Future<void> deleteSession(String id) => _repo.deleteSession(id);
  Future<void> deleteAllSessions() => _repo.deleteAllSessions();
  Future<List<LlmMessage>> listMessages(String sessionId) =>
      _repo.listMessages(sessionId);

  /// 仅落库 user 消息（Agent 化后由 ViewModel 先调此方法落 user，再跑 AgentLoop）
  Future<int> saveUserMessage({
    required String sessionId,
    required String userText,
    String? imageBase64,
  }) =>
      _repo.saveUserMessage(
        sessionId: sessionId,
        userText: userText,
        imageBase64: imageBase64,
      );

  /// 落库 assistant 消息（含 tool_calls 时间线）
  Future<LlmMessage> saveAgentRunResult({
    required String sessionId,
    required String assistantText,
    String? toolCallsJson,
    List<AgentEvent>? agentTimeline,
  }) =>
      _repo.saveAgentRunResult(
        sessionId: sessionId,
        assistantText: assistantText,
        toolCallsJson: toolCallsJson,
        agentTimeline: agentTimeline,
      );

  /// 删除指定消息及其之后的所有消息
  Future<void> deleteMessagesFrom(int messageId, String sessionId) =>
      _repo.deleteMessagesFrom(messageId, sessionId);

  /// 仅落库 user + assistant 消息（不调 LLM，无 tool 调用的单次回复场景）
  Future<LlmMessage> saveUserAndAssistantMessages({
    required String sessionId,
    required String userText,
    String? imageBase64,
    String? imagePath,
    required String assistantText,
  }) =>
      _repo.saveUserAndAssistantMessages(
        sessionId: sessionId,
        userText: userText,
        imageBase64: imageBase64,
        imagePath: imagePath,
        assistantText: assistantText,
      );

  /// 不落库的轻量调用（关键词抽取等中间步骤用）
  Future<String> chatCompletionsRaw({
    required String apiKey,
    required String baseUrl,
    required String model,
    required String systemPrompt,
    required String userText,
  }) =>
      _repo.chatCompletionsRaw(
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
        systemPrompt: systemPrompt,
        userText: userText,
      );
}
