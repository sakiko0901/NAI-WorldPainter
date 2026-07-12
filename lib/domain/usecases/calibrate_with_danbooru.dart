import 'package:nai_huishi/data/datasources/remote/danbooru_api_service.dart';
import 'package:nai_huishi/domain/entities/danbooru_tag.dart';

/// 校准结果。
class CalibrationResult {
  /// 校准后的正向 prompt 文本（可直接替换原 LLM 正向）
  final String calibratedPositive;

  /// 用 search 得到的标准化 tag 数（替换 LLM 非标准词）
  final int normalizedCount;

  /// 用 related 补充的共现 tag 数
  final int relatedCount;

  /// 全部 tag 元数据（用于悬浮展示中文名/wiki/热度）
  final Map<String, DanbooruTag> tagMeta;

  const CalibrationResult({
    required this.calibratedPositive,
    required this.normalizedCount,
    required this.relatedCount,
    required this.tagMeta,
  });
}

class CalibrateWithDanbooruUseCase {
  final DanbooruApiService _api;

  CalibrateWithDanbooruUseCase(this._api);

  /// 校准 LLM 输出的正向 prompt。
  ///
  /// 流程：
  ///   1. 把 LLM 正向拆成单 tag 列表（去权重括号、去多余空格）；
  ///   2. 并发调用：/search（用户原始中文查询）+ /related（LLM tag 作为种子）；
  ///   3. 用 /search 的高分结果替换 LLM 写错/幻觉的标签，保留 LLM 已是标准 tag 的；
  ///   4. 用 /related 的前 N 个共现标签作为补充追加；
  ///   5. 返回校准后的拼接字符串（保持原有逗号分隔风格，不破坏权重符号）。
  Future<CalibrationResult> call({
    required String llmPositive,
    required String userQuery,
    bool showNsfw = false,
    String? customBaseUrl,
    int relatedTopN = 8,
    int searchTopN = 6,
  }) async {
    final llmTokens = _splitTags(llmPositive);
    final llmCoreTags =
        llmTokens.map(_stripWeights).where((t) => t.isNotEmpty).toList();

    // 并发触发 search + related
    final searchFuture = _api
        .search(
          query: userQuery.trim().isEmpty ? llmCoreTags.join(', ') : userQuery,
          topK: 5,
          limit: searchTopN * 4,
          showNsfw: showNsfw,
          customBaseUrl: customBaseUrl,
        )
        .catchError((_) => <DanbooruTag>[]);

    // 种子 tag 要转成 Danbooru SD 风格（下划线）再发给 /related，
    // 否则服务端按 "white_serafuku" 索引时无法匹配 LLM 的 "white serafuku"。
    final relatedSeeds = llmCoreTags
        .take(12)
        .map(_toDanbooruTag)
        .where((t) => t.isNotEmpty)
        .toList();
    final relatedFuture = relatedSeeds.isEmpty
        ? Future.value(<DanbooruTag>[])
        : _api
            .related(
              tags: relatedSeeds,
              limit: relatedTopN * 4,
              showNsfw: showNsfw,
              customBaseUrl: customBaseUrl,
            )
            .catchError((_) => <DanbooruTag>[]);

    final results = await Future.wait([searchFuture, relatedFuture]);
    final searchTags = results[0];
    final relatedTags = results[1];

    if (searchTags.isEmpty && relatedTags.isEmpty) {
      // 两个端点都失败：交由调用方决定是否报错
      throw Exception('Danbooru 校准未返回任何结果');
    }

    // 构建 search 标签集合（用于判定 LLM tag 是否为真实标准 tag）。
    // Danbooru 返回的是 SD 风格下划线 tag（white_serafuku），LLM 按系统提示词输出
    // 的是 NovelAI 风格空格 tag（white serafuku），匹配键必须统一归一化，
    // 否则 LLM 标准 tag 会被全部误判为幻觉。
    final searchByTag = <String, DanbooruTag>{
      for (final t in searchTags) _normKey(t.tag): t,
    };

    // 1) 标准化：保留 LLM 中已存在于 search 命中或本身规范的 tag，
    //    其他用 search 高分结果替换。
    final keptTokens = <String>[];
    final keptSet = <String>{};
    int normalizedCount = 0;
    for (final raw in llmTokens) {
      if (raw.trim().isEmpty) continue;
      final core = _stripWeights(raw);
      if (core.isEmpty) continue;
      final coreKey = _normKey(core);
      // LLM 写的 tag 已是 search 命中的标准 tag → 直接保留（保留权重符号原样）
      if (searchByTag.containsKey(coreKey) || _looksLikeStandardTag(core)) {
        if (keptSet.add(coreKey)) {
          keptTokens.add(raw.trim());
        }
      } else {
        // 否则尝试用 search 头部结果替换：
        // 找 search 结果中第一个尚未加入的标签作为替代
        DanbooruTag? sub;
        for (final s in searchTags) {
          if (!keptSet.contains(_normKey(s.tag))) {
            sub = s;
            break;
          }
        }
        if (sub != null) {
          final subKey = _normKey(sub.tag);
          if (keptSet.add(subKey)) {
            keptTokens.add(_toNovelAiTag(sub.tag));
            normalizedCount++;
          }
        } else {
          // 没有可用替代时，保留 LLM 原 tag，避免丢信息
          if (keptSet.add(coreKey)) {
            keptTokens.add(raw.trim());
          }
        }
      }
    }

    // 2) 把 search 的 top N 中尚未加入的优质 tag 也补一遍
    int searchAdded = 0;
    for (final s in searchTags) {
      if (searchAdded >= searchTopN) break;
      final key = _normKey(s.tag);
      if (keptSet.add(key)) {
        keptTokens.add(_toNovelAiTag(s.tag));
        searchAdded++;
      }
    }

    // 3) 用 related 的 top N 共现 tag 追加
    int relatedAdded = 0;
    for (final r in relatedTags) {
      if (relatedAdded >= relatedTopN) break;
      final key = _normKey(r.tag);
      if (keptSet.add(key)) {
        keptTokens.add(_toNovelAiTag(r.tag));
        relatedAdded++;
      }
    }

    final calibrated = keptTokens.join(', ');

    // tag → 元数据映射（供 UI 悬浮展示）。
    // key 用归一化键，便于 UI 用 NovelAI 风格 tag 反查元数据。
    final meta = <String, DanbooruTag>{};
    for (final s in searchTags) {
      meta[_normKey(s.tag)] = s;
    }
    for (final r in relatedTags) {
      meta.putIfAbsent(_normKey(r.tag), () => r);
    }

    return CalibrationResult(
      calibratedPositive: calibrated,
      normalizedCount: normalizedCount,
      relatedCount: relatedAdded,
      tagMeta: meta,
    );
  }

