import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// WD-Tagger 模型选项
class WdTaggerModel {
  final String repo;
  final String label;

  const WdTaggerModel({required this.repo, required this.label});

  static const presets = [
    WdTaggerModel(repo: 'SmilingWolf/wd-swinv2-tagger-v3', label: 'SwinV2 v3'),
    WdTaggerModel(repo: 'SmilingWolf/wd-convnext-tagger-v3', label: 'ConvNext v3'),
    WdTaggerModel(repo: 'SmilingWolf/wd-vit-tagger-v3', label: 'ViT v3'),
    WdTaggerModel(repo: 'SmilingWolf/wd-v1-4-moat-tagger-v2', label: 'MOAT v2'),
    WdTaggerModel(repo: 'SmilingWolf/wd-v1-4-swinv2-tagger-v2', label: 'SwinV2 v2'),
    WdTaggerModel(repo: 'SmilingWolf/wd-v1-4-convnextv2-tagger-v2', label: 'ConvNextV2 v2'),
  ];
}

/// WD-Tagger 分析结果
class WdTaggerResult {
  final String caption;
  final Map<String, double> generalTags;
  final Map<String, double> characterTags;
  final Map<String, double> ratingTags;

  const WdTaggerResult({
    this.caption = '',
    this.generalTags = const {},
    this.characterTags = const {},
    this.ratingTags = const {},
  });
}

/// 调用 HuggingFace Spaces wd-tagger 的 Gradio 6.x API
///
/// Gradio 6.x 原生 call API 流程：
///   1. POST /gradio_api/call/predict          → 返回 {"event_id": "xxx"}
///   2. GET  /gradio_api/call/predict/<event_id>  (SSE 流) → 拿结果
///
/// SSE 行格式：
///   event: <type>\n
///   data: <JSON|string>\n\n
/// 关键事件:
///   - event: generating   data: [progress info]
///   - event: complete     data: [输出数组]
///   - event: error        data: "<错误信息>"
///   - event: heartbeat    data: ""
class WdTaggerApiService {
  final Dio _dio;

  WdTaggerApiService(this._dio);

  static const String _baseUrl = 'https://smilingwolf-wd-tagger.hf.space';

  /// 分析图片标签
  Future<WdTaggerResult> analyze({
    required String imagePath,
    required String modelRepo,
    double generalThreshold = 0.35,
    bool generalMcutEnabled = false,
    double characterThreshold = 0.85,
    bool characterMcutEnabled = false,
  }) async {
    // 1. 上传图片到 Gradio 临时文件，得到 file path
    final filePath = await _retryOn503(() => _uploadFile(imagePath),
        label: '上传图片');

    // 2. 提交任务
    final eventId = await _retryOn503(
        () => _submitTask(
              filePath: filePath,
              modelRepo: modelRepo,
              generalThreshold: generalThreshold,
              generalMcutEnabled: generalMcutEnabled,
              characterThreshold: characterThreshold,
              characterMcutEnabled: characterMcutEnabled,
            ),
        label: '提交任务');

    // 3. SSE 拉取结果
    final resultData = await _pollResult(eventId);

    if (resultData.length < 4) {
      throw Exception('WD-Tagger 返回数据不完整');
    }

    // SmilingWolf/wd-tagger 的实际返回顺序：
    //   [0] sorted_general_strings (caption)
    //   [1] rating              (general/sensitive/questionable/explicit)
    //   [2] character_res
    //   [3] general_res
    final caption = resultData[0]?.toString() ?? '';
    final ratingTags = _parseConfidences(resultData[1]);
    final characterTags = _parseConfidences(resultData[2]);
    final generalTags = _parseConfidences(resultData[3]);

    return WdTaggerResult(
      caption: caption,
      generalTags: generalTags,
      characterTags: characterTags,
      ratingTags: ratingTags,
    );
  }

