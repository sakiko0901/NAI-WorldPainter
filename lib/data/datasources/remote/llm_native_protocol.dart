import 'dart:convert';

import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_response.dart';
import 'package:nai_huishi/domain/entities/tool_call.dart';

typedef _Json = Map<String, dynamic>;

String llmEndpoint(LlmApiProtocol protocol, String baseUrl, String path) {
  final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  final version = protocol == LlmApiProtocol.gemini ? 'v1beta' : 'v1';
  if (RegExp(r'/v\d+(?:beta\d*|alpha\d*)?$').hasMatch(base)) {
    return '$base/$path';
  }
  if (protocol == LlmApiProtocol.openAiCompatible &&
      Uri.tryParse(base)?.host == 'api.deepseek.com') {
    return '$base/$path';
  }
  return '$base/$version/$path';
}

Map<String, String> llmAuthHeaders(LlmApiProtocol protocol, String key) =>
    switch (protocol) {
      LlmApiProtocol.gemini => {'x-goog-api-key': key},
      LlmApiProtocol.anthropic => {
          'Authorization': 'Bearer $key',
          'anthropic-version': '2026-10-21',
        },
      _ => {'Authorization': 'Bearer $key'},
    };

String geminiModelId(String model) =>
    model.trim().replaceFirst(RegExp(r'^models/'), '');

abstract class LlmNativeProtocol {
  factory LlmNativeProtocol(LlmApiProtocol protocol) => switch (protocol) {
        LlmApiProtocol.openAi => _OpenAiResponses(),
        LlmApiProtocol.anthropic => _ClaudeMessages(),
        LlmApiProtocol.gemini => _GeminiContent(),
        _ => throw ArgumentError.value(protocol),
      };

  LlmNativeProtocol._();

  String path(String model, bool stream);
  Map<String, dynamic> request(
      String model,
      List<Map<String, dynamic>> messages,
      List<Map<String, dynamic>> tools,
      String toolChoice,
      bool stream);
  String get text;
  bool get done;
  void addEvent(Map<String, dynamic> event);
  LlmResponse parse(Map<String, dynamic> data);
  LlmResponse finish();

  void _checkError(_Json data) {
    final error = data['error'];
    if (error != null) {
      throw ApiException(
          message: _map(error)['message']?.toString() ?? '模型接口返回错误');
    }
  }
}

class _OpenAiResponses extends LlmNativeProtocol {
  _OpenAiResponses() : super._();
  final _text = StringBuffer();
  _Json? _finalResponse;

  @override
  String path(String model, bool stream) => 'responses';
  @override
  String get text => _text.toString();
  @override
  bool get done => _finalResponse != null;

  @override
  _Json request(String model, List<_Json> messages, List<_Json> tools,
      String toolChoice, bool stream) {
    final input = <_Json>[];
    for (final message in messages) {
      switch (message['role']) {
        case 'system':
          break;
        case 'tool':
          input.add({
            'type': 'function_call_output',
            'call_id': message['tool_call_id'],
            'output': message['content'],
          });
        default:
          if (message['provider_items'] is List) {
            input.addAll(_maps(message['provider_items']));
            continue;
          }
          final text = message['content'];
          if (text is String && text.isNotEmpty) {
            input.add({'role': message['role'], 'content': text});
            continue;
          }
          final content = [
            for (final part in _parts(message))
              if (part['type'] == 'image_url')
                {
                  'type': 'input_image',
                  'image_url': _imageUrl(part),
                  'detail': 'auto'
                }
              else if (part['type'] == 'text')
                {
                  'type': 'input_text',
                  'text': part['text'],
                },
          ];
          if (content.isNotEmpty) {
            input.add({'role': message['role'], 'content': content});
          }
      }
    }
    final instructions = _systemText(messages);
    return {
      'model': model,
      'input': input,
      'store': false,
      'include': ['reasoning.encrypted_content'],
      'stream': stream,
      if (instructions.isNotEmpty) 'instructions': instructions,
      if (tools.isNotEmpty) ...{
        'tools': [
          for (final tool in tools)
            {'type': 'function', ..._map(tool['function']), 'strict': false},
        ],
        'tool_choice': toolChoice,
      },
    };
  }

