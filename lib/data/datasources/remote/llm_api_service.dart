import 'dart:convert';
import 'chat_stream_accumulator.dart';
import 'llm_native_protocol.dart';

import 'package:dio/dio.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_role_config.dart';
import 'package:nai_huishi/domain/entities/llm_response.dart';
import 'package:nai_huishi/domain/entities/tool_call.dart';
import 'package:nai_huishi/domain/services/llm_thinking.dart';

class LlmApiService {
  final Dio _dio;
  final LlmApiProtocol _protocol;
  final LlmRoleConfig? _connection;
  // Shared by all role-bound clients, so main and vision use the same key.
  final Map<String, String> _geminiActiveKeys;
  final Map<String, int> _geminiSelectionVersions;

  LlmApiService(Dio dio)
      : this._(dio, LlmApiProtocol.openAiCompatible, null, {}, {});

  LlmApiService._(this._dio, this._protocol, this._connection,
      this._geminiActiveKeys, this._geminiSelectionVersions);

  LlmApiService forConnection(LlmRoleConfig config) {
    if (config.protocol == LlmApiProtocol.openAiCompatible &&
        _protocol == config.protocol &&
        config.thinkingLevel == LlmThinkingLevel.automatic &&
        _connection == null) {
      return this;
    }
    return LlmApiService._(_dio, config.protocol, config, _geminiActiveKeys,
        _geminiSelectionVersions);
  }

  int activeGeminiKeyIndex(LlmProvider provider) => _activeKeyIndex(
        provider.id,
        [provider.apiKey, ...provider.backupApiKeys],
        provider.geminiKeyIndex,
      );

  void selectGeminiKey(String providerId, String? key) {
    _geminiSelectionVersions.update(providerId, (version) => version + 1,
        ifAbsent: () => 1);
    if (key == null) {
      _geminiActiveKeys.remove(providerId);
    } else {
      _geminiActiveKeys[providerId] = key;
    }
  }

  int _activeKeyIndex(String? id, List<String> keys, int preferred) {
    final active = keys.indexOf(_geminiActiveKeys[id] ?? '');
    if (active >= 0 && keys[active].isNotEmpty) return active;
    return preferred >= 0 && preferred < keys.length ? preferred : 0;
  }

  String _chatUrl(String baseUrl) =>
      llmEndpoint(_protocol, baseUrl, 'chat/completions');

  Map<String, dynamic> _thinkingFields(String baseUrl, String model,
          {required bool hasTools}) =>
      LlmThinking.requestFields(_protocol, baseUrl, model,
          _connection?.thinkingLevel ?? LlmThinkingLevel.automatic,
          hasTools: hasTools);

  bool _replayReasoning(Map<String, dynamic> fields) =>
      (fields['thinking'] as Map?)?['type'] == 'enabled';

  List<Map<String, dynamic>> _compatibleMessages(
      List<Map<String, dynamic>> messages, bool replayReasoning) {
    if (!replayReasoning) return messages;
    final lastUser =
        messages.lastIndexWhere((message) => message['role'] == 'user');
    // Ordinary saved replies predate provider reasoning blocks. Send them as
    // quoted conversation history, then replay the current tool turns exactly.
    return [
      for (var i = 0; i < messages.length; i++)
        if (i < lastUser &&
            messages[i]['role'] == 'assistant' &&
            !messages[i].containsKey('reasoning_content') &&
            !messages[i].containsKey('tool_calls'))
          {
            'role': 'user',
            'content': '以下是历史助手回复，仅作对话记录。\n> '
                '${messages[i]['content']?.toString().replaceAll('\n', '\n> ') ?? ''}',
          }
        else
          messages[i],
    ];
  }

  Options _chatOptions(String key, {bool stream = false}) => Options(
        responseType: stream ? ResponseType.stream : ResponseType.json,
        headers: {
          ...llmAuthHeaders(_protocol, key),
          'Content-Type': 'application/json',
          'Accept': stream ? 'text/event-stream' : 'application/json',
        },
        receiveTimeout: const Duration(minutes: 2),
        sendTimeout: const Duration(seconds: 30),
      );

