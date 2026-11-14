import 'package:nai_huishi/domain/entities/llm_session.dart';

class LlmSessionSearchResult {
  final LlmSession session;

  /// 最新命中消息中，匹配位置附近最多 160 个字符；仅标题命中或空查询时为 null。
  final String? snippet;

  const LlmSessionSearchResult({required this.session, this.snippet});
}