  @override
  void addEvent(_Json event) {
    _checkError(event);
    switch (event['type']) {
      case 'response.output_text.delta':
      case 'response.refusal.delta':
        _text.write(event['delta'] ?? '');
      case 'response.completed':
      case 'response.incomplete':
      case 'response.failed':
        _finalResponse = _map(event['response']);
      case 'error':
        throw ApiException(message: event['message']?.toString() ?? '模型接口返回错误');
    }
  }

  @override
  LlmResponse parse(_Json data) {
    _checkError(data);
    if (data['output'] is! List || data['status'] == 'failed') {
      throw ApiException(message: 'OpenAI 未返回有效回复');
    }
    final items = _maps(data['output']);
    final calls = [
      for (final item in items)
        if (item['type'] == 'function_call')
          _toolCall(item['call_id'], item['name'], item['arguments']),
    ];
    final content = [
      for (final item in items)
        for (final part in _maps(item['content']))
          if (part['type'] == 'output_text')
            part['text']
          else if (part['type'] == 'refusal')
            part['refusal'],
    ].join();
    final usage = _map(data['usage']);
    return _response(
      content: content,
      calls: calls,
      reason: data['status'] == 'incomplete' ? 'length' : 'stop',
      items: items,
      inputTokens: usage['input_tokens'],
      outputTokens: usage['output_tokens'],
    );
  }

  @override
  LlmResponse finish() => parse(_finalResponse ?? _interrupted());
}

class _ClaudeMessages extends LlmNativeProtocol {
  _ClaudeMessages() : super._();
  final _blocks = <int, _Json>{};
  final _arguments = <int, StringBuffer>{};
  final _text = StringBuffer();
  final _usage = <String, dynamic>{};
  String? _stopReason;
  bool _done = false;

  @override
  String path(String model, bool stream) => 'messages';
  @override
  String get text => _text.toString();
  @override
  bool get done => _done;

  @override
  _Json request(String model, List<_Json> messages, List<_Json> tools,
      String toolChoice, bool stream) {
    final turns = <_Json>[];
    for (final message in messages) {
      final role = message['role'];
      if (role == 'system') continue;
      if (role == 'tool') {
        _appendTurn(turns, 'user', 'content', [
          {
            'type': 'tool_result',
            'tool_use_id': message['tool_call_id'],
            'content': message['content'],
          }
        ]);
        continue;
      }
      final parts = message['provider_items'] is List
          ? _maps(message['provider_items'])
          : [
              for (final part in _parts(message))
                if (part['type'] == 'image_url')
                  {'type': 'image', 'source': _claudeImage(_imageUrl(part))}
                else if (part['type'] == 'text')
                  part,
            ];
      _appendTurn(
          turns, role == 'assistant' ? 'assistant' : 'user', 'content', parts);
    }
    final system = _systemText(messages);
    return {
      'model': model,
      'messages': turns,
      'max_tokens': 8192,
      'stream': stream,
      if (system.isNotEmpty) 'system': system,
      if (tools.isNotEmpty) ...{
        'tools': [
          for (final tool in tools)
            {
              'name': _map(tool['function'])['name'],
              'description': _map(tool['function'])['description'],
              'input_schema': _map(tool['function'])['parameters'],
            },
        ],
        'tool_choice': {'type': toolChoice == 'required' ? 'any' : toolChoice},
        if (toolChoice == 'required') 'thinking': {'type': 'disabled'},
      },
    };
  }

  @override
  void addEvent(_Json event) {
    _checkError(event);
    final index = event['index'] as int?;
    switch (event['type']) {
      case 'message_start':
        _usage.addAll(_map(_map(event['message'])['usage']));
      case 'content_block_start':
        final block = Map<String, dynamic>.of(_map(event['content_block']));
        _blocks[index!] = block;
        if (block['type'] == 'text') _text.write(block['text'] ?? '');
      case 'content_block_delta':
        final block = _blocks[index];
        if (block == null) return;
        final delta = _map(event['delta']);
        switch (delta['type']) {
          case 'text_delta':
            _text.write(delta['text']);
            block['text'] = '${block['text'] ?? ''}${delta['text']}';
          case 'thinking_delta':
            block['thinking'] =
                '${block['thinking'] ?? ''}${delta['thinking']}';
          case 'signature_delta':
            block['signature'] =
                '${block['signature'] ?? ''}${delta['signature']}';
          case 'input_json_delta':
            final buffer = _arguments.putIfAbsent(index!, StringBuffer.new);
            buffer.write(delta['partial_json']);
            if (buffer.length > 1000000) {
              throw const FormatException('工具参数过大');
            }
        }
      case 'message_delta':
        _stopReason = _map(event['delta'])['stop_reason'] as String?;
        _usage.addAll(_map(event['usage']));
      case 'message_stop':
        _done = true;
    }
  }

