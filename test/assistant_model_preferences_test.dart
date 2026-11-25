import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/agents/tool_registry.dart';
import 'package:nai_huishi/domain/agents/tools/ask_user_tool.dart';
import 'package:nai_huishi/domain/agents/tools/write_prompt_tool.dart';
import 'package:nai_huishi/domain/entities/llm_interaction.dart';
import 'package:nai_huishi/domain/entities/llm_profile_role.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_response.dart';
import 'package:nai_huishi/domain/entities/tool_call.dart';
import 'package:nai_huishi/domain/entities/prompt_draft_snapshot.dart';
import 'package:nai_huishi/domain/services/explicit_online_tag_query.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'support/chat_memory_fake.dart';
import 'support/frontend_generation_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          channel, (_) async => Directory.systemTemp.path));
  tearDownAll(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('extracts one explicitly requested online tag without sending prose',
      () {
    const requests = {
      '帮我在线查一下「绯英」的规范角色 Tag。': '绯英',
      '在线查这个 Tag：shunling_(blue_archive)': 'shunling_(blue_archive)',
      '联网查 shunling_(blue_archive)': 'shunling_(blue_archive)',
      '请在 Danbooru 官网查 绯英': '绯英',
      'Please search Danbooru for shunling_(blue_archive).':
          'shunling_(blue_archive)',
      'look up tag shunling_(blue_archive) online': 'shunling_(blue_archive)',
      '请在线查一下天气': null,
      '在线查一下「天气」': null,
      'search flights online': null,
      '在线查这个 Tag': null,
      '在线查这张图里的标签': null,
      '在线查绯英的 Tag，然后按之前的方案出图': null,
      '在线查 Tag：绯英\n我的整套提示词': null,
      '用绯英画一张图': null,
    };
    for (final request in requests.entries) {
      expect(explicitOnlineTagQuery(request.key), request.value,
          reason: request.key);
    }
  });

  for (final found in [true, false]) {
    test('explicit lookup runs before the first model request (found=$found)',
        () async {
      final h = createChatMemoryHarness();
      addTearDown(h.dispose);
      final tagTool = _TagLookupSpy(found);
      LlmChatViewModel.toolRegistrySingleton = ToolRegistry()
        ..register(tagTool);
      await h.viewModel.ensureInitialized();
      h.api.onMainRequest = () => expect(tagTool.calls, hasLength(1));

      const request = '在线查这个 Tag：shunling_(blue_archive)';
      await h.viewModel.sendUserMessage(request);

      expect(h.api.mainCalls.single.lastUserText, request);
      expect(tagTool.calls.single,
          {'query': 'shunling_(blue_archive)', 'source': 'online'});
      final context = h.api.mainCalls.single.messages
          .singleWhere((m) => m['content'].toString().contains('客户端已执行'));
      expect(context['role'], 'system');
      expect(
          context['content'], contains(found ? 'Danbooru 官网已核实' : '在线端点不可用'));
      final reply =
          (await h.chatRepository.listMessages(h.viewModel.activeSessionId!))
              .last;
      final events = reply.agentTimeline!;
      expect(events.map((e) => e.toolName),
          ['search_danbooru', 'read_current_prompts']);
      expect(events.first.status, found ? 'done' : 'error');
    });
  }

  test('per-model output modes persist independently and legacy values migrate',
      () {
    final provider = LlmProvider.create(
        name: 'test', models: ['a', 'b'], streaming: {'a': false, 'b': true});
    final restored = LlmProvider.fromJson(provider.toJson());
    expect(restored.streaming, {'a': false, 'b': true});
    expect(restored.copyWith(name: 'renamed').streaming, restored.streaming);
    expect(LlmProvider.fromJson({'name': 'legacy'}).streaming, isEmpty);
  });

  test(
      'fixed 1M budget ignores legacy capacities and main mode selects actual transport',
      () async {
    final h = createChatMemoryHarness();
    addTearDown(h.dispose);
    await h.viewModel.ensureInitialized();
    await h.viewModel.setProviders([
      for (final p in h.viewModel.providers)
        p.copyWith(contextWindows: {h.viewModel.mainBinding.model: 2048})
    ]);
    expect(h.viewModel.modelContextWindow, 1000000);
    await h.viewModel.setModelStreaming(LlmProfileRole.main, false);
    await h.viewModel.sendUserMessage('first');
    expect(h.api.mainCalls, hasLength(1));
    expect(h.api.streamRequests, 0);
    await h.viewModel.setModelStreaming(LlmProfileRole.main, true);
    await h.viewModel.sendUserMessage('second');
    expect(h.api.streamRequests, 1);
    expect(h.viewModel.errorMessage, isNull);
  });

  test('vision mode can stream without tools and still does not cache results',
      () async {
    final h = createChatMemoryHarness();
    addTearDown(h.dispose);
    await h.viewModel.ensureInitialized();
    await h.viewModel.setModelStreaming(LlmProfileRole.main, false);
    await h.viewModel.setModelStreaming(LlmProfileRole.vision, true);
    await h.viewModel
        .sendUserMessage('describe', imageBase64s: ['AQIDBA==', 'AQIDBA==']);
    expect(h.api.visionCalls, hasLength(2));
    expect(h.api.streamRequests, 2);
    expect(h.analyzeImageTags.calls, 1);
    expect(h.viewModel.errorMessage, isNull);
  });

  const write = LlmResponse(
      content: '',
      toolCalls: [
        ToolCall(id: 'w', name: 'write_prompt', arguments: {
          'target': 'positive',
          'content': 'new tags',
          'mode': 'replace'
        })
      ],
      finishReason: 'tool_calls');

  test('reads before every model request and writes without any confirmation',
      () async {
    final generation = FrontendGenerationFake()..prompt = 'original tags';
    final h = createChatMemoryHarness(
        generation: generation, scriptedMainResponses: [write]);
    addTearDown(h.dispose);
    LlmChatViewModel.toolRegistrySingleton = ToolRegistry()
      ..register(WritePromptTool(generation));
    var confirmations = 0;
    h.viewModel.onRequireConfirmation = (_) async {
      confirmations++;
      return false;
    };
    await h.viewModel.ensureInitialized();
    await h.viewModel.sendUserMessage('replace');
    expect(h.viewModel.errorMessage, isNull);
    expect(confirmations, 0);
    expect(generation.prompt, 'new tags');
    expect(h.viewModel.canUndoPrompt, isTrue);
    expect(
        h.api.mainCalls[0].messages[1]['content'], contains('original tags'));
    expect(h.api.mainCalls[1].messages[1]['content'], contains('new tags'));
    expect(h.api.mainCalls[1].messages[1]['content'],
        isNot(contains('original tags')));
  });

  test('manual edits made during model response are not overwritten', () async {
    final generation = FrontendGenerationFake()..prompt = 'original tags';
    final h = createChatMemoryHarness(
        generation: generation, scriptedMainResponses: [write]);
    addTearDown(h.dispose);
    LlmChatViewModel.toolRegistrySingleton = ToolRegistry()
      ..register(WritePromptTool(generation));
    await h.viewModel.ensureInitialized();
    h.api.onMainRequest = () {
      generation.prompt = 'manual tags';
      generation.version++;
      h.api.onMainRequest = null;
    };
    await h.viewModel.sendUserMessage('replace');
    expect(generation.prompt, 'manual tags');
    expect(h.viewModel.canUndoPrompt, isFalse);
    expect(h.api.mainCalls[1].messages[1]['content'], contains('manual tags'));
  });

  test('undo stays on the writing reply and only in its original session',
      () async {
    final generation = _UndoGenerationFake()..prompt = 'original tags';
    final h = createChatMemoryHarness(
        generation: generation, scriptedMainResponses: [write]);
    addTearDown(h.dispose);
    LlmChatViewModel.toolRegistrySingleton = ToolRegistry()
      ..register(WritePromptTool(generation));
    await h.viewModel.ensureInitialized();
    await h.viewModel.sendUserMessage('replace');
    final owner = h.viewModel.messages.last;
    expect(h.viewModel.undoPromptMessage?.id, owner.id);
    await h.viewModel.sendUserMessage('explain');
    expect(h.viewModel.undoPromptMessage?.id, owner.id);
    await h.viewModel.createNewSession();
    expect(h.viewModel.undoPromptMessage, isNull);
    await h.viewModel.selectSession(owner.sessionId);
    expect(h.viewModel.undoPromptMessage?.id, owner.id);
    await h.viewModel.undoPromptChange();
    expect(generation.prompt, 'original tags');
    expect(h.viewModel.undoPromptMessage, isNull);
  });
  test('one reply restores both writes and retry reads the current draft',
      () async {
    final generation = _UndoGenerationFake()
      ..prompt = 'original tags'
      ..negativePrompt = 'old negatives';
    final h =
        createChatMemoryHarness(generation: generation, scriptedMainResponses: [
      write,
      const LlmResponse(
          content: '',
          toolCalls: [
            ToolCall(id: 'negative', name: 'write_prompt', arguments: {
              'target': 'negative',
              'content': 'new negatives',
              'mode': 'replace',
            })
          ],
          finishReason: 'tool_calls'),
    ]);
    addTearDown(h.dispose);
    LlmChatViewModel.toolRegistrySingleton = ToolRegistry()
      ..register(WritePromptTool(generation));
    await h.viewModel.ensureInitialized();
    await h.viewModel.sendUserMessage('replace both');
    final source = h.viewModel.activeSessionId;
    final message = h.viewModel.messages.last;
    expect(message.agentTimeline?.map((e) => e.toolName),
        ['read_current_prompts', 'write_prompt', 'write_prompt']);
    expect(generation.prompt, 'new tags');
    expect(generation.negativePrompt, 'new negatives');
    await h.viewModel.undoPromptChange();
    expect(generation.prompt, 'original tags');
    expect(generation.negativePrompt, 'old negatives');
    final requestCount = h.api.mainCalls.length;
    await h.viewModel.branchFromReply(h.viewModel.messages.length - 1);
    expect(h.viewModel.activeSession?.parentSessionId, source);
    expect(h.viewModel.messages.last.content, message.content);
    expect(h.viewModel.messages.last.promptDraftChange, isNull);
    expect(h.api.mainCalls, hasLength(requestCount));
    await h.viewModel.selectSession(source!);
    await h.viewModel.retryFromIndex(h.viewModel.messages.length - 1);
    expect(h.viewModel.activeSessionId, source);
    expect(h.viewModel.sessions, hasLength(2));
    expect(h.viewModel.messages.last.id, message.id);
    expect(
        h.api.mainCalls.last.messages[1]['content'], contains('original tags'));
  });

  test('retries an older reply in its original slot and keeps later turns',
      () async {
    final h = createChatMemoryHarness(scriptedMainResponses: const [
      LlmResponse(content: '重试的回复', toolCalls: [], finishReason: 'stop'),
      LlmResponse(content: '第二次重试', toolCalls: [], finishReason: 'stop'),
    ]);
    addTearDown(h.dispose);
    final repo = h.chatRepository;
    final session = await repo.createSession();
    await repo.saveUserMessage(sessionId: session.id, userText: '原始问题');
    final original = await repo.saveAgentRunResult(
        sessionId: session.id, assistantText: '原始回复');
    await repo.saveUserMessage(sessionId: session.id, userText: '后续问题');
    await repo.saveAgentRunResult(sessionId: session.id, assistantText: '后续回复');
    await h.viewModel.ensureInitialized();
    final before = h.viewModel.messages;

    await h.viewModel.retryFromIndex(1);
    expect(h.viewModel.activeSessionId, session.id);
    expect(h.viewModel.sessions, hasLength(1));
    expect(h.viewModel.messages[1].id, original.id);
    expect(h.viewModel.messages[1].content, '重试的回复');
    expect(h.viewModel.messages.skip(2), before.skip(2));
    expect(
      h.api.mainCalls.single.messages
          .where((m) => m['role'] == 'user')
          .map((m) => m['content']),
      ['原始问题'],
    );

    await h.viewModel.retryFromIndex(0);
    final saved = await repo.listMessages(session.id);
    expect(saved.map((m) => m.id), before.map((m) => m.id));
    expect(saved[1].content, '第二次重试');
    expect(h.viewModel.sessions, hasLength(1));

    h.api.onMainRequest = () => throw StateError('mock retry failure');
    await h.viewModel.retryFromIndex(1);
    expect(h.viewModel.messages, saved);
    expect(await repo.listMessages(session.id), saved);
    expect(h.viewModel.errorMessage, contains('mock retry failure'));
  });

  test('places an interrupted earlier turn reply before later messages',
      () async {
    final h = createChatMemoryHarness();
    addTearDown(h.dispose);
    final repo = h.chatRepository;
    final session = await repo.createSession();
    final first =
        await repo.saveUserMessage(sessionId: session.id, userText: '中断的问题');
    final second =
        await repo.saveUserMessage(sessionId: session.id, userText: '后续问题');
    await h.viewModel.ensureInitialized();

    await h.viewModel.retryFromIndex(0);

    expect(h.viewModel.sessions, hasLength(1));
    final messages = await repo.listMessages(session.id);
    expect(messages, hasLength(3));
    expect(messages.first.id, first);
    expect(messages[1].content, '固定测试回复');
    expect(messages.last.id, second);
  });

  test('failed retry preserves the old reply and can undo its new draft edit',
      () async {
    final generation = _UndoGenerationFake()..prompt = 'original tags';
    final h = createChatMemoryHarness(
        generation: generation, scriptedMainResponses: [write]);
    addTearDown(h.dispose);
    LlmChatViewModel.toolRegistrySingleton = ToolRegistry()
      ..register(WritePromptTool(generation));
    final repo = h.chatRepository;
    final session = await repo.createSession();
    await repo.saveUserMessage(sessionId: session.id, userText: '修改提示词');
    final original = await repo.saveAgentRunResult(
      sessionId: session.id,
      assistantText: '先前回复',
      interaction: LlmInteraction(
        id: 'original-question',
        question: '请选择',
        options: const [LlmInteractionOption(id: 'a', label: '选项一')],
        createdAt: DateTime(2026),
      ),
    );
    await h.viewModel.ensureInitialized();
    h.api.onMainRequest = () {
      if (h.api.mainCalls.isNotEmpty) {
        throw StateError('retry failed after write');
      }
    };

    await h.viewModel.retryFromIndex(1);

    final saved = (await repo.listMessages(session.id)).last;
    expect(saved.id, original.id);
    expect(saved.content, original.content);
    expect(saved.interaction, original.interaction);
    expect(saved.promptDraftChange?.after.positive, 'new tags');
    expect(generation.prompt, 'new tags');
    expect(h.viewModel.undoPromptMessage?.id, original.id);
    await h.viewModel.undoPromptChange();
    expect(generation.prompt, 'original tags');
  });

  test('a question produced by retrying a historical reply stays in that turn',
      () async {
    final h = createChatMemoryHarness(scriptedMainResponses: const [
      LlmResponse(
        content: '',
        toolCalls: [
          ToolCall(id: 'q', name: 'ask_user', arguments: {
            'question': '选择景别',
            'options': [
              {'id': 'wide', 'label': '全景'},
              {'id': 'close', 'label': '近景'},
            ],
          }),
        ],
        finishReason: 'tool_calls',
      ),
    ]);
    addTearDown(h.dispose);
    LlmChatViewModel.toolRegistrySingleton = ToolRegistry()
      ..register(AskUserTool());
    final repo = h.chatRepository;
    final session = await repo.createSession();
    await repo.saveUserMessage(sessionId: session.id, userText: '旧问题');
    final old = await repo.saveAgentRunResult(
        sessionId: session.id, assistantText: '旧回复');
    final next =
        await repo.saveUserMessage(sessionId: session.id, userText: '新问题');
    await h.viewModel.ensureInitialized();

    await h.viewModel.retryFromIndex(1);

    final messages = await repo.listMessages(session.id);
    expect(messages.map((m) => m.id).skip(1), [old.id, next]);
    expect(messages[1].content, allOf(contains('选择景别'), contains('全景')));
    expect(messages[1].interaction, isNull);
  });
}

