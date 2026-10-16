import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/data/nsfw_book.dart';
import 'package:nai_huishi/domain/agents/agent_event.dart';
import 'package:nai_huishi/domain/agents/agent_loop.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/agents/tool_registry.dart';
import 'package:nai_huishi/domain/agents/tools/read_prompting_reference_tool.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/domain/entities/llm_profile_role.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_role_binding.dart';
import 'package:nai_huishi/domain/entities/llm_role_config.dart';
import 'package:nai_huishi/domain/entities/llm_session.dart';
import 'package:nai_huishi/domain/entities/nai_prompt_version.dart';
import 'package:nai_huishi/domain/services/prompt_memory_context.dart';
import 'package:nai_huishi/domain/services/prompting_skill_loader.dart';
import 'package:nai_huishi/domain/usecases/analyze_image_tags.dart';
import 'package:nai_huishi/domain/usecases/manage_llm_chat.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_memories.dart';
import 'package:nai_huishi/domain/usecases/manage_settings.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:path_provider/path_provider.dart';

class LlmChatViewModel extends ChangeNotifier {
  final ManageLlmChatUseCase _manageChat;
  final ManageSettingsUseCase _manageSettings;
  final ManagePromptMemoriesUseCase _memories;
  final GenerationViewModel _genVm;
  final AnalyzeImageTagsUseCase _analyzeImageTags;
  final PromptingSkillLoader _promptingSkillLoader;

  LlmChatViewModel({
    required ManageLlmChatUseCase manageChat,
    required ManageSettingsUseCase manageSettings,
    required ManagePromptMemoriesUseCase memories,
    required GenerationViewModel genVm,
    required AnalyzeImageTagsUseCase analyzeImageTags,
    required PromptingSkillLoader promptingSkillLoader,
  })  : _manageChat = manageChat,
        _manageSettings = manageSettings,
        _memories = memories,
        _genVm = genVm,
        _analyzeImageTags = analyzeImageTags,
        _promptingSkillLoader = promptingSkillLoader;

  // ── LLM 供应商 + 2 角色绑定 ──
  List<LlmProvider> _providers = [];
  LlmRoleBinding _mainBinding = const LlmRoleBinding();
  LlmRoleBinding _visionBinding = const LlmRoleBinding();
  String _systemPrompt = AppConstants.defaultLlmSystemPrompt;
  int _contextLimit = AppConstants.defaultLlmContextLimit;
  String _defaultStyleWordsV5 = '';
  String _defaultStyleWordsV45 = '';

  List<LlmProvider> get providers => List.unmodifiable(_providers);
  LlmRoleBinding get mainBinding => _mainBinding;
  LlmRoleBinding get visionBinding => _visionBinding;

  /// 当前 main 角色 configuration（从 _providers + _mainBinding 解析）
  LlmRoleConfig get mainConfig => _resolveConfig(_mainBinding);

  /// 当前 vision 角色 configuration（从 _providers + _visionBinding 解析）
  LlmRoleConfig get visionConfig => _resolveConfig(_visionBinding);

  LlmRoleConfig _resolveConfig(LlmRoleBinding binding) {
    if (binding.providerId == null || binding.model.isEmpty) {
      return const LlmRoleConfig();
    }
    final provider = _providers
        .cast<LlmProvider?>()
        .firstWhere((p) => p?.id == binding.providerId, orElse: () => null);
    if (provider == null) return const LlmRoleConfig();
    if (!provider.models.contains(binding.model)) {
      return const LlmRoleConfig();
    }
    return LlmRoleConfig(
      apiKey: provider.apiKey,
      baseUrl: provider.baseUrl,
      model: binding.model,
    );
  }

  LlmRoleBinding getBinding(LlmProfileRole role) {
    switch (role) {
      case LlmProfileRole.main:
        return _mainBinding;
      case LlmProfileRole.vision:
        return _visionBinding;
      case LlmProfileRole.aux:
        return const LlmRoleBinding();
    }
  }

  String get systemPrompt => _systemPrompt;
  int get contextLimit => _contextLimit;
  String get defaultStyleWordsV5 => _defaultStyleWordsV5;
  String get defaultStyleWordsV45 => _defaultStyleWordsV45;

  /// 知识库
  final NsfwBook _nsfwBook = NsfwBook();
  NsfwBook get nsfwBook => _nsfwBook;

  // 会话
  List<LlmSession> _sessions = [];
  String? _activeSessionId;
  List<LlmMessage> _messages = [];
  ToolRegistry? _scopedRegistry;
  String? _scopedSystemPrompt;
  String? _returnSessionId;

  // 状态
  bool _isSending = false;
  bool _isLoading = false;
  String? _errorMessage;
  bool _initialized = false;

