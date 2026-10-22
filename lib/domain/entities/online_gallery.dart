/// Public online references are separate from generated images and history.
enum OnlineGallerySource {
  aitag,
  artistRanking,
  danbooru,
  safebooru,
  gelbooru,
  quickTag,
  tagsGallery,
  civitai;

  String get id => switch (this) {
        artistRanking => 'artist-ranking',
        quickTag => 'quicktag',
        tagsGallery => 'tags-gallery',
        _ => name,
      };

  String get label => switch (this) {
        aitag => 'AI TAG',
        artistRanking => '画师排行榜',
        danbooru => 'Danbooru',
        safebooru => 'Safebooru',
        gelbooru => 'Gelbooru',
        quickTag => 'QuickTagCloud',
        tagsGallery => 'TAGs Gallery',
        civitai => 'Civitai',
      };

  String get siteUrl => switch (this) {
        aitag => 'https://aitag.win',
        artistRanking || danbooru => 'https://danbooru.donmai.us',
        safebooru => 'https://safebooru.donmai.us',
        gelbooru => 'https://gelbooru.com',
        quickTag => 'https://novelai.quicktagcloud.com',
        tagsGallery => 'https://tags.gallery',
        civitai => 'https://civitai.com',
      };

  List<String> get sorts => switch (this) {
        danbooru || safebooru => const [
            'default',
            'newest',
            'oldest',
            'score',
            'favorites',
            'random'
          ],
        gelbooru => const ['default', 'newest', 'oldest', 'score', 'random'],
        civitai => const [
            'score',
            'favorites',
            'comments',
            'newest',
            'oldest',
            'random'
          ],
        quickTag => const ['default', 'name', 'name-desc', 'random'],
        tagsGallery => const ['score', 'count', 'name', 'favorites'],
        artistRanking => const ['score', 'name'],
        aitag => const ['default', 'newest', 'favorites'],
      };

  bool get supportsTimeRange =>
      this == danbooru || this == safebooru || this == civitai || this == aitag;

  Map<String, String> get timeRanges {
    if (this != aitag) return galleryTimeRangeLabels;
    final now = DateTime.now();
    return {
      'all': '当前月榜',
      'older': '历史归档',
      for (var offset = 0; offset < 12; offset++)
        'm${DateTime(now.year, now.month - offset).year}-${DateTime(now.year, now.month - offset).month.toString().padLeft(2, '0')}':
            '${DateTime(now.year, now.month - offset).year} 年 ${DateTime(now.year, now.month - offset).month} 月',
      for (var year = now.year; year >= now.year - 4; year--)
        'y$year': '$year 年',
      for (var year = now.year; year >= now.year - 2; year--)
        for (var quarter = 4; quarter >= 1; quarter--)
          'q${year}Q$quarter': '$year 年第 $quarter 季度',
    };
  }

  String get searchHint => switch (this) {
        civitai => '搜索作者用户名（可带 @）',
        quickTag => '搜索画师、画风或提示词',
        artistRanking => '搜索画师名称',
        aitag => '搜索作品或提示词',
        _ => '搜索标签，多个标签用空格分隔',
      };

  static OnlineGallerySource parse(String? value) => values.firstWhere(
        (source) => source.id == value,
        orElse: () => tagsGallery,
      );
}

const gallerySortLabels = <String, String>{
  'default': '默认',
  'newest': '最新',
  'oldest': '最早',
  'score': '评分',
  'favorites': '收藏最多',
  'comments': '评论最多',
  'random': '随机',
  'name': '名称升序',
  'name-desc': '名称降序',
  'count': '投稿最多',
};
const galleryTimeRangeLabels = <String, String>{
  'all': '全部',
  'day': '最近一天',
  'week': '最近一周',
  'month': '最近一月',
  'year': '最近一年',
};

class OnlineGalleryQuery {
  final OnlineGallerySource source;
  final String query, sort, timeRange, model, category;
  final String? collectionId, cursor, collectionType;
  final List<String> categoryPath;
  final int page, pageSize, shuffleSeed;
  final bool safeOnly, searchAll;

  const OnlineGalleryQuery({
    this.source = OnlineGallerySource.tagsGallery,
    this.query = '',
    this.sort = 'score',
    this.timeRange = 'all',
    this.model = 'v5',
    this.category = 'artist',
    this.collectionId,
    this.cursor,
    this.collectionType,
    this.categoryPath = const [],
    this.page = 1,
    this.pageSize = 24,
    this.shuffleSeed = 1,
    this.safeOnly = true,
    this.searchAll = false,
  });

