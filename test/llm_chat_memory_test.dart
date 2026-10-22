import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/llm_response.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:nai_huishi/domain/entities/tool_call.dart';

import 'support/chat_memory_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    pathProviderChannel,
    (_) async => Directory.systemTemp.path,
  );

  ChatMemoryHarness? harness;

  setUp(() {
    harness = null;
  });

  tearDown(() {
    harness?.dispose();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  Future<ChatMemoryHarness> startHarness({
    List<PromptMemory>? memories,
    bool memoryReadFails = false,
    String systemPrompt = '测试自定义系统提示词',
    String visionDescription = '图中可见绿色长发角色穿着白色披肩与绿色连衣裙。',
    bool visionFails = false,
    bool registerSaveMemoryTool = false,
    List<LlmResponse> scriptedMainResponses = const [],
  }) async {
    final created = createChatMemoryHarness(
      memories: memories,
      memoryReadFails: memoryReadFails,
      systemPrompt: systemPrompt,
      visionDescription: visionDescription,
      visionFails: visionFails,
      registerSaveMemoryTool: registerSaveMemoryTool,
      scriptedMainResponses: scriptedMainResponses,
    );
    harness = created;
    await created.viewModel.ensureInitialized();
    return created;
  }

  Future<void> verifySaveAndPromoteLifecycle({
    required bool fromReferenceImage,
  }) async {
    const visionOutfit = '参考图可见白色披肩、绿色连衣裙和金色叶形发饰；鞋子被裁切，无法确认。';
    const textOutfit = '用户指定的标准穿搭：白色短上衣、绿色连衣裙和金色叶形发饰。';
    final candidateContent = fromReferenceImage ? visionOutfit : textOutfit;
    final saveMemoryResponse = LlmResponse(
      content: '',
      toolCalls: [
        ToolCall(
          id: 'save-memory-1',
          name: 'save_memory',
          arguments: {
            'trigger': '纳西妲',
            'aliases': ['草神', 'Nahida'],
            'content': candidateContent,
            'type': 'character_outfit',
          },
        ),
      ],
      finishReason: 'tool_calls',
    );
    final h = await startHarness(
      memories: const [],
      visionDescription: visionOutfit,
      registerSaveMemoryTool: true,
      scriptedMainResponses: [saveMemoryResponse],
    );

    final originalRequest = fromReferenceImage
        ? '请把参考图中纳西妲可见的穿搭记为她的标准穿搭。'
        : '请记住纳西妲的标准穿搭：白色短上衣、绿色连衣裙和金色叶形发饰。';
    await h.viewModel.sendUserMessage(
      originalRequest,
      imageBase64: fromReferenceImage ? 'AQIDBA==' : null,
    );

    expect(h.api.mainCalls, hasLength(2));
    expect(_toolNames(h.api.mainCalls.first), contains('save_memory'));
    final pending = h.memoryRepository.memories.single;
    expect(pending.id, isNotNull);
    expect(pending.type, PromptMemoryType.characterOutfit);
    expect(pending.source, PromptMemorySource.pendingLlmCandidate);
    expect(pending.content, candidateContent);
    if (fromReferenceImage) {
      expect(h.api.visionCalls, hasLength(1));
      expect(h.api.mainCalls.first.lastUserText, contains(visionOutfit));
    }

    await h.viewModel.createNewSession();
    await h.viewModel.sendUserMessage('新聊天请按纳西妲的标准穿搭来画。');
    final beforeConfirmation = h.api.mainCalls.last;
    expect(
      _systemMessages(beforeConfirmation).join('\n'),
      isNot(contains(candidateContent)),
    );
    expect(h.memoryRepository.incrementedIds, isEmpty);

    final confirmed = await h.memoryRepository.promotePending(pending.id!);
    expect(confirmed.source, PromptMemorySource.llmCandidate);
    await h.viewModel.createNewSession();
    await h.viewModel.sendUserMessage('新聊天请画草神的标准穿搭。');

    final afterConfirmation = h.api.mainCalls.last;
    expect(
      _systemMessages(afterConfirmation).join('\n'),
      contains(candidateContent),
    );
    expect(h.memoryRepository.incrementedIds, [pending.id]);
    expect(afterConfirmation.lastUserText, '新聊天请画草神的标准穿搭。');
  }

  test('text recall is injected automatically without a get_memories tool',
      () async {
    final h = await startHarness();

    await h.viewModel.sendUserMessage('请画纳西妲，保持她的标准穿搭。');

    expect(h.api.mainCalls, hasLength(1));
    final call = h.api.mainCalls.single;
    expect(_systemMessages(call), contains(contains('白色短上衣')));
    final toolNames = _toolNames(call);
    expect(toolNames, contains('test_noop'));
    expect(toolNames, isNot(contains('get_memories')));
    expect(h.memoryRepository.matchQueries.single, contains('纳西妲'));
    expect(h.memoryRepository.incrementedIds, [41]);
  });

  test('a new chat still recalls the shared memory without prior chat history',
      () async {
    final h = await startHarness();
    await h.viewModel.sendUserMessage('画纳西妲。');

    await h.viewModel.createNewSession();
    await h.viewModel.sendUserMessage('画草神的标准穿搭。');

    expect(h.api.mainCalls, hasLength(2));
    final secondCall = h.api.mainCalls[1];
    expect(_systemMessages(secondCall), contains(contains('白色短上衣')));
    final userMessages = secondCall.messages
        .where((message) => message['role'] == 'user')
        .map((message) => message['content'] as String)
        .toList();
    expect(userMessages, ['画草神的标准穿搭。']);
    expect(h.memoryRepository.matchQueries, [
      '画纳西妲。',
      '画草神的标准穿搭。',
    ]);
  });

  test('custom system prompt keeps memory policy and current outfit priority',
      () async {
    final h = await startHarness(systemPrompt: '用户自定义：回答简洁，使用中文。');

    await h.viewModel.sendUserMessage('纳西妲这次换成蓝色运动服。');

    final system = h.api.mainCalls.single.firstSystemContent!;
    expect(system, contains('用户自定义：回答简洁，使用中文。'));
    expect(system, contains('本地记忆规则'));
    expect(system, contains('本轮用户明确指定的换装、颜色或配饰优先'));
    expect(system, contains('同角色的默认服饰以 characterOutfit 记录为准'));
    expect(system, contains('各角色记忆只用于其姓名/别名指定的角色，不能相互套用'));
    expect(
        _systemMessages(h.api.mainCalls.single), contains(contains('白色短上衣')));
    expect(h.api.mainCalls.single.lastUserText, contains('蓝色运动服'));
  });

  test('memory read failure is reported while the main request still proceeds',
      () async {
    final h = await startHarness(memoryReadFails: true);

    await h.viewModel.sendUserMessage('请画纳西妲。');

    expect(h.api.mainCalls, hasLength(1));
    final system = _systemMessages(h.api.mainCalls.single).join('\n');
    expect(system, contains('本轮本地记忆读取失败'));
    expect(system, contains('不要据此断言没有记忆'));
    expect(system, isNot(contains('未找到任何记忆')));
    expect(h.api.mainCalls.single.lastUserText, '请画纳西妲。');
  });

  test(
      'image vision request carries image without tools and feeds its text to main',
      () async {
    const description = '画面中角色穿着白色披肩、绿色连衣裙，胸前细节可见。';
    const request = '请识别图中纳西妲的衣服，并记住这套标准穿搭。';
    final h = await startHarness(visionDescription: description);

    await h.viewModel.sendUserMessage(
      request,
      imageBase64: 'AQIDBA==',
    );

    expect(h.api.visionCalls, hasLength(1));
    final visionCall = h.api.visionCalls.single;
    expect(visionCall.tools, isNull);
    final visionUserContent = visionCall.messages.last['content'] as List;
    expect(
      visionUserContent.whereType<Map>().any(
            (part) => part['type'] == 'text' && part['text'] == request,
          ),
      isTrue,
    );
    final imagePart = visionUserContent
        .whereType<Map>()
        .firstWhere((part) => part['type'] == 'image_url');
    expect(
      (imagePart['image_url'] as Map)['url'],
      'data:image/jpeg;base64,AQIDBA==',
    );

    expect(h.api.mainCalls, hasLength(1));
    final mainUserText = h.api.mainCalls.single.lastUserText;
    expect(mainUserText, contains(description));
    expect(mainUserText, contains(request));
    expect(mainUserText, isNot(contains('image_url')));
    expect(mainUserText, isNot(contains('data:image/')));
    expect(h.analyzeImageTags.calls, 1);
  });

  test('vision failure forbids treating WD tags as learned standard outfit',
      () async {
    final h = await startHarness(visionFails: true);

    await h.viewModel.sendUserMessage(
      '请从图中识别纳西妲的标准穿搭并记住。',
      imageBase64: 'AQIDBA==',
    );

    expect(h.api.visionCalls, hasLength(1));
    final call = h.api.mainCalls.single;
    expect(
      call.lastUserText,
      contains('不能依据下面的自动标签猜测并保存标准穿搭'),
    );
    expect(call.lastUserText, contains('识图模型不可用'));
    expect(call.lastUserText, contains('white_dress'));
    expect(
      _systemMessages(call).join('\n'),
      contains('识图失败时不得把 WD-Tagger 猜测保存为图中标准穿搭'),
    );
    expect(call.lastUserText, contains('请从图中识别纳西妲的标准穿搭并记住。'));
  });

  test('character aliases in text attachments participate in automatic recall',
      () async {
    final memory = canonicalOutfitMemory(
      trigger: '纳西妲 | 小草神 | Nahida',
    );
    final h = await startHarness(memories: [memory]);

    await h.viewModel.sendUserMessage(
      '请参考附件。',
      textAttachment: '角色：小草神。请沿用她的标准穿搭。',
    );

    expect(
      h.memoryRepository.matchQueries.single,
      '请参考附件。\n角色：小草神。请沿用她的标准穿搭。',
    );
    expect(
        _systemMessages(h.api.mainCalls.single), contains(contains('白色短上衣')));
    expect(h.api.mainCalls.single.lastUserText, contains('角色：小草神'));
  });

  test('a text save_memory call stays pending until explicit promotion',
      () async {
    await verifySaveAndPromoteLifecycle(fromReferenceImage: false);
  });

  test('a vision-derived outfit follows the same confirmation lifecycle',
      () async {
    await verifySaveAndPromoteLifecycle(fromReferenceImage: true);
  });
}

List<String> _systemMessages(CapturedLlmCall call) => call.messages
    .where((message) => message['role'] == 'system')
    .map((message) => message['content'] as String)
    .toList();

List<String> _toolNames(CapturedLlmCall call) => call.tools!
    .map((tool) => (tool['function'] as Map<String, dynamic>)['name'] as String)
    .toList();
