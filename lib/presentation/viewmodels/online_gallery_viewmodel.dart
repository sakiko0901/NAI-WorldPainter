import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:nai_huishi/domain/entities/online_gallery.dart';
import 'package:nai_huishi/domain/repositories/online_gallery_repository.dart';

/// UI state for the public online gallery. Search and favorites stay separate
/// from generated history and never enqueue generation work.
class OnlineGalleryViewModel extends ChangeNotifier {
  OnlineGalleryViewModel(this._repository);

  final OnlineGalleryRepository _repository;
  final Random _random = Random();
  Future<void> _pendingQuerySave = Future<void>.value();

  OnlineGalleryQuery _query = const OnlineGalleryQuery();
  OnlineGalleryPage _page = const OnlineGalleryPage(items: []);
  List<OnlineGalleryItem> _items = const [];
  List<OnlineGalleryItem> _favorites = const [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isLoadingFavorites = false;
  bool _showFavorites = false;
  String? _errorMessage;
  String? _loadMoreErrorMessage;
  String? _favoritesErrorMessage;
  int _searchSequence = 0;
  int _favoritesSequence = 0;
  bool _initialized = false;
  bool _userChangedQuery = false;
  bool _disposed = false;
  final Set<String> _favoriteOperations = {};

  OnlineGalleryQuery get query => _query;
  OnlineGalleryPage get page => _page;
  List<OnlineGalleryItem> get items => List.unmodifiable(_items);
  List<OnlineGalleryItem> get favorites => List.unmodifiable(_favorites);
  List<OnlineGalleryItem> get visibleItems =>
      _showFavorites ? favorites : items;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isLoadingFavorites => _isLoadingFavorites;
  bool get isShowingFavorites => _showFavorites;
  bool get hasMore => _page.hasMore;
  String? get errorMessage => _errorMessage;
  String? get loadMoreErrorMessage => _loadMoreErrorMessage;
  String? get favoritesErrorMessage => _favoritesErrorMessage;
  OnlineGalleryRepository get repository => _repository;

  bool isFavorite(OnlineGalleryItem item) =>
      _favorites.any((favorite) => favorite.key == item.key);

  bool isFavoriteBusy(OnlineGalleryItem item) =>
      _favoriteOperations.contains(item.key);

  /// Restores the last search once. A user action that happens while the
  /// preference read is pending takes precedence over that older snapshot.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final saved = await _repository.loadLastQuery();
      if (!_disposed && !_userChangedQuery && saved != null) {
        _query = _normalizeQuery(saved).copyWith(page: 1, resetCursor: true);
      }
    } catch (_) {
      // A failed preference read should not prevent the public gallery opening.
    }
    if (_disposed) return;
    await Future.wait([search(_query, persist: false), loadFavorites()]);
  }

  Future<void> search(
    OnlineGalleryQuery nextQuery, {
    bool persist = true,
  }) async {
    if (_disposed) return;
    _userChangedQuery = true;
    final request =
        _normalizeQuery(nextQuery).copyWith(page: 1, resetCursor: true);
    final sequence = ++_searchSequence;
    _query = request;
    _page = const OnlineGalleryPage(items: []);
    _items = const [];
    _isLoading = true;
    _isLoadingMore = false;
    _errorMessage = null;
    _loadMoreErrorMessage = null;
    _notify();

    try {
      final result = await _repository.search(request);
      if (_disposed || sequence != _searchSequence) return;
      _page = result;
      _items = _uniqueItems(result.items);
      _query = request.copyWith(
        cursor: result.nextCursor,
        resetCursor: result.nextCursor == null,
      );
      if (persist) _queueSaveQuery(request);
    } catch (error) {
      if (_disposed || sequence != _searchSequence) return;
      _errorMessage = _safeErrorMessage(error, '加载失败，请检查网络后重试');
      if (persist) _queueSaveQuery(request);
    } finally {
      if (!_disposed && sequence == _searchSequence) {
        _isLoading = false;
        _notify();
      }
    }
  }

  Future<void> retrySearch() => search(_query, persist: false);

  /// Advances with both numeric pages and opaque cursors. An empty page with
  /// a non-empty next cursor remains continuable (notably Civitai).
  Future<void> loadMore() async {
    if (_disposed || _isLoading || _isLoadingMore || !_page.hasMore) return;
    final sequence = ++_searchSequence;
    final request = _query.copyWith(page: _query.page + 1);
    _isLoadingMore = true;
    _loadMoreErrorMessage = null;
    _notify();

    try {
      final result = await _repository.search(request);
      if (_disposed || sequence != _searchSequence) return;
      _page = result;
      _items = _uniqueItems([..._items, ...result.items]);
      _query = request.copyWith(
        cursor: result.nextCursor,
        resetCursor: result.nextCursor == null,
      );
    } catch (error) {
      if (_disposed || sequence != _searchSequence) return;
      _loadMoreErrorMessage = _safeErrorMessage(error, '继续加载失败，请重试');
    } finally {
      if (!_disposed && sequence == _searchSequence) {
        _isLoadingMore = false;
        _notify();
      }
    }
  }

  Future<void> refresh({bool clearCache = false}) async {
    if (clearCache) {
      try {
        await _repository.clearCache();
      } catch (_) {
        // Keep refresh available even if cache maintenance fails.
      }
    }
    await search(_query, persist: false);
  }

  Future<void> changeSource(OnlineGallerySource source) async {
    if (_query.source == source) return;
    _showFavorites = false;
    final category = source == OnlineGallerySource.tagsGallery ? 'artist' : '';
    final next = OnlineGalleryQuery(
      source: source,
      query: '',
      sort: source.sorts.first,
      timeRange: 'all',
      model: _query.model,
      category: category,
      pageSize: _query.pageSize,
      safeOnly: _query.safeOnly,
      shuffleSeed: _query.shuffleSeed,
    );
    await search(next);
  }

  Future<void> updateQuery(OnlineGalleryQuery nextQuery) => search(nextQuery);

  Future<bool> setFavoritesMode(bool value) async {
    if (_showFavorites == value) return true;
    if (value && !await loadFavorites()) return false;
    _showFavorites = value;
    _notify();
    return true;
  }

  Future<bool> loadFavorites() async {
    if (_disposed) return false;
    final sequence = ++_favoritesSequence;
    _isLoadingFavorites = true;
    _favoritesErrorMessage = null;
    _notify();
    try {
      final result = await _repository.favorites();
      if (_disposed || sequence != _favoritesSequence) return false;
      _favorites = _uniqueItems(result);
      return true;
    } catch (_) {
      if (_disposed || sequence != _favoritesSequence) return false;
      _favoritesErrorMessage = '加载收藏失败，请重试';
      return false;
    } finally {
      if (!_disposed && sequence == _favoritesSequence) {
        _isLoadingFavorites = false;
        _notify();
      }
    }
  }

  /// A favorite is reflected only after the repository confirms the write.
  Future<bool> setFavorite(OnlineGalleryItem item, bool value) async {
    if (_disposed || _favoriteOperations.contains(item.key)) return false;
    _favoriteOperations.add(item.key);
    _notify();
    try {
      await _repository.setFavorite(item, value);
      if (_disposed) return false;
      _favorites = value
          ? _uniqueItems([..._favorites, item])
          : _favorites.where((favorite) => favorite.key != item.key).toList();
      return true;
    } catch (_) {
      _favoritesErrorMessage = '收藏操作失败，请重试';
      return false;
    } finally {
      _favoriteOperations.remove(item.key);
      _notify();
    }
  }

  Future<void> enterCollection(OnlineGalleryItem item) async {
    _showFavorites = false;
    final collectionId = item.collectionId ?? item.id;
    final source = item.source;
    final baseQuery = _query.source == source
        ? _query
        : OnlineGalleryQuery(
            source: source,
            sort: source.sorts.first,
            timeRange: source.timeRanges.keys.first,
            model: _query.model,
            category: source == OnlineGallerySource.tagsGallery ? 'artist' : '',
            pageSize: _query.pageSize,
            safeOnly: _query.safeOnly,
            shuffleSeed: _query.shuffleSeed,
          );
    await search(baseQuery.copyWith(
      query: '',
      collectionId: collectionId,
      collectionType: item.metadata['collectionType']?.toString() ?? '',
      categoryPath: const [],
      searchAll: false,
      resetCursor: true,
    ));
  }

  Future<void> leaveCollection() async {
    await search(_query.copyWith(
      query: '',
      clearCollection: true,
      collectionType: '',
      categoryPath: const [],
      searchAll: false,
      resetCursor: true,
    ));
  }

  Future<void> chooseCategory(OnlineGalleryCategory category) async {
    await search(_query.copyWith(
      categoryPath: List.unmodifiable(category.path),
      category: category.path.isEmpty ? _query.category : category.path.first,
      clearCollection: _query.source == OnlineGallerySource.tagsGallery,
      collectionType: '',
      resetCursor: true,
    ));
  }

  Future<void> shuffle() async {
    await search(_query.copyWith(
      sort: 'random',
      shuffleSeed: _random.nextInt(0x7fffffff),
      resetCursor: true,
    ));
  }

  Future<void> saveGelbooruCredentials(OnlineGalleryCredentials credentials) =>
      _repository.setGelbooruCredentials(credentials);

  OnlineGalleryQuery _normalizeQuery(OnlineGalleryQuery query) {
    final source = query.source;
    return query.copyWith(
      sort: source.sorts.contains(query.sort) ? query.sort : source.sorts.first,
      timeRange: source.supportsTimeRange &&
              source.timeRanges.containsKey(query.timeRange)
          ? query.timeRange
          : source.timeRanges.keys.first,
      model: source == OnlineGallerySource.tagsGallery
          ? (query.model == 'v4-5' ? 'v4-5' : 'v5')
          : query.model,
      pageSize: query.pageSize.clamp(1, 60),
    );
  }

  List<OnlineGalleryItem> _uniqueItems(Iterable<OnlineGalleryItem> values) {
    final seen = <String>{};
    return values.where((item) => seen.add(item.key)).toList(growable: false);
  }

  String _safeErrorMessage(Object error, String fallback) {
    final message = switch (error) {
      StateError() => error.message,
      FormatException() => error.message,
      _ => null,
    };
    if (message == null || message.trim().isEmpty) return fallback;
    var safe = message
        .replaceAll(RegExp(r'https?://[^\s]+', caseSensitive: false), '[来源地址]')
        .replaceAllMapped(
          RegExp(
            r'\b(api[\s_-]?key|token|user[\s_-]?id|password)\b\s*[:=]\s*[^,\s;]+',
            caseSensitive: false,
          ),
          (match) => '${match[1]}=***',
        )
        .trim();
    if (safe.isEmpty) return fallback;
    if (safe.length > 160) safe = '${safe.substring(0, 157)}…';
    return safe;
  }

  void _queueSaveQuery(OnlineGalleryQuery query) {
    final value = query.copyWith(page: 1, resetCursor: true);
    _pendingQuerySave = _pendingQuerySave
        .then((_) => _repository.saveQuery(value))
        .catchError((Object _) {});
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