  OnlineGalleryQuery copyWith({
    OnlineGallerySource? source,
    String? query,
    String? sort,
    String? timeRange,
    String? model,
    String? category,
    String? collectionId,
    String? cursor,
    String? collectionType,
    List<String>? categoryPath,
    int? page,
    int? pageSize,
    int? shuffleSeed,
    bool? safeOnly,
    bool? searchAll,
    bool resetCursor = false,
    bool clearCollection = false,
  }) =>
      OnlineGalleryQuery(
        source: source ?? this.source,
        query: query ?? this.query,
        sort: sort ?? this.sort,
        timeRange: timeRange ?? this.timeRange,
        model: model ?? this.model,
        category: category ?? this.category,
        collectionId:
            clearCollection ? null : collectionId ?? this.collectionId,
        cursor: resetCursor ? null : cursor ?? this.cursor,
        collectionType: collectionType ?? this.collectionType,
        categoryPath: categoryPath ?? this.categoryPath,
        page: page ?? this.page,
        pageSize: pageSize ?? this.pageSize,
        shuffleSeed: shuffleSeed ?? this.shuffleSeed,
        safeOnly: safeOnly ?? this.safeOnly,
        searchAll: searchAll ?? this.searchAll,
      );

  Map<String, dynamic> toJson() => {
        'source': source.id,
        'query': query,
        'sort': sort,
        'timeRange': timeRange,
        'model': model,
        'category': category,
        'collectionId': collectionId,
        'collectionType': collectionType,
        'categoryPath': categoryPath,
        'safeOnly': safeOnly,
        'searchAll': searchAll,
        'pageSize': pageSize,
      };

  factory OnlineGalleryQuery.fromJson(Map<String, dynamic> json) {
    final source = OnlineGallerySource.parse(json['source'] as String?);
    final sort = json['sort'] as String? ?? source.sorts.first;
    return OnlineGalleryQuery(
      source: source,
      query: json['query'] as String? ?? '',
      sort: source.sorts.contains(sort) ? sort : source.sorts.first,
      timeRange: source.supportsTimeRange &&
              (source.timeRanges.containsKey(json['timeRange']) ||
                  source == OnlineGallerySource.aitag &&
                      RegExp(r'^(?:current|older|y\d{4}|q\d{4}Q[1-4]|m\d{4}-(?:0[1-9]|1[0-2]))$')
                          .hasMatch(json['timeRange'] as String? ?? ''))
          ? json['timeRange'] as String
          : 'all',
      model: json['model'] == 'v4-5' ? 'v4-5' : 'v5',
      category: json['category'] as String? ?? 'artist',
      collectionId: json['collectionId'] as String?,
      collectionType: json['collectionType'] as String?,
      categoryPath:
          (json['categoryPath'] as List?)?.whereType<String>().toList() ??
              const [],
      safeOnly: json['safeOnly'] != false,
      searchAll: json['searchAll'] == true,
      pageSize: ((json['pageSize'] as num?)?.toInt() ?? 24).clamp(1, 60),
    );
  }
}

class OnlineGalleryMedia {
  final String id, previewUrl, displayUrl, downloadUrl;
  final int width, height;
  final String? extension;

  const OnlineGalleryMedia({
    required this.id,
    this.previewUrl = '',
    this.displayUrl = '',
    this.downloadUrl = '',
    this.width = 0,
    this.height = 0,
    this.extension,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'previewUrl': previewUrl,
        'displayUrl': displayUrl,
        'downloadUrl': downloadUrl,
        'width': width,
        'height': height,
        'extension': extension,
      };

  factory OnlineGalleryMedia.fromJson(Map<String, dynamic> json) =>
      OnlineGalleryMedia(
        id: json['id'] as String? ?? '',
        previewUrl: json['previewUrl'] as String? ?? '',
        displayUrl: json['displayUrl'] as String? ?? '',
        downloadUrl: json['downloadUrl'] as String? ?? '',
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
        extension: json['extension'] as String?,
      );
}

class OnlineGalleryItem {
  final OnlineGallerySource source;
  final String id,
      title,
      author,
      description,
      sourceUrl,
      prompt,
      negativePrompt,
      rating,
      createdAt;
  final String? collectionId;
  final bool isCollection;
  final int score, favoriteCount, viewCount, mediaCount;
  final List<OnlineGalleryMedia> media;
  final List<String> categoryPath;
  final Map<String, List<String>> tags;
  final Map<String, dynamic> metadata;

  const OnlineGalleryItem({
    required this.source,
    required this.id,
    required this.title,
    this.author = '',
    this.description = '',
    this.sourceUrl = '',
    this.prompt = '',
    this.negativePrompt = '',
    this.rating = '',
    this.createdAt = '',
    this.collectionId,
    this.isCollection = false,
    this.score = 0,
    this.favoriteCount = 0,
    this.viewCount = 0,
    this.mediaCount = 1,
    this.media = const [],
    this.categoryPath = const [],
    this.tags = const {},
    this.metadata = const {},
  });