  /// 对 503 (Space 冷启动) 和队列满进行自动重试
  Future<T> _retryOn503<T>(Future<T> Function() fn, {String label = ''}) async {
    const maxRetries = 8;
    const delays = [
      Duration(seconds: 10), Duration(seconds: 15), Duration(seconds: 20),
      Duration(seconds: 30), Duration(seconds: 30), Duration(seconds: 45),
      Duration(seconds: 60), Duration(seconds: 60),
    ];

    for (int i = 0; i < maxRetries; i++) {
      try {
        return await fn();
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 503 || status == 502 || status == 429) {
          if (i < maxRetries - 1) {
            final delay = delays[i];
            debugPrint('[WD-Tagger] $label 收到 $status，${delay.inSeconds}s 后重试 (${i + 1}/$maxRetries)');
            await Future.delayed(delay);
            continue;
          }
          throw Exception('WD-Tagger 服务暂时不可用 (HTTP $status)，'
              'HuggingFace Space 可能正在冷启动，请稍后再试');
        }
        rethrow;
      } on Exception catch (e) {
        final msg = e.toString();
        if (msg.contains('Queue is full') || msg.contains('队列已满')) {
          if (i < maxRetries - 1) {
            final delay = delays[i];
            debugPrint('[WD-Tagger] $label 队列已满，${delay.inSeconds}s 后重试 (${i + 1}/$maxRetries)');
            await Future.delayed(delay);
            continue;
          }
          throw Exception('WD-Tagger 服务队列已满，请稍后再试');
        }
        rethrow;
      }
    }
    throw Exception('WD-Tagger 服务暂时不可用，请稍后再试');
  }

  /// 上传文件到 Gradio Spaces，返回服务器临时路径
  Future<String> _uploadFile(String imagePath) async {
    final file = File(imagePath);
    final fileName = imagePath.split(RegExp(r'[\\/]')).last;
    final ext = imagePath.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

    final formData = FormData.fromMap({
      'files': await MultipartFile.fromFile(
        file.path,
        filename: fileName,
        contentType: DioMediaType.parse(mimeType),
      ),
    });

    final resp = await _dio.post(
      '$_baseUrl/gradio_api/upload',
      data: formData,
      options: Options(
        sendTimeout: const Duration(seconds: 120),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    final data = resp.data;
    if (data is List && data.isNotEmpty) {
      return data[0].toString();
    }
    throw Exception('上传文件失败：返回格式异常');
  }

  /// 提交分析任务，返回 event_id
  Future<String> _submitTask({
    required String filePath,
    required String modelRepo,
    required double generalThreshold,
    required bool generalMcutEnabled,
    required double characterThreshold,
    required bool characterMcutEnabled,
  }) async {
    // 推断 mime
    final ext = filePath.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

    final resp = await _dio.post(
      '$_baseUrl/gradio_api/call/predict',
      data: {
        'data': [
          {
            'path': filePath,
            'url': '$_baseUrl/gradio_api/file=$filePath',
            'orig_name': filePath.split('/').last,
            'mime_type': mimeType,
            'meta': {'_type': 'gradio.FileData'},
          },
          modelRepo,
          generalThreshold,
          generalMcutEnabled,
          characterThreshold,
          characterMcutEnabled,
        ],
      },
      options: Options(
        contentType: Headers.jsonContentType,
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    final data = resp.data;
    if (data is Map && data['event_id'] is String) {
      return data['event_id'] as String;
    }
    // Gradio 6 队列满时返回 {"detail":"Queue is full..."}
    if (data is Map && data['detail'] is String) {
      final detail = data['detail'] as String;
      if (detail.contains('Queue is full')) {
        throw Exception('队列已满: $detail');
      }
      throw Exception('提交任务失败: $detail');
    }
    throw Exception('提交任务失败：未获取到 event_id');
  }

  /// 拉取 SSE 结果（Gradio 6.x /call/predict/<event_id> 协议）
  ///
  /// 实测此端点在拿到结果后立即发完 `event: complete` 帧并关闭连接，
  /// 不是长连接流，所以直接整体 GET 文本再解析比流式订阅更稳——
  /// 流式订阅在 release 包里偶尔会在 transform 链上丢最后一帧 + 触发 onDone，
  /// 表现为 "SSE 流意外结束"。
  Future<List<dynamic>> _pollResult(String eventId) async {
    final resp = await _dio.get<String>(
      '$_baseUrl/gradio_api/call/predict/$eventId',
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 600),
        headers: {'Accept': 'text/event-stream'},
      ),
    );

    final body = resp.data ?? '';
    if (body.isEmpty) {
      throw Exception('SSE 响应为空');
    }

    return _parseSseBody(body);
  }

  /// 解析整段 SSE 文本，返回 complete 事件的 data 数组。
  /// 兜底：如果没找到 complete 事件，取最后一个 data 数组。
  List<dynamic> _parseSseBody(String body) {
    final lines = const LineSplitter().convert(body);
    String? currentEvent;
    dynamic completeData;
    dynamic lastData;
    String? errorMessage;

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty) continue;

      if (line.startsWith('event:')) {
        currentEvent = line.substring(6).trim();
        continue;
      }
      if (!line.startsWith('data:')) continue;

      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;

      dynamic decoded;
      try {
        decoded = jsonDecode(payload);
      } catch (_) {
        decoded = payload;
      }

      switch (currentEvent) {
        case 'complete':
          completeData = decoded;
          break;
        case 'error':
          errorMessage = decoded.toString();
          break;
        case 'generating':
          if (decoded is List) lastData = decoded;
          break;
        default:
          if (decoded is List) lastData = decoded;
      }
    }

    if (completeData is List) return completeData;
    if (errorMessage != null) throw Exception('Gradio 服务错误: $errorMessage');
    if (lastData is List) return lastData as List;
    throw Exception('SSE 响应未包含 complete 事件，原始内容：'
        '${body.length > 500 ? '${body.substring(0, 500)}...' : body}');
  }

  /// 解析 Gradio confidences 格式
  /// 可能格式: {"confidences": [{"label": ..., "confidence": ...}], "label": "..."}
  /// 或直接 List
  Map<String, double> _parseConfidences(dynamic data) {
    final result = <String, double>{};
    List? list;
    if (data is List) {
      list = data;
    } else if (data is Map<String, dynamic>) {
      list = data['confidences'] as List?;
    }
    if (list == null) return result;

    for (final item in list) {
      if (item is! Map) continue;
      final label = item['label'] as String?;
      final confidence = item['confidence'];
      if (label != null && confidence != null) {
        result[label] = (confidence as num).toDouble();
      }
    }
    return result;
  }
}
