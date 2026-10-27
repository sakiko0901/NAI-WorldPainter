import 'package:nai_huishi/core/constants/api_constants.dart';

/// The native NovelAI protocol can use either its default host or a relay.
class NovelAiConnection {
  NovelAiConnection._();

  static String normalizeBaseUrl(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) return ApiConstants.officialImageBaseUrl;
    return Uri.tryParse(trimmed)?.toString() ?? trimmed;
  }

  static bool isCustomBaseUrl(String value) =>
      normalizeBaseUrl(value) != ApiConstants.officialImageBaseUrl;

  static String? validateBaseUrl(String value) {
    if (value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !const ['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return '请输入完整的 http:// 或 https:// 地址，不含账号、查询参数或锚点';
    }
    return null;
  }
}