class _TagLookupSpy extends AgentTool {
  _TagLookupSpy(this.found);

  final bool found;
  final calls = <Map<String, dynamic>>[];

  @override
  String get name => 'search_danbooru';

  @override
  String get description => '查找标签';

  @override
  Map<String, dynamic> get parametersSchema => const {'type': 'object'};

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    calls.add(arguments);
    return found
        ? ToolResult.success('Danbooru 官网已核实 shunling_(blue_archive)')
        : ToolResult.failure('在线端点不可用');
  }
}

class _UndoGenerationFake extends FrontendGenerationFake {
  @override
  Future<int> writePrompt({
    required String target,
    required String content,
    required bool append,
    double? centerX,
    double? centerY,
  }) async {
    if (target != 'negative') {
      return super.writePrompt(
          target: target,
          content: content,
          append: append,
          centerX: centerX,
          centerY: centerY);
    }
    negativePrompt = append && negativePrompt.isNotEmpty
        ? '$negativePrompt, $content'
        : content;
    version++;
    return version;
  }

  @override
  Future<bool> restorePromptDraft(
      PromptDraftSnapshot snapshot, int expectedVersion) async {
    if (version != expectedVersion || isInpaintingMode != snapshot.inpainting) {
      return false;
    }
    prompt = snapshot.positive;
    negativePrompt = snapshot.negative;
    inpaintPrompt = snapshot.inpaintPositive;
    inpaintNegativePrompt = snapshot.inpaintNegative;
    characters = List.of(snapshot.characters);
    version++;
    notifyListeners();
    return true;
  }
}
