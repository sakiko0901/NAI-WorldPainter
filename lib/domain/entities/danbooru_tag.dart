import 'package:equatable/equatable.dart';

/// Danbooru 校准引擎返回的单个 tag。
///
/// 来源：DanbooruSearchOnline 的 /search 与 /related 端点。
/// 字段语义沿用上游 TagOut / RelatedTagOut，所有字段都允许默认空值，
/// 以便兼容两个端点的字段差异。
class DanbooruTag extends Equatable {
  /// Danbooru 真实 tag 名（英文，如 white_serafuku）
  final String tag;

  /// 中文名（可能为空）
  final String cnName;

  /// 类别：General / Character / Copyright / Artist / Meta
  final String category;

  /// NSFW 等级：'safe' / 'questionable' / 'explicit' 等，原始字符串
  final String nsfw;

  /// Danbooru 上的图数（热度）
  final int count;

  /// 综合得分（仅 /search 返回）
  final double finalScore;

  /// wiki 释义（可能为空）
  final String wiki;

  /// 来源标签（仅 /related 返回，对应触发它的种子 tag 列表）
  final List<String> sources;

  /// 来源类型：'search' 表示来自 /search，'related' 表示来自 /related
  final String origin;

  const DanbooruTag({
    required this.tag,
    this.cnName = '',
    this.category = '',
    this.nsfw = '',
    this.count = 0,
    this.finalScore = 0,
    this.wiki = '',
    this.sources = const [],
    this.origin = '',
  });

  bool get isNsfw {
    final n = nsfw.toLowerCase();
    return n == 'questionable' ||
        n == 'explicit' ||
        n == 'r' ||
        n == 'q' ||
        n == 'e';
  }

  @override
  List<Object?> get props => [tag, origin];
}
