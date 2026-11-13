import 'package:nai_huishi/core/services/image_analysis_cache.dart';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:nai_huishi/core/services/app_update_install_guard.dart';
import 'package:nai_huishi/data/datasources/remote/llm_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/wd_tagger_api_service.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/agents/tool_registry.dart';
import 'package:nai_huishi/domain/agents/agent_event.dart';
import 'package:nai_huishi/domain/agents/tools/save_memory_tool.dart';
import 'package:nai_huishi/domain/entities/llm_interaction.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_profile_role.dart';
import 'package:nai_huishi/domain/entities/llm_response.dart';
import 'package:nai_huishi/domain/entities/llm_role_binding.dart';
import 'package:nai_huishi/domain/entities/llm_session.dart';
import 'package:nai_huishi/domain/entities/nai_prompt_version.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:nai_huishi/domain/entities/tool_call.dart';
import 'package:nai_huishi/domain/repositories/llm_chat_repository.dart';
import 'package:nai_huishi/domain/repositories/prompt_memory_repository.dart';
import 'package:nai_huishi/domain/repositories/settings_repository.dart';
import 'package:nai_huishi/domain/services/prompt_memory_context.dart';
import 'package:nai_huishi/domain/services/prompting_skill_loader.dart';
import 'package:nai_huishi/domain/usecases/analyze_image_tags.dart';
import 'package:nai_huishi/domain/usecases/manage_llm_chat.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_memories.dart';
import 'package:nai_huishi/domain/usecases/manage_settings.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';

import 'frontend_generation_fake.dart';

class ChatMemoryHarness {
  ChatMemoryHarness({
    required this.viewModel,
    required this.chatRepository,
    required this.memoryRepository,
    required this.api,
    required this.analyzeImageTags,
  });

  final LlmChatViewModel viewModel;
  final FakeLlmChatRepository chatRepository;
  final FakePromptMemoryRepository memoryRepository;
  final RecordingLlmApiService api;
  final FakeAnalyzeImageTagsUseCase analyzeImageTags;

  void dispose() => viewModel.dispose();
}

ChatMemoryHarness createChatMemoryHarness({
  FakeLlmChatRepository? chatRepository,
  FrontendGenerationFake? generation,
  AppUpdateInstallGuard? updateGuard,
  List<PromptMemory>? memories,
  bool memoryReadFails = false,
  String systemPrompt = '测试自定义系统提示词',
  String visionDescription = '图中可见绿色长发角色穿着白色披肩与绿色连衣裙。',
  bool visionFails = false,
  bool registerSaveMemoryTool = false,
  List<LlmResponse> scriptedMainResponses = const [],
  WdTaggerResult taggerResult = const WdTaggerResult(
    generalTags: {'white_dress': 0.98},
    characterTags: {'green_hair': 0.91},
  ),
}) {
  final repository = chatRepository ?? FakeLlmChatRepository();
  final memoryRepository = FakePromptMemoryRepository(
    memories: memories ?? [canonicalOutfitMemory()],
    readFails: memoryReadFails,
  );
  final settingsRepository = FakeSettingsRepository(systemPrompt: systemPrompt);
  final api = RecordingLlmApiService(
    visionDescription: visionDescription,
    visionFails: visionFails,
    mainResponses: scriptedMainResponses,
  );
  final analyzeImageTags = FakeAnalyzeImageTagsUseCase(taggerResult);
  final registry = ToolRegistry()..register(_NoopTool());
  final manageMemories = ManagePromptMemoriesUseCase(memoryRepository);
  if (registerSaveMemoryTool) {
    registry.register(SaveMemoryTool(manageMemories));
  }

  LlmChatViewModel.apiServiceSingleton = api;
  LlmChatViewModel.toolRegistrySingleton = registry;

  final viewModel = LlmChatViewModel(
    imageAnalysisCache: ImageAnalysisCache.memory(),
    manageChat: ManageLlmChatUseCase(repository),
    manageSettings: ManageSettingsUseCase(settingsRepository),
    memories: manageMemories,
    genVm: generation ?? FrontendGenerationFake(),
    analyzeImageTags: analyzeImageTags,
    promptingSkillLoader: _FakePromptingSkillLoader(),
    updateGuard: updateGuard,
  );

  return ChatMemoryHarness(
    viewModel: viewModel,
    chatRepository: repository,
    memoryRepository: memoryRepository,
    api: api,
    analyzeImageTags: analyzeImageTags,
  );
}

