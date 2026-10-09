import 'dart:io';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/data/datasources/local/llm_chat_local_datasource.dart';
import 'package:nai_huishi/data/datasources/remote/llm_api_service.dart';
import 'package:nai_huishi/domain/agents/agent_event.dart';
import 'package:nai_huishi/domain/entities/llm_interaction.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/domain/entities/llm_session.dart';
import 'package:nai_huishi/domain/entities/nai_prompt_version.dart';
import 'package:nai_huishi/domain/repositories/llm_chat_repository.dart';

class LlmChatRepositoryImpl implements LlmChatRepository {
  final LlmChatLocalDatasource _local;
  final LlmApiService _api;
  final Dio _dio;
  final _uuid = const Uuid();

  LlmChatRepositoryImpl({
    required LlmChatLocalDatasource local,
    required LlmApiService api,
    Dio? dio,
  })  : _local = local,
        _api = api,
        _dio = dio ?? Dio();

  @override
  Future<List<LlmSession>> listSessions() => _local.listSessions();

  @override
  Future<LlmSession> createSession({
    String? initialTitle,
    String scope = 'general',
    String? contextKey,
    NaiPromptVersion promptVersion = NaiPromptVersion.v45,
  }) async {
    final now = DateTime.now();
    final session = LlmSession(
      id: _uuid.v4(),
      title: initialTitle ?? '新对话',
      scope: scope,
      contextKey: contextKey,
      promptVersion: promptVersion,
      createdAt: now,
      updatedAt: now,
    );
    await _local.insertSession(session);
    return session;
  }

  @override
  Future<LlmSession?> findSessionByContextKey(String contextKey) =>
      _local.findSessionByContextKey(contextKey);

  @override
  Future<void> renameSession(String id, String title) async {
    final existing = await _local.getSession(id);
    if (existing == null) return;
    final updated = existing.copyWith(
      title: title.trim().isEmpty ? '新对话' : title.trim(),
      updatedAt: DateTime.now(),
    );
    await _local.updateSession(updated);
  }

  @override
  Future<void> setSessionPromptVersion(
    String id,
    NaiPromptVersion version,
  ) async {
    final session = await _local.getSession(id);
    if (session == null) return;
    await _local.updateSession(session.copyWith(
      promptVersion: version,
      updatedAt: DateTime.now(),
    ));
  }

  @override
  Future<void> deleteSession(String id) => _local.deleteSession(id);

  @override
  Future<void> deleteAllSessions() => _local.deleteAllSessions();

  @override
  Future<List<LlmMessage>> listMessages(String sessionId) =>
      _local.listMessages(sessionId);

  @override
  Future<int> saveUserMessage({
    required String sessionId,
    required String userText,
    String? imageBase64,
  }) async {
    final now = DateTime.now();
    final storeContent = userText.trim().isNotEmpty ? userText : '[图片]';
    String? userImagePath;
    if (imageBase64 != null) {
      try {
        final filename = ImageUtils.generateFilename();
        userImagePath = await ImageUtils.saveBase64Image(imageBase64, filename);
      } catch (_) {/* 忽略 */}
    }
    final userMessage = LlmMessage(
      sessionId: sessionId,
      role: LlmMessageRole.user,
      content: storeContent,
      createdAt: now,
      imagePath: userImagePath,
    );
    final userId = await _local.insertMessage(userMessage);

    // 更新 session title（如果是第一条用户消息）
    final allMessages = await _local.listMessages(sessionId);
    final existingSession = await _local.getSession(sessionId);
    if (existingSession != null && allMessages.length == 1) {
      final preview = storeContent.replaceAll(RegExp(r'\s+'), ' ').trim();
      final title = preview.length > 20 ? preview.substring(0, 20) : preview;
      await _local.updateSession(existingSession.copyWith(
        title: title.isEmpty ? '新对话' : title,
        updatedAt: now,
      ));
    } else if (existingSession != null) {
      await _local.touchSession(sessionId, now);
    }
    return userId;
  }

  @override
  Future<LlmMessage> saveAgentRunResult({
    required String sessionId,
    required String assistantText,
    String? toolCallsJson,
    List<AgentEvent>? agentTimeline,
    LlmInteraction? interaction,
  }) async {
    final replyTime = DateTime.now();
    final processed = await _tryExtractAndDownloadAssistantImage(assistantText);
    final assistantMessage = LlmMessage(
      sessionId: sessionId,
      role: LlmMessageRole.assistant,
      content: processed.cleanedText,
      createdAt: replyTime,
      imagePath: processed.imagePath,
      toolCallsJson: toolCallsJson ??
          (agentTimeline != null && agentTimeline.isNotEmpty
              ? AgentEvent.toJsonList(agentTimeline)
              : null),
      agentTimeline: agentTimeline,
      interaction: interaction,
    );
    final assistantId = await _local.insertMessage(assistantMessage);
    await _local.touchSession(sessionId, replyTime);
    return LlmMessage(
      id: assistantId,
      sessionId: sessionId,
      role: LlmMessageRole.assistant,
      content: processed.cleanedText,
      createdAt: replyTime,
      imagePath: processed.imagePath,
      toolCallsJson: toolCallsJson,
      agentTimeline: agentTimeline ?? const [],
      interaction: interaction,
    );
  }

