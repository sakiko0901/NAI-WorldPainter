import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';

class NanoBananaApiService {
  final Dio _dio;

  NanoBananaApiService(this._dio);

  void _configureAuth(String apiKey, String baseUrl) {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    _dio.options.baseUrl = normalized;
    _dio.options.headers['Authorization'] = 'Bearer $apiKey';
    _dio.options.headers['Content-Type'] = 'application/json';
    _dio.options.headers['Accept'] = 'application/json';
  }

  /// 文生图（无参考图）
  Future<GenerationTask> generateImage(
      GenerationTask task, String apiKey, String baseUrl) async {
    _configureAuth(apiKey, baseUrl);

    final body = _buildBody(task, imageParts: []);

    try {
      final response = await _dio.post(
        '/v1/chat/completions',
        data: body,
        options: Options(
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: const Duration(minutes: 2),
        ),
      );
      return await _parseAndSave(response.data, task);
    } on DioException catch (e) {
      throw ApiException(
        message: _handleDioError(e),
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  /// 图生图（带参考图）
  Future<GenerationTask> editImage(
      GenerationTask task, String apiKey, String baseUrl) async {
    _configureAuth(apiKey, baseUrl);

    // 收集所有参考图路径
    final imagePaths = <String>[];
    imagePaths.addAll(task.gptImagePaths ?? []);

    if (imagePaths.isEmpty) {
      throw ApiException(message: '传图编辑缺少图片', code: 'MISSING_IMAGE');
    }

    // 将图片编码为 Gemini inline_data parts
    final imageParts = <Map<String, dynamic>>[];
    for (final path in imagePaths) {
      final bytes = await File(path).readAsBytes();
      final b64 = base64Encode(bytes);
      final mime = _guessMime(path);
      imageParts.add({
        'inline_data': {'mime_type': mime, 'data': b64},
      });
    }

    final body = _buildBody(task, imageParts: imageParts);

    try {
      final response = await _dio.post(
        '/v1/chat/completions',
        data: body,
        options: Options(
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: const Duration(minutes: 3),
        ),
      );
      return await _parseAndSave(response.data, task);
    } on DioException catch (e) {
      throw ApiException(
        message: _handleDioError(e),
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  Map<String, dynamic> _buildBody(
    GenerationTask task, {
    required List<Map<String, dynamic>> imageParts,
  }) {
    final aspectRatio = task.size ?? '1:1';
    final imageSize = task.nanoImageSize ?? '1K';
    final enrichedPrompt =
        '[aspect_ratio:$aspectRatio,image_size:$imageSize] ${task.prompt}';

    return {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': enrichedPrompt},
            ...imageParts,
          ],
        }
      ],
      'generationConfig': {
        'responseModalities': ['TEXT', 'IMAGE'],
      },
    };
  }

  Future<GenerationTask> _parseAndSave(
      dynamic data, GenerationTask originalTask) async {
    String? imagePath;
    String? imageUrl;

    if (data is Map<String, dynamic>) {
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'];
        final parts = content is Map<String, dynamic>
            ? content['parts'] as List<dynamic>?
            : null;
        if (parts != null) {
          for (final part in parts) {
            if (part is! Map<String, dynamic>) continue;
            final inline = part['inlineData'] ?? part['inline_data'];
            if (inline is Map<String, dynamic>) {
              final b64 = inline['data'] as String?;
              if (b64 != null && b64.isNotEmpty) {
                final filename = ImageUtils.generateFilename();
                imagePath = await ImageUtils.saveBase64Image(b64, filename);
                break;
              }
            }
            final text = part['text'] as String?;
            if (text != null) {
              final extracted = ImageUtils.extractImageUrlFromMarkdown(text);
              if (extracted != null) {
                imageUrl = extracted;
                break;
              }
            }
          }
        }
      }

      final choices = data['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        final message = choices[0]['message'];
        if (message != null) {
          final content = message['content'];
          if (content is String) {
            if (content.startsWith('data:image')) {
              // data URI → 直接解码保存
              final commaIdx = content.indexOf(',');
              if (commaIdx != -1) {
                final b64 = content.substring(commaIdx + 1);
                final filename = ImageUtils.generateFilename();
                imagePath = await ImageUtils.saveBase64Image(b64, filename);
              }
            } else if (content.startsWith('http')) {
              imageUrl = content;
            } else {
              // 尝试从 Markdown 提取 data URI：![image](data:image/...;base64,...)
              final dataUriRegex = RegExp(r'!\[.*?\]\((data:image/[^)]+)\)');
              final dataMatch = dataUriRegex.firstMatch(content);
              if (dataMatch != null) {
                final dataUri = dataMatch.group(1)!;
                final commaIdx = dataUri.indexOf(',');
                if (commaIdx != -1) {
                  final b64 = dataUri
                      .substring(commaIdx + 1)
                      .replaceAll(RegExp(r'\s'), '');
                  final filename = ImageUtils.generateFilename();
                  imagePath = await ImageUtils.saveBase64Image(b64, filename);
                }
              } else {
                imageUrl = ImageUtils.extractImageUrlFromMarkdown(content);
              }
            }
          } else if (content is List) {
            for (final part in content) {
              if (part is Map<String, dynamic>) {
                if (part['type'] == 'image_url') {
                  final url = part['image_url']?['url'] as String?;
                  if (url != null) {
                    if (url.startsWith('data:image')) {
                      final commaIdx = url.indexOf(',');
                      if (commaIdx != -1) {
                        final b64 = url.substring(commaIdx + 1);
                        final filename = ImageUtils.generateFilename();
                        imagePath =
                            await ImageUtils.saveBase64Image(b64, filename);
                      }
                    } else {
                      imageUrl = url;
                    }
                    break;
                  }
                } else if (part['type'] == 'text') {
                  final text = part['text'] as String? ?? '';
                  final extracted =
                      ImageUtils.extractImageUrlFromMarkdown(text);
                  if (extracted != null) {
                    imageUrl = extracted;
                    break;
                  }
                }
              }
            }
          }
        }
      }
    }

    final success = imageUrl != null || imagePath != null;

    String? debugMsg;
    if (!success && data is Map<String, dynamic>) {
      final choices = data['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        final message = choices[0]['message'];
        final content = message?['content'];
        final contentPreview = content?.toString() ?? 'null';
        final preview = contentPreview.length > 300
            ? contentPreview.substring(0, 300)
            : contentPreview;
        debugMsg = '未能提取图片。content类型=${content?.runtimeType}, 内容预览=$preview';
      } else {
        debugMsg = '未能提取图片。choices为空或不存在。响应键=${data.keys.toList()}';
      }
    }

    return originalTask.copyWith(
      status: success ? 'success' : 'failed',
      imageUrl: imageUrl,
      imagePath: imagePath,
      errorMessage: success ? null : (debugMsg ?? '未能从 Nano Banana 响应中提取图片'),
      completedAt: DateTime.now(),
    );
  }

  String _guessMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  String _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时，请检查网络或 Base URL';
      case DioExceptionType.sendTimeout:
        return '上传超时，图片可能过大';
      case DioExceptionType.receiveTimeout:
        return '接收超时，服务器生成时间过长，请稍后重试';
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final body = e.response?.data;
        if (statusCode == 401) return 'API Key 无效或已过期';
        if (statusCode == 402) return '额度不足';
        if (statusCode == 429) return '请求过于频繁，请稍后再试';
        if (statusCode == 500 || statusCode == 502 || statusCode == 504) {
          final detail = body?.toString() ?? '无详细信息';
          final preview =
              detail.length > 500 ? detail.substring(0, 500) : detail;
          return '服务器错误 ($statusCode): $preview';
        }
        if (body is Map) {
          return body['error']?['message']?.toString() ?? '请求失败 ($statusCode)';
        }
        return '请求失败 ($statusCode)';
      case DioExceptionType.connectionError:
        return '无法连接到服务器，请检查 Base URL 和网络';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.unknown:
        final inner = e.error;
        if (inner is SocketException) {
          final msg = inner.message;
          if (msg.contains('Connection closed before full header')) {
            return '中转站网关超时断开连接，请稍后重试';
          }
          return '连接中断: $msg';
        }
        final msg = e.message;
        return '网络异常: ${msg ?? inner?.toString() ?? '无详细信息'}';
      default:
        final msg = e.message;
        return msg != null && msg.isNotEmpty
            ? '网络错误: $msg'
            : '网络错误 (${e.type.name})';
    }
  }
}
