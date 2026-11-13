import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/agents/tool_registry.dart';
import 'package:nai_huishi/domain/agents/tools/write_prompt_tool.dart';
import 'package:nai_huishi/domain/entities/llm_profile_role.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_response.dart';
import 'package:nai_huishi/domain/entities/tool_call.dart';
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
}