  @override
  LlmResponse parse(_Json data) {
    _checkError(data);
    if (data['content'] is! List) throw ApiException(message: 'Claude 未返回有效回复');
    final blocks = _maps(data['content']);
    final usage = _map(data['usage']);
    final reason = data['stop_reason'];
    return _response(
      content: [
        for (final block in blocks)
          if (block['type'] == 'text') block['text'],
      ].join(),
      calls: [
        for (final block in blocks)
          if (block['type'] == 'tool_use')
            _toolCall(block['id'], block['name'], block['input']),
      ],
      reason: reason == 'max_tokens' ? 'length' : 'stop',
      items: blocks,
      inputTokens: usage['input_tokens'],
      outputTokens: usage['output_tokens'],
    );
  }

  @override
  LlmResponse finish() {
    if (!done) _interrupted();
    if (_stopReason == 'max_tokens' &&
        _blocks.values.any((block) => block['type'] == 'tool_use')) {
      throw const FormatException('工具参数被截断，未执行');
    }
    for (final MapEntry(:key, :value) in _arguments.entries) {
      if (value.isNotEmpty) {
        _blocks[key]!['input'] = _parseArguments(value.toString());
      }
    }
    return parse({
      'content': [
        for (final index in _blocks.keys.toList()..sort()) _blocks[index]
      ],
      'stop_reason': _stopReason,
      'usage': _usage,
    });
  }
}

class _GeminiContent extends LlmNativeProtocol {
  _GeminiContent() : super._();
  final _partsReceived = <_Json>[];
  final _usage = <String, dynamic>{};
  final _text = StringBuffer();
  String? _finishReason;

  @override
  String path(String model, bool stream) =>
      'models/${Uri.encodeComponent(geminiModelId(model))}:${stream ? 'streamGenerateContent?alt=sse' : 'generateContent'}';
  @override
  String get text => _text.toString();
  @override
  bool get done => false; // Usage can arrive after the finish reason.

  @override
  _Json request(String model, List<_Json> messages, List<_Json> tools,
      String toolChoice, bool stream) {
    final turns = <_Json>[];
    final callIds = <String>{};
    for (final message in messages) {
      final role = message['role'];
      if (role == 'system') continue;
      if (role == 'tool') {
        final id = message['tool_call_id'];
        _appendTurn(turns, 'user', 'parts', [
          {
            'functionResponse': {
              if (callIds.contains(id)) 'id': id,
              'name': message['name'],
              'response': {'result': message['content']},
            }
          }
        ]);
        continue;
      }
      final parts = message['provider_items'] is List
          ? _maps(message['provider_items'])
          : [
              for (final part in _parts(message))
                if (part['type'] == 'image_url')
                  _geminiImage(_imageUrl(part))
                else if (part['type'] == 'text')
                  {'text': part['text']},
            ];
      if (role == 'assistant') {
        callIds
          ..clear()
          ..addAll(parts
              .map((p) => _map(p['functionCall'])['id'])
              .whereType<String>());
      }
      _appendTurn(
          turns, role == 'assistant' ? 'model' : 'user', 'parts', parts);
    }
    final system = _systemText(messages);
    return {
      'contents': turns,
      if (system.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': system}
          ]
        },
      if (tools.isNotEmpty) ...{
        'tools': [
          {
            'functionDeclarations': [
              for (final tool in tools)
                {
                  'name': _map(tool['function'])['name'],
                  'description': _map(tool['function'])['description'],
                  'parametersJsonSchema': _map(tool['function'])['parameters'],
                },
            ],
          }
        ],
        'toolConfig': {
          'functionCallingConfig': {
            'mode': switch (toolChoice) {
              'required' => 'ANY',
              'none' => 'NONE',
              _ => 'AUTO',
            },
          },
        },
      },
    };
  }

  @override
  void addEvent(_Json event) {
    _checkError(event);
    final candidate = _maps(event['candidates']).firstOrNull;
    final blocked = _map(event['promptFeedback'])['blockReason'];
    if (blocked != null) throw ApiException(message: 'Gemini 拒绝处理请求（$blocked）');
    _usage.addAll(_map(event['usageMetadata']));
    if (candidate == null) return;
    _finishReason = candidate['finishReason'] as String? ?? _finishReason;
    for (final part in _maps(_map(candidate['content'])['parts'])) {
      final visible = part['text'] is String && part['thought'] != true;
      if (visible) _text.write(part['text']);
      final previous = _partsReceived.lastOrNull;
      if (part.length == 1 &&
          part['text'] is String &&
          previous?.length == 1 &&
          previous?['text'] is String) {
        previous!['text'] = '${previous['text']}${part['text']}';
      } else {
        _partsReceived.add(Map.of(part));
      }
    }
  }

  @override
  LlmResponse parse(_Json data) {
    addEvent(data);
    return finish();
  }

  @override
  LlmResponse finish() {
    final reason = _finishReason ?? _interrupted();
    if (reason != 'STOP' && reason != 'MAX_TOKENS') {
      throw ApiException(message: 'Gemini 回复已停止（$reason）');
    }
    final calls = <ToolCall>[];
    for (final part in _partsReceived) {
      final call = _map(part['functionCall']);
      if (call.isNotEmpty) {
        calls.add(_toolCall(call['id'] ?? 'gemini_call_${calls.length}',
            call['name'], call['args']));
      }
    }
    final thoughts = _usage['thoughtsTokenCount'] as num? ?? 0;
    final output = _usage['candidatesTokenCount'] as num?;
    return _response(
      content: text,
      calls: calls,
      reason: reason == 'MAX_TOKENS' ? 'length' : 'stop',
      items: _partsReceived,
      inputTokens: _usage['promptTokenCount'],
      outputTokens: output == null ? null : output + thoughts,
    );
  }
}

