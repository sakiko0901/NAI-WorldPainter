import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/domain/entities/director_tool.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/novelai_connection.dart';

/// 官方专用超分模型（与官方 Web 客户端一致，不随生成模型变化）。
const String officialUpscaleModel = 'nai-diffusion-5-curated';

class OfficialNovelAiAccount {
  final String? tier;
  final int? anlas;
  final double? v5UsagePercent;

  /// 订阅赠送 Anlas（fixedTrainingStepsLeft）。
  final int? fixedTrainingStepsLeft;

  /// 购买的 Anlas（purchasedTrainingSteps）。
  final int? purchasedTrainingSteps;

  /// 剩余总点数 = fixed + purchased。
  int? get totalTrainingSteps {
    if (fixedTrainingStepsLeft == null && purchasedTrainingSteps == null) {
      return anlas;
    }
    return (fixedTrainingStepsLeft ?? 0) + (purchasedTrainingSteps ?? 0);
  }

  const OfficialNovelAiAccount({
    this.tier,
    this.anlas,
    this.v5UsagePercent,
    this.fixedTrainingStepsLeft,
    this.purchasedTrainingSteps,
  });
}

/// 官方订阅信息与 Opus V5 体力，来自 /user/subscription。
class OfficialNovelAiV5Usage {
  /// 剩余百分比（0-100），即官网汉堡菜单里那条体力条。
  final double? percent;

  /// 是否已扣穿：true 时免费 V5 额度用完，再出图会开始扣 Anlas。
  final bool isNegative;

  /// 下一次补充的 Unix 时间戳（秒）。
  final int? nextRefill;

  /// 订阅档位（3 = Opus）。
  final int? tier;

  /// 已付费订阅周期的结束时间；取消自动续费后仍然有效。
  final DateTime? expiresAt;

  /// 订阅赠送 Anlas（fixedTrainingStepsLeft）。
  final int? fixedTrainingStepsLeft;

  /// 购买的 Anlas（purchasedTrainingSteps）。
  final int? purchasedTrainingSteps;

  /// 剩余总点数 = fixed + purchased。
  int? get totalAnlas {
    if (fixedTrainingStepsLeft == null && purchasedTrainingSteps == null) {
      return null;
    }
    return (fixedTrainingStepsLeft ?? 0) + (purchasedTrainingSteps ?? 0);
  }

  const OfficialNovelAiV5Usage({
    required this.percent,
    required this.isNegative,
    this.nextRefill,
    this.tier,
    this.expiresAt,
    this.fixedTrainingStepsLeft,
    this.purchasedTrainingSteps,
  });
}

/// Native NovelAI transport, isolated from the app's generic gateway clients.
/// A relay uses a separate client and a separately stored credential.
class OfficialNovelAiApiService {
  final Dio _dio;
  final bool _isCustom;

