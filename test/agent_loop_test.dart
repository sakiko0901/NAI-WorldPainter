import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/datasources/remote/llm_api_service.dart';
import 'package:nai_huishi/domain/agents/agent_loop.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/agents/tools/ask_user_tool.dart';
import 'package:nai_huishi/domain/agents/tool_registry.dart';
import 'package:nai_huishi/domain/entities/llm_response.dart';
import 'package:nai_huishi/domain/entities/tool_call.dart';

void main() {
  test('successful tool responses include function names', () async {
    final api =
        await _runLoop(registry: ToolRegistry()..register(_ImageTool()));
    _expectNamedToolResponse(api, 'inspect_image');
  });

  test('missing tool responses include function names', () async {
    final api = await _runLoop(
      registry: ToolRegistry()..register(_ImageTool()),
      toolName: 'missing_tool',
    );
    _expectNamedToolResponse(api, 'missing_tool');
  });

  test('cancelled tool responses include function names', () async {
    final api = await _runLoop(
      registry: ToolRegistry()..register(_ConfirmingTool()),
      onRequireConfirmation: (_, __) async => false,
    );
    _expectNamedToolResponse(api, 'confirm_action');
  });

  test('failed tool responses include function names', () async {
    final api = await _runLoop(
      registry: ToolRegistry()..register(_ThrowingTool()),
    );
    _expectNamedToolResponse(api, 'throw_error');
  });

  test('ask_user pauses the agent loop with a structured interaction',
      () async {
    final api = _CapturingLlmApiService(
      'ask_user',
      arguments: {
        'question': '请选择画面时间',
        'options': [
          {'id': 'day', 'label': '白天'},
          {'id': 'night', 'label': '夜晚'},
        ],
      },
    );
    final result = await AgentLoop(
      api: api,
      registry: ToolRegistry()..register(AskUserTool()),
    ).run(
      apiKey: 'key',
      baseUrl: 'https://example.com',
      model: 'model',
      initialMessages: const [
        {'role': 'user', 'content': '帮我画一个场景'},
      ],
    );

    expect(result.awaitingUserInput, isTrue);
    expect(result.pendingInteraction?.question, '请选择画面时间');
    expect(result.pendingInteraction?.options, hasLength(2));
    expect(api.requests, hasLength(1));
    expect(result.timeline.single.status, 'awaiting_user');
  });
}

Future<_CapturingLlmApiService> _runLoop({
  required ToolRegistry registry,
  String? toolName,
  ToolConfirmationCallback? onRequireConfirmation,
}) async {
  final api = _CapturingLlmApiService(toolName ?? registry.all.first.name);
  final loop = AgentLoop(
    api: api,
    registry: registry,
    onRequireConfirmation: onRequireConfirmation,
  );
  await loop.run(
    apiKey: 'key',
    baseUrl: 'https://example.com',
    model: 'vision-model',
    initialMessages: [
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '分析这张图片'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,AA=='},
          },
        ],
      },
    ],
  );
  return api;
}

void _expectNamedToolResponse(_CapturingLlmApiService api, String name) {
  expect(api.requests, hasLength(2));
  final toolMessage = api.requests.last.singleWhere(
    (message) => message['role'] == 'tool',
  );
  expect(toolMessage['tool_call_id'], 'call-1');
  expect(toolMessage['name'], name);
}

class _CapturingLlmApiService extends LlmApiService {
  _CapturingLlmApiService(this.toolName, {this.arguments = const {}})
      : super(Dio());

  final String toolName;
  final Map<String, dynamic> arguments;
  final List<List<Map<String, dynamic>>> requests = [];

  @override
  Future<LlmResponse> chatCompletionsWithTools({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String toolChoice = 'auto',
  }) async {
    requests.add(messages.map((message) => {...message}).toList());
    if (requests.length == 1) {
      return LlmResponse(
        content: '',
        toolCalls: [
          ToolCall(id: 'call-1', name: toolName, arguments: arguments),
        ],
        finishReason: 'tool_calls',
      );
    }
    return const LlmResponse(
      content: '完成',
      toolCalls: [],
      finishReason: 'stop',
    );
  }
}

class _ImageTool extends AgentTool {
  @override
  String get name => 'inspect_image';

  @override
  String get description => '分析图片';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': <String, dynamic>{},
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    return ToolResult.success('图片分析完成');
  }
}

class _ConfirmingTool extends _ImageTool {
  @override
  String get name => 'confirm_action';

  @override
  bool get requireConfirmation => true;
}

class _ThrowingTool extends _ImageTool {
  @override
  String get name => 'throw_error';

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) {
    throw StateError('工具失败');
  }
}
