import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:nai_huishi/domain/entities/pixiv_settings.dart';
import 'package:nai_huishi/domain/entities/pixiv_upload_task.dart';

class PixivUploadException implements Exception {
  final String message;
  final dynamic raw;
  PixivUploadException(this.message, {this.raw});
  @override
  String toString() => 'PixivUploadException: $message';
}

class PixivCooldownException implements Exception {
  final String message;
  PixivCooldownException(this.message);
  @override
  String toString() => 'PixivCooldownException: $message';
}

class PixivAuthException implements Exception {
  final String message;
  PixivAuthException(this.message);
  @override
  String toString() => 'PixivAuthException: $message';
}

/// Pixiv 投稿 HTTP 接口（移植自 SANP utils/pixivposter.py）
class PixivApiService {
  final _uuid = const Uuid();

  Dio _buildDio(PixivSettings s) {
    final adapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.idleTimeout = const Duration(minutes: 5);
        client.connectionTimeout = const Duration(seconds: 30);
        client.badCertificateCallback = (_, __, ___) => true;
        if (s.proxy.trim().isNotEmpty) {
          final proxy = _parseProxy(s.proxy.trim());
          if (proxy != null) {
            client.findProxy = (uri) => 'PROXY $proxy';
          }
        }
        return client;
      },
    );

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(minutes: 5),
      receiveTimeout: const Duration(minutes: 5),
      validateStatus: (_) => true,
      headers: _baseHeaders(s),
    ))
      ..httpClientAdapter = adapter;

    if (kDebugMode) {
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (o, h) {
          debugPrint('[Pixiv] >>> ${o.method} ${o.uri}');
          h.next(o);
        },
        onResponse: (r, h) {
          debugPrint('[Pixiv] <<< ${r.statusCode} ${r.requestOptions.uri}');
          h.next(r);
        },
        onError: (e, h) {
          debugPrint('[Pixiv] !!! ${e.type} ${e.message}');
          h.next(e);
        },
      ));
    }
    return dio;
  }

  String? _parseProxy(String raw) {
    try {
      final uri = Uri.parse(raw.contains('://') ? raw : 'http://$raw');
      if (uri.host.isEmpty) return null;
      final port = uri.hasPort ? uri.port : 80;
      return '${uri.host}:$port';
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _baseHeaders(PixivSettings s) {
    return {
      'accept': 'application/json',
      'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'origin': 'https://www.pixiv.net',
      'referer': 'https://www.pixiv.net/illustration/create',
      'sec-fetch-dest': 'empty',
      'sec-fetch-mode': 'cors',
      'sec-fetch-site': 'same-origin',
      'user-agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0',
      'cookie': s.cookie,
      'x-csrf-token': s.csrfToken,
      'sentry-trace':
          '${_uuid.v4().replaceAll('-', '')}-${_uuid.v4().replaceAll('-', '').substring(0, 16)}-"0"',
    };
  }

  // ── 推荐 tag ──
  Future<List<String>> suggestTags({
    required PixivSettings settings,
    required String imagePath,
  }) async {
    if (!settings.hasCredentials) {
      throw PixivAuthException('未配置 Pixiv Cookie / CSRF Token');
    }
    final dio = _buildDio(settings);
    final file = File(imagePath);
    if (!await file.exists()) {
      throw PixivUploadException('图片不存在: $imagePath');
    }
    final ext = p.extension(imagePath).toLowerCase();
    final mime = ext == '.png' ? 'image/png' : 'image/jpeg';

    final form = FormData.fromMap({
      'image': MultipartFile.fromBytes(
        await file.readAsBytes(),
        filename: p.basename(imagePath),
        contentType: DioMediaType.parse(mime),
      ),
    });

    final resp = await dio.post(
      'https://www.pixiv.net/rpc/suggest_tags_by_image.php',
      data: form,
    );

    if (resp.statusCode != 200) {
      throw PixivUploadException('推荐 tag 失败: HTTP ${resp.statusCode}',
          raw: resp.data);
    }
    final body = resp.data;
    if (body is! Map) throw PixivUploadException('推荐 tag 响应格式异常', raw: body);
    if (body['error'] == true) {
      throw PixivAuthException('Pixiv 返回错误: ${body['message'] ?? body}');
    }
    final tags = (body['body']?['tags'] as List?) ?? const [];
    return tags.map((e) => e.toString()).toList();
  }

  // ── 上传 ──
  Future<String> uploadIllustration({
    required PixivSettings settings,
    required PixivUploadTask task,
  }) async {
    if (!settings.hasCredentials) {
      throw PixivAuthException('未配置 Pixiv Cookie / CSRF Token');
    }
    if (task.imagePaths.isEmpty) {
      throw PixivUploadException('未选择图片');
    }
    final dio = _buildDio(settings);

    // 表单字段（顺序参考原 Python 实现）
    final formMap = <String, dynamic>{
      'aiType': 'aiGenerated',
      'allowComment': 'true',
      'allowTagEdit': task.allowTagEdit ? 'true' : 'false',
      'attributes[bl]': 'false',
      'attributes[furry]': 'false',
      'attributes[lo]': 'false',
      'attributes[yuri]': 'false',
      'caption': task.caption,
      'captionTranslations[en]': '',
      'original': 'true',
      'ratings[antisocial]': 'false',
      'ratings[drug]': 'false',
      'ratings[religion]': 'false',
      'ratings[thoughts]': 'false',
      'ratings[violent]': 'false',
      'responseAutoAccept': 'false',
      'restrict': 'public',
      'suggestedTags[]': const <String>['女の子'],
      'tags[]': task.tags,
      'title': task.title,
      'titleTranslations[en]': '',
      'xRestrict': task.isR18 ? 'r18' : 'general',
    };
    if (!task.isR18) {
      formMap['sexual'] = 'false';
    }

    // 文件 + imageOrder
    for (int i = 0; i < task.imagePaths.length; i++) {
      final path = task.imagePaths[i];
      final file = File(path);
      if (!await file.exists()) {
        throw PixivUploadException('图片不存在: $path');
      }
      final ext = p.extension(path).toLowerCase();
      final mime = ext == '.png' ? 'image/png' : 'image/jpeg';
      formMap['files[]'] = formMap['files[]'] ?? <MultipartFile>[];
      (formMap['files[]'] as List).add(MultipartFile.fromBytes(
        await file.readAsBytes(),
        filename: p.basename(path),
        contentType: DioMediaType.parse(mime),
      ));
      formMap['imageOrder[$i][fileKey]'] = '$i';
      formMap['imageOrder[$i][type]'] = 'newFile';
    }

    final form = FormData();
    formMap.forEach((k, v) {
      if (v is List) {
        for (final item in v) {
          if (item is MultipartFile) {
            form.files.add(MapEntry(k, item));
          } else {
            form.fields.add(MapEntry(k, item.toString()));
          }
        }
      } else if (v is MultipartFile) {
        form.files.add(MapEntry(k, v));
      } else {
        form.fields.add(MapEntry(k, v.toString()));
      }
    });

    final resp = await dio.post(
      'https://www.pixiv.net/ajax/work/create/illustration',
      data: form,
    );

    final data = resp.data;
    if (data is! Map) {
      throw PixivUploadException('上传响应格式异常: HTTP ${resp.statusCode}',
          raw: data);
    }

    if (data['error'] == true) {
      final errors = data['body']?['errors'];
      if (errors is Map && errors['gRecaptchaResponse'] != null) {
        throw PixivCooldownException('投稿冷却（gRecaptcha），请稍后再试');
      }
      final msg =
          data['message']?.toString() ?? errors?.toString() ?? 'unknown error';
      // 常见认证失效
      if (msg.contains('csrf') ||
          msg.contains('CSRF') ||
          msg.contains('未登录') ||
          msg.contains('login')) {
        throw PixivAuthException(msg);
      }
      throw PixivUploadException('上传失败: $msg', raw: data);
    }

    final convertKey = data['body']?['convertKey']?.toString();
    if (convertKey == null || convertKey.isEmpty) {
      throw PixivUploadException('未获取到 convertKey', raw: data);
    }

    return _pollProgress(dio: dio, convertKey: convertKey);
  }

  Future<String> _pollProgress({
    required Dio dio,
    required String convertKey,
  }) async {
    final url = 'https://www.pixiv.net/ajax/work/create/illustration/progress'
        '?convertKey=$convertKey&lang=zh';
    for (int i = 0; i < 120; i++) {
      // 最多轮询 ~2 分钟
      final resp = await dio.get(url);
      final data = resp.data;
      if (data is Map && data['body'] is Map) {
        final status = data['body']['status']?.toString();
        if (status == 'COMPLETE') {
          final illustId = data['body']['illustId']?.toString();
          if (illustId == null || illustId.isEmpty) {
            throw PixivUploadException('完成但未返回 illustId', raw: data);
          }
          return illustId;
        }
        if (status == 'FAILED') {
          throw PixivUploadException('Pixiv 处理失败', raw: data);
        }
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    throw PixivUploadException('上传进度查询超时');
  }
}
