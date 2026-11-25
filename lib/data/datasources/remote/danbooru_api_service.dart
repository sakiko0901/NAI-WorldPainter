import 'dart:async';

import 'package:dio/dio.dart';
import 'package:nai_huishi/domain/entities/danbooru_tag.dart';
import 'package:nai_huishi/domain/entities/tag_completion.dart';

enum VerifiedDanbooruMatch { exact, alias, qualified, wikiName, semantic }

class VerifiedDanbooruTag {
  const VerifiedDanbooruTag(this.tag, this.match,
      {this.matchedTerm, this.semanticProvider});

  final DanbooruTag tag;
  final VerifiedDanbooruMatch match;
  final String? matchedTerm;
  final String? semanticProvider;
}

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
  static const _officialBaseUrl = 'https://danbooru.donmai.us';
  static const _lookupDeadline = Duration(seconds: 12);
  static const _requestDeadline = Duration(seconds: 3);

  /// ModelScope 创空间端点（国内直连）
  static const String defaultModelScopeBaseUrl =
      'https://sakizuki-danboorusearchonline.ms.show';

  /// HuggingFace Space 端点（备份）
  static const String defaultHuggingFaceBaseUrl =
      'https://sakizuki-danboorusearch.hf.space';

  final Dio _dio;

  DanbooruApiService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
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
    final response = await _post('/api/search',
        _searchBody(query, topK, limit, showNsfw), customBaseUrl, cancelToken);
    return _searchResults(response.data);
  }

  Map<String, dynamic> _searchBody(
          String query, int topK, int limit, bool showNsfw) =>
      {'query': query, 'top_k': topK, 'limit': limit, 'show_nsfw': showNsfw};

  List<DanbooruTag> _searchResults(dynamic data) {
    if (data is! Map) return const [];
    final results = data['results'];
    if (results is! List) return const [];
    return results
        .whereType<Map>()
        .map((e) => _parseSearchTag(e.cast<String, dynamic>()))
        .where((t) => t.tag.isNotEmpty)
        .toList();
  }

  /// Looks up a canonical name or active alias before using semantic search.
  /// Every result is verified by Danbooru. Semantic similarity only supplies a
  /// candidate, and never establishes a match between the query and the tag.
  Future<List<VerifiedDanbooruTag>> searchVerified({
    required String query,
    int limit = 15,
    bool showNsfw = true,
  }) async {
    final cancel = CancelToken();
    try {
      return await _lookupVerified(query, limit.clamp(1, 30), showNsfw, cancel)
          .timeout(_lookupDeadline);
    } finally {
      cancel.cancel();
    }
  }

  Future<List<VerifiedDanbooruTag>> _lookupVerified(
      String query, int limit, bool showNsfw, CancelToken cancel) async {
    final queryName = _tagKey(query);
    if (showNsfw && queryName != null) {
      final found = await _resolveOfficialNames({queryName}, cancel);
      final tag = found[queryName];
      if (tag != null) {
        return [_queryMatch(tag, queryName)];
      }
      if (queryName.length >= 3 && !queryName.endsWith(')')) {
        final prefix = '${queryName}_(';
        final matches = await _officialTags({
          'search[name_matches]': '$prefix*)',
          'search[order]': 'count',
          'limit': limit,
        }, cancel);
        final seen = <String>{};
        final qualified = matches
            .where((tag) =>
                tag.tag.startsWith(prefix) &&
                tag.tag.endsWith(')') &&
                seen.add(tag.tag))
            .map((tag) =>
                VerifiedDanbooruTag(tag, VerifiedDanbooruMatch.qualified))
            .take(limit)
            .toList();
        if (qualified.isNotEmpty) return qualified;
      }
    }

    if (showNsfw &&
        !query.contains('*') &&
        RegExp(r'[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]').hasMatch(query)) {
      final matches = await _lookupWikiNames(query, limit, cancel);
      if (matches.isNotEmpty) return matches;
    }

    // Danbooru's tag metadata has no NSFW rating. In filtered mode only tags
    // returned by the filtered semantic service can proceed to verification.
    final semantic = await _post(
        '/api/search', _searchBody(query, 5, limit, showNsfw), null, cancel,
        options: _lookupOptions());
    final data = semantic.data;
    if (data is! Map || data['results'] is! List) {
      throw const FormatException('语义服务未返回有效结果');
    }
    final candidates = <String, DanbooruTag>{};
    for (final candidate in _searchResults(data)) {
      final name = _tagKey(candidate.tag);
      if (name == null ||
          (!showNsfw && (candidate.isNsfw || candidate.nsfw.trim() == '1'))) {
        continue;
      }
      candidates.putIfAbsent(name, () => candidate);
      if (candidates.length == limit) break;
    }
    if (candidates.isEmpty) return const [];
    final resolved = await _resolveOfficialNames({
      ...candidates.keys,
      if (!showNsfw && queryName != null) queryName,
    }, cancel);
    final direct = queryName == null ? null : resolved[queryName];
    final provider = semantic.baseUrl == defaultHuggingFaceBaseUrl
        ? 'Hugging Face'
        : 'ModelScope';
    final hits = <String, VerifiedDanbooruTag>{};
    for (final entry in candidates.entries) {
      final official = resolved[entry.key];
      if (official == null) continue;
      final tag = DanbooruTag(
        tag: official.tag,
        category: official.category,
        count: official.count,
        cnName: entry.value.cnName,
        nsfw: entry.value.nsfw,
      );
      hits.putIfAbsent(
          tag.tag,
          () => tag.tag == direct?.tag
              ? _queryMatch(tag, queryName!, semanticProvider: provider)
              : VerifiedDanbooruTag(tag, VerifiedDanbooruMatch.semantic,
                  matchedTerm: entry.key == tag.tag ? null : entry.key,
                  semanticProvider: provider));
    }
    final directHit = hits.remove(direct?.tag);
    return [if (directHit != null) directHit, ...hits.values];
  }

  VerifiedDanbooruTag _queryMatch(DanbooruTag tag, String queryName,
      {String? semanticProvider}) {
    final exact = tag.tag == queryName;
    return VerifiedDanbooruTag(
        tag, exact ? VerifiedDanbooruMatch.exact : VerifiedDanbooruMatch.alias,
        matchedTerm: exact ? null : queryName,
        semanticProvider: semanticProvider);
  }

  Future<List<VerifiedDanbooruTag>> _lookupWikiNames(
      String query, int limit, CancelToken cancel) async {
    final rows = await _officialRows(
        '/wiki_pages.json',
        {
          'search[other_names_match]': query,
          'search[hide_deleted]': 'true',
          'only': 'title,other_names,is_deleted',
          'limit': limit,
        },
        cancel);
    final titles = <String, String>{};
    final normalizedQuery = _wikiNameKey(query);
    for (final row in rows) {
      final title = row['title'];
      final otherNames = row['other_names'];
      if (title is! String ||
          row['is_deleted'] == true ||
          otherNames is! List) {
        continue;
      }
      for (final name in otherNames.whereType<String>()) {
        if (_wikiNameKey(name) == normalizedQuery) titles[title] = name;
      }
    }
    final resolved = await _resolveOfficialNames(titles.keys.toSet(), cancel);
    final hits = <String, VerifiedDanbooruTag>{};
    for (final entry in resolved.entries) {
      hits[entry.value.tag] = VerifiedDanbooruTag(
        entry.value,
        VerifiedDanbooruMatch.wikiName,
        matchedTerm: titles[entry.key],
      );
    }
    return hits.values.toList();
  }

  // Align common full-width punctuation with Danbooru Wiki's NFKC search.
  String _wikiNameKey(String value) => normalizeCompletionTag(
        String.fromCharCodes(value.runes.map(
            (rune) => rune >= 0xff01 && rune <= 0xff5e ? rune - 0xfee0 : rune)),
      );

  String? _tagKey(String value) {
    final key = normalizeCompletionTag(value)
        .replaceAll(r'\(', '(')
        .replaceAll(r'\)', ')');
    if (key.length > 160 ||
        !RegExp(r'^[!-~]+$').hasMatch(key) ||
        key.contains(RegExp(r'[*,\\]'))) {
      return null;
    }
    return key;
  }

  Future<Map<String, DanbooruTag>> _resolveOfficialNames(
      Set<String> names, CancelToken cancel) async {
    if (names.isEmpty) return {};
    final tags = await _officialTagsByName(names, cancel);
    final missing = names.difference(tags.keys.toSet());
    if (missing.isEmpty) return tags;
    final rows = await _officialRows(
        '/tag_aliases.json',
        {
          'search[antecedent_name]': missing.toList(),
          'search[status]': 'active',
          'limit': missing.length,
        },
        cancel);
    final aliases = <String, String>{};
    for (final row in rows) {
      final from = row['antecedent_name'];
      final to = row['consequent_name'];
      if (from is String &&
          missing.contains(from) &&
          to is String &&
          _tagKey(to) == to &&
          to != from &&
          row['status'] == 'active') {
        aliases[from] = to;
      }
    }
    final targets = aliases.values.toSet().difference(tags.keys.toSet());
    final canonical = {...tags, ...await _officialTagsByName(targets, cancel)};
    for (final entry in aliases.entries) {
      final tag = canonical[entry.value];
      if (tag != null) tags[entry.key] = tag;
    }
    return tags;
  }

  Future<Map<String, DanbooruTag>> _officialTagsByName(
      Set<String> names, CancelToken cancel) async {
    if (names.isEmpty) return {};
    final tags = await _officialTags({
      'search[name_normalize]': names.join(','),
      'limit': names.length,
    }, cancel);
    return {
      for (final tag in tags)
        if (names.contains(tag.tag)) tag.tag: tag
    };
  }

  Future<List<DanbooruTag>> _officialTags(
      Map<String, dynamic> parameters, CancelToken cancel) async {
    final rows = await _officialRows(
        '/tags.json',
        {
          ...parameters,
          'search[hide_empty]': 'true',
          'only': 'name,category,post_count,is_deprecated',
        },
        cancel);
    final tags = <DanbooruTag>[];
    for (final row in rows) {
      final name = row['name'];
      final count = _asInt(row['post_count']);
      final category = switch (row['category']) {
        0 => 'General',
        1 => 'Artist',
        3 => 'Copyright',
        4 => 'Character',
        5 => 'Meta',
        _ => null,
      };
      if (name is String &&
          _tagKey(name) == name &&
          count > 0 &&
          category != null &&
          row['is_deprecated'] != true) {
        tags.add(DanbooruTag(tag: name, count: count, category: category));
      }
    }
    return tags;
  }

  Future<List<Map>> _officialRows(
      String path, Map<String, dynamic> parameters, CancelToken cancel) async {
    Future<List<Map>> fetch() async {
      final response = await _dio.get<dynamic>('$_officialBaseUrl$path',
          queryParameters: parameters,
          options: _lookupOptions()
              .copyWith(headers: {'User-Agent': 'NAI-WorldPainter tag lookup'}),
          cancelToken: cancel);
      final data = response.data;
      if (data is! List || data.any((row) => row is! Map)) {
        throw const FormatException('Danbooru 官方接口未返回有效结果');
      }
      return data.cast<Map>();
    }

    try {
      return await fetch();
    } on DioException catch (error) {
      if (!const {502, 503, 504}.contains(error.response?.statusCode)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return fetch();
    }
  }

  Options _lookupOptions() => Options(
        connectTimeout: _requestDeadline,
        sendTimeout: _requestDeadline,
        receiveTimeout: _requestDeadline,
        listFormat: ListFormat.multiCompatible,
      );

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
    final response =
        await _post('/api/related', body, customBaseUrl, cancelToken);
    final data = response.data;
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => _parseRelatedTag(e.cast<String, dynamic>()))
        .where((t) => t.tag.isNotEmpty)
        .toList();
  }

  /// 内部：按 base URL 顺序尝试，第一个成功的 base URL 直接返回。
  Future<({dynamic data, String baseUrl})> _post(
    String path,
    Map<String, dynamic> body,
    String? customBaseUrl,
    CancelToken? cancelToken, {
    Options? options,
  }) async {
    final baseUrls = _resolveBaseUrls(customBaseUrl);
    Object? lastError;
    for (final base in baseUrls) {
      try {
        final response = await _dio.post<dynamic>(
          '$base$path',
          data: body,
          options: options,
          cancelToken: cancelToken,
        );
        if (response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 300) {
          return (data: response.data, baseUrl: base);
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