PromptMemory canonicalOutfitMemory({
  String trigger = '纳西妲|草神|Nahida',
  String content = '纳西妲标准穿搭：白色短上衣、绿色连衣裙、白色披肩与金色叶形发饰。',
}) =>
    PromptMemory(
      id: 41,
      trigger: trigger,
      content: content,
      type: PromptMemoryType.characterOutfit,
      source: PromptMemorySource.manual,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

class CapturedLlmCall {
  CapturedLlmCall({
    required this.messages,
    this.tools,
  });

  final List<Map<String, dynamic>> messages;
  final List<Map<String, dynamic>>? tools;

  String? get firstSystemContent {
    for (final message in messages) {
      final content = message['content'];
      if (message['role'] == 'system' && content is String) return content;
    }
    return null;
  }

  String get lastUserText {
    final message = messages.lastWhere((message) => message['role'] == 'user');
    final content = message['content'];
    return content is String ? content : jsonEncode(content);
  }
}

class RecordingLlmApiService extends LlmApiService {
  RecordingLlmApiService({
    required this.visionDescription,
    required this.visionFails,
    List<LlmResponse> mainResponses = const [],
  })  : scriptedMainResponses = List.of(mainResponses),
        super(Dio());

  final String visionDescription;
  final bool visionFails;
  final List<LlmResponse> scriptedMainResponses;
  final List<CapturedLlmCall> mainCalls = [];
  final List<CapturedLlmCall> visionCalls = [];
  int _mainResponseIndex = 0;
  int streamRequests = 0;
  void Function()? onMainRequest;

  @override
  Future<LlmResponse> chatCompletionsStreamWithTools({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    required void Function(String) onText,
    CancelToken? cancelToken,
  }) async {
    streamRequests++;
    if (tools.isEmpty) {
      final text = await chatCompletions(
          apiKey: apiKey,
          baseUrl: baseUrl,
          model: model,
          messages: messages,
          cancelToken: cancelToken);
      onText(text);
      return LlmResponse(
          content: text, toolCalls: const [], finishReason: 'stop');
    }
    final result = await chatCompletionsWithTools(
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
        messages: messages,
        tools: tools);
    onText(result.content);
    return result;
  }

  @override
  Future<LlmResponse> chatCompletionsWithTools({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String toolChoice = 'auto',
    CancelToken? cancelToken,
  }) async {
    onMainRequest?.call();
    mainCalls.add(CapturedLlmCall(
      messages: _copyMessages(messages),
      tools: _copyTools(tools),
    ));
    if (_mainResponseIndex < scriptedMainResponses.length) {
      return scriptedMainResponses[_mainResponseIndex++];
    }
    return const LlmResponse(
      content: '固定测试回复',
      toolCalls: <ToolCall>[],
      finishReason: 'stop',
    );
  }

  @override
  Future<String> chatCompletions({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, dynamic>> messages,
    CancelToken? cancelToken,
  }) async {
    visionCalls.add(CapturedLlmCall(messages: _copyMessages(messages)));
    if (visionFails) throw StateError('vision unavailable in test');
    return visionDescription;
  }

  static List<Map<String, dynamic>> _copyMessages(
    List<Map<String, dynamic>> messages,
  ) =>
      (jsonDecode(jsonEncode(messages)) as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);

  static List<Map<String, dynamic>> _copyTools(
    List<Map<String, dynamic>> tools,
  ) =>
      (jsonDecode(jsonEncode(tools)) as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
}

class FakeLlmChatRepository implements LlmChatRepository {
  final Map<String, List<LlmMessage>> _messagesBySession = {};
  final List<LlmSession> _sessions = [];
  int _sessionSequence = 0;
  int _messageSequence = 0;

  @override
  Future<LlmSession> forkSession(String sessionId, int beforeMessageId) async {
    final source = _sessions.firstWhere((s) => s.id == sessionId);
    final history = _messagesBySession[sessionId]!;
    final index = history.indexWhere((m) => m.id == beforeMessageId);
    if (index < 0) throw StateError('消息不存在');
    final branch = await createSession(
        initialTitle: '${source.title} · 分支',
        contextKey: 'branch:$sessionId:$beforeMessageId',
        promptVersion: source.promptVersion);
    _messagesBySession[branch.id] = history
        .take(index)
        .map((m) => m.copyWith(sessionId: branch.id))
        .toList();
    return branch;
  }

  @override
  Future<List<LlmSession>> listSessions() async => List.of(_sessions);

  @override
  Future<LlmSession> createSession({
    String? initialTitle,
    String scope = 'general',
    String? contextKey,
    NaiPromptVersion promptVersion = NaiPromptVersion.v45,
  }) async {
    final now = DateTime(2026, 1, 1).add(Duration(minutes: _sessionSequence));
    final session = LlmSession(
      id: 'chat-${++_sessionSequence}',
      title: initialTitle ?? '新聊天',
      scope: scope,
      contextKey: contextKey,
      promptVersion: promptVersion,
      createdAt: now,
      updatedAt: now,
    );
    _sessions.insert(0, session);
    _messagesBySession[session.id] = [];
    return session;
  }

  @override
  Future<void> deleteMessagesFrom(int messageId, String sessionId) async {
    _messagesBySession[sessionId]?.removeWhere(
        (message) => message.id != null && message.id! >= messageId);
  }

  @override
  Future<List<LlmMessage>> listMessages(String sessionId) async =>
      List.of(_messagesBySession[sessionId] ?? const []);

  @override
  Future<int> saveUserMessage({
    required String sessionId,
    required String userText,
    String? imageBase64,
    List<String> imageBase64s = const [],
  }) async {
    final id = ++_messageSequence;
    _messagesBySession.putIfAbsent(sessionId, () => []).add(LlmMessage(
          id: id,
          sessionId: sessionId,
          role: LlmMessageRole.user,
          content: userText,
          imageBase64: imageBase64,
          imageBase64s: imageBase64s,
          createdAt: DateTime(2026, 1, 1).add(Duration(seconds: id)),
        ));
    return id;
  }

  @override
  Future<LlmMessage> saveAgentRunResult({
    required String sessionId,
    required String assistantText,
    String? toolCallsJson,
    List<AgentEvent>? agentTimeline,
    LlmInteraction? interaction,
  }) async {
    final message = LlmMessage(
      id: ++_messageSequence,
      sessionId: sessionId,
      role: LlmMessageRole.assistant,
      content: assistantText,
      toolCallsJson: toolCallsJson,
      agentTimeline: agentTimeline,
      interaction: interaction,
      createdAt: DateTime(2026, 1, 1).add(Duration(seconds: _messageSequence)),
    );
    _messagesBySession.putIfAbsent(sessionId, () => []).add(message);
    return message;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePromptMemoryRepository implements PromptMemoryRepository {
  FakePromptMemoryRepository({
    required List<PromptMemory> memories,
    required this.readFails,
  }) : memories = List.of(memories);

  final List<PromptMemory> memories;
  final bool readFails;
  final List<String> matchQueries = [];
  final List<int> incrementedIds = [];

  @override
  Future<List<PromptMemory>> matchText(String text) async {
    matchQueries.add(text);
    if (readFails) throw StateError('local memory database unavailable');
    return memories
        .where((memory) =>
            memory.isRetrievable &&
            PromptMemoryTriggers.matches(memory.trigger, text))
        .toList(growable: false);
  }

  @override
  Future<void> incrementHit(int id) async {
    incrementedIds.add(id);
  }

  @override
  Future<PromptMemory> save(PromptMemory memory) async {
    final nextId = memories
            .map((existing) => existing.id ?? 0)
            .fold<int>(0, (maximum, id) => id > maximum ? id : maximum) +
        1;
    final saved = memory.copyWith(id: nextId);
    memories.add(saved);
    return saved;
  }

  @override
  Future<PromptMemory> promotePending(
    int id, {
    String? newTrigger,
    String? newContent,
    PromptMemoryType? newType,
  }) async {
    final index = memories.indexWhere((memory) => memory.id == id);
    if (index < 0) throw StateError('memory $id not found');
    final current = memories[index];
    if (current.source != PromptMemorySource.pendingLlmCandidate) {
      throw StateError('memory $id is not pending');
    }
    final promoted = current.copyWith(
      trigger: newTrigger,
      content: newContent,
      type: newType,
      source: PromptMemorySource.llmCandidate,
      updatedAt: DateTime.now(),
    );
    memories[index] = promoted;
    return promoted;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository({required this.systemPrompt});

  String systemPrompt;
  String styleWordsV5 = '';
  String styleWordsV45 = '';
  String negativeWordsV5 = '';
  String negativeWordsV45 = '';
  String? activeSessionId;
  final _provider = LlmProvider(
    id: 'test-provider',
    name: 'Test Provider',
    apiKey: 'test-key',
    baseUrl: 'https://example.invalid/v1',
    models: const ['main-test-model', 'vision-test-model'],
    createdAt: 1,
  );

  @override
  Future<List<LlmProvider>> getLlmProviders() async =>
      _savedProviders ?? [_provider];
  List<LlmProvider>? _savedProviders;
  @override
  Future<void> saveLlmProviders(List<LlmProvider> providers) async {
    _savedProviders = List.of(providers);
  }

  @override
  Future<LlmRoleBinding> getLlmRoleBinding(LlmProfileRole role) async =>
      switch (role) {
        LlmProfileRole.main => const LlmRoleBinding(
            providerId: 'test-provider', model: 'main-test-model'),
        LlmProfileRole.vision => const LlmRoleBinding(
            providerId: 'test-provider', model: 'vision-test-model'),
        LlmProfileRole.aux => const LlmRoleBinding(),
      };

  @override
  Future<void> setLlmRoleBinding(
      LlmProfileRole role, LlmRoleBinding binding) async {}

  @override
  Future<String> getLlmSystemPrompt() async => systemPrompt;

  @override
  Future<void> setLlmSystemPrompt(String value) async => systemPrompt = value;

  @override
  Future<int> getLlmContextLimit() async => 20;

  @override
  Future<bool> getLlmMultimodal() async => _multimodal;
  bool _multimodal = false;
  @override
  Future<void> setLlmMultimodal(bool value) async {
    _multimodal = value;
  }

  @override
  Future<void> setDefaultNegativeWordsV5(String value) async =>
      negativeWordsV5 = value;
  @override
  Future<void> setDefaultNegativeWordsV45(String value) async =>
      negativeWordsV45 = value;
  @override
  Future<String> getDefaultNegativeWordsV5() async => negativeWordsV5;
  @override
  Future<String> getDefaultNegativeWordsV45() async => negativeWordsV45;
  @override
  Future<String> getDefaultStyleWordsV5() async => styleWordsV5;

  @override
  Future<void> setDefaultStyleWordsV5(String value) async =>
      styleWordsV5 = value;

  @override
  Future<String> getDefaultStyleWordsV45() async => styleWordsV45;

  @override
  Future<void> setDefaultStyleWordsV45(String value) async =>
      styleWordsV45 = value;

  @override
  Future<String?> getLlmActiveSessionId() async => activeSessionId;

  @override
  Future<void> setLlmActiveSessionId(String? value) async {
    activeSessionId = value;
  }

  @override
  Future<String?> getNsfwBookPath() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAnalyzeImageTagsUseCase implements AnalyzeImageTagsUseCase {
  FakeAnalyzeImageTagsUseCase(this.result);

  final WdTaggerResult result;
  int calls = 0;
  String? lastImagePath;

  @override
  Future<WdTaggerResult> analyze({
    required String imagePath,
    required String modelRepo,
    double generalThreshold = 0.35,
    double characterThreshold = 0.85,
  }) async {
    calls++;
    lastImagePath = imagePath;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePromptingSkillLoader implements PromptingSkillLoader {
  @override
  Future<String> loadSkill() async => '测试 skill';

  @override
  Future<String> loadReference(PromptingReference reference) async => '测试参考';
}

class _NoopTool extends AgentTool {
  @override
  String get name => 'test_noop';

  @override
  String get description => '测试用的无副作用工具';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': <String, dynamic>{},
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async =>
      ToolResult.success('ok');
}
