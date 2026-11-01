import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nai_huishi/data/datasources/local/tag_completion_catalog.dart';
import 'package:nai_huishi/data/datasources/remote/danbooru_api_service.dart';
import 'package:nai_huishi/domain/entities/tag_completion.dart';

/// Shared data and preferences; each editor owns its query/focus lifecycle.
class TagCompletionService extends ChangeNotifier {
  TagCompletionService({TagCompletionCatalog? catalog, DanbooruApiService? api})
      : catalog = catalog ?? TagCompletionCatalog(),
        _api = api ?? DanbooruApiService();
  static final instance = TagCompletionService();
  final TagCompletionCatalog catalog;
  final DanbooruApiService _api;
  final _cache = <String, List<TagCompletion>>{};
  final _remoteCache = <String, List<TagCompletion>>{};
  Future<void>? _initializing;
  bool enabled = true;
  bool showTranslation = true;
  bool onlineEnabled = false;
  bool autoComma = true;

  Future<void> initialize() => _initializing ??= _load();
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool('tag_completion.enabled') ?? true;
      showTranslation = prefs.getBool('tag_completion.translation') ?? true;
      onlineEnabled = prefs.getBool('tag_completion.online') ?? false;
      autoComma = prefs.getBool('tag_completion.comma') ?? true;
    } catch (_) {/* Defaults also work when preferences are unavailable. */}
  }

  Future<void> update(
      {bool? enabled,
      bool? showTranslation,
      bool? onlineEnabled,
      bool? autoComma}) async {
    await initialize();
    this.enabled = enabled ?? this.enabled;
    this.showTranslation = showTranslation ?? this.showTranslation;
    this.onlineEnabled = onlineEnabled ?? this.onlineEnabled;
    this.autoComma = autoComma ?? this.autoComma;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool('tag_completion.enabled', this.enabled),
      prefs.setBool('tag_completion.translation', this.showTranslation),
      prefs.setBool('tag_completion.online', this.onlineEnabled),
      prefs.setBool('tag_completion.comma', this.autoComma),
    ]);
  }

  Future<List<TagCompletion>> search(String query,
      {bool artistOnly = false}) async {
    final key = '$artistOnly:$query';
    if (_cache.containsKey(key)) return _cache[key]!;
    final result = await catalog.search(query, artistOnly: artistOnly);
    _remember(_cache, key, result);
    return result;
  }

  Future<List<TagCompletion>> online(String query,
      {bool related = false, CancelToken? cancelToken}) async {
    final key = '$related:$query';
    if (_remoteCache.containsKey(key)) return _remoteCache[key]!;
    final results = related
        ? await _api.related(
            tags: [query], limit: 32, showNsfw: true, cancelToken: cancelToken)
        : await _api.search(
            query: query.replaceAll('_', ' '),
            limit: 20,
            showNsfw: true,
            cancelToken: cancelToken);
    final candidates = results
        .map((t) => TagCompletion(
            tag: normalizeCompletionTag(t.tag),
            translation: t.cnName,
            count: t.count,
            online: true,
            category: switch (t.category.toLowerCase()) {
              'artist' => 1,
              'copyright' => 3,
              'character' => 4,
              'meta' => 5,
              _ => 0,
            }))
        .toList(growable: false);
    _remember(_remoteCache, key, candidates);
    return candidates;
  }

  void _remember(Map<String, List<TagCompletion>> cache, String key,
      List<TagCompletion> value) {
    cache[key] = value;
    if (cache.length > 80) cache.remove(cache.keys.first);
  }
}
