import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/nai_model.dart';
import 'package:nai_huishi/domain/entities/novelai_route.dart';

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
    if (trimmed.endsWith('/origin')) {
      return trimmed.substring(0, trimmed.length - 7);
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
      final route = NovelAiRoute.fromIds(task.endpointId, task.protocol);
      final is7877 = route.isGateway7877;
      final isIkun = route.isIkun;
      final usesGatewayImages = is7877 || isIkun;
      final usesV5Medium = usesGatewayImages && _isV5MediumModel(task.model);
      final usesPreciseReference = isIkun && task.preciseReferences.isNotEmpty;
      final usesImg2Img = task.img2imgSourceImagePath != null;
      final requestPath = usesGatewayImages
          ? ApiConstants.imageGenerations
          : ApiConstants.chatCompletions;
      final requestOptions = Options(
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(minutes: 1),
      );
      final requestBody = usesV5Medium
          ? await _buildV5MediumImageGenerationsBody(
              task,
              is7877: is7877,
              operation: usesImg2Img ? 'img2img' : null,
            )
          : usesImg2Img
              ? await _buildImg2ImgBody(task, isIkun: isIkun)
              : usesPreciseReference
                  ? await _buildPreciseReferenceBody(task)
                  : is7877
                      ? await _build7877ImageGenerationsBody(task)
                      : isIkun
                          ? await _buildImageGenerationsBody(task)
                          : _buildChatCompletionsBody(task);
      final response = await _dio.post(
        requestPath,
        data: requestBody,
        options: requestOptions.copyWith(
          responseType: ResponseType.json,
        ),
      );

      if (usesGatewayImages) {
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
    required String model,
    required String apiKey,
    required String baseUrl,
    String? prompt,
    int? defry,
  }) async {
    return _processDirectorImageV1(
      imagePath: imagePath,
      operation: operation,
      model: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
      prompt: prompt,
      defry: defry,
      usesGatewayExtra: true,
    );
  }

  Future<Uint8List> processDirectorImageIkun({
    required String imagePath,
    required String operation,
    required String model,
    required String apiKey,
    required String baseUrl,
    String? prompt,
    int? defry,
  }) =>
      _processDirectorImageV1(
        imagePath: imagePath,
        operation: operation,
        model: model,
        apiKey: apiKey,
        baseUrl: baseUrl,
        prompt: prompt,
        defry: defry,
      );

  Future<Uint8List> _processDirectorImageV1({
    required String imagePath,
    required String operation,
    required String model,
    required String apiKey,
    required String baseUrl,
    String? prompt,
    int? defry,
    bool usesGatewayExtra = false,
  }) async {
    _configureAuth(apiKey, baseUrl);
    final bytes = await File(imagePath).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw ApiException(message: '无法读取图片，请选择有效的 PNG 或 JPEG 图片');
    }
    final body = <String, dynamic>{
      (usesGatewayExtra ? 'extra' : 'novelai_operation'): operation,
      'image': base64Encode(bytes),
      'width': image.width,
      'height': image.height,
      'model': model,
      'response_format': 'b64_json',
    };
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
              final rawBase64 = first['b64_json'] as String;
              final base64Data = rawBase64.contains(',')
                  ? rawBase64.substring(rawBase64.indexOf(',') + 1)
                  : rawBase64;
              return base64Decode(base64Data);
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

  Future<Uint8List> upscaleImage7877({
    required String imagePath,
    required String model,
    required String apiKey,
    required String baseUrl,
  }) async {
    _configureAuth(apiKey, baseUrl);
    final bytes = await File(imagePath).readAsBytes();
    try {
      final response = await _dio.post<List<int>>(
        ApiConstants.originUpscale,
        data: {'image': base64Encode(bytes), 'scale': 4},
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 5),
          headers: {'Accept': 'application/zip, image/png'},
        ),
      );
      return _extractNativeImageBytes(
        response.data,
        response.headers.value('content-type'),
        '4x 放大',
      );
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

    try {
      final route = NovelAiRoute.fromIds(task.endpointId, task.protocol);
      final usesUnifiedImageRoute = route.isGateway7877 || route.isIkun;
      final response = await _dio.post(
        usesUnifiedImageRoute
            ? ApiConstants.imageGenerations
            : ApiConstants.imageEdits,
        data: await _buildInpaintingBody(task),
        options: Options(
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 2),
        ),
      );
      final parsed = await _parseInpaintingResponse(response.data, task);
      return _downloadIfNeeded(parsed, apiKey);
    } on DioException catch (e) {
      throw ApiException(
        message: _handleDioError(e),
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
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
      'sampler': _normalizeIkunSampler(task.sampler),
      'noise_schedule': _normalizeIkunNoiseSchedule(task.noiseSchedule),
      'cfg_rescale': task.cfgRescale,
      if (task.seed != null) 'seed': task.seed,
      'response_format': responseFormat,
      'references': references,
    };
  }

  Future<String> encode7877VibeReference({
    required GenerationTask task,
    required CharacterReferenceImage reference,
    required String apiKey,
    required String baseUrl,
  }) async {
    if (NovelAiRoute.fromIds(task.endpointId, task.protocol).isIkun) {
      throw ApiException(
        message: 'ikun 的 Vibe 原图应随生成请求提交，由网关自动编码',
        code: 'IKUN_VIBE_ENCODING_VIA_GENERATION',
      );
    }
    _configureAuth(apiKey, baseUrl);
    final image = await _readReferenceIfAvailable(reference);
    if (image == null) {
      throw ApiException(message: '氛围参考图像不可用，请重新选择');
    }
    try {
      final response = await _dio.post(
        ApiConstants.imageGenerations,
        data: {
          'model':
              _is7877Task(task) ? _normalize7877Model(task.model) : task.model,
          'extra': 'encode-vibe',
          'image': image,
          'information_extracted': reference.informationExtracted,
        },
        options: Options(receiveTimeout: const Duration(minutes: 3)),
      );
      return _extractVibeEncoding(response.data);
    } on DioException catch (e) {
      throw ApiException(
        message: _handleDioError(e),
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  Future<Map<String, dynamic>> _build7877ImageGenerationsBody(
    GenerationTask task,
  ) async {
    if (_isV5Model(task.model) && task.vibeReferences.isNotEmpty) {
      throw ApiException(message: 'V5 模型不支持 Vibe 氛围参考');
    }
    final vibe = await _encode7877VibeReferencesV1(task);
    final characters = _buildCharacterPrompts(task.characters);
    return {
      'model': _normalize7877Model(task.model),
      'prompt': task.prompt,
      'n': 1,
      'size': '${task.width}x${task.height}',
      'width': task.width,
      'height': task.height,
      'response_format': 'b64_json',
      'params': {
        'steps': task.steps,
        'scale': task.scale,
        'cfg_rescale': task.cfgRescale,
        'sampler': _normalizeImageGenerationsSampler(task.sampler),
        'noise_schedule': _normalizeImageGenerationsNoiseSchedule(
          task.noiseSchedule,
        ),
        if (task.seed != null) 'seed': task.seed,
        if (task.negativePrompt != null && task.negativePrompt!.isNotEmpty)
          'negative_prompt': task.negativePrompt,
        'quality': true,
        'uc_preset': 'light',
        'sm': false,
        'sm_dyn': false,
        if (characters.isNotEmpty) 'characters': characters,
        if (characters.isNotEmpty) 'use_coords': task.useCoords,
        if (vibe.images.isNotEmpty) 'reference_image_multiple': vibe.images,
        if (vibe.images.isNotEmpty)
          'reference_strength_multiple': vibe.strengths,
        if (vibe.images.isNotEmpty)
          'reference_information_extracted_multiple': vibe.informationExtracted,
      },
    };
  }

  Future<
      ({
        List<String> images,
        List<double> strengths,
        List<double> informationExtracted
      })> _encode7877VibeReferencesV1(GenerationTask task) async {
    final images = <String>[];
    final strengths = <double>[];
    final informationExtracted = <double>[];
    for (var index = 0; index < task.vibeReferences.length; index++) {
      final reference = task.vibeReferences[index];
      final encoded = reference.encodedVibe?.isNotEmpty == true
          ? reference.encodedVibe!
          : await _encodeVibeReferenceV1(task, reference);
      images.add(encoded);
      strengths.add(reference.strength);
      informationExtracted.add(reference.informationExtracted);
    }
    return (
      images: images,
      strengths: strengths,
      informationExtracted: informationExtracted,
    );
  }

  Future<String> _encodeVibeReferenceV1(
    GenerationTask task,
    CharacterReferenceImage reference,
  ) async {
    final image = await _readReferenceIfAvailable(reference);
    if (image == null) {
      throw ApiException(message: '氛围参考图像不可用，请重新选择');
    }
    try {
      final response = await _dio.post(
        ApiConstants.imageGenerations,
        data: {
          'model':
              _is7877Task(task) ? _normalize7877Model(task.model) : task.model,
          'extra': 'encode-vibe',
          'image': image,
          'information_extracted': reference.informationExtracted,
        },
        options: Options(receiveTimeout: const Duration(minutes: 3)),
      );
      return _extractVibeEncoding(response.data);
    } on DioException catch (e) {
      throw ApiException(
        message: _handleDioError(e),
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  String _extractVibeEncoding(dynamic data) {
    final images = data is Map ? data['data'] : null;
    final first = images is List && images.isNotEmpty ? images.first : null;
    final value = first is Map
        ? first['b64_json'] ?? first['encoding'] ?? first['encoded_vibe']
        : null;
    if (value is! String || value.isEmpty) {
      throw ApiException(message: '氛围参考图像编码失败');
    }
    return value;
  }

  // 保留原生请求构造，供未来显式 /origin 模式调用。
  Future<Map<String, dynamic>> _build7877NativeGenerationBody(
    GenerationTask task,
  ) async {
    final action = task.sourceImagePath != null && task.maskImagePath != null
        ? 'infill'
        : task.img2imgSourceImagePath != null
            ? 'img2img'
            : 'generate';
    final parameters = <String, dynamic>{
      'params_version': 3,
      'width': task.width,
      'height': task.height,
      'steps': task.steps.clamp(1, 28),
      'scale': task.scale,
      'sampler': task.sampler,
      if (task.seed != null) 'seed': task.seed,
      'n_samples': 1,
      'noise_schedule': task.noiseSchedule == 'native'
          ? ApiConstants.defaultNoiseSchedule
          : task.noiseSchedule,
      'cfg_rescale': task.cfgRescale,
      'negative_prompt': task.negativePrompt ?? '',
      'qualityToggle': true,
      'ucPreset': 1,
      'sm': false,
      'sm_dyn': false,
    };

    if (action == 'img2img') {
      final sourcePath = task.img2imgSourceImagePath!;
      final source = File(sourcePath);
      if (!await source.exists()) {
        throw ApiException(message: '图生图源图不可用，请重新选择');
      }
      parameters['image'] = base64Encode(await source.readAsBytes());
      parameters['strength'] = task.img2imgStrength ?? 0.7;
      parameters['noise'] = 0.2;
    }

    if (action == 'infill') {
      final sourcePath = task.sourceImagePath;
      final maskPath = task.maskImagePath;
      if (sourcePath == null || sourcePath.isEmpty) {
        throw ApiException(message: '局部重绘缺少原图');
      }
      if (maskPath == null || maskPath.isEmpty) {
        throw ApiException(message: '局部重绘缺少遮罩图');
      }
      final source = File(sourcePath);
      final mask = File(maskPath);
      if (!await source.exists()) {
        throw ApiException(message: '局部重绘原图不可用，请重新选择');
      }
      if (!await mask.exists()) {
        throw ApiException(message: '局部重绘遮罩图不可用，请重新绘制');
      }
      parameters['image'] = base64Encode(await source.readAsBytes());
      parameters['mask'] = base64Encode(await mask.readAsBytes());
    }

    final isV5 = _isV5Model(task.model);
    if (isV5 && task.width * task.height > 1024 * 1024) {
      throw ApiException(message: 'V5 模型要求总像素不超过 1024×1024');
    }
    if (!isV5) {
      final characters = _buildNativeCharacterPrompts(task.characters);
      if (characters.isNotEmpty) {
        parameters['characterPrompts'] = characters;
        parameters['use_coords'] = task.useCoords;
      }

      final vibe = await _encode7877VibeReferences(task);
      if (vibe.images.isNotEmpty) {
        parameters['reference_image_multiple'] = vibe.images;
        parameters['reference_strength_multiple'] = vibe.strengths;
        parameters['reference_information_extracted_multiple'] =
            vibe.informationExtracted;
      }
    }

    return {
      'input': task.prompt,
      'model': _normalize7877Model(
        action == 'infill' ? _nativeInpaintingModel(task.model) : task.model,
      ),
      'action': action,
      'parameters': parameters,
    };
  }

  List<Map<String, dynamic>> _buildNativeCharacterPrompts(
    List<CharacterSpec>? characters,
  ) {
    if (characters == null) return const [];
    return characters.where((character) => character.enabled).map((character) {
      return {
        'prompt': character.prompt,
        'uc': character.uc ?? '',
        if (character.centerX != null && character.centerY != null)
          'center': {'x': character.centerX, 'y': character.centerY},
      };
    }).toList();
  }

  String _nativeInpaintingModel(String model) {
    final normalized = _normalize7877Model(model);
    if (normalized.endsWith('-inpainting')) return normalized;
    return '$normalized-inpainting';
  }

  Future<
      ({
        List<String> images,
        List<double> strengths,
        List<double> informationExtracted
      })> _encode7877VibeReferences(GenerationTask task) async {
    final images = <String>[];
    final strengths = <double>[];
    final informationExtracted = <double>[];
    for (var index = 0; index < task.vibeReferences.length; index++) {
      final reference = task.vibeReferences[index];
      final preEncoded = reference.encodedVibe;
      if (preEncoded != null && preEncoded.isNotEmpty) {
        images.add(preEncoded);
        strengths.add(reference.strength);
        informationExtracted.add(reference.informationExtracted);
        continue;
      }
      final image = await _readReferenceIfAvailable(reference);
      if (image == null) {
        throw ApiException(message: '氛围参考图像 ${index + 1} 不可用，请重新选择');
      }
      final response = await _dio.post(
        ApiConstants.originEncodeVibe,
        data: {
          'image': image,
          'information_extracted': reference.informationExtracted,
        },
        options: Options(receiveTimeout: const Duration(minutes: 3)),
      );
      final data = response.data;
      final encoded = data is Map ? data['data'] : null;
      final first =
          encoded is List && encoded.isNotEmpty ? encoded.first : null;
      final value = first is Map
          ? first['encoding'] ?? first['encoded_vibe'] ?? first['b64_json']
          : null;
      if (value is! String || value.isEmpty) {
        throw ApiException(message: '氛围参考图像 ${index + 1} 编码失败');
      }
      images.add(value);
      strengths.add(reference.strength);
      informationExtracted.add(reference.informationExtracted);
    }
    return (
      images: images,
      strengths: strengths,
      informationExtracted: informationExtracted,
    );
  }

  bool _is7877Task(GenerationTask task) =>
      NovelAiRoute.fromIds(task.endpointId, task.protocol).isGateway7877;

  bool _isV5Model(String model) =>
      model.trim().toLowerCase().contains('diffusion-5') ||
      model.trim().toLowerCase().contains('v5');

  bool _isV5MediumModel(String model) => const {
        'nai-v5-full-medium',
        'nai-v5-inpaint-medium',
        'nai-diffusion-5-full-medium',
        'nai-diffusion-5-full-medium-inpainting',
      }.contains(model.trim().toLowerCase());

  String _normalize7877Model(String model) {
    final normalized = model.trim().toLowerCase();
    return switch (normalized) {
      'nai-v5-full' => 'nai-diffusion-5-full',
      'nai-v5-full-medium' => 'nai-diffusion-5-full-medium',
      'nai-v5-inpaint' => 'nai-diffusion-5-full-inpainting',
      'nai-v5-inpaint-medium' => 'nai-diffusion-5-full-medium-inpainting',
      'nai-v4.5-full' || 'nai-v4-5-full' => 'nai-diffusion-4-5-full',
      'nai-v4.5-curated' || 'nai-v4-5-curated' => 'nai-diffusion-4-5-curated',
      'nai-v4-full' => 'nai-diffusion-4-full',
      'nai-v4-curated' => 'nai-diffusion-4-curated',
      'nai-v3' => 'nai-diffusion-3',
      'nai-v3-furry' || 'nai-v3-furry-limit' => 'nai-diffusion-3-furry',
      _ => model,
    };
  }

  String _v5MediumRequestModel(
    String model, {
    required bool is7877,
    required bool inpainting,
  }) {
    final normalized = model.trim().toLowerCase();
    if (is7877) {
      final gatewayModel = _normalize7877Model(normalized);
      return inpainting ? _nativeInpaintingModel(gatewayModel) : gatewayModel;
    }
    if (!inpainting) return normalized;
    return switch (normalized) {
      'nai-v5-full-medium' => 'nai-v5-inpaint-medium',
      'nai-diffusion-5-full-medium' => 'nai-diffusion-5-full-medium-inpainting',
      _ => normalized,
    };
  }

  void _rejectV5MediumReferences(GenerationTask task) {
    if (task.vibeReferences.isEmpty && task.preciseReferences.isEmpty) return;
    throw ApiException(
      message: 'V5 Medium 当前不支持 Vibe 或精密参照，请先移除参考图',
      code: 'V5_MEDIUM_REFERENCES_UNSUPPORTED',
    );
  }

  Future<Map<String, dynamic>> _buildV5MediumImageGenerationsBody(
    GenerationTask task, {
    required bool is7877,
    String? operation,
  }) async {
    _rejectV5MediumReferences(task);
    if (task.width <= 0 ||
        task.height <= 0 ||
        task.width % 64 != 0 ||
        task.height % 64 != 0 ||
        task.width * task.height > 1048576) {
      throw ApiException(
        message: 'V5 Medium 要求宽高为正数、64 的倍数，且总像素不超过 1048576',
        code: 'V5_MEDIUM_DIMENSIONS_UNSUPPORTED',
      );
    }

    final characters = _buildIkunCharacterPrompts(_enabledCharacters(task));
    final body = <String, dynamic>{
      if (operation != null) 'novelai_operation': operation,
      'model': _v5MediumRequestModel(
        task.model,
        is7877: is7877,
        inpainting: operation == 'inpainting',
      ),
      'prompt': task.prompt,
      'n': 1,
      'size': '${task.width}x${task.height}',
      'width': task.width,
      'height': task.height,
      'steps': 14,
      'scale': task.scale,
      'sampler': 'k_euler_ancestral',
      'noise_schedule': is7877
          ? _normalizeImageGenerationsNoiseSchedule(task.noiseSchedule)
          : _normalizeIkunNoiseSchedule(task.noiseSchedule),
      if (task.seed != null) 'seed': task.seed,
      'ucPreset': 0,
      'tag_hint_uc_preset': 2,
      if (characters.isNotEmpty) 'characterPrompts': characters,
      if (characters.isNotEmpty) 'use_coords': task.useCoords,
      'response_format': 'b64_json',
    };

    if (operation == 'img2img') {
      final sourcePath = task.img2imgSourceImagePath;
      if (sourcePath == null || sourcePath.isEmpty) {
        throw ApiException(message: '图生图缺少源图');
      }
      final source = File(sourcePath);
      if (!await source.exists()) {
        throw ApiException(message: '图生图源图不可用，请重新选择');
      }
      body.addAll({
        'image': base64Encode(await source.readAsBytes()),
        'strength': task.img2imgStrength ?? 0.7,
        'noise': 0.0,
        'color_correct': task.colorCorrect,
      });
    } else if (operation == 'inpainting') {
      final sourcePath = task.sourceImagePath;
      final maskPath = task.maskImagePath;
      if (sourcePath == null || sourcePath.isEmpty) {
        throw ApiException(message: '局部重绘缺少原图');
      }
      if (maskPath == null || maskPath.isEmpty) {
        throw ApiException(message: '局部重绘缺少遮罩图');
      }
      final source = File(sourcePath);
      final mask = File(maskPath);
      if (!await source.exists()) {
        throw ApiException(message: '局部重绘原图不可用，请重新选择');
      }
      if (!await mask.exists()) {
        throw ApiException(message: '局部重绘遮罩图不可用，请重新绘制');
      }
      body.addAll({
        'image': base64Encode(await source.readAsBytes()),
        'mask': base64Encode(await mask.readAsBytes()),
        'strength': task.inpaintStrength ?? 1.0,
        'noise': 0.0,
        'add_original_image': !task.disabledOriginalImage,
        'color_correct': task.colorCorrect,
      });
    }

    return body;
  }

  Future<Map<String, dynamic>> _buildImg2ImgBody(
    GenerationTask task, {
    required bool isIkun,
  }) async {
    final sourcePath = task.img2imgSourceImagePath;
    if (sourcePath == null || sourcePath.isEmpty) {
      throw ApiException(message: '图生图缺少源图');
    }
    final file = File(sourcePath);
    if (!await file.exists()) {
      throw ApiException(message: '图生图源图不可用，请重新选择');
    }

    if (!isIkun) {
      final characterPrompts = _buildCharacterPrompts(task.characters);
      return {
        'model': _normalize7877Model(task.model),
        'prompt': task.prompt,
        'image': base64Encode(await file.readAsBytes()),
        'strength': task.img2imgStrength ?? 0.7,
        'noise': 0.0,
        'color_correct': true,
        'n': 1,
        'size': '${task.width}x${task.height}',
        'response_format': 'b64_json',
        'params': {
          'steps': task.steps,
          'scale': task.scale,
          'cfg_rescale': task.cfgRescale,
          'sampler': _normalizeImageGenerationsSampler(task.sampler),
          'noise_schedule': _normalizeImageGenerationsNoiseSchedule(
            task.noiseSchedule,
          ),
          if (task.seed != null) 'seed': task.seed,
          if (task.negativePrompt != null && task.negativePrompt!.isNotEmpty)
            'negative_prompt': task.negativePrompt,
          'quality': true,
          'uc_preset': 'light',
          if (characterPrompts.isNotEmpty) 'characters': characterPrompts,
          if (characterPrompts.isNotEmpty) 'use_coords': task.useCoords,
        },
      };
    }

    if (_enabledCharacters(task).isNotEmpty) {
      throw ApiException(
        message: 'ikun 网关当前不支持图生图与多角色控制同时使用，请先移除角色控制',
        code: 'IKUN_CHARACTERS_IMG2IMG_UNSUPPORTED',
      );
    }
    if (task.vibeReferences.isNotEmpty || task.preciseReferences.isNotEmpty) {
      throw ApiException(
        message: 'ikun 网关当前不支持图生图与参考图同时使用，请先移除其中一种参考',
        code: 'IKUN_REFERENCES_IMG2IMG_UNSUPPORTED',
      );
    }

    return {
      'novelai_operation': 'img2img',
      'model': task.model,
      'prompt': task.prompt,
      if (task.negativePrompt != null && task.negativePrompt!.isNotEmpty)
        'negative_prompt': task.negativePrompt,
      'image': base64Encode(await file.readAsBytes()),
      'width': task.width,
      'height': task.height,
      'strength': task.img2imgStrength ?? 0.7,
      'noise': 0.0,
      'steps': task.steps,
      'scale': task.scale,
      'cfg_rescale': task.cfgRescale,
      'sampler': _normalizeIkunSampler(task.sampler),
      'noise_schedule': _normalizeIkunNoiseSchedule(task.noiseSchedule),
      if (task.seed != null) 'seed': task.seed,
      'response_format': 'b64_json',
    };
  }

  Future<Map<String, dynamic>> _buildImageGenerationsBody(
      GenerationTask task) async {
    if (task.vibeReferences.length > AppConstants.maxIkunVibeReferences) {
      throw ApiException(
        message: 'ikun 渠道当前仅支持 4 条 Vibe 氛围参考，请移除多余参考图',
        code: 'IKUN_VIBE_LIMIT',
      );
    }
    final referenceImages = <String>[];
    for (var index = 0; index < task.vibeReferences.length; index++) {
      final reference = task.vibeReferences[index];
      final image = reference.encodedVibe?.isNotEmpty == true
          ? reference.encodedVibe
          : await _readReferenceIfAvailable(reference);
      if (image == null || image.isEmpty) {
        throw ApiException(message: '氛围参考图像 ${index + 1} 不可用，请重新选择');
      }
      referenceImages.add(image);
    }
    final characters = _enabledCharacters(task);
    final characterPrompts = _buildIkunCharacterPrompts(characters);
    final characterNegativePrompt =
        _buildIkunCharacterNegativePrompt(task, characters);
    return {
      'prompt': task.prompt,
      'model': task.model,
      'n': 1,
      'size': '${task.width}x${task.height}',
      'width': task.width,
      'height': task.height,
      'steps': task.steps,
      'scale': task.scale,
      'cfg_rescale': task.cfgRescale,
      'sampler': _normalizeIkunSampler(task.sampler),
      'noise_schedule': _normalizeIkunNoiseSchedule(task.noiseSchedule),
      if (task.seed != null) 'seed': task.seed,
      if (task.negativePrompt != null && task.negativePrompt!.isNotEmpty)
        'negative_prompt': task.negativePrompt,
      if (characterPrompts.isNotEmpty) 'characterPrompts': characterPrompts,
      if (characterPrompts.isNotEmpty) 'use_coords': task.useCoords,
      if (characterNegativePrompt != null)
        'v4_negative_prompt': characterNegativePrompt,
      if (referenceImages.length == 1)
        'reference_image': referenceImages.single,
      if (referenceImages.length > 1) 'reference_images': referenceImages,
      if (referenceImages.length == 1)
        'reference_strength': task.vibeReferences.single.strength,
      if (referenceImages.length == 1)
        'reference_information_extracted':
            task.vibeReferences.single.informationExtracted,
      if (referenceImages.length > 1)
        'reference_strength_multiple':
            task.vibeReferences.map((reference) => reference.strength).toList(),
      if (referenceImages.length > 1)
        'reference_information_extracted_multiple': task.vibeReferences
            .map((reference) => reference.informationExtracted)
            .toList(),
      'response_format': 'b64_json',
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
    final normalized = sampler.trim().toLowerCase();
    return ApiConstants.supportedSamplers.contains(normalized)
        ? normalized
        : ApiConstants.defaultSampler;
  }

  String _normalizeIkunSampler(String sampler) {
    final normalized = sampler.trim().toLowerCase();
    return ApiConstants.ikunSupportedSamplers.contains(normalized)
        ? normalized
        : ApiConstants.defaultSampler;
  }

  String _normalizeImageGenerationsNoiseSchedule(String noiseSchedule) {
    final normalized = noiseSchedule.trim().toLowerCase();
    return ApiConstants.supportedNoiseSchedules.contains(normalized)
        ? normalized
        : ApiConstants.defaultNoiseSchedule;
  }

  String _normalizeIkunNoiseSchedule(String noiseSchedule) {
    final normalized = noiseSchedule.trim().toLowerCase();
    return ApiConstants.ikunSupportedNoiseSchedules.contains(normalized)
        ? normalized
        : ApiConstants.defaultNoiseSchedule;
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

  List<CharacterSpec> _enabledCharacters(GenerationTask task) =>
      task.characters?.where((character) => character.enabled).toList() ??
      const [];

  List<Map<String, dynamic>> _buildIkunCharacterPrompts(
    List<CharacterSpec> characters,
  ) =>
      characters
          .map((character) => {
                'prompt': character.prompt,
                if (character.centerX != null && character.centerY != null)
                  'center': {
                    'x': character.centerX,
                    'y': character.centerY,
                  },
              })
          .toList();

  Map<String, dynamic>? _buildIkunCharacterNegativePrompt(
    GenerationTask task,
    List<CharacterSpec> characters,
  ) {
    if (characters.isEmpty ||
        !characters.any((character) => character.uc?.isNotEmpty == true)) {
      return null;
    }
    return {
      'caption': {
        'base_caption': task.negativePrompt ?? '',
        'char_captions': characters
            .map((character) => {
                  'char_caption': character.uc ?? '',
                  'centers':
                      character.centerX != null && character.centerY != null
                          ? [
                              {
                                'x': character.centerX,
                                'y': character.centerY,
                              }
                            ]
                          : const <Map<String, dynamic>>[],
                })
            .toList(),
      },
      'legacy_uc': false,
    };
  }

  Future<GenerationTask> _parseImageGenerationResponse(
    dynamic data,
    GenerationTask originalTask,
    String apiKey,
  ) async {
    final parsed = await _parseImageResponse(data, originalTask);
    return _downloadIfNeeded(parsed, apiKey);
  }

  Future<GenerationTask> _parseImageResponse(
    dynamic data,
    GenerationTask originalTask,
  ) async {
    if (data is List<int>) {
      return _parseImageResponse(
        utf8.decode(data, allowMalformed: true),
        originalTask,
      );
    }
    if (data is String) {
      try {
        return _parseImageResponse(jsonDecode(data), originalTask);
      } on FormatException {
        return originalTask.copyWith(
          status: 'failed',
          errorMessage: '接口返回的图片数据不是有效 JSON',
          completedAt: DateTime.now(),
        );
      }
    }
    if (data is Map) {
      final images = data['data'];
      if (images is List && images.isNotEmpty && images.first is Map) {
        final imageData = images.first as Map;
        final url = imageData['url'];
        if (url is String && url.isNotEmpty) {
          return originalTask.copyWith(
            status: 'success',
            imageUrl: url,
            completedAt: DateTime.now(),
          );
        }
        final rawBase64 = imageData['b64_json'];
        if (rawBase64 is String && rawBase64.isNotEmpty) {
          try {
            final base64Data = rawBase64.contains(',')
                ? rawBase64.substring(rawBase64.indexOf(',') + 1)
                : rawBase64;
            final filePath = await ImageUtils.saveBase64Image(
              base64Data,
              ImageUtils.generateFilename(),
            );
            return originalTask.copyWith(
              status: 'success',
              imagePath: filePath,
              completedAt: DateTime.now(),
            );
          } on FormatException {
            return originalTask.copyWith(
              status: 'failed',
              errorMessage: '接口返回的 b64_json 无效',
              completedAt: DateTime.now(),
            );
          }
        }
      }
      final error = data['error'];
      final message = error is Map ? error['message'] : null;
      return originalTask.copyWith(
        status: 'failed',
        errorMessage: message?.toString() ?? '接口未返回图片数据',
        completedAt: DateTime.now(),
      );
    }
    return originalTask.copyWith(
      status: 'failed',
      errorMessage: '接口未返回有效图片响应',
      completedAt: DateTime.now(),
    );
  }

  Future<GenerationTask> _saveNativeImageResponse(
    List<int>? data,
    String? contentType,
    GenerationTask originalTask,
    String featureName,
  ) async {
    final bytes = _extractNativeImageBytes(data, contentType, featureName);
    final filePath = await _saveNativeImageBytes(bytes);
    return originalTask.copyWith(
      status: 'success',
      imagePath: filePath,
      completedAt: DateTime.now(),
    );
  }

  Uint8List _extractNativeImageBytes(
    List<int>? data,
    String? contentType,
    String featureName,
  ) {
    if (data == null || data.isEmpty) {
      throw ApiException(message: '$featureName未返回图片数据');
    }
    final bytes = Uint8List.fromList(data);
    final isZip = contentType?.toLowerCase().contains('zip') == true ||
        (bytes.length >= 4 &&
            bytes[0] == 0x50 &&
            bytes[1] == 0x4b &&
            bytes[2] == 0x03 &&
            bytes[3] == 0x04);
    if (!isZip) return bytes;

    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final name = entry.name.toLowerCase();
        if (name.endsWith('.png') ||
            name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.webp')) {
          final entryBytes = entry.readBytes();
          if (entryBytes != null && entryBytes.isNotEmpty) {
            return Uint8List.fromList(entryBytes);
          }
        }
      }
    } catch (_) {
      throw ApiException(message: '$featureName返回的 ZIP 无效');
    }
    throw ApiException(message: '$featureName返回的 ZIP 中没有图片');
  }

  Future<String> _saveNativeImageBytes(Uint8List bytes) async {
    final dir = await ImageUtils.getImageDirectory();
    final filePath =
        '${dir.path}${Platform.pathSeparator}${ImageUtils.generateFilename()}';
    await File(filePath).writeAsBytes(bytes);
    return filePath;
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
    final sourceImagePath = task.sourceImagePath;
    final maskImagePath = task.maskImagePath;
    if (sourceImagePath == null || sourceImagePath.isEmpty) {
      throw ApiException(message: '局部重绘缺少原图');
    }
    if (maskImagePath == null || maskImagePath.isEmpty) {
      throw ApiException(message: '局部重绘缺少遮罩图');
    }

    final source = File(sourceImagePath);
    final mask = File(maskImagePath);
    if (!await source.exists()) {
      throw ApiException(message: '局部重绘原图不可用，请重新选择');
    }
    if (!await mask.exists()) {
      throw ApiException(message: '局部重绘遮罩图不可用，请重新绘制');
    }

    final route = NovelAiRoute.fromIds(task.endpointId, task.protocol);
    final is7877 = route.isGateway7877;
    if ((is7877 || route.isIkun) && _isV5MediumModel(task.model)) {
      return _buildV5MediumImageGenerationsBody(
        task,
        is7877: is7877,
        operation: 'inpainting',
      );
    }
    if (is7877) {
      final characterPrompts = _buildCharacterPrompts(_enabledCharacters(task));
      return {
        'model': _normalize7877Model(task.model),
        'prompt': task.prompt,
        'image': base64Encode(await source.readAsBytes()),
        'mask': base64Encode(await mask.readAsBytes()),
        'strength': task.inpaintStrength ?? 1.0,
        'n': 1,
        'size': '${task.width}x${task.height}',
        'response_format': 'b64_json',
        'params': {
          'steps': task.steps,
          'scale': task.scale,
          'cfg_rescale': task.cfgRescale,
          'sampler': _normalizeImageGenerationsSampler(task.sampler),
          'noise_schedule': _normalizeImageGenerationsNoiseSchedule(
            task.noiseSchedule,
          ),
          if (task.seed != null) 'seed': task.seed,
          if (task.negativePrompt != null && task.negativePrompt!.isNotEmpty)
            'negative_prompt': task.negativePrompt,
          'quality': true,
          'uc_preset': 'light',
          if (characterPrompts.isNotEmpty) 'characters': characterPrompts,
          if (characterPrompts.isNotEmpty) 'use_coords': task.useCoords,
        },
      };
    }

    final characters = _enabledCharacters(task);
    final characterPrompts = _buildIkunCharacterPrompts(characters);
    final characterNegativePrompt =
        _buildIkunCharacterNegativePrompt(task, characters);

    return {
      'novelai_operation': 'inpainting',
      'model': task.model,
      'prompt': task.prompt,
      if (task.negativePrompt != null && task.negativePrompt!.isNotEmpty)
        'negative_prompt': task.negativePrompt,
      'image': base64Encode(await source.readAsBytes()),
      'mask': base64Encode(await mask.readAsBytes()),
      'strength': task.inpaintStrength ?? 1.0,
      'noise': 0.0,
      'add_original_image': !task.disabledOriginalImage,
      'color_correct': task.colorCorrect,
      'n': 1,
      'size': '${task.width}x${task.height}',
      'width': task.width,
      'height': task.height,
      'steps': task.steps,
      'scale': task.scale,
      'cfg_rescale': task.cfgRescale,
      'sampler': _normalizeIkunSampler(task.sampler),
      'noise_schedule': _normalizeIkunNoiseSchedule(task.noiseSchedule),
      if (task.seed != null) 'seed': task.seed,
      if (route.isIkun && characterPrompts.isNotEmpty)
        'characterPrompts': characterPrompts,
      if (route.isIkun && characterPrompts.isNotEmpty)
        'use_coords': task.useCoords,
      if (route.isIkun && characterNegativePrompt != null)
        'v4_negative_prompt': characterNegativePrompt,
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
    return _parseImageResponse(data, originalTask);
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
      final response = await _dio.get(
        ApiConstants.models,
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