  // ── 副作用工具确认回调（UI 设置）──
  /// 当 AgentLoop 需要执行副作用工具时调用此回调，UI 弹窗让用户确认。
  /// 返回 true 表示用户同意，false 表示拒绝。
  Future<bool> Function(AgentToolConfirmRequest request)? onRequireConfirmation;

  List<LlmSession> get sessions => List.unmodifiable(_sessions);
  String? get activeSessionId => _activeSessionId;
  LlmSession? get activeSession {
    for (final s in _sessions) {
      if (s.id == _activeSessionId) return s;
    }
    return null;
  }

  List<LlmMessage> get messages => List.unmodifiable(_messages);
  bool get isSending => _isSending;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isConfigured => mainConfig.isConfigured;

  GenerationViewModel get genVm => _genVm;

  /// 初次进入面板时调用；幂等
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    _isLoading = true;
    notifyListeners();

    await _loadLlmConfigs();

    // 加载知识库：先用打包进 APK 的默认 asset，再让用户外部路径覆盖
    await _nsfwBook.loadFromAsset();
    final bookPath = await _manageSettings.getNsfwBookPath();
    if (bookPath != null && bookPath.isNotEmpty) {
      await _nsfwBook.load(bookPath);
    }

    _sessions = await _manageChat.listSessions();
    final lastActive = await _manageSettings.getLlmActiveSessionId();
    if (lastActive != null && _sessions.any((s) => s.id == lastActive)) {
      _activeSessionId = lastActive;
    } else if (_sessions.isNotEmpty) {
      _activeSessionId = _sessions.first.id;
      await _manageSettings.setLlmActiveSessionId(_activeSessionId);
    } else {
      final created = await _manageChat.createSession(
        promptVersion: NaiPromptVersion.v45,
      );
      _sessions = [created];
      _activeSessionId = created.id;
      await _manageSettings.setLlmActiveSessionId(_activeSessionId);
    }

