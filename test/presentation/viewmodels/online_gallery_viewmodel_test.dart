import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/online_gallery.dart';
import 'package:nai_huishi/domain/repositories/online_gallery_repository.dart';
import 'package:nai_huishi/presentation/viewmodels/online_gallery_viewmodel.dart';

void main() {
  late _GalleryRepositoryFake repository;
  late OnlineGalleryViewModel viewModel;

  setUp(() {
    repository = _GalleryRepositoryFake();
    viewModel = OnlineGalleryViewModel(repository);
  });

  tearDown(() => viewModel.dispose());

  test('a stale search response cannot replace the latest result', () async {
    final slow = Completer<OnlineGalleryPage>();
    repository.searchOverride = (query) => query.query == 'slow'
        ? slow.future
        : Future.value(OnlineGalleryPage(items: [_item('latest')]));

    final oldRequest = viewModel.search(
      const OnlineGalleryQuery(query: 'slow'),
    );
    await viewModel.search(const OnlineGalleryQuery(query: 'latest'));
    slow.complete(OnlineGalleryPage(items: [_item('stale')]));
    await oldRequest;

    expect(viewModel.items.map((item) => item.id), ['latest']);
  });

  test('an empty cursor page remains continuable', () async {
    repository.searchOverride = (query) async {
      repository.queries.add(query);
      if (query.page == 1) {
        return const OnlineGalleryPage(
          items: [],
          hasMore: true,
          nextCursor: 'opaque-cursor-2',
        );
      }
      return OnlineGalleryPage(items: [_item('next')]);
    };

    await viewModel.search(const OnlineGalleryQuery(
      source: OnlineGallerySource.civitai,
      query: 'artist_name',
    ));
    expect(viewModel.hasMore, isTrue);
    expect(viewModel.items, isEmpty);

    await viewModel.loadMore();

    expect(repository.queries.last.cursor, 'opaque-cursor-2');
    expect(viewModel.items.map((item) => item.id), ['next']);
  });

  test('favorite state changes only after repository confirms the write',
      () async {
    final item = _item('favorite-candidate');
    repository.favoriteWriteError = StateError('disk unavailable');

    final succeeded = await viewModel.setFavorite(item, true);

    expect(succeeded, isFalse);
    expect(viewModel.isFavorite(item), isFalse);
    expect(viewModel.favoritesErrorMessage, contains('收藏操作失败'));
  });

  test('opening a favorite collection switches to its own source', () async {
    const collection = OnlineGalleryItem(
      source: OnlineGallerySource.quickTag,
      id: 'soft-collection',
      title: 'Soft collection',
      collectionId: 'soft-collection',
      isCollection: true,
      metadata: {'collectionType': 'artist'},
    );
    repository.favoriteItems = [collection];
    await viewModel.search(
      const OnlineGalleryQuery(source: OnlineGallerySource.tagsGallery),
    );
    expect(await viewModel.setFavoritesMode(true), isTrue);

    await viewModel.enterCollection(collection);

    expect(viewModel.isShowingFavorites, isFalse);
    expect(repository.queries.last.source, OnlineGallerySource.quickTag);
    expect(repository.queries.last.collectionId, 'soft-collection');
    expect(repository.queries.last.collectionType, 'artist');
  });

  test('search shows sanitized format errors and hides URLs and credentials',
      () async {
    repository.searchOverride = (_) async => throw const FormatException(
          'bad response https://gallery.example/private?token=url-secret '
          'apiKey=visible-secret',
        );

    await viewModel.search(const OnlineGalleryQuery());

    expect(viewModel.errorMessage, contains('bad response'));
    expect(viewModel.errorMessage, isNot(contains('https://')));
    expect(viewModel.errorMessage, isNot(contains('visible-secret')));
    expect(viewModel.errorMessage, isNot(contains('url-secret')));
  });
}

OnlineGalleryItem _item(String id) => OnlineGalleryItem(
      source: OnlineGallerySource.tagsGallery,
      id: id,
      title: id,
    );

class _GalleryRepositoryFake implements OnlineGalleryRepository {
  final List<OnlineGalleryQuery> queries = [];
  Future<OnlineGalleryPage> Function(OnlineGalleryQuery query)? searchOverride;
  Object? favoriteWriteError;
  List<OnlineGalleryItem> favoriteItems = [];

  @override
  Future<OnlineGalleryPage> search(OnlineGalleryQuery query) {
    queries.add(query);
    return searchOverride?.call(query) ??
        Future.value(const OnlineGalleryPage(items: []));
  }

  @override
  Future<OnlineGalleryItem> detail(OnlineGalleryItem item,
          {bool safeOnly = true}) async =>
      item;

  @override
  Future<List<OnlineGalleryItem>> favorites() async => favoriteItems;

  @override
  Future<void> setFavorite(OnlineGalleryItem item, bool value) async {
    if (favoriteWriteError case final error?) throw error;
  }

  @override
  Future<OnlineGalleryQuery?> loadLastQuery() async => null;

  @override
  Future<void> saveQuery(OnlineGalleryQuery query) async {}

  @override
  Future<String?> previewPath(
    OnlineGalleryItem item,
    OnlineGalleryMedia media,
  ) async =>
      null;

  @override
  Future<OnlineGalleryDownloadResult> download(
    OnlineGalleryItem item,
    List<OnlineGalleryMedia> media,
  ) async =>
      OnlineGalleryDownloadResult(saved: media.length);

  @override
  Future<void> saveStyle(OnlineGalleryItem item) async {}

  @override
  Future<void> openSource(OnlineGalleryItem item) async {}

  @override
  Future<void> clearCache() async {}

  @override
  Future<bool> hasGelbooruCredentials() async => true;

  @override
  Future<void> setGelbooruCredentials(
    OnlineGalleryCredentials credentials,
  ) async {}
}
