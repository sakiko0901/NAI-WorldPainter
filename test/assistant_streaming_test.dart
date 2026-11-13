import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/datasources/remote/llm_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/chat_stream_accumulator.dart';
import 'package:nai_huishi/domain/agents/agent_loop.dart';
import 'package:nai_huishi/domain/agents/agent_run_control.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/agents/tool_registry.dart';
import 'package:nai_huishi/domain/entities/llm_response.dart';
import 'package:nai_huishi/domain/entities/tool_call.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/services/chat_token_budget.dart';

class _Adapter implements HttpClientAdapter {
  final Stream<Uint8List> bytes;
  _Adapter(this.bytes);
  RequestOptions? request;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    request = options;
    return ResponseBody(bytes, 200, headers: {
      'content-type': ['text/event-stream']
    });
  }

  @override
  void close({bool force = false}) {}
}

class _Tool extends AgentTool {
  int calls = 0;
  @override
  String get name => 'write_prompt';
  @override
  String get description => 'test';
  @override
  Map<String, dynamic> get parametersSchema => {};
  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    calls++;
    return ToolResult.success('done');
  }
}

class _Api extends LlmApiService {
  _Api() : super(Dio());
  @override
  Future<LlmResponse> chatCompletionsWithTools(
          {required String apiKey,
          required String baseUrl,
          required String model,
          required List<Map<String, dynamic>> messages,
          required List<Map<String, dynamic>> tools,
          String toolChoice = 'auto',
          CancelToken? cancelToken}) async =>
      const LlmResponse(
          content: '',
          toolCalls: [ToolCall(id: '1', name: 'write_prompt', arguments: {})],
          finishReason: 'tool_calls');
}

void main() {
  String chunk(Map<String, dynamic> delta, {String? finish}) => jsonEncode({
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': finish}
        ]
      });
  test(
      'SSE transport handles UTF-8 fragmentation, tool arguments and actual usage',
      () async {
    final events = [
      chunk({'content': '你好'}),
      chunk({
        'tool_calls': [
          {
            'index': 0,
            'id': 'c1',
            'function': {'name': 'write_prompt', 'arguments': '{"content":'}
          }
        ]
      }),
      chunk({
        'tool_calls': [
          {
            'index': 0,
            'function': {'arguments': '"长发"}'}
          }
        ]
      }, finish: 'tool_calls'),
      jsonEncode({
        'choices': [],
        'usage': {'prompt_tokens': 123, 'completion_tokens': 45}
      }),
      '[DONE]',
    ];
    final encoded = utf8.encode(events.map((s) => 'data: $s\r\n\r\n').join());
    final adapter = _Adapter(
        Stream.fromIterable(encoded.map((b) => Uint8List.fromList([b]))));
    final dio = Dio()..httpClientAdapter = adapter;
    final updates = <String>[];
    final response = await LlmApiService(dio).chatCompletionsStreamWithTools(
        apiKey: 'key',
        baseUrl: 'https://example.invalid/v1',
        model: 'model',
        messages: [],
        tools: [],
        onText: updates.add);
    expect(updates, contains('你好'));
    expect(response.toolCalls.single.arguments['content'], '长发');
    expect(response.promptTokens, 123);
    expect(response.completionTokens, 45);
    expect(adapter.request!.uri.path, '/v1/chat/completions');
  });
  test('truncated and malformed tool streams never become executable calls',
      () {
    final unfinished = ChatStreamAccumulator()
      ..add(chunk({'content': 'partial'}));
    expect(unfinished.finish, throwsFormatException);
    final malformed = ChatStreamAccumulator()
      ..add(chunk({
        'tool_calls': [
          {
            'index': 0,
            'id': 'x',
            'function': {'name': 'write_prompt', 'arguments': '{'}
          }
        ]
      }, finish: 'tool_calls'));
    expect(malformed.finish, throwsFormatException);
  });
  test('cancelling a network stream terminates the request', () async {
    final controller = StreamController<Uint8List>();
    final adapter = _Adapter(controller.stream);
    final dio = Dio()..httpClientAdapter = adapter;
    final token = CancelToken();
    final started = Completer<void>();
    final request = LlmApiService(dio).chatCompletionsStreamWithTools(
        apiKey: 'key',
        baseUrl: 'https://example.invalid',
        model: 'm',
        messages: [],
        tools: [],
        cancelToken: token,
        onText: (_) {
          if (!started.isCompleted) started.complete();
        });
    final check = expectLater(request, throwsA(isA<DioException>()));
    controller.add(Uint8List.fromList(
        utf8.encode('data: ${chunk({'content': 'partial'})}\n\n')));
    await started.future;
    token.cancel('stop');
    await check;
    await controller.close();
  });
  test('stop during preview prevents tool execution and later requests',
      () async {
    final control = AgentRunControl();
    final tool = _Tool();
    final preview = Completer<bool>();
    final entered = Completer<void>();
    final run = AgentLoop(
        api: _Api(),
        registry: ToolRegistry()..register(tool),
        control: control,
        beforeTool: (_, __) {
          entered.complete();
          return preview.future;
        }).run(apiKey: 'key', baseUrl: 'url', model: 'm', initialMessages: []);
    await entered.future;
    control.stop();
    final result = await run.timeout(const Duration(seconds: 1));
    preview.complete(true);
    expect(tool.calls, 0);
    expect(result.failed, isTrue);
    expect(result.error, contains('已停止'));
  });
  test('capacity round trip and image costs exclude base64 byte count', () {
    final provider = LlmProvider.create(
        name: 'test', models: ['m'], contextWindows: {'m': 131072});
    expect(LlmProvider.fromJson(provider.toJson()).contextWindows['m'], 131072);
    expect(
        ChatTokenBudget.content({
          'type': 'image_url',
          'image_url': {'url': 'a' * 500000}
        }),
        1600);
    expect(ChatTokenBudget.text('中文'), greaterThan(ChatTokenBudget.text('ab')));
  });
}