    if (_activeSessionId != null) {
      _messages = await _manageChat.listMessages(_activeSessionId!);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadLlmConfigs() async {
    _providers = await _manageSettings.getLlmProviders();
    _mainBinding = await _manageSettings.getLlmRoleBinding(LlmProfileRole.main);
    _visionBinding =
        await _manageSettings.getLlmRoleBinding(LlmProfileRole.vision);
    _systemPrompt = await _manageSettings.getLlmSystemPrompt();
    _contextLimit = await _manageSettings.getLlmContextLimit();
    _defaultStyleWordsV5 = await _manageSettings.getDefaultStyleWordsV5();
    _defaultStyleWordsV45 = await _manageSettings.getDefaultStyleWordsV45();
    // 启动后校验：binding 引用的 providerId/model 不存在则清空
    _sanitizeBindings();
  }

  /// 检查 3 个 binding 是否仍指向有效 provider+model，无效则清空。
  void _sanitizeBindings() {
    bool changed = false;
    if (!_isBindingValid(_mainBinding)) {
      if (_mainBinding != const LlmRoleBinding()) {
        _mainBinding = const LlmRoleBinding();
        changed = true;
      }
    }
    if (!_isBindingValid(_visionBinding)) {
      if (_visionBinding != const LlmRoleBinding()) {
        _visionBinding = const LlmRoleBinding();
        changed = true;
      }
    }
    if (changed) {
      // 后台持久化清空后的 binding（不阻塞 UI）
      Future.wait([
        _manageSettings.setLlmRoleBinding(LlmProfileRole.main, _mainBinding),
        _manageSettings.setLlmRoleBinding(
            LlmProfileRole.vision, _visionBinding),
      ]);
    }
  }

  bool _isBindingValid(LlmRoleBinding b) {
    if (b.providerId == null || b.model.isEmpty) return true; // 空 binding 视为有效
    final provider = _providers
        .cast<LlmProvider?>()
        .firstWhere((p) => p?.id == b.providerId, orElse: () => null);
    return provider != null && provider.models.contains(b.model);
  }

  // ── 配置 setter ──
  Future<void> setProviders(List<LlmProvider> providers) async {
    _providers = List<LlmProvider>.from(providers);
    await _manageSettings.saveLlmProviders(_providers);
    _sanitizeBindings();
    notifyListeners();
  }

  Future<void> setRoleBinding(
      LlmProfileRole role, LlmRoleBinding binding) async {
    switch (role) {
      case LlmProfileRole.main:
        _mainBinding = binding;
        break;
      case LlmProfileRole.vision:
        _visionBinding = binding;
        break;
      case LlmProfileRole.aux:
        return;
    }
    await _manageSettings.setLlmRoleBinding(role, binding);
    notifyListeners();
  }

  Future<void> setSystemPrompt(String value) async {
    final v =
        value.trim().isEmpty ? AppConstants.defaultLlmSystemPrompt : value;
    await _manageSettings.setLlmSystemPrompt(v);
    _systemPrompt = v;
    notifyListeners();
  }

  Future<void> resetSystemPrompt() async {
    await setSystemPrompt(AppConstants.defaultLlmSystemPrompt);
  }

  Future<void> setContextLimit(int value) async {
    final v = value.clamp(1, 200);
    await _manageSettings.setLlmContextLimit(v);
    _contextLimit = v;
    notifyListeners();
  }

  Future<void> setDefaultStyleWordsV5(String value) async {
    _defaultStyleWordsV5 = value;
    await _manageSettings.setDefaultStyleWordsV5(value);
    notifyListeners();
  }

  Future<void> setDefaultStyleWordsV45(String value) async {
    _defaultStyleWordsV45 = value;
    await _manageSettings.setDefaultStyleWordsV45(value);
    notifyListeners();
  }

  /// 从设置读取路径并重新加载知识库。
  Future<void> reloadNsfwBook() async {
    await _nsfwBook.loadFromAsset();
    final path = await _manageSettings.getNsfwBookPath();
    if (path != null && path.isNotEmpty) {
      await _nsfwBook.load(path);
    }
  }

  // ── 会话管理 ──
  Future<void> openScopedSession({
    required String contextKey,
    required String title,
    required String systemPrompt,
    required ToolRegistry registry,
  }) async {
    await ensureInitialized();
    final existing = await _manageChat.findSessionByContextKey(contextKey);
    final session = existing ??
        await _manageChat.createSession(
          initialTitle: title,
          scope: 'comic',
          contextKey: contextKey,
          promptVersion: NaiPromptVersion.v45,
        );
    if (_activeSessionId != session.id) _returnSessionId ??= _activeSessionId;
    _sessions = await _manageChat.listSessions();
    _activeSessionId = session.id;
    _messages = await _manageChat.listMessages(session.id);
    _scopedRegistry = registry;
    _scopedSystemPrompt = systemPrompt;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> closeScopedSession() async {
    final returnId = _returnSessionId;
    _scopedRegistry = null;
    _scopedSystemPrompt = null;
    _returnSessionId = null;
    if (returnId != null &&
        _sessions.any((session) => session.id == returnId)) {
      _activeSessionId = returnId;
      _messages = await _manageChat.listMessages(returnId);
    }
    notifyListeners();
  }

  Future<void> createNewSession({
    NaiPromptVersion promptVersion = NaiPromptVersion.v5,
  }) async {
    if (_isSending) return;
    final created =
        await _manageChat.createSession(promptVersion: promptVersion);
    _sessions = [created, ..._sessions];
    _activeSessionId = created.id;
    _messages = [];
    await _manageSettings.setLlmActiveSessionId(_activeSessionId);
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> selectSession(String id) async {
    if (_isSending || id == _activeSessionId) return;
    _activeSessionId = id;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    _messages = await _manageChat.listMessages(id);
    await _manageSettings.setLlmActiveSessionId(id);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> renameSession(String id, String title) async {
    await _manageChat.renameSession(id, title);
    _sessions = await _manageChat.listSessions();
    notifyListeners();
  }

  Future<void> setActivePromptVersion(NaiPromptVersion version) async {
    final session = activeSession;
    if (session == null || session.promptVersion == version) return;
    await _manageChat.setSessionPromptVersion(session.id, version);
    _sessions = await _manageChat.listSessions();
    notifyListeners();
  }

  Future<void> deleteSession(String id) async {
    await _manageChat.deleteSession(id);
    _sessions = await _manageChat.listSessions();
    if (_activeSessionId == id) {
      if (_sessions.isNotEmpty) {
        _activeSessionId = _sessions.first.id;
        _messages = await _manageChat.listMessages(_activeSessionId!);
      } else {
        final created = await _manageChat.createSession(
          promptVersion: NaiPromptVersion.v45,
        );
        _sessions = [created];
        _activeSessionId = created.id;
        _messages = [];
      }
      await _manageSettings.setLlmActiveSessionId(_activeSessionId);
    }
    notifyListeners();
  }

  Future<void> deleteAllSessions() async {
    await _manageChat.deleteAllSessions();
    final created = await _manageChat.createSession(
      promptVersion: NaiPromptVersion.v45,
    );
    _sessions = [created];
    _activeSessionId = created.id;
    _messages = [];
    await _manageSettings.setLlmActiveSessionId(_activeSessionId);
    _errorMessage = null;
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  // ── 发送消息：走 AgentLoop ──
  Future<void> sendUserMessage(
    String text, {
    String? imageBase64,
    String? textAttachment,
    bool alreadyPersisted = false,
  }) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty && imageBase64 == null && textAttachment == null) ||
        _isSending) return;
    if (_activeSessionId == null) {
      await createNewSession();
    }
    if (!isConfigured) {
      _errorMessage = '请先点击右上角齿轮，配置主模型 API Key / Base URL / 模型名';
      notifyListeners();
      return;
    }

    final sessionId = _activeSessionId!;
    final session = activeSession!;
    final promptVersion = session.promptVersion.value;
    final runRegistry = _scopedRegistry;
    final runScopedSystemPrompt = _scopedSystemPrompt;
    final runSystemPrompt = _systemPrompt;
    final mainConfig = this.mainConfig;
    final visionConfig = this.visionConfig;
    if (imageBase64 != null && !visionConfig.isConfigured) {
      _errorMessage = '发送图片需要先配置识图模型。请到设置 → 模型配置 → 识图模型，'
          '选择一个支持 vision 的供应商和模型（如 GPT-4o / Claude 3.5 Sonnet 等）。';
      notifyListeners();
      return;
    }
    _isSending = true;
    _errorMessage = null;

    // 立即显示 user 消息 + 占位 assistant 消息。
    // 已持久化的交互答案只补 assistant 占位，避免重复插入用户消息。
    final displayContent = [
      if (trimmed.isNotEmpty) trimmed,
      if (imageBase64 != null) '[图片]',
      if (textAttachment != null) '[文本附件]',
    ].join('\n');
    final tentativeUserMessage = LlmMessage(
      sessionId: sessionId,
      role: LlmMessageRole.user,
      content: displayContent,
      createdAt: DateTime.now(),
      imageBase64: imageBase64,
    );
    final placeholderCreatedAt =
        DateTime.now().add(const Duration(milliseconds: 1));
    var placeholder = LlmMessage(
      sessionId: sessionId,
      role: LlmMessageRole.assistant,
      content: '',
      createdAt: placeholderCreatedAt,
      agentTimeline: <AgentEvent>[],
    );
    _messages = alreadyPersisted
        ? [..._messages, placeholder]
        : [..._messages, tentativeUserMessage, placeholder];
    notifyListeners();

    void updatePlaceholder(LlmMessage next) {
      placeholder = next;
      final list = List<LlmMessage>.from(_messages);
      for (int i = list.length - 1; i >= 0; i--) {
        if (list[i].createdAt == placeholderCreatedAt &&
            list[i].role == LlmMessageRole.assistant) {
          list[i] = next;
          break;
        }
      }
      _messages = list;
      notifyListeners();
    }

    try {
      // 落库 user 消息。点击结构化选项时，答案已在事务中写入。
      if (!alreadyPersisted) {
        await _manageChat.saveUserMessage(
          sessionId: sessionId,
          userText: textAttachment == null
              ? trimmed
              : '${trimmed.isEmpty ? '' : '$trimmed\n\n'}$textAttachment',
          imageBase64: imageBase64,
        );
      }

      // 构造初始 messages：system + 上下文历史 + 当前用户消息
      final history = await _manageChat.listMessages(sessionId);
      // 截断历史：保留最近 _contextLimit 条；含 tool_calls 的 assistant 消息也保留（配对 tool 消息已落库为单独行，
      // 但本设计把 tool_calls 作为 assistant 消息的 JSON 字段保存，没有独立 tool 行，所以无需成对丢弃）
      final historyLimited = history.length > _contextLimit
          ? history.sublist(history.length - _contextLimit)
          : history;

      // 组装 system prompt：使用发送开始时捕获的会话上下文。
      final baseSystemPrompt = runScopedSystemPrompt == null
          ? runSystemPrompt
          : '$runSystemPrompt\n\n$runScopedSystemPrompt';
      final defaultStyleWords = promptVersion == 'v4.5'
          ? _defaultStyleWordsV45.trim()
          : _defaultStyleWordsV5.trim();
      var sysContent = defaultStyleWords.isEmpty
          ? '$baseSystemPrompt\n\n## 当前 NovelAI 画风版本\n本会话使用 $promptVersion 画风。'
          : '$baseSystemPrompt\n\n## 当前 NovelAI 画风版本\n本会话使用 $promptVersion 画风。\n\n## 默认画风画师词（本会话版本）\n用户为 $promptVersion 设定的默认画风画师词：`$defaultStyleWords`\n\n约束：调用写入提示词工具时，必须把这段画风画师词拼到正向提示词的最前面（多个 tag 用逗号空格分隔）。除非用户明确要求更换画风，否则每次生成都要带上。';

      final isV5PromptingSession = session.scope == 'general' &&
          session.promptVersion == NaiPromptVersion.v5;
      ToolRegistry? v5Registry;
      if (isV5PromptingSession) {
        try {
          final skill = await _promptingSkillLoader.loadSkill();
          sysContent = '$sysContent\n\n## V5 提示词 Skill\n$skill\n\n'
              '## App 集成边界\n'
              '以上 Skill 只负责 V5 提示词的构思与编排。App 的工具名称、确认机制、提示词框目标、'
              'read-then-write 约束和图片生成流程以本系统规则为准，不要自行发明工具。需要详细构思或写法时，'
              '调用 `read_prompting_reference` 读取对应参考文档；修改现有内容仍必须先调用 `read_current_prompts`。';
          v5Registry = (_agentLoopRegistry()).copy()
            ..register(ReadPromptingReferenceTool(_promptingSkillLoader));
        } catch (e) {
          if (kDebugMode) debugPrint('V5 prompting skill unavailable: $e');
        }
      }

      // 固定集成规则也适用于自定义系统提示词；记忆每轮直接召回，不依赖模型选工具。
      final memoryQuery =
          [trimmed, if (textAttachment != null) textAttachment].join('\n');
      final memoryContext = await _loadMemoryContext(memoryQuery);
      final payload = <Map<String, dynamic>>[
        {
          'role': 'system',
          'content': '$sysContent\n\n${PromptMemoryContext.policy}'
        },
        if (memoryContext.isNotEmpty)
          {'role': 'system', 'content': memoryContext},
      ];

      // 知识库匹配
      final knowledgeEntries = _nsfwBook.match(trimmed);
      if (knowledgeEntries.isNotEmpty) {
        final knowledgeText = knowledgeEntries
            .map((e) => '[来源: ${e.source} - ${e.title}]\n${e.content}')
            .join('\n\n---\n\n');
        payload.add({
          'role': 'system',
          'content':
              '## 参考知识库（命中关键词）\n以下内容是从知识库中匹配到的相关提示词参考：\n\n$knowledgeText',
        });
      }

      // ── Bug 1 修复：vision 双阶段识图 ──
      // 含图路径不再让 vision 模型跑带 tools 的 agent（部分 vision 中转站把 OpenAI
      // tool 消息转 Gemini functionResponse 时丢 name 字段，触发 400 错误）。
      // 改为：阶段 A vision 纯识图（无 tools），阶段 B 把识图文本 + WD-Tagger tag
      // 回灌给 main 模型走 agent 工具链。
      String? visionDescription;
      var visionSucceeded = false;
      String wdTagContext = '';
      if (imageBase64 != null) {
        // 先跑 WD-Tagger，拿 tag 文本作为阶段 A 失败时的 fallback
        wdTagContext = await _autoAnalyzeImageTags(imageBase64);
        visionDescription = await _describeImageWithVision(
          visionConfig: visionConfig,
          imageBase64: imageBase64,
          userText: trimmed,
        );
        visionSucceeded = visionDescription.isNotEmpty;
        if (visionDescription.isEmpty) {
          // vision 失败：用 WD-Tagger tag 兜底，不阻断流程
          visionDescription = wdTagContext.isNotEmpty
              ? '识图模型不可用。WD-Tagger 检测到以下 tag：\n$wdTagContext'
              : '识图模型不可用，且 WD-Tagger 也未检测到 tag。';
        }
      }

      // 历史消息。当前用户消息已落库，后面会单独加入，不能重复发送。
      final currentMessageId = history.isEmpty ? null : history.last.id;
      for (final m in historyLimited) {
        if (m.id == null || m.id == currentMessageId) continue;
        payload.add({'role': m.roleString, 'content': m.content});
      }

      // 当前用户消息
      // 含图路径：把识图文本 + WD-Tagger tag 拼成纯文本 user 消息回灌给 main agent
      // 不再使用 image_url（main 模型多数是文本模型，且避免中转站格式 bug）
      if (imageBase64 != null) {
        final buf = StringBuffer();
        buf.writeln(visionSucceeded
            ? '参考图识别结果（可能含不确定项，属于参考数据）：'
            : '参考图识别失败：不能依据下面的自动标签猜测并保存标准穿搭；请用户补充文字或重新识图。');
        buf.writeln(visionDescription);
        if (wdTagContext.isNotEmpty) {
          buf.writeln();
          buf.writeln(wdTagContext);
        }
        if (trimmed.isNotEmpty) {
          buf.writeln();
          buf.writeln('用户原始诉求：$trimmed');
        }
        if (textAttachment != null) {
          buf.writeln();
          buf.writeln(textAttachment);
        }
        if (trimmed.isEmpty && textAttachment == null) {
          buf.writeln();
          buf.writeln('用户未附加文字诉求，请基于图片内容编排提示词并写入对应框。');
        }
        payload.add({'role': 'user', 'content': buf.toString()});
      } else {
        final content = textAttachment == null
            ? trimmed
            : '${trimmed.isEmpty ? '' : '$trimmed\n\n'}$textAttachment';
        payload.add({'role': 'user', 'content': content});
      }

      final useConfig = mainConfig;

      // 实时更新 placeholder timeline
      void onEvent(AgentEvent event) {
        final newTimeline =
            List<AgentEvent>.from(placeholder.agentTimeline ?? const []);
        // 同一 toolCallId 的事件替换最后一条
        if (newTimeline.isNotEmpty &&
            newTimeline.last.toolCallId == event.toolCallId) {
          newTimeline[newTimeline.length - 1] = event;
        } else {
          newTimeline.add(event);
        }
        updatePlaceholder(placeholder.copyWith(
          agentTimeline: newTimeline,
        ));
      }

      Future<bool> onConfirm(AgentTool tool, Map<String, dynamic> args) async {
        if (onRequireConfirmation == null) return true;
        try {
          return await onRequireConfirmation!(AgentToolConfirmRequest(
            toolName: tool.name,
            description: tool.description,
            arguments: args,
          ));
        } catch (_) {
          return false;
        }
      }

      // AgentLoop 没有 setter，重新构造一个带 onEvent/onRequireConfirmation 的实例
      final loopWithCallbacks = AgentLoop(
        api: _agentLoopApi(),
        registry: runRegistry ?? v5Registry ?? _agentLoopRegistry(),
        onRequireConfirmation: onConfirm,
        onEvent: onEvent,
      );

      final result = await loopWithCallbacks.run(
        apiKey: useConfig.apiKey,
        baseUrl: useConfig.baseUrl,
        model: useConfig.model,
        initialMessages: payload,
      );

      // 落库 user + assistant（含 tool_calls JSON）
      final timeline = result.timeline;
      final toolNamesSet = timeline.map((e) => e.toolName).toSet();
      // Bug 3 修复：检测"有 read 无 write"——用户含修改类动词但 agent 只读未写
      final hasReadNoWrite = toolNamesSet.contains('read_current_prompts') &&
          !toolNamesSet.contains('write_prompt');
      final hasModifyVerb = _containsModifyVerb(trimmed);

      String statusText;
      if (result.failed) {
        if (hasReadNoWrite && hasModifyVerb) {
          statusText =
              'Agent 失败：读取了提示词但未完成写入。${result.error ?? "未知错误"}。建议重试或换更具体的指令。';
        } else {
          statusText = 'Agent 失败：${result.error ?? "未知错误"}';
        }
      } else if (result.hitMaxIterations) {
        if (hasReadNoWrite && hasModifyVerb) {
          statusText = 'Agent 读取了提示词但未完成写入（已达迭代上限）。建议重试或换更具体的指令。';
        } else {
          statusText = 'Agent 达到迭代上限';
        }
      } else if (timeline.isEmpty) {
        statusText = 'Agent 完成';
      } else if (hasReadNoWrite && hasModifyVerb) {
        // 正常完成但没写入——可能是 LLM 误解 read 即终点
        statusText = 'Agent 调用了 read 但未写入提示词。建议明确说"把改动写入正向框"或重试。';
      } else {
        final toolNames = toolNamesSet.join(', ');
        statusText = 'Agent 完成，调用工具：$toolNames';
      }

      final assistantText = result.finalContent.isEmpty
          ? (result.failed ? '（执行失败）' : '（Agent 未给出文本回复）')
          : result.finalContent;

      final toolCallsJson =
          timeline.isNotEmpty ? AgentEvent.toJsonList(timeline) : null;

      final saved = await _manageChat.saveAgentRunResult(
        sessionId: sessionId,
        assistantText: assistantText,
        toolCallsJson: toolCallsJson,
        agentTimeline: timeline,
        interaction: result.pendingInteraction,
      );

      _messages = await _manageChat.listMessages(sessionId);
      // 给真消息打上 agent timeline
      _messages = _messages
          .map((m) => m.id == saved.id
              ? m.copyWith(
                  agentTimeline: timeline,
                  interaction: result.pendingInteraction,
                )
              : m)
          .toList();
      _sessions = await _manageChat.listSessions();

      // 如果失败，把错误信息也写到 errorMessage
      if (result.failed) {
        _errorMessage = statusText;
      }
      // 触发 placeholder 清理（真消息已替换占位）
      updatePlaceholder(placeholder.copyWith(
        content: '',
        agentTimeline: const [],
      ));
    } catch (e) {
      updatePlaceholder(placeholder.copyWith(
        content: 'Agent 失败：$e',
      ));
      _errorMessage = e.toString().replaceFirst('AppException(null): ', '');
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  // LlmApiService 和 ToolRegistry 通过 factory 拿到
  // 这里用 getter 从 DI 中拿（避免循环依赖，每次都拿同一单例）
  dynamic _agentLoopApi() {
    // 直接从 DI 拿 LlmApiService 单例
    return _apiServiceSingleton;
  }

  ToolRegistry _agentLoopRegistry() {
    return _toolRegistrySingleton!;
  }

  // 用 static 注入：避免在 ViewModel 里 import Dio/LlmApiService 形成强依赖
  // injection.dart 在 registerFactory LlmChatViewModel 时会设置这两个静态字段
  // 注意：不能用 late final，否则 factory 第二次创建实例时会抛 LateInitializationError
  static dynamic _apiServiceSingleton;
  static ToolRegistry? _toolRegistrySingleton;
  static set apiServiceSingleton(dynamic s) => _apiServiceSingleton = s;
  static set toolRegistrySingleton(ToolRegistry r) =>
      _toolRegistrySingleton = r;

  Future<String?> _restoreMessageImage(LlmMessage message) async {
    if (message.imageBase64 != null && message.imageBase64!.isNotEmpty) {
      return message.imageBase64;
    }
    final path = message.imagePath;
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) {
        _errorMessage = '原图片文件已不存在，未删除历史消息。';
        notifyListeners();
        return null;
      }
      return base64Encode(await file.readAsBytes());
    } catch (e) {
      _errorMessage = '读取原图片失败，未删除历史消息：$e';
      notifyListeners();
      return null;
    }
  }

  Future<void> answerInteraction({
    required LlmMessage message,
    String? optionId,
    String? customAnswer,
  }) async {
    final interaction = message.interaction;
    if (_isSending ||
        message.sessionId != _activeSessionId ||
        message.id == null ||
        interaction == null ||
        interaction.isAnswered) {
      return;
    }
    if (!isConfigured) {
      _errorMessage = '请先点击右上角齿轮，配置主模型 API Key / Base URL / 模型名';
      notifyListeners();
      return;
    }
    final saved = await _manageChat.answerInteraction(
      sessionId: message.sessionId,
      messageId: message.id!,
      interactionId: interaction.id,
      optionId: optionId,
      customAnswer: customAnswer,
    );
    if (saved == null) return;
    _messages = await _manageChat.listMessages(message.sessionId);
    notifyListeners();
    await sendUserMessage(saved.content, alreadyPersisted: true);
  }

  /// 重试：从指定用户消息处重新发送。
  Future<void> retryFromIndex(int messageIndex) async {
    if (messageIndex < 0 || messageIndex >= _messages.length) return;
    final msg = _messages[messageIndex];
    if (msg.role != LlmMessageRole.user || msg.id == null || _isSending) return;
    final imageBase64 = await _restoreMessageImage(msg);
    if (msg.imagePath != null && imageBase64 == null) return;
    final text = msg.content.replaceAll(RegExp(r'\n?\[图片\]$'), '').trim();
    if (text.isEmpty && imageBase64 == null) return;
    await _manageChat.deleteMessagesFrom(msg.id!, _activeSessionId!);
    _messages = await _manageChat.listMessages(_activeSessionId!);
    notifyListeners();
    await sendUserMessage(text, imageBase64: imageBase64);
  }

  /// 编辑并重发，保留原消息附带的图片。
  Future<void> editAndResend(int messageIndex, String newText) async {
    if (messageIndex < 0 || messageIndex >= _messages.length) return;
    final msg = _messages[messageIndex];
    if (msg.role != LlmMessageRole.user || msg.id == null || _isSending) return;
    final trimmed = newText.trim();
    final imageBase64 = await _restoreMessageImage(msg);
    if (msg.imagePath != null && imageBase64 == null) return;
    if (trimmed.isEmpty && imageBase64 == null) return;
    await _manageChat.deleteMessagesFrom(msg.id!, _activeSessionId!);
    _messages = await _manageChat.listMessages(_activeSessionId!);
    notifyListeners();
    await sendUserMessage(trimmed, imageBase64: imageBase64);
  }

  /// 自动跑 WD-Tagger 解析图片，返回 system 上下文文本（失败时返回空字符串，不阻断主流程）。
  /// [imageBase64] 是用户发送的图片 base64 字符串（不含 data: 前缀）。
  Future<String> _autoAnalyzeImageTags(String imageBase64) async {
    File? tempFile;
    try {
      final tempDir = await getTemporaryDirectory();
      tempFile = File(
          '${tempDir.path}/agent_img_${DateTime.now().millisecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(base64Decode(imageBase64));

      final wdResult = await _analyzeImageTags.analyze(
        imagePath: tempFile.path,
        modelRepo: 'SmilingWolf/wd-swinv2-tagger-v3',
        generalThreshold: 0.35,
        characterThreshold: 0.85,
      );

      final generalTags = wdResult.generalTags.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final characterTags = wdResult.characterTags.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final buf = StringBuffer();
      buf.writeln('## 用户上传图片已自动解析（WD-Tagger）');
      buf.writeln('以下是图片中检测到的 Danbooru 风格 tag（按置信度排序）：');
      if (characterTags.isNotEmpty) {
        buf.writeln('### 角色标签');
        for (final e in characterTags) {
          buf.writeln('- ${e.key}（置信度 ${(e.value * 100).toStringAsFixed(0)}%）');
        }
      }
      if (generalTags.isNotEmpty) {
        buf.writeln('### 通用标签');
        // 限制最多 40 个，避免上下文过长
        final top = generalTags.take(40).toList();
        for (final e in top) {
          buf.writeln('- ${e.key}（${(e.value * 100).toStringAsFixed(0)}%）');
        }
        if (generalTags.length > 40) {
          buf.writeln('- ... 其余 ${generalTags.length - 40} 个 tag 已省略');
        }
      }
      buf.writeln('\n你可以在 vision 模型看图基础上参考这些 tag 编排提示词。');
      return buf.toString();
    } catch (e) {
      // 解析失败不阻断主流程，vision 模型仍能看图
      if (kDebugMode) {
        debugPrint('autoAnalyzeImageTags failed: $e');
      }
      return '';
    } finally {
      try {
        await tempFile?.delete();
      } catch (_) {}
    }
  }

  Future<String> _loadMemoryContext(String query) async {
    if (query.trim().isEmpty) return '';
    try {
      final matches = await _memories.matchText(query);
      final context = PromptMemoryContext.format(matches);
      if (context.isNotEmpty) {
        for (final memory in matches.take(PromptMemoryContext.maxEntries)) {
          if (memory.id == null || !memory.isRetrievable) continue;
          try {
            await _memories.incrementHit(memory.id!);
          } catch (e) {
            if (kDebugMode) debugPrint('Memory hit statistics unavailable: $e');
          }
        }
      }
      return context;
    } catch (e) {
      if (kDebugMode) debugPrint('Local memory retrieval unavailable: $e');
      return '本轮本地记忆读取失败。不要据此断言没有记忆，或声称已调用角色标准穿搭；'
          '请说明读取暂不可用，并按用户本轮明确提供的信息继续。';
    }
  }

  /// Bug 1 修复：用 vision 模型对图片做纯描述（不调用 tools）。
  /// 失败时返回空字符串，由调用方 fallback 到 WD-Tagger tag。
  /// 设计动机：部分 vision 中转站把 OpenAI tool 消息转 Gemini functionResponse
  /// 时丢 name 字段，触发 400 错误。本方法只发 system + user(图) 两条消息，
  /// 不带 tools 字段，规避中转站的 tool 格式转换 bug。
  Future<String> _describeImageWithVision({
    required LlmRoleConfig visionConfig,
    required String imageBase64,
    required String userText,
  }) async {
    if (!visionConfig.isConfigured) return '';
    try {
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': AppConstants.defaultVisionDescribePrompt},
        {
          'role': 'user',
          'content': [
            if (userText.isNotEmpty) {'type': 'text', 'text': userText},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$imageBase64'},
            },
          ],
        },
      ];
      // _apiServiceSingleton 实际是 LlmApiService 单例（DI 注入），
      // dynamic 调用走 Dart 动态分发。
      final desc = await (_apiServiceSingleton as dynamic).chatCompletions(
        apiKey: visionConfig.apiKey,
        baseUrl: visionConfig.baseUrl,
        model: visionConfig.model,
        messages: messages,
      ) as String;
      return desc.trim();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('describeImageWithVision failed: $e');
      }
      return '';
    }
  }

  /// Bug 3 修复：检测用户原文是否含修改类动词。
  /// 用于判断"有 read 无 write"是否为误判——纯查询（"读一下"）不应触发警告。
  static final RegExp _modifyVerbPattern = RegExp(
    r'改|加|换|删|调整|变成|修改|重新编排|重排|替换|覆盖|新增|去掉|删除|添加',
  );

  bool _containsModifyVerb(String text) {
    return _modifyVerbPattern.hasMatch(text);
  }
}

/// 副作用工具确认请求。UI 用此对象构造弹窗。
class AgentToolConfirmRequest {
  final String toolName;
  final String description;
  final Map<String, dynamic> arguments;
  const AgentToolConfirmRequest({
    required this.toolName,
    required this.description,
    required this.arguments,
  });
}
