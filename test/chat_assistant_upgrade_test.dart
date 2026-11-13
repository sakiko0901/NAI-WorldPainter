import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/data/datasources/local/settings_local_datasource.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nai_huishi/domain/services/chat_context_compressor.dart';
import 'support/chat_memory_fake.dart';

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

  test(
      'multimodal and version-specific negative defaults persist independently',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsLocalDatasource(prefs);
    expect(settings.getLlmMultimodal(), isFalse);
    await settings.setLlmMultimodal(true);
    await settings.setDefaultNegativeWordsV5('v5 excluded');
    await settings.setDefaultNegativeWordsV45('v45 excluded');
    final reloaded = SettingsLocalDatasource(prefs);
    expect(reloaded.getLlmMultimodal(), isTrue);
    expect(reloaded.getDefaultNegativeWordsV5(), 'v5 excluded');
    expect(reloaded.getDefaultNegativeWordsV45(), 'v45 excluded');
  });

  test('legacy image paths and multiple image paths are both readable', () {
    expect(LlmMessage.decodeImagePaths('C:/old.png'), ['C:/old.png']);
    expect(
        LlmMessage.decodeImagePaths('["a.png","b.png"]'), ['a.png', 'b.png']);
  });
  test('multimodal sends all ten images to main without vision or tagger',
      () async {
    final h = createChatMemoryHarness();
    addTearDown(h.dispose);
    await h.viewModel.ensureInitialized();
    await h.viewModel.setMultimodal(true);
    final images = List.generate(10, (_) => 'AQIDBA==');
    await h.viewModel.sendUserMessage('比较参考图', imageBase64s: images);
    expect(h.viewModel.errorMessage, isNull);
    expect(h.api.visionCalls, isEmpty);
    expect(h.analyzeImageTags.calls, 0);
    final content = h.api.mainCalls.single.messages.last['content'] as List;
    expect(content.where((p) => p['type'] == 'image_url'), hasLength(10));
    expect(h.viewModel.messages.first.allImageBase64s, images);
    await h.viewModel.editAndResend(0, '保留附件重新比较');
    expect(h.viewModel.messages.first.allImageBase64s, images);
    expect(h.api.mainCalls, hasLength(2));
  });
  test('eleven images are rejected before persistence and requests', () async {
    final h = createChatMemoryHarness();
    addTearDown(h.dispose);
    await h.viewModel.ensureInitialized();
    await h.viewModel
        .sendUserMessage('图', imageBase64s: List.filled(11, 'AQIDBA=='));
    expect(h.viewModel.messages, isEmpty);
    expect(h.api.mainCalls, isEmpty);
    expect(h.viewModel.errorMessage, contains('10'));
  });
  test('separate vision mode analyzes every reference in order', () async {
    final h = createChatMemoryHarness();
    addTearDown(h.dispose);
    await h.viewModel.ensureInitialized();
    await h.viewModel
        .sendUserMessage('比较', imageBase64s: ['AQIDBA==', 'BQYHCA==']);
    expect(h.api.visionCalls, hasLength(2));
    expect(h.api.mainCalls.single.lastUserText, contains('图片 2'));
  });
  test('only tagger is cached; repeated vision always requests fresh analysis',
      () async {
    final h = createChatMemoryHarness();
    addTearDown(h.dispose);
    await h.viewModel.ensureInitialized();
    await h.viewModel
        .sendUserMessage('describe', imageBase64s: ['AQIDBA==', 'AQIDBA==']);
    expect(h.api.visionCalls, hasLength(2));
    expect(h.analyzeImageTags.calls, 1);
    await h.viewModel.sendUserMessage('describe', imageBase64s: ['AQIDBA==']);
    expect(h.api.visionCalls, hasLength(3));
    await h.viewModel.sendUserMessage('colors', imageBase64s: ['AQIDBA==']);
    expect(h.api.visionCalls, hasLength(4));
    expect(h.analyzeImageTags.calls, 1);
    await h.viewModel.clearImageAnalysisCache();
    await h.viewModel.sendUserMessage('colors', imageBase64s: ['AQIDBA==']);
    expect(h.api.visionCalls, hasLength(5));
    expect(h.analyzeImageTags.calls, 2);
    expect(h.viewModel.errorMessage, isNull);
  });
  test('negative prompts follow the session version', () async {
    final h = createChatMemoryHarness();
    addTearDown(h.dispose);
    await h.viewModel.ensureInitialized();
    await h.viewModel.setDefaultNegativeWordsV5('v5-negative');
    await h.viewModel.setDefaultNegativeWordsV45('v45-negative');
    await h.viewModel.sendUserMessage('画一个风景');
    expect(h.api.mainCalls.single.firstSystemContent, contains('v45-negative'));
    expect(h.api.mainCalls.single.firstSystemContent,
        isNot(contains('v5-negative')));
    await h.viewModel.createNewSession();
    await h.viewModel.sendUserMessage('再画风景');
    expect(h.api.mainCalls.last.firstSystemContent, contains('v5-negative'));
    expect(h.api.mainCalls.last.firstSystemContent,
        isNot(contains('v45-negative')));
  });
  List<LlmMessage> history(int count) => List.generate(
      count,
      (i) => LlmMessage(
          id: i,
          sessionId: 's',
          role: i.isEven ? LlmMessageRole.user : LlmMessageRole.assistant,
          content: '消息$i：${'画面描述' * 30}',
          createdAt: DateTime(2026)));
  test(
      'compression preserves original history and reuses only matching prefixes',
      () async {
    final compressor =
        ChatContextCompressor(characterBudget: 500, keepRecent: 2);
    final original = history(12);
    var calls = 0;
    Future<String> summarize(String text) async {
      calls++;
      return '保持红色外套，排除蓝色';
    }

    final first = await compressor.prepare(
        sessionId: 's', history: original, summarize: summarize);
    expect(first.summary, contains('红色外套'));
    expect(first.recent, original.sublist(10));
    expect(original, hasLength(12));
    final count = calls;
    await compressor.prepare(
        sessionId: 's', history: original, summarize: summarize);
    expect(calls, count);
    final edited = List<LlmMessage>.of(original)
      ..[0] = original[0].copyWith(content: '改成绿色');
    await compressor.prepare(
        sessionId: 's', history: edited, summarize: summarize);
    expect(calls, greaterThan(count));
  });
  test('image-heavy context triggers compression even with short text',
      () async {
    final compressor = ChatContextCompressor();
    final messages = List.generate(
        10,
        (i) => LlmMessage(
            id: i,
            sessionId: 's',
            role: i.isEven ? LlmMessageRole.user : LlmMessageRole.assistant,
            content: '参考',
            imageBase64s: i.isEven ? List.filled(10, 'AQIDBA==') : const [],
            createdAt: DateTime(2026)));
    final result = await compressor.prepare(
        sessionId: 's', history: messages, summarize: (_) async => '参考图的历史摘要');
    expect(result.summary, isNotEmpty);
    expect(result.recent, messages.sublist(8));
  });

  test('large historical documents are summarized in bounded chunks', () async {
    final compressor =
        ChatContextCompressor(characterBudget: 500, keepRecent: 2);
    final messages = history(4);
    messages[0] = messages[0].copyWith(content: 'a' * 30000);
    var calls = 0;
    await compressor.prepare(
        sessionId: 's',
        history: messages,
        summarize: (text) async {
          calls++;
          expect(text.length, lessThan(12500));
          return '摘要';
        });
    expect(calls, greaterThan(1));
  });

  test(
      'configured token budget compresses oversized recent history without deleting it',
      () async {
    final compressor = ChatContextCompressor();
    final messages =
        history(6).map((m) => m.copyWith(content: '人物细节' * 500)).toList();
    final result = await compressor.prepare(
        sessionId: 'budget-test',
        tokenBudget: 1000,
        history: messages,
        summarize: (_) async => '保留角色和画风约束');
    expect(result.summary, isNotEmpty);
    expect(result.recent, isEmpty);
    expect(messages, hasLength(6));
    await expectLater(
        compressor.prepare(
            sessionId: 'too-small',
            tokenBudget: 100,
            history: messages,
            summarize: (_) async => '摘要'),
        throwsStateError);
  });

  test('failed summaries never cause silent history loss', () async {
    final compressor =
        ChatContextCompressor(characterBudget: 500, keepRecent: 2);
    final original = history(12);
    await expectLater(
        compressor.prepare(
            sessionId: 's', history: original, summarize: (_) async => ''),
        throwsStateError);
    final result = await compressor.prepare(
        sessionId: 's', history: original, summarize: (_) async => '完整摘要');
    expect(result.summary, '完整摘要');
    expect(original, hasLength(12));
  });
}