  OfficialNovelAiApiService([Dio? dio])
      : _isCustom = false,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: ApiConstants.officialImageBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(minutes: 5),
              sendTimeout: const Duration(minutes: 1),
              headers: const {
                'Accept': 'application/zip, application/octet-stream, image/png'
              },
            ));

  OfficialNovelAiApiService._custom(this._dio) : _isCustom = true;

  OfficialNovelAiApiService forBaseUrl(String baseUrl) {
    final error = NovelAiConnection.validateBaseUrl(baseUrl);
    if (error != null) throw ApiException(message: error);
    if (!NovelAiConnection.isCustomBaseUrl(baseUrl)) {
      return _isCustom ? OfficialNovelAiApiService() : this;
    }
    return OfficialNovelAiApiService._custom(_dio.clone(
      options: _dio.options.copyWith(
        baseUrl: NovelAiConnection.normalizeBaseUrl(baseUrl),
        followRedirects: false,
      ),
    ));
  }

  Options _options(String token,
          {ResponseType responseType = ResponseType.bytes}) =>
      Options(
        responseType: responseType,
        headers: {'Authorization': 'Bearer ${token.trim()}'},
      );

  Future<OfficialNovelAiAccount> verifyToken(String token) async {
    if (_isCustom) {
      throw ApiException(message: '自定义渠道不查询 NovelAI 官方账户');
    }
    if (token.trim().isEmpty) {
      throw ApiException(message: '请先填写 NovelAI Persistent API Token');
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        ApiConstants.officialUserData,
        options: _options(token, responseType: ResponseType.json),
      );
      final root = response.data ?? const <String, dynamic>{};
      final info = _map(root['information']) ?? _map(root['data']) ?? root;
      final subscription =
          _map(info['subscription']) ?? _map(root['subscription']);
      final anlasValue =
          info['anlas'] ?? root['anlas'] ?? subscription?['anlas'];
      final usage = _map(info['opus_usage']) ?? _map(root['opus_usage']);
      final percent = usage?['percent'] ?? usage?['usage'];
      final training = _map(subscription?['trainingStepsLeft']) ??
          _map(info['trainingStepsLeft']);
      int? parseNum(Object? value) => value is num
          ? value.round()
          : value != null
              ? int.tryParse('$value')
              : null;
      return OfficialNovelAiAccount(
        tier: (subscription?['tier'] ?? subscription?['plan'] ?? info['tier'])
            ?.toString(),
        anlas: parseNum(anlasValue),
        v5UsagePercent:
            percent is num ? percent.toDouble() : double.tryParse('$percent'),
        fixedTrainingStepsLeft: parseNum(training?['fixedTrainingStepsLeft']),
        purchasedTrainingSteps: parseNum(training?['purchasedTrainingSteps']),
      );
    } on DioException catch (error) {
      throw _error(error, '验证官方 Token 失败');
    }
  }

  /// 查询官方订阅到期时间、Anlas 与 Opus V5 体力（免费额度剩余）。
  Future<OfficialNovelAiV5Usage?> fetchV5Usage(String token) async {
    if (_isCustom) return null;
    if (token.trim().isEmpty) {
      throw ApiException(message: '请先填写 NovelAI Persistent API Token');
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        ApiConstants.officialUserSubscription,
        options: _options(token, responseType: ResponseType.json),
      );
      final root = response.data ?? const <String, dynamic>{};
      final info = _map(root['information']) ?? _map(root['data']) ?? root;
      final subscription =
          _map(info['subscription']) ?? _map(root['subscription']) ?? info;
      if (subscription.isEmpty) return null;
      // usage 可能出现在 subscription.usage / subscription.activeExperiment
      // 等位置，逐层兜底解析。
      Map<String, dynamic>? usage = _map(subscription['usage']);
      usage ??= _map(subscription['opus_usage']);
      if (usage == null) {
        // 遍历 subscription 顶层字段找带 percent 的 usage 形状。
        for (final value in subscription.values) {
          final candidate = _map(value);
          if (candidate != null &&
              candidate.containsKey('percent') &&
              (candidate.containsKey('isNegative') ||
                  candidate.containsKey('nextRefill'))) {
            usage = candidate;
            break;
          }
        }
      }
      final percentValue = usage?['percent'];
      final percent = percentValue is num
          ? percentValue.toDouble()
          : double.tryParse('$percentValue');
      final nextRefillValue = usage?['nextRefill'];
      final training = _map(subscription['trainingStepsLeft']);
      int? parseNum(Object? value) => value is num
          ? value.round()
          : value != null
              ? int.tryParse('$value')
              : null;
      final expiresAtSeconds = parseNum(subscription['expiresAt']);
      return OfficialNovelAiV5Usage(
        percent:
            percent != null && percent.isFinite ? percent.clamp(0, 100) : null,
        isNegative: usage?['isNegative'] == true,
        expiresAt: expiresAtSeconds != null &&
                expiresAtSeconds > 0 &&
                expiresAtSeconds <= 8640000000000
            ? DateTime.fromMillisecondsSinceEpoch(expiresAtSeconds * 1000,
                isUtc: true)
            : null,
        nextRefill: nextRefillValue is int
            ? nextRefillValue
            : int.tryParse('$nextRefillValue'),
        tier: subscription['tier'] is int
            ? subscription['tier'] as int
            : int.tryParse('${subscription['tier']}'),
        fixedTrainingStepsLeft: parseNum(training?['fixedTrainingStepsLeft']),
        purchasedTrainingSteps: parseNum(training?['purchasedTrainingSteps']),
      );
    } on DioException catch (error) {
      throw _error(error, '查询 V5 体力失败');
    }
  }

  Future<GenerationTask> generateImage(
      GenerationTask task, String token) async {
    if (token.trim().isEmpty) {
      throw ApiException(
          message: '请先在 API 配置中填写 NovelAI 官方 Token', code: 'NO_OFFICIAL_TOKEN');
    }
    try {
      final payload = await buildPayload(task);
      final hasPrecise = task.preciseReferences.isNotEmpty;
      final response = hasPrecise
          ? await _dio.post<List<int>>(
              ApiConstants.officialGenerateImage,
              data: await _buildMultipart(payload, task),
              options: _options(token),
            )
          : await _dio.post<List<int>>(
              ApiConstants.officialGenerateImage,
              data: payload,
              options: _options(token),
            );
      final filePath =
          await _saveImage(_extractImageBytes(response.data, '生成'));
      return task.copyWith(
        status: 'success',
        imagePath: filePath,
        completedAt: DateTime.now(),
      );
    } on DioException catch (error) {
      throw _error(error, '官方生图失败');
    }
  }

  /// 流式生成：官方 V4/V4.5/V5 模型可用（V3 与精确参考 multipart 不支持）。
  ///
  /// 协议（参考 NekoAI-JS StreamingMsgpackParser）：
  /// 响应为重复的 [4字节大端长度][MessagePack 消息体]；
  /// msgpack 字段 event_type = "intermediate"（JPEG 预览）/ "final"（PNG 成品），
  /// image 字段直接是原始字节。每帧回调 onFrame(imageBytes, step, total?)。
  Future<GenerationTask> generateImageStream(
    GenerationTask task,
    String token, {
    void Function(Uint8List imageBytes, int? step)? onFrame,
  }) async {
    if (token.trim().isEmpty) {
      throw ApiException(
          message: '请先在 API 配置中填写 NovelAI 官方 Token', code: 'NO_OFFICIAL_TOKEN');
    }
    try {
      final payload = await buildPayload(task);
      (payload['parameters'] as Map<String, dynamic>)['stream'] = 'msgpack';
      final response = await _dio.post<ResponseBody>(
        ApiConstants.officialGenerateImageStream,
        data: payload,
        options: _options(token, responseType: ResponseType.stream),
      );
      final stream = response.data!;
      Uint8List? finalImage;
      final buffer = BytesBuilder();
      await for (final chunk in stream.stream) {
        buffer.add(chunk);
        final data = buffer.toBytes();
        var pos = 0;
        while (pos + 4 <= data.length) {
          final length = (data[pos] << 24) |
              (data[pos + 1] << 16) |
              (data[pos + 2] << 8) |
              data[pos + 3];
          if (pos + 4 + length > data.length) break;
          final message = data.sublist(pos + 4, pos + 4 + length);
          pos += 4 + length;
          final decoded = _decodeMsgpackMap(message);
          if (decoded == null) continue;
          final eventType = decoded['event_type']?.toString();
          final image = decoded['image'];
          if (image is List<int>) {
            final bytes = Uint8List.fromList(image);
            if (eventType == 'final') {
              finalImage = bytes;
            } else if (eventType == 'intermediate') {
              onFrame?.call(bytes, decoded['step_ix'] as int?);
            }
          } else if (decoded.containsKey('error') ||
              decoded.containsKey('message') && eventType == null) {
            throw ApiException(
                message: decoded['error']?.toString() ??
                    decoded['message']?.toString() ??
                    '官方流式生成失败');
          }
        }
        buffer.clear();
        buffer.add(data.sublist(pos));
      }
      if (finalImage == null) {
        throw ApiException(message: '官方流式生成未返回最终图像');
      }
      final filePath = await _saveImage(finalImage);
      return task.copyWith(
        status: 'success',
        imagePath: filePath,
        completedAt: DateTime.now(),
      );
    } on DioException catch (error) {
      throw _error(error, '官方流式生成失败');
    }
  }

  /// 解码一条 msgpack 消息为 Map（仅支持本协议用到的类型子集）。
  static Map<String, dynamic>? _decodeMsgpackMap(Uint8List message) {
    try {
      final value = msgpack.deserialize(message, copyBinaryData: true);
      if (value is Map) {
        return value.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return null;
  }

  Future<String> encodeVibeReference({
    required String imagePath,
    required String model,
    required double informationExtracted,
    required String token,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) throw ApiException(message: '氛围参考图像不可用，请重新选择');
    try {
      final response = await _dio.post<List<int>>(
        ApiConstants.officialEncodeVibe,
        data: {
          'image': base64Encode(await file.readAsBytes()),
          'model': model,
          'information_extracted': informationExtracted.clamp(0, 1),
        },
        options: _options(token),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty)
        throw ApiException(message: '官方 Vibe 编码未返回数据');
      return base64Encode(bytes);
    } on DioException catch (error) {
      throw _error(error, '官方 Vibe 编码失败');
    }
  }

  Future<Uint8List> augmentImage({
    required String imagePath,
    required DirectorToolType tool,
    required String token,
    String? prompt,
    int? defry,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) throw ApiException(message: '请选择有效图片');
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw ApiException(message: '无法读取待处理图片');
      final payload = <String, dynamic>{
        'image': base64Encode(bytes),
        'width': decoded.width,
        'height': decoded.height,
        'req_type': tool.officialOperation,
        'defry': (defry ?? 0).clamp(0, 5),
      };
      if (tool.usesPrompt && prompt?.trim().isNotEmpty == true) {
        payload['prompt'] = tool == DirectorToolType.emotion
            ? '${prompt!.trim()};;${(defry ?? 0).clamp(0, 5)}'
            : prompt!.trim();
      }
      final response = await _dio.post<List<int>>(
        ApiConstants.officialAugmentImage,
        data: payload,
        options: _options(token),
      );
      return _extractImageBytes(response.data, 'Director Tools');
    } on DioException catch (error) {
      throw _error(error, '官方 Director Tools 处理失败');
    }
  }

  /// 官方超分：POST image.novelai.net/ai/upscale。
  /// 固定使用官方专用超分模型，每次请求放大 2 倍；4 倍时迭代两遍。
  /// 输入总像素超过 3MP 时会先等比缩小到限制内，返回的文件路径附带实际输出尺寸。
  Future<String> upscaleImage({
    required String imagePath,
    required String token,
    int scale = 2,
    void Function(String status)? onStatus,
  }) async {
    if (scale != 2 && scale != 4) {
      throw ApiException(message: '超分倍率仅支持 2 或 4');
    }
    final file = File(imagePath);
    if (!await file.exists()) throw ApiException(message: '请选择有效图片');
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw ApiException(message: '无法读取待超分图片');
      var payloadBytes = bytes;

      const maxInputPixels = 3 * 1024 * 1024;
      var inputWidth = decoded.width;
      var inputHeight = decoded.height;
      if (inputWidth * inputHeight > maxInputPixels) {
        final shrink = math.sqrt(maxInputPixels / (inputWidth * inputHeight));
        inputWidth = (inputWidth * shrink).floor().clamp(1, decoded.width);
        inputHeight = (inputHeight * shrink).floor().clamp(1, decoded.height);
        onStatus?.call('原图超过超分输入上限，先缩放至 $inputWidth×$inputHeight');
        final resized = img.copyResize(
          decoded,
          width: inputWidth,
          height: inputHeight,
          interpolation: img.Interpolation.cubic,
        );
        payloadBytes = Uint8List.fromList(img.encodePng(resized));
      }

      final passes = scale == 4 ? 2 : 1;
      var passInput = payloadBytes;
      var currentWidth = inputWidth;
      var currentHeight = inputHeight;
      for (var pass = 0; pass < passes; pass++) {
        onStatus?.call(
            '超分第 ${pass + 1}/$passes 遍（当前 $currentWidth×$currentHeight）');
        final response = await _dio.post<List<int>>(
          ApiConstants.officialUpscale,
          data: {
            'image': base64Encode(passInput),
            'model': officialUpscaleModel,
            'declared_blur_sigma': 0,
          },
          options: _options(token),
        );
        final out = _extractImageBytes(response.data, '官方超分');
        final outDecoded = img.decodeImage(out);
        if (outDecoded == null) throw ApiException(message: '官方超分返回的图片无法读取');
        final expectedWidth = currentWidth * 2;
        final expectedHeight = currentHeight * 2;
        if (outDecoded.width != expectedWidth ||
            outDecoded.height != expectedHeight) {
          throw ApiException(
              message:
                  '超分返回尺寸 ${outDecoded.width}×${outDecoded.height} 与预期 $expectedWidth×$expectedHeight 不符');
        }
        passInput = out;
        currentWidth = expectedWidth;
        currentHeight = expectedHeight;
      }

      final directory = await ImageUtils.getImageDirectory();
      final path =
          '${directory.path}${Platform.pathSeparator}upscale_${DateTime.now().millisecondsSinceEpoch}_x$scale.png';
      await File(path).writeAsBytes(passInput);
      onStatus?.call('超分完成：$currentWidth×$currentHeight');
      return path;
    } on DioException catch (error) {
      throw _error(error, '官方超分失败');
    }
  }

  /// Enhance：按提示词重绘放大（无单独接口，走生图接口的 img2img action）。
  /// 原图先缩放到目标尺寸（[scale] 倍，64 对齐，≤3145728 像素）再传，
  /// [strength] 越低越贴原图（网页低 Magnitude 约 0.2-0.4），[noise] 越高细节越多。
  /// V5 [upscaledEnhance]（Max）：原图按原尺寸（64 对齐）传，服务端放大到 2×
  /// 或像素上限；即使 Opus 也会扣 Anlas。
  Future<String> enhanceImage({
    required String imagePath,
    required String token,
    required String model,
    required String prompt,
    String? negativePrompt,
    int? seed,
    int steps = 23,
    double scaleValue = 5.0,
    required double strength,
    double noise = 0.0,
    double scale = 1.5,
    bool upscaledEnhance = false,
    void Function(String status)? onStatus,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) throw ApiException(message: '请选择有效图片');
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw ApiException(message: '无法读取待处理图片');

      var targetWidth = decoded.width;
      var targetHeight = decoded.height;
      var imageBytes = bytes;
      if (upscaledEnhance) {
        // Max：原图按自己的尺寸传，仅 64 对齐（服务端放大到 2× 或像素上限）。
        const maxPixels = 3 * 1024 * 1024;
        final alignedWidth = (decoded.width ~/ 64) * 64;
        final alignedHeight = (decoded.height ~/ 64) * 64;
        var w = alignedWidth;
        var h = alignedHeight;
        if (w * h > maxPixels) {
          final shrink = math.sqrt(maxPixels / (w * h));
          w = (w * shrink ~/ 64) * 64;
          h = (h * shrink ~/ 64) * 64;
        }
        w = w.clamp(64, 4096);
        h = h.clamp(64, 4096);
        if (w != decoded.width || h != decoded.height) {
          onStatus?.call('原图 64 对齐缩放至 $w×$h');
          final resized = img.copyResize(
            decoded,
            width: w,
            height: h,
            interpolation: img.Interpolation.cubic,
          );
          imageBytes = Uint8List.fromList(img.encodePng(resized));
        }
        targetWidth = w;
        targetHeight = h;
      } else {
        // 普通 1× / 1.5× / 2×：自己把图缩到目标宽高再传。
        var w = (decoded.width * scale).round();
        var h = (decoded.height * scale).round();
        const maxPixels = 3 * 1024 * 1024;
        if (w * h > maxPixels) {
          final shrink = math.sqrt(maxPixels / (w * h));
          w = (w * shrink).floor();
          h = (h * shrink).floor();
        }
        // 64 对齐。
        w = ((w ~/ 64) * 64).clamp(64, 4096);
        h = ((h ~/ 64) * 64).clamp(64, 4096);
        if (w != decoded.width || h != decoded.height) {
          onStatus?.call('缩放至 $w×$h 后重绘');
          final resized = img.copyResize(
            decoded,
            width: w,
            height: h,
            interpolation: img.Interpolation.cubic,
          );
          imageBytes = Uint8List.fromList(img.encodePng(resized));
        }
        targetWidth = w;
        targetHeight = h;
      }

      final effectiveNoiseSeed = seed ?? 0;
      final parameters = <String, dynamic>{
        'width': targetWidth,
        'height': targetHeight,
        'image': base64Encode(imageBytes),
        'strength': strength.clamp(0.01, 0.99),
        'noise': noise.clamp(0, 0.99),
        'extra_noise_seed': effectiveNoiseSeed,
        'steps': steps,
        'scale': scaleValue,
        'sampler': 'k_euler_ancestral',
        'n_samples': 1,
        'negative_prompt': negativePrompt ?? '',
        'qualityToggle': true,
        'ucPreset': 1,
      };
      if (seed != null) parameters['seed'] = seed;
      if (upscaledEnhance) parameters['upscaled_enhance'] = true;
      if (_isV4Plus(model)) {
        final negative = negativePrompt ?? '';
        parameters.addAll({
          'use_coords': false,
          'v4_prompt': {
            'caption': {'base_caption': prompt, 'char_captions': []},
            'use_coords': false,
            'use_order': true,
          },
          'v4_negative_prompt': {
            'caption': {'base_caption': negative, 'char_captions': []},
            'use_coords': false,
            'use_order': false,
          },
        });
      }

      onStatus?.call('Enhance 重绘中（$targetWidth×$targetHeight）');
      final response = await _dio.post<List<int>>(
        ApiConstants.officialGenerateImage,
        data: {
          'input': prompt,
          'model': model,
          'action': 'img2img',
          'parameters': parameters,
        },
        options: _options(token),
      );
      final out = _extractImageBytes(response.data, 'Enhance');
      final directory = await ImageUtils.getImageDirectory();
      final path =
          '${directory.path}${Platform.pathSeparator}enhance_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(path).writeAsBytes(out);
      onStatus?.call('Enhance 完成：$targetWidth×$targetHeight');
      return path;
    } on DioException catch (error) {
      throw _error(error, '官方 Enhance 失败');
    }
  }

  Future<Map<String, dynamic>> buildPayload(GenerationTask task) async {
    final action = task.mode == GenerationMode.inpainting
        ? 'infill'
        : task.img2imgSourceImagePath != null
            ? 'img2img'
            : 'generate';
    if (_isV5(task.model) &&
        (task.vibeReferences.isNotEmpty || task.preciseReferences.isNotEmpty)) {
      throw ApiException(message: 'NovelAI V5 当前不支持 Vibe 或精密参考，请切换 V4.5 模型');
    }
    final negative = task.negativePrompt ?? '';
    final characters =
        task.characters?.where((character) => character.enabled).toList() ??
            const [];
    final hasCoords = characters.any(
        (character) => character.centerX != null && character.centerY != null);
    final characterCaptions = characters
        .map((character) => {
              'char_caption': character.prompt,
              'centers': [
                {'x': character.centerX ?? 0.5, 'y': character.centerY ?? 0.5}
              ],
            })
        .toList();
    final negativeCharacters = characters
        .map((character) => {
              'char_caption': character.uc ?? '',
              'centers': [
                {'x': character.centerX ?? 0.5, 'y': character.centerY ?? 0.5}
              ],
            })
        .toList();
    final parameters = <String, dynamic>{
      'params_version': 4,
      'width': task.width,
      'height': task.height,
      'steps': task.steps,
      'scale': task.scale,
      'cfg_rescale': task.cfgRescale,
      'sampler': task.sampler,
      'noise_schedule': _isV5(task.model) ? 'karras' : task.noiseSchedule,
      'n_samples': 1,
      if (task.seed != null) 'seed': task.seed,
      'uc': negative,
      'negative_prompt': negative,
      'qualityToggle': true,
      'quality_toggle': true,
      'ucPreset': 1,
      'uc_preset': 1,
    };
    if (_isV4Plus(task.model)) {
      parameters.addAll({
        'use_coords': hasCoords,
        'v4_prompt': {
          'caption': {
            'base_caption': task.prompt,
            'char_captions': characterCaptions
          },
          'use_coords': hasCoords,
          'use_order': true,
        },
        'v4_negative_prompt': {
          'caption': {
            'base_caption': negative,
            'char_captions': negativeCharacters
          },
          'use_coords': hasCoords &&
              negativeCharacters.any(
                  (caption) => (caption['char_caption'] as String).isNotEmpty),
          'use_order': false,
        },
      });
    } else {
      parameters.addAll({'sm': false, 'sm_dyn': false});
    }
    if (action == 'img2img') {
      parameters['image'] =
          await _readBase64(task.img2imgSourceImagePath!, '图生图源图');
      parameters['strength'] = task.img2imgStrength ?? 0.7;
      parameters['noise'] = 0.2;
    }
    if (action == 'infill') {
      parameters['image'] = await _readBase64(task.sourceImagePath, '重绘原图');
      parameters['mask'] = await _readBase64(task.maskImagePath, '重绘遮罩');
      parameters['strength'] = task.inpaintStrength ?? 1.0;
    }
    if (task.vibeReferences.isNotEmpty) {
      if (task.vibeReferences
          .any((reference) => reference.encodedVibe?.isEmpty != false)) {
        throw ApiException(message: '氛围参考尚未完成官方编码，请重新提交');
      }
      parameters['reference_image_multiple'] = task.vibeReferences
          .map((reference) => reference.encodedVibe)
          .toList();
      parameters['reference_strength_multiple'] = task.vibeReferences
          .map((reference) => reference.strength.clamp(0, 1))
          .toList();
      parameters['reference_information_extracted_multiple'] = task
          .vibeReferences
          .map((reference) => reference.informationExtracted.clamp(0, 1))
          .toList();
    }
    if (task.preciseReferences.isNotEmpty) {
      parameters
          .addAll(await _preciseReferenceParameters(task.preciseReferences));
    }
    final model = action == 'infill' && !task.model.endsWith('-inpainting')
        ? '${task.model}-inpainting'
        : task.model;
    return {
      'input': task.prompt,
      'model': model,
      'action': action,
      'parameters': parameters
    };
  }

  Future<FormData> _buildMultipart(
      Map<String, dynamic> payload, GenerationTask task) async {
    final parameters = Map<String, dynamic>.from(payload['parameters'] as Map);
    final files = <MapEntry<String, MultipartFile>>[];
    for (var index = 0; index < task.preciseReferences.length; index++) {
      final bytes =
          await File(task.preciseReferences[index].path).readAsBytes();
      files.add(MapEntry('director_ref_$index',
          MultipartFile.fromBytes(bytes, filename: 'reference_$index.png')));
    }
    for (final name in ['image', 'mask']) {
      final value = parameters[name];
      if (value is String && value.isNotEmpty) {
        files.add(MapEntry(
            name,
            MultipartFile.fromBytes(base64Decode(value),
                filename: '$name.png')));
        parameters[name] = name;
      }
    }
    payload['parameters'] = parameters;
    return FormData.fromMap({
      'request': MultipartFile.fromString(jsonEncode(payload),
          filename: 'request.json'),
      for (final file in files) file.key: file.value,
    });
  }

  Future<Map<String, dynamic>> _preciseReferenceParameters(
      List<PreciseReferenceImage> references) async {
    final encoded = <String>[];
    for (final reference in references) {
      final file = File(reference.path);
      if (!await file.exists()) throw ApiException(message: '精密参考图像不可用，请重新选择');
      encoded.add(base64Encode(await file.readAsBytes()));
    }
    return {
      'director_reference_images_cached': [
        for (var index = 0; index < encoded.length; index++)
          {
            'cache_secret_key':
                sha256.convert(base64Decode(encoded[index])).toString(),
            'data': 'director_ref_$index'
          },
      ],
      'director_reference_descriptions': [
        for (final reference in references)
          {
            'caption': {
              'base_caption': reference.referenceType,
              'char_captions': []
            },
            'legacy_uc': false
          },
      ],
      'director_reference_strength_values': references
          .map((reference) => reference.strength.clamp(0, 1))
          .toList(),
      'director_reference_secondary_strength_values':
          List.filled(references.length, 0),
      'director_reference_information_extracted':
          List.filled(references.length, 1),
      'normalize_reference_strength_multiple': true,
    };
  }

  Future<String> _readBase64(String? path, String label) async {
    if (path == null || path.isEmpty || !await File(path).exists()) {
      throw ApiException(message: '$label不可用，请重新选择');
    }
    return base64Encode(await File(path).readAsBytes());
  }

  Uint8List _extractImageBytes(List<int>? data, String feature) {
    if (data == null || data.isEmpty)
      throw ApiException(message: '$feature未返回图片数据');
    final bytes = Uint8List.fromList(data);
    if (bytes.length < 4 ||
        bytes[0] != 0x50 ||
        bytes[1] != 0x4b ||
        bytes[2] != 0x03 ||
        bytes[3] != 0x04) return bytes;
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final name = entry.name.toLowerCase();
        if (name.endsWith('.png') ||
            name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.webp')) {
          final image = entry.readBytes();
          if (image != null && image.isNotEmpty)
            return Uint8List.fromList(image);
        }
      }
    } catch (_) {
      throw ApiException(message: '$feature返回的 ZIP 无效');
    }
    throw ApiException(message: '$feature返回的 ZIP 中没有图片');
  }

  Future<String> _saveImage(Uint8List bytes) async {
    final directory = await ImageUtils.getImageDirectory();
    final path =
        '${directory.path}${Platform.pathSeparator}${ImageUtils.generateFilename()}';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  ApiException _error(DioException error, String fallback) {
    final status = error.response?.statusCode;
    final message = switch (status) {
      401 => 'NovelAI 官方 Token 无效或已失效',
      402 => 'NovelAI 账户额度不足或当前套餐不可用',
      429 => 'NovelAI 请求过于频繁，请稍后重试',
      _ => '$fallback${status == null ? '，请检查网络' : '（HTTP $status）'}',
    };
    return ApiException(
        message: message, statusCode: status, originalError: error);
  }

  Map<String, dynamic>? _map(Object? value) => value is Map<String, dynamic>
      ? value
      : value is Map
          ? Map<String, dynamic>.from(value)
          : null;
  bool _isV5(String model) => model.toLowerCase().contains('diffusion-5');
  bool _isV4Plus(String model) =>
      model.toLowerCase().contains('diffusion-4') || _isV5(model);
}
