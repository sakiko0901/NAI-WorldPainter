import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';

class GptApiService {
  final Dio _dio;

  GptApiService(this._dio);

  void _configureAuth(String apiKey, String baseUrl, {bool multipart = false}) {
    final normalizedBaseUrl = _normalizeBaseUrl(baseUrl);
    _dio.options.baseUrl = normalizedBaseUrl;
    _dio.options.headers['Authorization'] = 'Bearer $apiKey';
    if (multipart) {
      _dio.options.headers.remove('Content-Type');
    } else {
      _dio.options.headers['Content-Type'] = 'application/json';
    }
    _dio.options.headers['Accept'] = 'application/json';
  }

  String _normalizeBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/v1')) {
      return trimmed.substring(0, trimmed.length - 3);
    }
    return trimmed;
  }

  Future<GenerationTask> generateImage(
      GenerationTask task, String apiKey, String baseUrl) async {
    _configureAuth(apiKey, baseUrl);

    try {
      final requestBody = _buildImageGenerationsBody(task);
      final response = await _dio.post(
        ApiConstants.imageGenerations,
        data: requestBody,
        options: Options(
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 1),
        ),
      );

      final parsed = await _parseResponse(response.data, task);
      return await _downloadIfNeeded(parsed, apiKey);
    } on DioException catch (e) {
      throw ApiException(
        message: _handleDioError(e),
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  Future<GenerationTask> editImage(
      GenerationTask task, String apiKey, String baseUrl) async {
    // 局部重绘用 sourceImagePath，图生图用 gptImagePaths
    final imagePaths = task.mode == GenerationMode.inpainting
        ? (task.sourceImagePath != null ? [task.sourceImagePath!] : <String>[])
        : (task.gptImagePaths ?? <String>[]);

    if (imagePaths.isEmpty) {
      throw ApiException(message: '传图编辑缺少图片', code: 'MISSING_IMAGE');
    }

    _configureAuth(apiKey, baseUrl, multipart: true);

    try {
      // 用 files + fields 分开追加，支持同名多个 image 字段
      final multiImageFormData = FormData();
      for (final path in imagePaths) {
        multiImageFormData.files
            .add(MapEntry('image', await MultipartFile.fromFile(path)));
      }
      multiImageFormData.fields.add(MapEntry('prompt', task.prompt));
      multiImageFormData.fields.add(MapEntry('model', task.model));
      multiImageFormData.fields
          .add(MapEntry('size', task.size ?? '${task.width}x${task.height}'));
      multiImageFormData.fields.add(const MapEntry('n', '1'));
      if (task.maskImagePath != null) {
        multiImageFormData.files.add(MapEntry(
            'mask', await MultipartFile.fromFile(task.maskImagePath!)));
      }

      final response = await _dio.post(
        ApiConstants.imageEdits,
        data: multiImageFormData,
        options: Options(
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: const Duration(minutes: 3),
        ),
      );

      final parsed = await _parseResponse(response.data, task);
      return await _downloadIfNeeded(parsed, apiKey);
    } on DioException catch (e) {
      throw ApiException(
        message: _handleDioError(e),
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  Map<String, dynamic> _buildImageGenerationsBody(GenerationTask task) {
    final size = task.size ?? '${task.width}x${task.height}';
    return {
      'model': task.model,
      'prompt': task.prompt,
      'size': size,
      'response_format': 'url',
    };
  }

  Future<GenerationTask> _parseResponse(
      dynamic data, GenerationTask originalTask) async {
    String? imageUrl;
    String? imagePath;

    if (data is Map<String, dynamic>) {
      // 格式1: data[0].url — 标准 OpenAI images/generations 响应
      final images = data['data'] as List<dynamic>?;
      if (images != null && images.isNotEmpty) {
        final imageData = images[0];
        if (imageData is Map<String, dynamic>) {
          if (imageData.containsKey('url')) {
            imageUrl = imageData['url'] as String;
          } else if (imageData.containsKey('b64_json')) {
            // 格式2: data[0].b64_json — 返回 base64 编码图片
            final b64 = imageData['b64_json'] as String;
            final filename = ImageUtils.generateFilename();
            imagePath = await ImageUtils.saveBase64Image(b64, filename);
          }
        }
      }

      // 格式3: choices[0].message.content — 某些中转站走 chat 格式返回
      if (imageUrl == null && imagePath == null) {
        final choices = data['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final message = choices[0]['message'];
          if (message != null) {
            final content = message['content'];
            if (content is String) {
              // 尝试从 markdown 提取图片 URL
              imageUrl = ImageUtils.extractImageUrlFromMarkdown(content);
              // 尝试解析为 JSON
              if (imageUrl == null) {
                try {
                  final json = jsonDecode(content);
                  if (json is Map) {
                    if (json['url'] != null) imageUrl = json['url'] as String;
                  }
                } catch (_) {}
              }
            } else if (content is List) {
              for (final part in content) {
                if (part is Map<String, dynamic>) {
                  if (part['type'] == 'image_url') {
                    imageUrl = part['image_url']?['url'];
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
    return originalTask.copyWith(
      status: success ? 'success' : 'failed',
      imageUrl: imageUrl,
      imagePath: imagePath,
      errorMessage: success
          ? null
          : '未能从 GPT 响应中提取图片 (响应键: ${data is Map ? data.keys.toList() : data.runtimeType})',
      completedAt: DateTime.now(),
    );
  }

  Future<GenerationTask> _downloadIfNeeded(
      GenerationTask task, String apiKey) async {
    if (task.imageUrl != null && task.imagePath == null) {
      try {
        final filename = ImageUtils.generateFilename();
        final dir = await ImageUtils.getImageDirectory();
        final filePath = '${dir.path}${Platform.pathSeparator}$filename';
        await _dio.download(
          task.imageUrl!,
          filePath,
          options: Options(
            receiveTimeout: const Duration(minutes: 5),
            headers: {
              'Authorization': 'Bearer $apiKey',
            },
          ),
        );
        return task.copyWith(imagePath: filePath);
      } catch (_) {
        return task;
      }
    }
    return task;
  }

  String _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时，请检查网络或 Base URL';
      case DioExceptionType.sendTimeout:
        return '上传超时，图片可能过大';
      case DioExceptionType.receiveTimeout:
        return '接收超时，服务器生成时间过长，请稍后重试（若已扣费说明图已生成，可能是网络问题）';
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final body = e.response?.data;
        if (statusCode == 401) return 'API Key 无效或已过期';
        if (statusCode == 402) return '额度不足';
        if (statusCode == 429) return '请求过于频繁，请稍后再试';
        if (statusCode == 500) return '服务器内部错误 (500)';
        if (statusCode == 502 || statusCode == 504)
          return '网关错误 ($statusCode)，中转站或上游服务暂时不可用';
        if (body is Map)
          return body['error']?['message']?.toString() ?? '请求失败 ($statusCode)';
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
            return '中转站网关超时断开连接（图像生成耗时过长，服务器已处理但未能返回结果）。若已扣费说明图已生成，请稍后重试';
          }
          return '连接中断: $msg';
        }
        final msg = e.message;
        return '网络异常 (unknown): ${msg ?? inner?.toString() ?? '无详细信息'}';
      default:
        final msg = e.message;
        return msg != null && msg.isNotEmpty
            ? '网络错误: $msg'
            : '网络错误 (${e.type.name})';
    }
  }
}