  /// 尝试从 assistant 回复中提取并下载图片。
  /// 成功：返回去掉 markdown 图片标记的文本和本地文件路径。
  /// 失败：返回原文本，imagePath 为 null（不中断流程）。
  Future<_AssistantImageResult> _tryExtractAndDownloadAssistantImage(
      String text) async {
    final url = ImageUtils.extractImageUrlFromMarkdown(text);
    if (url == null) return _AssistantImageResult(text, null);
    try {
      final dir = await ImageUtils.getImageDirectory();
      final filename = ImageUtils.extractFilenameFromUrl(url);
      final filePath = '${dir.path}${Platform.pathSeparator}$filename';
      final file = File(filePath);
      if (!await file.exists()) {
        await _dio.download(url, filePath);
      }
      // 剥离 markdown 图片标记
      final cleaned = text
          .replaceAllMapped(
            RegExp(r'!\[image\]\([^)]+\)'),
            (_) => '',
          )
          .trim();
      return _AssistantImageResult(cleaned, filePath);
    } catch (_) {
      return _AssistantImageResult(text, null);
    }
  }

  @override
  Future<void> deleteMessagesFrom(int messageId, String sessionId) =>
      _local.deleteMessagesFrom(messageId, sessionId);

  @override
  Future<LlmMessage?> answerInteraction({
    required String sessionId,
    required int messageId,
    required String interactionId,
    String? optionId,
    String? customAnswer,
  }) =>
      _local.answerInteraction(
        sessionId: sessionId,
        messageId: messageId,
        interactionId: interactionId,
        optionId: optionId,
        customAnswer: customAnswer,
      );

  @override
  Future<LlmMessage> saveUserAndAssistantMessages({
    required String sessionId,
    required String userText,
    String? imageBase64,
    String? imagePath,
    required String assistantText,
  }) async {
    final now = DateTime.now();

    // 1. 落库 user 消息
    final storeContent = userText.trim().isNotEmpty ? userText : '[图片]';
    String? userImagePath = imagePath;
    if (userImagePath == null && imageBase64 != null) {
      try {
        final filename = ImageUtils.generateFilename();
        userImagePath = await ImageUtils.saveBase64Image(imageBase64, filename);
      } catch (_) {/* 忽略 */}
    }
    final userMessage = LlmMessage(
      sessionId: sessionId,
      role: LlmMessageRole.user,
      content: storeContent,
      createdAt: now,
      imagePath: userImagePath,
    );
    final userId = await _local.insertMessage(userMessage);

    // 2. 更新 session title（如果是第一条用户消息）
    final allMessages = await _local.listMessages(sessionId);
    final existingSession = await _local.getSession(sessionId);
    if (existingSession != null && allMessages.length == 1) {
      final preview = storeContent.replaceAll(RegExp(r'\s+'), ' ').trim();
      final title = preview.length > 20 ? preview.substring(0, 20) : preview;
      await _local.updateSession(existingSession.copyWith(
        title: title.isEmpty ? '新对话' : title,
        updatedAt: now,
      ));
    } else if (existingSession != null) {
      await _local.touchSession(sessionId, now);
    }

    // 3. 落库 assistant 消息
    final replyTime = DateTime.now();
    final processed = await _tryExtractAndDownloadAssistantImage(assistantText);
    final assistantMessage = LlmMessage(
      sessionId: sessionId,
      role: LlmMessageRole.assistant,
      content: processed.cleanedText,
      createdAt: replyTime,
      imagePath: processed.imagePath,
    );
    final assistantId = await _local.insertMessage(assistantMessage);
    await _local.touchSession(sessionId, replyTime);

    // ignore: unused_local_variable
    final _ = userId;
    return LlmMessage(
      id: assistantId,
      sessionId: sessionId,
      role: LlmMessageRole.assistant,
      content: processed.cleanedText,
      createdAt: replyTime,
      imagePath: processed.imagePath,
    );
  }

  @override
  Future<String> chatCompletionsRaw({
    required String apiKey,
    required String baseUrl,
    required String model,
    required String systemPrompt,
    required String userText,
  }) {
    return _api.chatCompletions(
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userText},
      ],
    );
  }
}

class _AssistantImageResult {
  final String cleanedText;
  final String? imagePath;
  const _AssistantImageResult(this.cleanedText, this.imagePath);
}
