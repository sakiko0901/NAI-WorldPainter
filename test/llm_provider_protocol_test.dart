import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/data/datasources/remote/llm_api_service.dart';
import 'package:nai_huishi/domain/agents/agent_loop.dart';
import 'package:nai_huishi/domain/agents/agent_result.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/agents/tool_registry.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_role_config.dart';
import 'package:nai_huishi/domain/services/llm_thinking.dart';

void main() {
  test('legacy and Gemini provider settings round-trip', () {
    final legacy = LlmProvider.fromJson({'name': 'existing'});
    expect(legacy.protocol, LlmApiProtocol.openAiCompatible);
    expect(legacy.backupApiKeys, isEmpty);
    final provider = legacy.copyWith(
      protocol: LlmApiProtocol.gemini,
      backupApiKeys: ['second'],
      geminiKeyIndex: 1,
      thinkingLevels: {'test-model': LlmThinkingLevel.high},
    );
    final restored =
        LlmProvider.listFromJsonString(LlmProvider.listToJsonString([provider]))
            .single;
    expect(restored.protocol, LlmApiProtocol.gemini);
    expect(restored.backupApiKeys, ['second']);
    expect(restored.geminiKeyIndex, 1);
    expect(restored.thinkingLevels, {'test-model': LlmThinkingLevel.high});
  });

  test('OpenAI Responses retains tool items and returns function output',
      () async {
    final config =
        _config(LlmProviderPreset.chatGpt, thinking: LlmThinkingLevel.max);
    final reasoning = {
      'type': 'reasoning',
      'id': 'rs_1',
      'encrypted_content': 'encrypted',
      'summary': []
    };
    final call = {
      'type': 'function_call',
      'call_id': 'call_1',
      'name': 'test_tool',
      'arguments': '{"value":1}'
    };
    final adapter = _Adapter([
      _json({
        'status': 'completed',
        'output': [reasoning, call]
      }),
      _json({
        'status': 'completed',
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': 'done'}
            ]
          },
        ]
      }),
    ]);
    final result = await _runAgent(config, adapter);
    expect(result.failed, isFalse, reason: result.error);
    expect(adapter.requests.first.uri.path, '/v1/responses');
    expect(adapter.requests.first.headers['authorization'], 'Bearer first');
    final payload = adapter.requests.first.data as Map;
    expect(payload['store'], false);
    expect(payload['reasoning'], {'effort': 'max'});
    expect(payload['instructions'], 'system prompt');
    expect(payload['input'][0]['content'][1]['type'], 'input_image');
    expect(payload['tools'][0]['name'], 'test_tool');
    expect(
        adapter.requests.last.data['input'],
        containsAllInOrder([
          reasoning,
          call,
          {
            'type': 'function_call_output',
            'call_id': 'call_1',
            'output': 'local result'
          },
        ]));
  });

  test(
      'Claude uses Messages, assembles streamed tool blocks and returns results',
      () async {
    final config =
        _config(LlmProviderPreset.claude, thinking: LlmThinkingLevel.xhigh);
    final adapter = _Adapter([
      _sse([
        {
          'type': 'message_start',
          'message': {
            'usage': {'input_tokens': 45}
          }
        },
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'test_tool',
            'input': {}
          }
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'input_json_delta', 'partial_json': '{"val'}
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'input_json_delta', 'partial_json': 'ue":1}'}
        },
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
          'usage': {'output_tokens': 10}
        },
        {'type': 'message_stop'},
      ]),
      _sse([
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'text', 'text': ''}
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': '完成'}
        },
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn'}
        },
        {'type': 'message_stop'},
      ]),
    ]);
    final updates = <String>[];
    final result = await _runAgent(config, adapter, onText: updates.add);
    expect(result.failed, isFalse, reason: result.error);
    expect(updates, contains('完成'));
    final first = adapter.requests.first;
    expect(first.uri.path, '/v1/messages');
    expect(first.headers['anthropic-version'], '2026-10-21');
    expect(first.data['output_config'], {'effort': 'xhigh'});
    expect(first.data['max_tokens'], 32768);
    expect(first.data['messages'][0]['content'][1]['source']['type'], 'base64');
    final turns = adapter.requests.last.data['messages'] as List;
    expect(turns[1]['content'][0]['input'], {'value': 1});
    expect(turns[2]['content'], [
      {
        'type': 'tool_result',
        'tool_use_id': 'toolu_1',
        'content': 'local result'
      },
    ]);
  });

  test(
      'Gemini switches on 429 and preserves signed tool calls and the active key',
      () async {
    final config = _config(LlmProviderPreset.gemini,
        backupKeys: ['second'], thinking: LlmThinkingLevel.high);
    final signedCall = {
      'functionCall': {
        'id': 'fc1',
        'name': 'test_tool',
        'args': {'value': 1}
      },
      'thoughtSignature': 'signed',
    };
    final adapter = _Adapter([
      _json({
        'error': {'status': 'RESOURCE_EXHAUSTED'}
      }, status: 429),
      _sse([_gemini(signedCall)]),
      _sse([
        _gemini({'text': '完成'})
      ]),
      _json(_gemini({'text': 'OK'})),
    ]);
    final root = LlmApiService(Dio(BaseOptions(headers: {
      'Authorization': 'Bearer unrelated',
    }))
      ..httpClientAdapter = adapter);
    final result = await _runAgent(config, adapter, root: root, onText: (_) {});
    expect(result.failed, isFalse, reason: result.error);
    expect(adapter.requests.map((r) => r.headers['x-goog-api-key']), [
      'first',
      'second',
      'second',
    ]);
    final post = adapter.requests.first;
    expect(post.headers.containsKey('Authorization'), isFalse);
    expect(
        post.uri.path, '/v1beta/models/${config.model}:streamGenerateContent');
    expect(post.uri.queryParameters, {'alt': 'sse'});
    expect(post.data['generationConfig'], {
      'thinkingConfig': {'thinkingLevel': 'HIGH'}
    });
    expect(post.data['contents'][0]['parts'][1]['inlineData']['mimeType'],
        'image/png');
    final turns = adapter.requests.last.data['contents'] as List;
    expect(turns[1]['parts'], [signedCall]);
    expect(turns[2]['parts'][0]['functionResponse'], {
      'id': 'fc1',
      'name': 'test_tool',
      'response': {'result': 'local result'},
    });

    root.selectGeminiKey(config.providerId!, 'first');
    final reply = await _plainChat(root, config);
    expect(reply, 'OK');
    expect(adapter.requests.last.headers['x-goog-api-key'], 'first');
    expect(adapter.requests.last.uri.path,
        '/v1beta/models/${config.model}:generateContent');
  });

  test('Gemini respects the saved starting key and tries each key at most once',
      () async {
    final config = _config(LlmProviderPreset.gemini,
        backupKeys: ['second', 'third', 'first'], selected: 1);
    final adapter = _Adapter([
      for (var i = 0; i < 3; i++)
        _json({
          'error': {'status': 'RESOURCE_EXHAUSTED'}
        }, status: 429),
    ]);
    final root = LlmApiService(Dio()..httpClientAdapter = adapter);
    await expectLater(
        _plainChat(root, config),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status code', 429)));
    expect(adapter.requests.map((r) => r.headers['x-goog-api-key']),
        ['second', 'third', 'first']);
  });

  test('Gemini does not switch keys on an invalid request', () async {
    final config = _config(LlmProviderPreset.gemini, backupKeys: ['second']);
    final adapter = _Adapter([
      _json({
        'error': {'message': 'bad request'}
      }, status: 400),
    ]);
    final root = LlmApiService(Dio()..httpClientAdapter = adapter);
    await expectLater(
        _plainChat(root, config),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status code', 400)));
    expect(adapter.requests, hasLength(1));
  });

  test('DeepSeek preset uses the official OpenAI-compatible route', () async {
    final config = _config(LlmProviderPreset.deepSeek);
    final adapter = _Adapter([
      _json({
        'choices': [
          {
            'message': {'content': 'OK'}
          }
        ]
      }),
    ]);
    final root = LlmApiService(Dio()..httpClientAdapter = adapter);
    expect(await _plainChat(root, config), 'OK');
    expect(adapter.requests.single.uri.toString(),
        'https://api.deepseek.com/chat/completions');
  });

  test('compatible Chat Completions sends reasoning_effort', () async {
    const config = LlmRoleConfig(
      apiKey: 'test',
      baseUrl: 'https://example.invalid/v1',
      model: 'custom-reasoner',
      thinkingLevel: LlmThinkingLevel.medium,
    );
    final adapter = _Adapter([_json(_chatReply())]);
    final api = LlmApiService(Dio()..httpClientAdapter = adapter);
    expect(await _plainChat(api, config), 'OK');
    expect(adapter.requests.single.data['reasoning_effort'], 'medium');
  });

  test('model-specific labels stay separate from compatible API values',
      () async {
    const config = LlmRoleConfig(
      apiKey: 'test',
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'openai/gpt-6.2-sol',
      thinkingLevel: LlmThinkingLevel.max,
    );
    final adapter = _Adapter([_json(_chatReply()), _json(_chatReply())]);
    final api = LlmApiService(Dio()..httpClientAdapter = adapter);

    expect(LlmThinking.label(config.model, config.thinkingLevel), 'Ultra');
    expect(await _plainChat(api, config), 'OK');
    expect(adapter.requests.first.data['reasoning'], {'effort': 'max'});

    final claude = config.copyWith(model: 'anthropic/claude-opus-4.7');
    expect(LlmThinking.label(claude.model, claude.thinkingLevel), 'Max');
    expect(await _plainChat(api, claude), 'OK');
    expect(adapter.requests.last.data['reasoning'], {'effort': 'max'});
  });

  test('Gemini variant controls follow its supported levels', () {
    const automatic = LlmThinkingLevel.automatic;
    const minimal = LlmThinkingLevel.minimal;
    const high = LlmThinkingLevel.high;
    const medium = LlmThinkingLevel.medium;
    const low = LlmThinkingLevel.low;
    const protocol = LlmApiProtocol.openAiCompatible;
    const endpoint = 'https://example.invalid/v1';

    expect(
        LlmThinking.levels(protocol, endpoint, 'google/gemini-3.1-flash-lite'),
        [automatic, minimal, low, medium, high]);
    expect(
        LlmThinking.levels(
            protocol, endpoint, 'google/gemini-3.1-flash-lite-image'),
        [automatic, minimal, high]);
    expect(
        LlmThinking.levels(protocol, endpoint, 'google/gemini-2.5-flash-image'),
        [automatic]);
    expect(
      LlmThinking.requestFields(
          protocol, endpoint, 'google/gemini-3-pro-preview', medium,
          hasTools: false),
      isEmpty,
    );
  });

  test('Gemini uses a thinking budget for 2.5 and omits unsupported levels',
      () async {
    final adapter = _Adapter([
      for (var i = 0; i < 2; i++) _json(_gemini({'text': 'OK'})),
    ]);
    final api = LlmApiService(Dio()..httpClientAdapter = adapter);
    final flash25 =
        _config(LlmProviderPreset.gemini, thinking: LlmThinkingLevel.low)
            .copyWith(model: 'gemini-2.5-flash');
    final flash38 =
        _config(LlmProviderPreset.gemini, thinking: LlmThinkingLevel.minimal);
    expect(await _plainChat(api, flash25), 'OK');
    expect(await _plainChat(api, flash38), 'OK');
    expect(adapter.requests.first.data['generationConfig'], {
      'thinkingConfig': {'thinkingBudget': 1024}
    });
    expect(adapter.requests.last.data['generationConfig'], isNull);
  });

  for (final stream in [false, true]) {
    test('DeepSeek keeps reasoning across tool rounds (stream: $stream)',
        () async {
      final config =
          _config(LlmProviderPreset.deepSeek, thinking: LlmThinkingLevel.max);
      final toolCall = {
        'index': 0,
        'id': 'call_1',
        'type': 'function',
        'function': {'name': 'test_tool', 'arguments': '{"value":1}'},
      };
      final adapter = _Adapter(stream
          ? [
              _sse([
                {
                  'choices': [
                    {
                      'delta': {'reasoning_content': 'first '}
                    }
                  ]
                },
                {
                  'choices': [
                    {
                      'delta': {
                        'reasoning_content': 'analysis',
                        'tool_calls': [toolCall]
                      },
                      'finish_reason': 'tool_calls'
                    },
                  ]
                },
              ]),
              _sse([
                {
                  'choices': [
                    {
                      'delta': {'content': 'OK'},
                      'finish_reason': 'stop'
                    },
                  ]
                },
              ]),
            ]
          : [
              _json({
                'choices': [
                  {
                    'message': {
                      'reasoning_content': 'first analysis',
                      'tool_calls': [toolCall]
                    },
                    'finish_reason': 'tool_calls'
                  },
                ],
              }),
              _json(_chatReply()),
            ]);
      final result = await _runAgent(config, adapter,
          onText: stream ? (_) {} : null,
          history: [
            {'role': 'user', 'content': 'Previous user message'},
            {'role': 'assistant', 'content': 'Previous reply'},
          ]);
      expect(result.failed, isFalse, reason: result.error);
      expect(result.finalContent, 'OK');
      expect(adapter.requests.first.data['reasoning_effort'], 'max');
      expect(adapter.requests.first.data['thinking'], {'type': 'enabled'});
      final messages = adapter.requests.last.data['messages'] as List;
      expect(messages[2]['role'], 'user');
      expect(messages[2]['content'], contains('Previous reply'));
      expect(
          messages
              .where((m) => m['role'] == 'assistant')
              .single['reasoning_content'],
          'first analysis');
    });
  }
}

const _user = {'role': 'user', 'content': 'hello'};

Map<String, dynamic> _chatReply() => {
      'choices': [
        {
          'message': {'content': 'OK'},
          'finish_reason': 'stop'
        },
      ],
    };

LlmRoleConfig _config(LlmProviderPreset preset,
        {List<String> backupKeys = const [],
        int selected = 0,
        LlmThinkingLevel thinking = LlmThinkingLevel.automatic}) =>
    LlmRoleConfig(
        providerId: preset.name,
        apiKey: 'first',
        baseUrl: preset.baseUrl,
        model: preset.model,
        protocol: preset.protocol,
        backupApiKeys: backupKeys,
        thinkingLevel: thinking,
        geminiKeyIndex: selected);

Future<String> _plainChat(LlmApiService root, LlmRoleConfig config) =>
    root.forConnection(config).chatCompletions(
        apiKey: config.apiKey,
        baseUrl: config.baseUrl,
        model: config.model,
        messages: [_user]);

Future<AgentResult> _runAgent(LlmRoleConfig config, _Adapter adapter,
    {LlmApiService? root,
    void Function(String)? onText,
    List<Map<String, dynamic>> history = const []}) {
  final service = root ?? LlmApiService(Dio()..httpClientAdapter = adapter);
  return AgentLoop(
          api: service.forConnection(config),
          registry: ToolRegistry()..register(_Tool()),
          onText: onText)
      .run(
    apiKey: config.apiKey,
    baseUrl: config.baseUrl,
    model: config.model,
    initialMessages: [
      {'role': 'system', 'content': 'system prompt'},
      ...history,
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'hello'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,AA=='}
          },
        ]
      },
    ],
  );
}

class _Tool extends AgentTool {
  @override
  String get name => 'test_tool';
  @override
  String get description => 'Local test';
  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'value': {'type': 'integer'}
        },
      };
  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    expect(arguments, {'value': 1});
    return ToolResult.success('local result');
  }
}

class _Adapter implements HttpClientAdapter {
  final List<ResponseBody> replies;
  final requests = <RequestOptions>[];
  _Adapter(this.replies);
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return replies[requests.length - 1];
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _gemini(Map<String, dynamic> part) => {
      'candidates': [
        {
          'finishReason': 'STOP',
          'content': {
            'role': 'model',
            'parts': [part]
          }
        },
      ],
    };

ResponseBody _json(Map<String, dynamic> data, {int status = 200}) =>
    ResponseBody.fromString(jsonEncode(data), status, headers: {
      'content-type': ['application/json']
    });

ResponseBody _sse(List<Map<String, dynamic>> events) => ResponseBody.fromString(
        events.map((event) => 'data: ${jsonEncode(event)}\r\n\r\n').join(), 200,
        headers: {
          'content-type': ['text/event-stream']
        });