_Json _map(Object? object) => object is _Json ? object : const {};
List<_Json> _maps(Object? object) =>
    object is List ? object.whereType<_Json>().toList() : const [];

List<_Json> _parts(_Json message) {
  final content = message['content'];
  if (content is String && content.isNotEmpty) {
    return [
      {'type': 'text', 'text': content}
    ];
  }
  return _maps(content);
}

String _systemText(List<_Json> messages) => [
      for (final message in messages)
        if (message['role'] == 'system')
          for (final part in _parts(message))
            if (part['type'] == 'text') part['text'],
    ].join('\n\n');

void _appendTurn(
    List<_Json> turns, String role, String field, List<_Json> parts) {
  if (parts.isEmpty) return;
  if (turns.lastOrNull?['role'] == role) {
    (turns.last[field] as List<_Json>).addAll(parts);
  } else {
    turns.add({'role': role, field: List<_Json>.of(parts)});
  }
}

String _imageUrl(_Json part) => _map(part['image_url'])['url'] as String;
final _inlineImage = RegExp(r'^data:(image/[^;]+);base64,(.+)$', dotAll: true);

_Json _claudeImage(String url) {
  final match = _inlineImage.firstMatch(url);
  return match == null
      ? {'type': 'url', 'url': url}
      : {'type': 'base64', 'media_type': match[1], 'data': match[2]};
}

_Json _geminiImage(String url) {
  final match = _inlineImage.firstMatch(url);
  return match == null
      ? {
          'fileData': {'fileUri': url}
        }
      : {
          'inlineData': {'mimeType': match[1], 'data': match[2]}
        };
}

Never _interrupted() => throw const FormatException('回复流意外中断，请重试');

_Json _parseArguments(Object? arguments) {
  if (arguments == null) return {};
  final parsed = arguments is String ? jsonDecode(arguments) : arguments;
  if (parsed is! _Json) throw const FormatException('工具参数格式错误');
  return parsed;
}

ToolCall _toolCall(Object? id, Object? name, Object? arguments) {
  if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
    throw const FormatException('工具调用缺少标识');
  }
  return ToolCall(id: id, name: name, arguments: _parseArguments(arguments));
}

LlmResponse _response({
  required String content,
  required List<ToolCall> calls,
  required String reason,
  required List<_Json> items,
  Object? inputTokens,
  Object? outputTokens,
}) {
  if (reason == 'length' && calls.isNotEmpty) {
    throw const FormatException('工具参数被截断，未执行');
  }
  return LlmResponse(
    content: content,
    toolCalls: calls,
    finishReason: calls.isNotEmpty ? 'tool_calls' : reason,
    providerItems: items,
    promptTokens: (inputTokens as num?)?.toInt(),
    completionTokens: (outputTokens as num?)?.toInt(),
  );
}