  Future<LlmResponse> chatCompletionsStreamWithTools({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    required void Function(String) onText,
    CancelToken? cancelToken,
  }) async {
    if (apiKey.trim().isEmpty ||
        baseUrl.trim().isEmpty ||
        model.trim().isEmpty) {
      throw ApiException(message: '请完整配置模型连接');
    }
    if (_protocol != LlmApiProtocol.openAiCompatible) {
      return _nativeChat(apiKey, baseUrl, model, messages,
          tools: tools, onText: onText, cancelToken: cancelToken);
    }
    final thinking =
        _thinkingFields(baseUrl, model, hasTools: tools.isNotEmpty);
    final replayReasoning = tools.isNotEmpty && _replayReasoning(thinking);
    try {
      final response = await _dio.post<ResponseBody>(
        _chatUrl(baseUrl),
        data: {
          'model': model,
          'messages': _compatibleMessages(messages, replayReasoning),
          'stream': true,
          if (tools.isNotEmpty) 'tools': tools,
          if (tools.isNotEmpty) 'tool_choice': 'auto',
          'stream_options': {'include_usage': true},
          ...thinking,
        },
        cancelToken: cancelToken,
        options: _chatOptions(apiKey, stream: true),
      );
      final accumulator =
          ChatStreamAccumulator(captureReasoning: replayReasoning);
      final body = response.data!;
      if ((body.headers['content-type'] ?? [])
          .any((v) => v.contains('application/json'))) {
        final json = await utf8.decoder.bind(body.stream).join();
        accumulator.add(json);
      } else {
        await _readEvents(body, cancelToken, (event) {
          accumulator.add(event);
          onText(accumulator.text);
          return accumulator.done;
        });
      }
      final result = accumulator.finish();
      onText(result.content);
      return result;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw ApiException(
          message: _handleDioError(e), statusCode: e.response?.statusCode);
    }
  }

