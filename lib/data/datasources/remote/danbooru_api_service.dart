import 'package:dio/dio.dart';
import 'package:nai_huishi/domain/entities/danbooru_tag.dart';

/// Danbooru 校准 API 服务。
///
/// 调用 [DanbooruSearchOnline](https://github.com/SuzumiyaAkizuki/ComfyUI-DanbooruSearcher)
/// 部署的两个公共端点，提供 /api/search（语义检索）与 /api/related（共现推荐）。
///
/// 双端点 failover 策略：
///   1. 用户自定义 Base URL（如填写）优先使用，单端点不做 failover；
///   2. 否则按顺序尝试 HuggingFace（NSFW 查询更稳定） → ModelScope（备用）；
///   3. 任一端点 5 秒内未响应或返回非 2xx，立即切到下一个；
///   4. 全部失败抛出最后一次异常，由调用方降级。
///
/// 使用独立 Dio 实例，避免污染主 LLM Dio 的 baseUrl/Authorization。
class DanbooruApiService {
  /// ModelScope 创空间端点（国内直连）
  static const String defaultModelScopeBaseUrl =
      'https://sakizuki-danboorusearchonline.ms.show';

  /// HuggingFace Space 端点（备份）
  static const String defaultHuggingFaceBaseUrl =
      'https://sakizuki-danboorusearch.hf.space';

  final Dio _dio;

  DanbooruApiService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ));

  /// 解析为待尝试的 base URL 列表。
  /// 自定义 Base URL 非空时仅返回该地址（不再 failover），否则用默认双端点。
  List<String> _resolveBaseUrls(String? customBaseUrl) {
    final custom = customBaseUrl?.trim();
    if (custom != null && custom.isNotEmpty) {
      return [_normalize(custom)];
    }
    return [
      _normalize(defaultHuggingFaceBaseUrl),
      _normalize(defaultModelScopeBaseUrl),
    ];
  }

  String _normalize(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// POST /api/search：用中文/英文 query 做语义检索。
  ///
  /// 返回 Danbooru 真实标签列表，按 final_score 降序。
  Future<List<DanbooruTag>> search({
    required String query,
    int topK = 5,
    int limit = 30,
    bool showNsfw = false,
    String? customBaseUrl,
    CancelToken? cancelToken,
  }) async {
    final body = <String, dynamic>{
      'query': query,
      'top_k': topK,
      'limit': limit,
      'show_nsfw': showNsfw,
    };
    final data = await _post('/api/search', body, customBaseUrl, cancelToken);
    if (data is! Map) return const [];
    final results = data['results'];
    if (results is! List) return const [];
    return results
        .whereType<Map>()
        .map((e) => _parseSearchTag(e.cast<String, dynamic>()))
        .where((t) => t.tag.isNotEmpty)
        .toList();
  }

  /// POST /api/related：基于种子标签做共现推荐。
  ///
  /// [tags]：已选种子标签（Danbooru 英文 tag 名）
  Future<List<DanbooruTag>> related({
    required List<String> tags,
    int limit = 30,
    bool showNsfw = false,
    String? customBaseUrl,
    CancelToken? cancelToken,
  }) async {
    if (tags.isEmpty) return const [];
    final body = <String, dynamic>{
      'tags': tags,
      'limit': limit,
      'show_nsfw': showNsfw,
    };
    final data = await _post('/api/related', body, customBaseUrl, cancelToken);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => _parseRelatedTag(e.cast<String, dynamic>()))
        .where((t) => t.tag.isNotEmpty)
        .toList();
  }

  /// 内部：按 base URL 顺序尝试，第一个成功的 base URL 直接返回。
  Future<dynamic> _post(
    String path,
    Map<String, dynamic> body,
    String? customBaseUrl,
    CancelToken? cancelToken,
  ) async {
    final baseUrls = _resolveBaseUrls(customBaseUrl);
    Object? lastError;
    for (final base in baseUrls) {
      try {
        final response = await _dio.post<dynamic>(
          '$base$path',
          data: body,
          cancelToken: cancelToken,
        );
        if (response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 300) {
          return response.data;
        }
        lastError = Exception('HTTP ${response.statusCode}');
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        lastError = e;
        // 继续下一个端点
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('Danbooru 校准全部端点失败: $lastError');
  }

  DanbooruTag _parseSearchTag(Map<String, dynamic> json) {
    return DanbooruTag(
      tag: (json['tag'] ?? '').toString(),
      cnName: (json['cn_name'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      nsfw: (json['nsfw'] ?? '').toString(),
      count: _asInt(json['count']),
      finalScore: _asDouble(json['final_score']),
      wiki: (json['wiki'] ?? '').toString(),
      origin: 'search',
    );
  }

  DanbooruTag _parseRelatedTag(Map<String, dynamic> json) {
    final sources = json['sources'];
    final sourceList = <String>[];
    if (sources is List) {
      for (final s in sources) {
        if (s != null) sourceList.add(s.toString());
      }
    }
    return DanbooruTag(
      tag: (json['tag'] ?? '').toString(),
      cnName: (json['cn_name'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      nsfw: (json['nsfw'] ?? '').toString(),
      count: _asInt(json['post_count']),
      finalScore: _asDouble(json['cooc_score']),
      wiki: (json['wiki'] ?? '').toString(),
      sources: sourceList,
      origin: 'related',
    );
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  double _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
