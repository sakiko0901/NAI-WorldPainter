import 'package:equatable/equatable.dart';

/// Pixiv 上传相关的全部用户配置
class PixivSettings extends Equatable {
  final String cookie;
  final String csrfToken;
  final String proxy; // 形如 "http://127.0.0.1:7890"，空字符串表示直连
  final String captionPrefix;
  final List<String> defaultTags;
  final bool r18Default;
  final bool allowTagEdit;
  final bool stripMetadata;
  final bool suggestTagsEnabled;
  final int cooldownMinutes;
  final double repTagsPercent; // 0~1，>=1 表示不替换
  final String repTagsFill;
  final String junkText;

  const PixivSettings({
    required this.cookie,
    required this.csrfToken,
    required this.proxy,
    required this.captionPrefix,
    required this.defaultTags,
    required this.r18Default,
    required this.allowTagEdit,
    required this.stripMetadata,
    required this.suggestTagsEnabled,
    required this.cooldownMinutes,
    required this.repTagsPercent,
    required this.repTagsFill,
    required this.junkText,
  });

  PixivSettings copyWith({
    String? cookie,
    String? csrfToken,
    String? proxy,
    String? captionPrefix,
    List<String>? defaultTags,
    bool? r18Default,
    bool? allowTagEdit,
    bool? stripMetadata,
    bool? suggestTagsEnabled,
    int? cooldownMinutes,
    double? repTagsPercent,
    String? repTagsFill,
    String? junkText,
  }) {
    return PixivSettings(
      cookie: cookie ?? this.cookie,
      csrfToken: csrfToken ?? this.csrfToken,
      proxy: proxy ?? this.proxy,
      captionPrefix: captionPrefix ?? this.captionPrefix,
      defaultTags: defaultTags ?? this.defaultTags,
      r18Default: r18Default ?? this.r18Default,
      allowTagEdit: allowTagEdit ?? this.allowTagEdit,
      stripMetadata: stripMetadata ?? this.stripMetadata,
      suggestTagsEnabled: suggestTagsEnabled ?? this.suggestTagsEnabled,
      cooldownMinutes: cooldownMinutes ?? this.cooldownMinutes,
      repTagsPercent: repTagsPercent ?? this.repTagsPercent,
      repTagsFill: repTagsFill ?? this.repTagsFill,
      junkText: junkText ?? this.junkText,
    );
  }

  bool get hasCredentials => cookie.trim().isNotEmpty && csrfToken.trim().isNotEmpty;

  @override
  List<Object?> get props => [
        cookie,
        csrfToken,
        proxy,
        captionPrefix,
        defaultTags,
        r18Default,
        allowTagEdit,
        stripMetadata,
        suggestTagsEnabled,
        cooldownMinutes,
        repTagsPercent,
        repTagsFill,
        junkText,
      ];
}
