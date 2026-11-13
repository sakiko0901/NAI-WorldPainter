import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/datasources/remote/llm_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/model_capability_probe.dart';
import 'package:nai_huishi/domain/entities/llm_response.dart';
import 'package:nai_huishi/domain/entities/tool_call.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'support/chat_memory_fake.dart';

class _BlockingApi extends LlmApiService {
  _BlockingApi() : super(Dio());
  final entered = Completer<void>();
  final response = Completer<LlmResponse>();
  @override
  Future<LlmResponse> chatCompletionsStreamWithTools(
      {required String apiKey,
      required String baseUrl,
      required String model,
      required List<Map<String, dynamic>> messages,
      required List<Map<String, dynamic>> tools,
      required void Function(String) onText,
      CancelToken? cancelToken}) {
    onText('已经生成的部分回复');
    entered.complete();
    return response.future;
  }
}

class _ProbeApi extends LlmApiService {
  _ProbeApi() : super(Dio());
  bool toolValid = true;
  List<Map<String, dynamic>>? imageRequest;
  @override
  Future<String> chatCompletions(
      {required String apiKey,
      required String baseUrl,
      required String model,
      required List<Map<String, dynamic>> messages,
      CancelToken? cancelToken}) async {
    imageRequest = messages;
    return 'cannot read';
  }

  @override
  Future<LlmResponse> chatCompletionsWithTools(
      {required String apiKey,
      required String baseUrl,
      required String model,
      required List<Map<String, dynamic>> messages,
      required List<Map<String, dynamic>> tools,
      String toolChoice = 'auto',
      CancelToken? cancelToken}) async {
    final code =
        RegExp(r'"(\d+)"').firstMatch(messages.single['content'])!.group(1)!;
    return LlmResponse(
        content: '',
        toolCalls: toolValid
            ? [
                ToolCall(
                    id: 'probe',
                    name: 'capability_probe',
                    arguments: {'code': code})
              ]
            : [],
        finishReason: 'stop');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('stop persists partial reply and releases sending state immediately',
      () async {
    final h = createChatMemoryHarness();
    addTearDown(h.dispose);
    await h.viewModel.ensureInitialized();
    final api = _BlockingApi();
    LlmChatViewModel.apiServiceSingleton = api;
    final pending = h.viewModel.sendUserMessage('测试停止');
    await api.entered.future;
    h.viewModel.stopSending();
    await pending.timeout(const Duration(seconds: 2));
    expect(h.viewModel.isSending, isFalse);
    expect(h.viewModel.messages.last.content, contains('已经生成的部分回复'));
    expect(h.viewModel.messages.last.content, contains('已停止'));
    expect(h.viewModel.errorMessage, isNull);
    api.response.complete(const LlmResponse(
        content: '过期结果', toolCalls: [], finishReason: 'stop'));
    await Future<void>.delayed(Duration.zero);
    expect(h.viewModel.messages.last.content, isNot(contains('过期结果')));
  });
  test('editing creates a new session while original transcript remains intact',
      () async {
    final h = createChatMemoryHarness();
    addTearDown(h.dispose);
    await h.viewModel.ensureInitialized();
    await h.viewModel.sendUserMessage('原始内容');
    final originalId = h.viewModel.activeSessionId!;
    final original = List.of(h.viewModel.messages);
    await h.viewModel.editAndResend(0, '分支内容');
    expect(h.viewModel.activeSessionId, isNot(originalId));
    expect(h.viewModel.activeSession!.parentSessionId, originalId);
    expect(await h.chatRepository.listMessages(originalId), original);
    expect(h.viewModel.messages.first.content, '分支内容');
  });
  test('capability probes validate results instead of HTTP success', () async {
    final api = _ProbeApi();
    final probe = ModelCapabilityProbe(api);
    expect(await probe.tools(apiKey: 'k', baseUrl: 'url', model: 'm'), isTrue);
    api.toolValid = false;
    expect(await probe.tools(apiKey: 'k', baseUrl: 'url', model: 'm'), isFalse);
    expect(await probe.image(apiKey: 'k', baseUrl: 'url', model: 'm'), isFalse);
    final content = api.imageRequest!.single['content'] as List;
    expect(
        content[1]['image_url']['url'], startsWith('data:image/png;base64,'));
    expect(content[0]['text'], isNot(matches(RegExp(r'[A-Z0-9]{4}'))));
  });
}