  /// 把 prompt 文本拆成单 tag 列表，保留 LLM 原始权重符号。
  List<String> _splitTags(String text) {
    final parts = <String>[];
    final buf = StringBuffer();
    int depth = 0; // 兼容 {} [] () 嵌套
    for (final ch in text.split('')) {
      if (ch == '{' || ch == '[' || ch == '(') depth++;
      if (ch == '}' || ch == ']' || ch == ')')
        depth = depth > 0 ? depth - 1 : 0;
      if (ch == ',' && depth == 0) {
        final piece = buf.toString().trim();
        if (piece.isNotEmpty) parts.add(piece);
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    final tail = buf.toString().trim();
    if (tail.isNotEmpty) parts.add(tail);
    return parts;
  }

  /// 去掉权重符号 {}/[]/()/数字权重，保留核心 tag 文本。
  String _stripWeights(String token) {
    var t = token.trim();
    // 去外层 {}、[]、()
    while (t.length >= 2) {
      final first = t[0];
      final last = t[t.length - 1];
      if ((first == '{' && last == '}') ||
          (first == '[' && last == ']') ||
          (first == '(' && last == ')')) {
        t = t.substring(1, t.length - 1).trim();
      } else {
        break;
      }
    }
    // 去掉 ":1.2" 之类权重
    final colonIdx = t.lastIndexOf(':');
    if (colonIdx > 0 && colonIdx < t.length - 1) {
      final after = t.substring(colonIdx + 1).trim();
      if (RegExp(r'^[0-9]+(\.[0-9]+)?$').hasMatch(after)) {
        t = t.substring(0, colonIdx).trim();
      }
    }
    return t;
  }

  /// Danbooru SD 风格 tag → NovelAI 风格 tag：
  /// 把单词间的下划线转空格（white_serafuku → white serafuku）。
  /// 用于最终拼接到正向提示词的输出值。
  String _toNovelAiTag(String tag) {
    return tag.replaceAll('_', ' ').trim();
  }

  /// NovelAI 风格 tag → Danbooru SD 风格 tag：
  /// 把空格转下划线（white serafuku → white_serafuku），用于发给
  /// /related 等需要标准 SD 索引的接口。
  String _toDanbooruTag(String tag) {
    return tag.trim().replaceAll(RegExp(r'\s+'), '_');
  }

  /// 归一化键：用于 search/related 命中判定与去重。
  /// 统一忽略大小写、去掉首尾空白，并把下划线视同空格——
  /// 这样 LLM 输出的 "white serafuku" 与 Danbooru 返回的 "white_serafuku"
  /// 能正确判定为同一个 tag。
  String _normKey(String tag) {
    return tag.toLowerCase().replaceAll('_', ' ').trim();
  }

  /// 简单启发式：判断一个 token 是否"看起来已是 Danbooru 标准 tag"。
  /// 用于在 search 结果不命中时仍然保留它（避免误删合理输入）。
  bool _looksLikeStandardTag(String tag) {
    if (tag.isEmpty) return false;
    // 只允许 ASCII 字母数字下划线、空格、连字符
    final ascii = RegExp(r'^[a-zA-Z0-9_\- ]+$');
    if (!ascii.hasMatch(tag)) return false;
    // 排除明显是英文短语而非 tag（含多个空格）的情况
    final spaceCount = ' '.allMatches(tag).length;
    return spaceCount <= 2;
  }
}