  String get key => '${source.id}:${collectionId ?? ''}:$id';
  OnlineGalleryMedia get cover =>
      media.isEmpty ? OnlineGalleryMedia(id: id) : media.first;

  OnlineGalleryItem copyWith({
    String? title,
    String? author,
    String? description,
    String? sourceUrl,
    String? prompt,
    String? negativePrompt,
    String? rating,
    String? createdAt,
    List<OnlineGalleryMedia>? media,
    Map<String, List<String>>? tags,
    Map<String, dynamic>? metadata,
    List<String>? categoryPath,
  }) =>
      OnlineGalleryItem(
        source: source,
        id: id,
        title: title ?? this.title,
        author: author ?? this.author,
        description: description ?? this.description,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        prompt: prompt ?? this.prompt,
        negativePrompt: negativePrompt ?? this.negativePrompt,
        rating: rating ?? this.rating,
        createdAt: createdAt ?? this.createdAt,
        collectionId: collectionId,
        isCollection: isCollection,
        score: score,
        favoriteCount: favoriteCount,
        viewCount: viewCount,
        mediaCount: mediaCount,
        media: media ?? this.media,
        tags: tags ?? this.tags,
        categoryPath: categoryPath ?? this.categoryPath,
        metadata: metadata ?? this.metadata,
      );

  Map<String, dynamic> toJson() => {
        'source': source.id,
        'id': id,
        'title': title,
        'author': author,
        'description': description,
        'sourceUrl': sourceUrl,
        'prompt': prompt,
        'negativePrompt': negativePrompt,
        'rating': rating,
        'createdAt': createdAt,
        'collectionId': collectionId,
        'isCollection': isCollection,
        'score': score,
        'favoriteCount': favoriteCount,
        'viewCount': viewCount,
        'mediaCount': mediaCount,
        'media': media.map((value) => value.toJson()).toList(),
        'categoryPath': categoryPath,
        'tags': tags,
        'metadata': metadata,
      };

  factory OnlineGalleryItem.fromJson(Map<String, dynamic> json) =>
      OnlineGalleryItem(
        source: OnlineGallerySource.parse(json['source'] as String?),
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        author: json['author'] as String? ?? '',
        description: json['description'] as String? ?? '',
        sourceUrl: json['sourceUrl'] as String? ?? '',
        prompt: json['prompt'] as String? ?? '',
        negativePrompt: json['negativePrompt'] as String? ?? '',
        rating: json['rating'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
        collectionId: json['collectionId'] as String?,
        isCollection: json['isCollection'] == true,
        score: (json['score'] as num?)?.toInt() ?? 0,
        favoriteCount: (json['favoriteCount'] as num?)?.toInt() ?? 0,
        viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
        mediaCount: (json['mediaCount'] as num?)?.toInt() ?? 1,
        media: (json['media'] as List?)
                ?.whereType<Map>()
                .map((v) =>
                    OnlineGalleryMedia.fromJson(Map<String, dynamic>.from(v)))
                .toList() ??
            const [],
        categoryPath:
            (json['categoryPath'] as List?)?.whereType<String>().toList() ??
                const [],
        tags: (json['tags'] as Map?)?.map((k, v) => MapEntry(
                k.toString(), (v as List).whereType<String>().toList())) ??
            const {},
        metadata:
            Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
      );
}

class OnlineGalleryCollection {
  final String id, title, type, version;
  final int count;
  const OnlineGalleryCollection(
      {required this.id,
      required this.title,
      this.count = 0,
      this.type = '',
      this.version = ''});
}

class OnlineGalleryCategory {
  final List<String> path;
  final String title;
  final int count;
  const OnlineGalleryCategory(
      {required this.path, required this.title, this.count = 0});
}

class OnlineGalleryPage {
  final List<OnlineGalleryItem> items;
  final bool hasMore;
  final String? nextCursor;
  final int? total;
  final String title;
  final List<OnlineGalleryCollection> collections;
  final List<OnlineGalleryCategory> categories;
  final List<String> warnings;
  const OnlineGalleryPage(
      {required this.items,
      this.hasMore = false,
      this.nextCursor,
      this.total,
      this.title = '',
      this.collections = const [],
      this.categories = const [],
      this.warnings = const []});
}

class OnlineGalleryDownloadResult {
  final int saved, failed;
  final List<String> paths;
  const OnlineGalleryDownloadResult(
      {required this.saved, this.failed = 0, this.paths = const []});
}

class OnlineGalleryCredentials {
  final String userId, apiKey;
  const OnlineGalleryCredentials({required this.userId, required this.apiKey});
}
