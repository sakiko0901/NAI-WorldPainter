import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/nai_model.dart';

class NovelAiApiService {
  final Dio _dio;

  NovelAiApiService(this._dio);

  void _configureAuth(String apiKey, String baseUrl) {
    final normalizedBaseUrl = _normalizeBaseUrl(baseUrl);
    _dio.options.baseUrl = normalizedBaseUrl;
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

  Future<List<NaiModel>> fetchModels(String apiKey, String baseUrl) async {
    _configureAuth(apiKey, baseUrl);
    try {
      final response = await _dio.get(ApiConstants.models);
      final data = response.data;

      if (data is Map<String, dynamic> && data.containsKey('data')) {
        final List list = data['data'];
        return list
            .map((e) => NaiModel(
                  id: e['id'] ?? '',
                  name: e['id'] ?? '',
                  description: e['object'] ?? '',
                  type: e['owned_by'] ?? '',
                ))
            .toList();
      }

      return [];
    } on DioException catch (e) {
      throw ApiException(
        message: _handleDioError(e),
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  Future<GenerationTask> generateImage(
      GenerationTask task, String apiKey, String baseUrl) async {
    _configureAuth(apiKey, baseUrl);

    try {
      final usesImageGenerations =
          task.protocol == AppConstants.novelAiImageGenerationsProtocol;
      final usesPreciseReference =
          usesImageGenerations && task.preciseReferences.isNotEmpty;
      final usesImg2Img = task.img2imgSourceImagePath != null;
      final requestPath = usesImg2Img && !usesImageGenerations
          ? ApiConstants.imageImg2Img
          : usesImageGenerations
              ? ApiConstants.imageGenerations
              : ApiConstants.chatCompletions;
      final response = await _dio.post(
        requestPath,
        data: usesImg2Img
            ? await _buildImg2ImgBody(
                task,
                unifiedRoute: usesImageGenerations,
              )
            : usesPreciseReference
                ? await _buildPreciseReferenceBody(task)
                : usesImageGenerations
                    ? await _buildImageGenerationsBody(task)
                    : _buildChatCompletionsBody(task),
        options: Options(
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 1),
        ),
      );

      if (usesImageGenerations || usesImg2Img) {
        return _parseImageGenerationResponse(response.data, task, apiKey);
      }
      final parsed = _parseResponse(response.data, task);
      return await _downloadIfNeeded(parsed, apiKey);
    } on DioException catch (e) {
      throw ApiException(
        message: _handleDioError(e),
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  Future<Uint8List> annotateImage({
    required String imagePath,
    required String apiKey,
    required String baseUrl,
  }) async {
    _configureAuth(apiKey, baseUrl);
    final bytes = await File(imagePath).readAsBytes();
    try {
      final response = await _dio.post<List<int>>(
        ApiConstants.imageAnnotate,
        data: Stream.fromIterable([bytes]),
        options: Options(
          contentType: 'image/png',
          responseType: ResponseType.bytes,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Accept': 'image/png',
          },
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw ApiException(message: '标注接口未返回 PNG');
      }
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      throw ApiException(
        message: _handleDioError(e),
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  Future<Uint8List> processDirectorImage({
    required String imagePath,
    required String operation,
    required String apiKey,
    required String baseUrl,
    String? model,
    String? prompt,
    int? defry,
  }) async {
    _configureAuth(apiKey, baseUrl);
    final bytes = await File(imagePath).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw ApiException(message: '无法读取图片，请选择有效的 PNG 或 JPEG 图片');
    }
    final body = <String, dynamic>{
      'novelai_operation': operation,
      'image': base64Encode(bytes),
      'width': image.width,
      'height': image.height,
    };
    if (model != null && model.trim().isNotEmpty) body['model'] = model.trim();
    if (prompt != null) body['prompt'] = prompt.trim();
    if (defry != null) body['defry'] = defry.clamp(0, 5);
    try {
      final response = await _dio.post(
        ApiConstants.imageGenerations,
        data: body,
        options: Options(
          contentType: 'application/json',
          receiveTimeout: const Duration(minutes: 3),
        ),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final images = data['data'];
        if (images is List && images.isNotEmpty) {
          final first = images.first;
          if (first is Map && first['b64_json'] is String) {
            try {
              return base64Decode(first['b64_json'] as String);
            } on FormatException {
              throw ApiException(message: '导演工具返回的 b64_json 无效');
            }
          }
        }
      }
      throw ApiException(message: '导演工具未返回 b64_json');
    } on DioException catch (e) {
      throw ApiException(
        message: _handleDioError(e),
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  Future<GenerationTask> inpaintImage(
      GenerationTask task, String apiKey, String baseUrl) async {
    _configureAuth(apiKey, baseUrl);

    print('[NAI] === INPAINT START ===');
    print('[NAI] baseUrl: ${_dio.options.baseUrl}');
    print('[NAI] sourceImage: ${task.sourceImagePath}');
    print('[NAI] maskImage: ${task.maskImagePath}');
    print('[NAI] prompt: ${task.prompt}');
    print('[NAI] model: ${task.model}');
    print('[NAI] strength: ${task.inpaintStrength}');
    print('[NAI] size: ${task.width}x${task.height}');

    final sourceBytes = await File(task.sourceImagePath!).readAsBytes();
    final maskBytes = await File(task.maskImagePath!).readAsBytes();
    final alphaSourceBytes = _applyMaskToImageAlpha(sourceBytes, maskBytes);

    print('[NAI] sourceBytes length: ${sourceBytes.length}');
    print('[NAI] maskBytes length: ${maskBytes.length}');
    print('[NAI] alphaSourceBytes length: ${alphaSourceBytes.length}');

    // /v1/images/edits: 不传 mask，使用 image alpha 通道；透明区域会被转换为 NovelAI 白色重绘区域
    final formData = FormData.fromMap({
      'model': task.model,
      'prompt': task.prompt,
      'negative_prompt': task.negativePrompt ?? '',
      'image': MultipartFile.fromBytes(alphaSourceBytes,
          filename: 'source_alpha.png'),
      'size': '${task.width}x${task.height}',
      'width': task.width,
      'height': task.height,
      'steps': task.steps,
      'n_samples': 1,
      'scale': task.scale,
      'sampler': task.sampler,
      'noise_schedule': task.noiseSchedule,
      'cfg_rescale': task.cfgRescale,
      if (task.seed != null) 'seed': task.seed,
      'characterPrompts': jsonEncode(_buildCharacterPrompts(task.characters)),
      'use_coords': task.useCoords,
      'strength': task.inpaintStrength ?? 1.0,
      'response_format': 'b64_json',
    });

    print(
        '[NAI] sending alpha image as multipart/form-data to /v1/images/edits');

    try {
      final response = await _dio.post(
        ApiConstants.imageEdits,
        data: formData,
        options: Options(
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 2),
          headers: {
            'Authorization': 'Bearer $apiKey',
          },
        ),
      );

      print('[NAI] response statusCode: ${response.statusCode}');
      print('[NAI] response data type: ${response.data.runtimeType}');
      if (response.data is Map) {
        print('[NAI] response keys: ${(response.data as Map).keys.toList()}');
        final data = response.data as Map<String, dynamic>;
        if (data.containsKey('data')) {
          final dataList = data['data'] as List?;
          print('[NAI] response data[].length: ${dataList?.length}');
          if (dataList != null && dataList.isNotEmpty) {
            final first = dataList.first;
            if (first is Map) {
              print('[NAI] response data[0] keys: ${first.keys.toList()}');
              if (first.containsKey('b64_json')) {
                print(
                    '[NAI] response data[0].b64_json length: ${(first['b64_json'] as String?)?.length}');
              }
              if (first.containsKey('url')) {
                print('[NAI] response data[0].url: ${first['url']}');
              }
            }
          }
        }
      }

      final parsed = await _parseInpaintingResponse(response.data, task);
      print(
          '[NAI] parsed status: ${parsed.status}, imagePath: ${parsed.imagePath}, imageUrl: ${parsed.imageUrl}');
      return parsed;
    } on DioException catch (e) {
      print(
          '[NAI] DioException: ${e.type}, statusCode: ${e.response?.statusCode}');
      print('[NAI] DioException response: ${e.response?.data}');
      throw ApiException(
        message: _handleDioError(e),
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  List<int> _applyMaskToImageAlpha(List<int> sourceBytes, List<int> maskBytes) {
    final source = img.decodeImage(Uint8List.fromList(sourceBytes));
    final mask = img.decodeImage(Uint8List.fromList(maskBytes));
    if (source == null || mask == null) {
      return sourceBytes;
    }

    final output = img.Image.from(source);
    final resizedMask =
        mask.width == output.width && mask.height == output.height
            ? mask
            : img.copyResize(mask,
                width: output.width,
                height: output.height,
                interpolation: img.Interpolation.nearest);

    int transparentPixels = 0;
    for (int y = 0; y < output.height; y++) {
      for (int x = 0; x < output.width; x++) {
        final maskPixel = resizedMask.getPixel(x, y);
        final shouldRepaint = maskPixel.r > 127 ||
            maskPixel.g > 127 ||
            maskPixel.b > 127 ||
            maskPixel.a < 128;
        final sourcePixel = output.getPixel(x, y);
        output.setPixelRgba(
          x,
          y,
          sourcePixel.r,
          sourcePixel.g,
          sourcePixel.b,
          shouldRepaint ? 0 : 255,
        );
        if (shouldRepaint) transparentPixels++;
      }
    }

    final totalPixels = output.width * output.height;
    print(
        '[NAI] alpha source transparent pixels: $transparentPixels / $totalPixels (${(transparentPixels / totalPixels * 100).toStringAsFixed(2)}%)');
    return img.encodePng(output);
  }

  Future<Map<String, dynamic>> _buildPreciseReferenceBody(
    GenerationTask task,
  ) async {
    final references = <Map<String, dynamic>>[];
    for (var index = 0; index < task.preciseReferences.length; index++) {
      final reference = task.preciseReferences[index];
      final referenceImage = await _readPreciseReferenceIfAvailable(reference);
      if (referenceImage == null) {
        throw ApiException(message: '精密参照图像 ${index + 1} 不可用，请重新选择');
      }
      references.add({
        'reference_image': referenceImage,
        'reference_type': reference.referenceType,
        'strength': reference.strength,
        'fidelity': 1.0,
      });
    }

    final responseFormat =
        const {'b64_json', 'url'}.contains(task.responseFormat)
            ? task.responseFormat!
            : 'b64_json';
    return {
      'novelai_operation': 'precise-reference',
      'prompt': task.prompt,
      if (task.negativePrompt != null && task.negativePrompt!.isNotEmpty)
        'negative_prompt': task.negativePrompt,
      'model': task.model,
      'size': '${task.width}x${task.height}',
      'width': task.width,
      'height': task.height,
      'steps': task.steps,
      'n_samples': 1,
      'scale': task.scale,
      'sampler': _normalizeImageGenerationsSampler(task.sampler),
      'noise_schedule':
          _normalizeImageGenerationsNoiseSchedule(task.noiseSchedule),
      'cfg_rescale': task.cfgRescale,
      if (task.seed != null) 'seed': task.seed,
      'response_format': responseFormat,
      'references': references,
    };
  }

  Future<Map<String, dynamic>> _buildImg2ImgBody(
    GenerationTask task, {
    required bool unifiedRoute,
  }) async {
    final sourcePath = task.img2imgSourceImagePath;
    if (sourcePath == null) {
      throw ApiException(message: '图生图缺少源图');
    }
    final file = File(sourcePath);
    if (!await file.exists()) {
      throw ApiException(message: '图生图源图不可用，请重新选择');
    }

    return {
      if (unifiedRoute) 'novelai_operation': 'img2img',
      'model': task.model,
      'prompt': task.prompt,
      'image': base64Encode(await file.readAsBytes()),
      'strength': task.img2imgStrength ?? 0.7,
      'size': '${task.width}x${task.height}',
      'width': task.width,
      'height': task.height,
      'steps': task.steps,
      'scale': task.scale,
      'cfg_rescale': task.cfgRescale,
      'sampler': unifiedRoute
          ? _normalizeImageGenerationsSampler(task.sampler)
          : task.sampler,
      'noise_schedule': unifiedRoute
          ? _normalizeImageGenerationsNoiseSchedule(task.noiseSchedule)
          : task.noiseSchedule,
      if (task.seed != null) 'seed': task.seed,
      if (task.negativePrompt != null && task.negativePrompt!.isNotEmpty)
        'negative_prompt': task.negativePrompt,
      'response_format': 'b64_json',
    };
  }

  Future<Map<String, dynamic>> _buildImageGenerationsBody(
      GenerationTask task) async {
    final reference =
        task.vibeReferences.isEmpty ? null : task.vibeReferences.first;
    final referenceImage =
        reference == null ? null : await _readReferenceIfAvailable(reference);
    final characterPrompts = _buildCharacterPrompts(task.characters);
    final responseFormat =
        const {'b64_json', 'url'}.contains(task.responseFormat)
            ? task.responseFormat!
            : 'b64_json';
    return {
      'prompt': task.prompt,
      if (task.negativePrompt != null && task.negativePrompt!.isNotEmpty)
        'negative_prompt': task.negativePrompt,
      'model': task.model,
      'size': '${task.width}x${task.height}',
      'width': task.width,
      'height': task.height,
      'steps': task.steps,
      'n_samples': 1,
      'scale': task.scale,
      'sampler': _normalizeImageGenerationsSampler(task.sampler),
      'noise_schedule':
          _normalizeImageGenerationsNoiseSchedule(task.noiseSchedule),
      'cfg_rescale': task.cfgRescale,
      if (task.seed != null) 'seed': task.seed,
      'response_format': responseFormat,
      if (characterPrompts.isNotEmpty) 'characterPrompts': characterPrompts,
      if (characterPrompts.isNotEmpty) 'use_coords': task.useCoords,
      if (referenceImage != null) 'reference_image': referenceImage,
      if (referenceImage != null) 'reference_strength': reference!.strength,
      if (referenceImage != null)
        'reference_information_extracted': reference!.informationExtracted,
    };
  }

  Future<String?> _readPreciseReferenceIfAvailable(
    PreciseReferenceImage reference,
  ) async {
    try {
      final file = File(reference.path);
      if (!await file.exists()) return null;
      return base64Encode(await file.readAsBytes());
    } on FileSystemException {
      return null;
    }
  }

  Future<String?> _readReferenceIfAvailable(
    CharacterReferenceImage reference,
  ) async {
    try {
      final file = File(reference.path);
      if (!await file.exists()) return null;
      return base64Encode(await file.readAsBytes());
    } on FileSystemException {
      return null;
    }
  }

  String _normalizeImageGenerationsSampler(String sampler) {
    return sampler == 'ddim' ? 'ddim_v3' : sampler;
  }

  String _normalizeImageGenerationsNoiseSchedule(String noiseSchedule) {
    return noiseSchedule == 'polyexponential' ? 'exponential' : noiseSchedule;
  }

  List<Map<String, dynamic>> _buildCharacterPrompts(
    List<CharacterSpec>? characters,
  ) {
    if (characters == null) return const [];
    return characters.where((character) => character.enabled).map((character) {
      return {
        'prompt': character.prompt,
        'uc': character.uc ?? '',
        if (character.centerX != null && character.centerY != null)
          'center': {
            'x': character.centerX,
            'y': character.centerY,
          },
      };
    }).toList();
  }

  Future<GenerationTask> _parseImageGenerationResponse(
    dynamic data,
    GenerationTask originalTask,
    String apiKey,
  ) async {
    final parsed = await _parseInpaintingResponse(data, originalTask);
    return _downloadIfNeeded(parsed, apiKey);
  }

  Map<String, dynamic> _buildChatCompletionsBody(GenerationTask task) {
    final messages = <Map<String, dynamic>>[];

    // 方式二：JSON 结构化提示词
    messages.add({
      'role': 'user',
      'content': _buildStructuredPrompt(task),
    });

    // 方式三：负面提示词通过 system 消息传递
    if (task.negativePrompt != null && task.negativePrompt!.isNotEmpty) {
      messages.add({
        'role': 'system',
        'content': 'Negative prompt: ${task.negativePrompt}',
      });
    }

    // 方式三：多人物坐标通过 system 消息传递
    if (task.characters != null && task.characters!.isNotEmpty) {
      messages.add({
        'role': 'system',
        'content': _buildCharactersPrompt(task.characters!),
      });
    }

    return {
      'model': task.model,
      'stream': false,
      'scale': task.scale,
      'cfg_rescale': task.cfgRescale,
      'width': task.width,
      'height': task.height,
      'sampler': task.sampler,
      'noise_schedule': task.noiseSchedule,
      if (task.seed != null) 'seed': task.seed,
      'messages': messages,
    };
  }

  Future<Map<String, dynamic>> _buildInpaintingBody(GenerationTask task) async {
    if (task.sourceImagePath == null || task.maskImagePath == null) {
      throw Exception('局部重绘缺少原图或遮罩图');
    }

    final sourceBytes = await File(task.sourceImagePath!).readAsBytes();
    final maskBytes = await File(task.maskImagePath!).readAsBytes();

    final imageBase64 = base64Encode(sourceBytes);
    final maskBase64 = base64Encode(maskBytes);

    return {
      'model': task.model,
      'prompt': task.prompt,
      'image': imageBase64,
      'mask': maskBase64,
      'strength': task.inpaintStrength ?? 1.0,
      if (task.seed != null) 'seed': task.seed,
      'size': '${task.width}x${task.height}',
      if (task.negativePrompt != null && task.negativePrompt!.isNotEmpty)
        'negative_prompt': task.negativePrompt,
      'steps': ApiConstants.defaultInpaintingSteps,
      'scale': task.scale,
      'cfg_rescale': task.cfgRescale,
      'sampler': task.sampler,
      'noise_schedule': task.noiseSchedule,
      'n': 1,
      'response_format': 'b64_json',
    };
  }

  String _buildStructuredPrompt(GenerationTask task) {
    return jsonEncode({
      'prompt': task.prompt,
      'size': [task.width, task.height],
    });
  }

  String _buildCharactersPrompt(List<CharacterSpec> characters) {
    final payload = characters.where((c) => c.enabled).map((c) {
      final map = <String, dynamic>{
        'prompt': c.prompt,
      };
      if (c.centerX != null && c.centerY != null) {
        map['center'] = {
          'x': c.centerX,
          'y': c.centerY,
        };
      }
      if (c.uc != null && c.uc!.isNotEmpty) {
        map['uc'] = c.uc;
      }
      return map;
    }).toList();

    return 'Characters: ${jsonEncode(payload)}';
  }

  Future<GenerationTask> _parseInpaintingResponse(
      dynamic data, GenerationTask originalTask) async {
    if (data is Map<String, dynamic>) {
      final images = data['data'] as List<dynamic>?;
      if (images != null && images.isNotEmpty) {
        final imageData = images.first;
        if (imageData is Map<String, dynamic>) {
          if (imageData['url'] is String) {
            return originalTask.copyWith(
              status: 'success',
              imageUrl: imageData['url'] as String,
              completedAt: DateTime.now(),
            );
          }
          if (imageData['b64_json'] is String) {
            final filename = ImageUtils.generateFilename();
            final filePath = await ImageUtils.saveBase64Image(
                imageData['b64_json'] as String, filename);
            return originalTask.copyWith(
              status: 'success',
              imagePath: filePath,
              completedAt: DateTime.now(),
            );
          }
        }
      }
    }

    return originalTask.copyWith(
      status: 'failed',
      errorMessage: '未能从局部重绘响应中提取图片',
      completedAt: DateTime.now(),
    );
  }

  GenerationTask _parseResponse(dynamic data, GenerationTask originalTask) {
    String? imageUrl;
    String? imagePath;

    if (data is Map<String, dynamic>) {
      final choices = data['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        final message = choices[0]['message'];
        if (message != null) {
          final content = message['content'];
          if (content is String) {
            imageUrl = ImageUtils.extractImageUrlFromMarkdown(content);
          } else if (content is List) {
            for (final part in content) {
              if (part is Map<String, dynamic>) {
                if (part['type'] == 'image_url') {
                  imageUrl = part['image_url']?['url'];
                  break;
                } else if (part['type'] == 'text') {
                  imageUrl = ImageUtils.extractImageUrlFromMarkdown(
                      part['text'] ?? '');
                  if (imageUrl != null) break;
                }
              }
            }
          }
        }
      }

      if (imageUrl == null) {
        final images = data['data'] as List<dynamic>?;
        if (images != null && images.isNotEmpty) {
          final imageData = images[0];
          if (imageData is Map<String, dynamic>) {
            if (imageData.containsKey('url')) {
              imageUrl = imageData['url'];
            } else if (imageData.containsKey('b64_json')) {
              imagePath = null;
            }
          }
        }
      }
    }

    return originalTask.copyWith(
      status: imageUrl != null || imagePath != null ? 'success' : 'failed',
      imageUrl: imageUrl,
      imagePath: imagePath,
      errorMessage: imageUrl == null && imagePath == null ? '未能从响应中提取图片' : null,
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

  Future<bool> testConnection(String apiKey, String baseUrl) async {
    _configureAuth(apiKey, baseUrl);
    try {
      final response = await _dio.post(
        ApiConstants.chatCompletions,
        data: {
          'model': 'nai-diffusion-4-5-curated',
          'stream': false,
          'width': 832,
          'height': 1216,
          'messages': [
            {
              'role': 'user',
              'content': jsonEncode({
                'prompt': '1girl',
                'size': [832, 1216],
              }),
            },
          ],
        },
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return '请求超时，请检查网络连接';
      case DioExceptionType.receiveTimeout:
        return '响应超时，服务器未在规定时间内返回结果';
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final body = e.response?.data;
        if (statusCode == 401) return 'API Key 无效或已过期';
        if (statusCode == 402) return '额度不足';
        if (statusCode == 429) return '请求过于频繁，请稍后再试';
        final summary = _extractErrorSummary(body);
        if (statusCode != null && statusCode >= 500) {
          return summary == null
              ? '服务器错误 ($statusCode)'
              : '服务器错误 ($statusCode)：$summary';
        }
        return summary ?? '请求失败 ($statusCode)';
      case DioExceptionType.connectionError:
        return '无法连接到服务器，请检查 Base URL';
      default:
        final summary = _extractErrorSummary(e.response?.data);
        if (summary != null) return summary;
        final message = e.message?.trim();
        if (message != null && message.isNotEmpty) return '网络错误：$message';
        final original = e.error?.toString().trim();
        if (original != null && original.isNotEmpty) return '网络错误：$original';
        return '网络请求失败';
    }
  }

  String? _extractErrorSummary(dynamic body) {
    if (body is List<int>) {
      final decoded = utf8.decode(body, allowMalformed: true).trim();
      if (decoded.isEmpty) return null;
      try {
        return _extractErrorSummary(jsonDecode(decoded));
      } catch (_) {
        return decoded.length > 300 ? '${decoded.substring(0, 300)}…' : decoded;
      }
    }
    if (body is String) {
      final trimmed = body.trim();
      if (trimmed.isEmpty) return null;
      try {
        return _extractErrorSummary(jsonDecode(trimmed));
      } catch (_) {
        return trimmed.length > 300 ? '${trimmed.substring(0, 300)}…' : trimmed;
      }
    }
    if (body is Map) {
      final error = body['error'];
      if (error is Map && error['message'] != null) {
        return error['message'].toString();
      }
      if (error is String && error.trim().isNotEmpty) return error.trim();
      for (final key in const ['message', 'detail']) {
        final value = body[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString().trim();
        }
      }
    }
    return null;
  }
}