  /// 发起一次 OpenAI 兼容的 chat completions 请求，返回 assistant 文本
  /// messages 支持纯文本格式 Map<String,String> 和 vision 格式 Map<String,dynamic>
  Future<String> chatCompletions({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, dynamic>> messages,
    CancelToken? cancelToken,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw ApiException(message: '请先在齿轮设置中填写 LLM API Key');
    }
    if (baseUrl.trim().isEmpty) {
      throw ApiException(message: '请先在齿轮设置中填写 LLM Base URL');
    }
    if (model.trim().isEmpty) {
      throw ApiException(message: '请先在齿轮设置中填写 LLM 模型名');
    }

    if (_protocol != LlmApiProtocol.openAiCompatible) {
      final response = await _nativeChat(apiKey, baseUrl, model, messages,
          cancelToken: cancelToken);
      final content = response.content.trim();
      if (content.isNotEmpty) return content;
      throw ApiException(message: '响应格式异常，未能解析到回复内容');
    }

    try {
      final response = await _dio.post(
        _chatUrl(baseUrl),
        cancelToken: cancelToken,
        data: {
          'model': model,
          'messages': messages,
          'stream': false,
          ..._thinkingFields(baseUrl, model, hasTools: false),
        },
        options: _chatOptions(apiKey),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        final choices = data['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final message = choices.first['message'];
          if (message is Map) {
            final c = message['content'];
            if (c is String) {
              final content = c.trim();
              if (content.isNotEmpty) return content;
            } else if (c is List) {
              // vision 模型可能返回 [{type:'text', text:'...'}, {type:'image_url', image_url:{url:'...'}}]
              final buf = StringBuffer();
              for (final part in c) {
                if (part is! Map) continue;
                final type = part['type'];
                if (type == 'text' && part['text'] is String) {
                  buf.write(part['text'] as String);
                } else if (type == 'image_url') {
                  final url = part['image_url'] is Map
                      ? (part['image_url'] as Map)['url']
                      : null;
                  if (url is String && url.isNotEmpty) {
                    buf.write('\n![image]($url)\n');
                  }
                }
              }
              final content = buf.toString().trim();
              if (content.isNotEmpty) return content;
            }
          }
        }
      }
      throw ApiException(message: '响应格式异常，未能解析到回复内容');
    } on DioException catch (e) {
      throw ApiException(
        message: _handleDioError(e),
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  /// 带 tools 的 chat completions 请求，返回结构化 LlmResponse。
  ///
  /// [tools] 是 OpenAI function-calling schema：每个元素是
  /// `{type:'function', function:{name, description, parameters}}`。
  /// [toolChoice] 默认 'auto'，可传 'none' / 'required' / 具体 function 对象。
  Future<LlmResponse> chatCompletionsWithTools({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String toolChoice = 'auto',
    CancelToken? cancelToken,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw ApiException(message: '请先在齿轮设置中填写 LLM API Key');
    }
    if (baseUrl.trim().isEmpty) {
      throw ApiException(message: '请先在齿轮设置中填写 LLM Base URL');
    }
    if (model.trim().isEmpty) {
      throw ApiException(message: '请先在齿轮设置中填写 LLM 模型名');
    }

    if (_protocol != LlmApiProtocol.openAiCompatible) {
      return _nativeChat(apiKey, baseUrl, model, messages,
          tools: tools, toolChoice: toolChoice, cancelToken: cancelToken);
    }

    final thinking =
        _thinkingFields(baseUrl, model, hasTools: tools.isNotEmpty);
    final replayReasoning = tools.isNotEmpty && _replayReasoning(thinking);
    try {
      final response = await _dio.post(
        _chatUrl(baseUrl),
        cancelToken: cancelToken,
        data: {
          'model': model,
          'messages': _compatibleMessages(messages, replayReasoning),
          'stream': false,
          'tools': tools,
          'tool_choice': toolChoice,
          ...thinking,
        },
        options: _chatOptions(apiKey),
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '响应格式异常');
      }
      final choices = data['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        throw ApiException(message: '响应没有 choices');
      }
      final firstChoice = choices.first as Map<String, dynamic>;
      final finishReason = (firstChoice['finish_reason'] ?? 'stop').toString();
      final message = firstChoice['message'] as Map<String, dynamic>?;

      String contentText = '';
      if (message != null) {
        final c = message['content'];
        if (c is String) {
          contentText = c.trim();
        } else if (c is List) {
          final buf = StringBuffer();
          for (final part in c) {
            if (part is! Map) continue;
            final type = part['type'];
            if (type == 'text' && part['text'] is String) {
              buf.write(part['text'] as String);
            }
          }
          contentText = buf.toString().trim();
        }
      }

      final toolCalls = <ToolCall>[];
      if (message != null) {
        final tc = message['tool_calls'];
        if (tc is List) {
          for (final item in tc) {
            if (item is! Map) continue;
            final id = (item['id'] ?? '').toString();
            final fn = item['function'];
            if (fn is! Map) continue;
            final name = (fn['name'] ?? '').toString();
            final rawArgs = fn['arguments'];
            Map<String, dynamic> parsedArgs = {};
            if (rawArgs is String && rawArgs.isNotEmpty) {
              try {
                final decoded = jsonDecode(rawArgs);
                if (decoded is Map<String, dynamic>) {
                  parsedArgs = decoded;
                }
              } catch (_) {
                // 解析失败就保持空 Map，由调用方决定是否处理
              }
            } else if (rawArgs is Map<String, dynamic>) {
              parsedArgs = rawArgs;
            }
            if (id.isNotEmpty && name.isNotEmpty) {
              toolCalls.add(ToolCall(
                id: id,
                name: name,
                arguments: parsedArgs,
              ));
            }
          }
        }
      }

      if (replayReasoning && finishReason == 'length' && toolCalls.isNotEmpty) {
        throw const FormatException('工具参数被截断，未执行');
      }
      return LlmResponse(
        content: contentText,
        toolCalls: toolCalls,
        finishReason: finishReason,
        reasoningContent:
            replayReasoning ? (message?['reasoning_content'] as String?) : null,
      );
    } on DioException catch (e) {
      throw ApiException(
        message: _handleDioError(e),
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  Future<LlmResponse> _nativeChat(
    String apiKey,
    String baseUrl,
    String model,
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>> tools = const [],
    String toolChoice = 'auto',
    void Function(String)? onText,
    CancelToken? cancelToken,
  }) async {
    final config = _connection;
    final id = config?.providerId;
    final keys = {
      apiKey.trim(),
      if (_protocol.supportsKeyRotation(baseUrl))
        ...?config?.backupApiKeys.map((key) => key.trim()),
    }..remove('');
    final pool = keys.toList();
    final preferred = config?.geminiKeyIndex ?? 0;
    final start = _activeKeyIndex(id, pool, preferred);
    final selectionVersion = _geminiSelectionVersions[id];
    final stream = onText != null;
    final thinking =
        _thinkingFields(baseUrl, model, hasTools: tools.isNotEmpty);
    final useAutoTools = _protocol == LlmApiProtocol.anthropic &&
        toolChoice == 'required' &&
        LlmThinking.levels(_protocol, baseUrl, model).length > 1;
    for (var attempt = 0; attempt < pool.length; attempt++) {
      final index = (start + attempt) % pool.length;
      final adapter = LlmNativeProtocol(_protocol);
      final options = _chatOptions(pool[index], stream: stream)
        ..method = 'POST'
        ..receiveDataWhenStatusError = !stream;
      final request = options.compose(
        _dio.options,
        llmEndpoint(_protocol, baseUrl, adapter.path(model, stream)),
        data: {
          ...adapter.request(model, messages, tools,
              useAutoTools ? 'auto' : toolChoice, stream),
          ...thinking,
        },
        cancelToken: cancelToken,
      );
      if (_protocol == LlmApiProtocol.gemini) {
        request.headers.remove('Authorization');
        request.followRedirects = false;
      }
      try {
        final response = await _dio.fetch<dynamic>(request);
        final data = response.data;
        if (data is! ResponseBody) {
          return adapter.parse(_jsonObject(data));
        }
        if ((data.headers['content-type'] ?? [])
            .any((value) => value.contains('application/json'))) {
          final result = adapter.parse(_jsonObject(
              jsonDecode(await utf8.decoder.bind(data.stream).join())));
          onText?.call(result.content);
          return result;
        }
        await _readEvents(data, cancelToken, (event) {
          if (event == '[DONE]') return true;
          final previous = adapter.text;
          adapter.addEvent(_jsonObject(jsonDecode(event)));
          if (adapter.text != previous) onText?.call(adapter.text);
          return adapter.done;
        });
        final result = adapter.finish();
        onText?.call(result.content);
        return result;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        if (e.response?.statusCode == 429 && pool.length > 1) {
          final next = (index + 1) % pool.length;
          if (attempt + 1 < pool.length) {
            if (id != null &&
                _geminiSelectionVersions[id] == selectionVersion &&
                _activeKeyIndex(id, pool, preferred) == index) {
              _geminiActiveKeys[id] = pool[next];
            }
            continue;
          }
          throw ApiException(
              message: 'Gemini 的所有 API Key 均已达到额度或频率限制', statusCode: 429);
        }
        throw ApiException(
            message: _handleDioError(e), statusCode: e.response?.statusCode);
      }
    }
    throw ApiException(message: '请先在齿轮设置中填写 LLM API Key');
  }

  Map<String, dynamic> _jsonObject(Object? data) {
    if (data is Map<String, dynamic>) return data;
    throw const FormatException('响应格式异常');
  }

  Future<void> _readEvents(ResponseBody body, CancelToken? cancelToken,
      bool Function(String) consume) async {
    final event = <String>[];
    await for (final line in body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
      if (line.isEmpty && event.isNotEmpty) {
        if (consume(event.join('\n'))) return;
        event.clear();
      } else if (line.startsWith('data:')) {
        event.add(line.substring(5).trimLeft());
      }
    }
    if (event.isNotEmpty) consume(event.join('\n'));
  }

  String _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '请求超时，请检查网络连接';
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final body = e.response?.data;
        if (statusCode == 401) return 'API Key 无效或已过期';
        if (statusCode == 402) return '额度不足';
        if (statusCode == 404) return '接口不存在，请检查 Base URL 是否正确';
        if (statusCode == 429) return '请求过于频繁，请稍后再试';
        if (statusCode == 500) return '服务器内部错误';
        if (body is Map) {
          return body['error']?['message']?.toString() ?? '请求失败 ($statusCode)';
        }
        return '请求失败 ($statusCode)';
      case DioExceptionType.connectionError:
        final msg = e.message ?? e.error?.toString();
        return msg != null && msg.isNotEmpty ? msg : '无法连接到服务器，请检查 Base URL';
      case DioExceptionType.unknown:
        final msg = e.message ?? e.error?.toString();
        return msg != null && msg.isNotEmpty ? msg : '未知网络错误';
      default:
        // badCertificate / cancel 等
        final msg = e.message ?? e.error?.toString() ?? '无详细信息';
        return '网络错误 [${e.type}]: $msg';
    }
  }
}
