import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/domain/entities/llm_response.dart';
import 'package:nai_huishi/domain/entities/tool_call.dart';

class LlmApiService {
  final Dio _dio;

  LlmApiService(this._dio);

  void _configureAuth(String apiKey, String baseUrl) {
    _dio.options.baseUrl = _normalizeBaseUrl(baseUrl);
    _dio.options.headers['Authorization'] = 'Bearer $apiKey';
    _dio.options.headers['Content-Type'] = 'application/json';
    _dio.options.headers['Accept'] = 'application/json';
  }

  String _normalizeBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/v1')) {
      return trimmed.substring(0, trimmed.length - 3);
    }
    return trimmed;
  }

  /// 发起一次 OpenAI 兼容的 chat completions 请求，返回 assistant 文本
  /// messages 支持纯文本格式 Map<String,String> 和 vision 格式 Map<String,dynamic>
  Future<String> chatCompletions({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, dynamic>> messages,
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

    _configureAuth(apiKey, baseUrl);

    try {
      final response = await _dio.post(
        ApiConstants.chatCompletions,
        data: {
          'model': model,
          'messages': messages,
          'stream': false,
        },
        options: Options(
          receiveTimeout: const Duration(minutes: 2),
          sendTimeout: const Duration(seconds: 30),
        ),
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

    _configureAuth(apiKey, baseUrl);

    try {
      final response = await _dio.post(
        ApiConstants.chatCompletions,
        data: {
          'model': model,
          'messages': messages,
          'stream': false,
          'tools': tools,
          'tool_choice': toolChoice,
        },
        options: Options(
          receiveTimeout: const Duration(minutes: 2),
          sendTimeout: const Duration(seconds: 30),
        ),
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

      return LlmResponse(
        content: contentText,
        toolCalls: toolCalls,
        finishReason: finishReason,
      );
    } on DioException catch (e) {
      throw ApiException(
        message: _handleDioError(e),
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
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
