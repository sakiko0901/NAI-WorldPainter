import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nai_huishi/data/datasources/local/online_gallery_local_store.dart';
import 'package:nai_huishi/data/datasources/local/online_gallery_media_store.dart';
import 'package:nai_huishi/data/datasources/remote/gallery/gallery_adapter.dart';
import 'package:nai_huishi/data/datasources/remote/gallery/gallery_http.dart';
import 'package:nai_huishi/data/repositories/online_gallery_repository_impl.dart';
import 'package:nai_huishi/domain/entities/online_gallery.dart';
import 'package:nai_huishi/domain/entities/style_preset.dart';
import 'package:nai_huishi/domain/repositories/style_preset_repository.dart';
import 'package:nai_huishi/domain/usecases/manage_style_presets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late Directory directory;
  late _ImageTransport transport;
  late GalleryHttp http;
  late OnlineGalleryMediaStore media;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'existing_generation_key': 'preserve'});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    directory =
        await Directory.systemTemp.createTemp('online_gallery_storage_');
    transport = _ImageTransport();
    final dio = GalleryHttp.createDio()..httpClientAdapter = transport;
    http = GalleryHttp(dio);
    media = OnlineGalleryMediaStore(
      http,
      cacheDirectory: () async => Directory('${directory.path}/cache'),
      downloadDirectory: () async => Directory('${directory.path}/originals'),
      saveToAlbum: (path) async => true,
    );
  });
  tearDown(() async {
    http.dio.close(force: true);
    await directory.delete(recursive: true);
  });

  test(
      'favorite add/update/remove survives reopen without touching generation keys',
      () async {
    final store = OnlineGalleryLocalStore(prefs);
    await Future.wait([
      store.setFavorite(_item('one'), true),
      store.setFavorite(_item('two'), true),
    ]);
    await store.setFavorite(
        _item('one').copyWith(prompt: 'new exact prompt'), true);
    final reopened =
        OnlineGalleryLocalStore(await SharedPreferences.getInstance());
    final favorites = await reopened.favorites();
    expect(favorites, hasLength(2));
    expect(favorites.first.prompt, 'new exact prompt');
    expect(favorites.first.media.single.downloadUrl,
        'https://cdn.example.test/image.png');
    expect(prefs.getString('existing_generation_key'), 'preserve');
    await reopened.setFavorite(_item('one'), false);
    expect((await store.favorites()).single.id, 'two');
  });

  test('TAGs V4.5/V5 and QuickTag collection ids remain separate favorites',
      () async {
    final store = OnlineGalleryLocalStore(prefs);
    await store.setFavorite(_item('artist/example'), true);
    await store.setFavorite(_item('v5/artist/example'), true);
    for (final id in ['collection-a', 'collection-b']) {
      await store.setFavorite(
          OnlineGalleryItem(
              source: OnlineGallerySource.quickTag,
              id: 'same-id',
              title: 'Entry',
              collectionId: id),
          true);
    }
    expect(await store.favorites(), hasLength(4));
  });

  test('saved query restores filters and resets transient pagination',
      () async {
    final store = OnlineGalleryLocalStore(prefs);
    const query = OnlineGalleryQuery(
        source: OnlineGallerySource.civitai,
        query: '@synthetic-author',
        sort: 'favorites',
        timeRange: 'week',
        page: 3,
        cursor: 'opaque-private-cursor',
        safeOnly: true);
    await store.saveQuery(query);
    final loaded = OnlineGalleryLocalStore(prefs).loadQuery()!;
    expect(loaded.query, '@synthetic-author');
    expect(loaded.sort, 'favorites');
    expect(loaded.page, 1);
    expect(loaded.cursor, isNull);
    expect(prefs.getString(OnlineGalleryLocalStore.queryKey),
        isNot(contains('opaque-private-cursor')));
  });

  test('corrupt favorite data is not silently overwritten', () async {
    await prefs.setString(OnlineGalleryLocalStore.favoritesKey, 'invalid-json');
    final store = OnlineGalleryLocalStore(prefs);
    await expectLater(
        store.setFavorite(_item('new'), true), throwsFormatException);
    expect(
        prefs.getString(OnlineGalleryLocalStore.favoritesKey), 'invalid-json');
  });

  test('Gelbooru credentials use secure storage only and can be cleared',
      () async {
    final store = OnlineGalleryCredentialStore();
    await store.write(
        const OnlineGalleryCredentials(userId: '123', apiKey: 'synthetic-key'));
    final loaded = await OnlineGalleryCredentialStore().read();
    expect(loaded!.userId, '123');
    expect(loaded.apiKey, 'synthetic-key');
    expect(prefs.getKeys(), isNot(contains(OnlineGalleryCredentialStore.key)));
    await store.write(const OnlineGalleryCredentials(userId: '', apiKey: ''));
    expect(await store.read(), isNull);
  });

  test(
      'preview cache deduplicates concurrent requests and clear preserves originals and bookmarks',
      () async {
    final item = _item('one');
    final store = OnlineGalleryLocalStore(prefs);
    await store.setFavorite(item, true);
    final paths = await Future.wait(
        List.generate(5, (_) => media.preview(item, item.cover)));
    expect(paths.toSet(), hasLength(1));
    expect(transport.requests, hasLength(1));
    expect(await File(paths.first!).readAsBytes(), transport.image);
    final original = await media.original(item, item.cover);
    await media.clearCache();
    expect(await File(paths.first!).exists(), isFalse);
    expect(await File(original).exists(), isTrue);
    expect(await store.favorites(), hasLength(1));
  });

  test(
      'originals preserve exact bytes and simultaneous downloads do not duplicate album writes',
      () async {
    final saved = <String>[];
    final store = OnlineGalleryMediaStore(http,
        cacheDirectory: () async => Directory('${directory.path}/cache'),
        downloadDirectory: () async => Directory('${directory.path}/originals'),
        saveToAlbum: (path) async {
          saved.add(path);
          return true;
        });
    final item = _item('one');
    final results = await Future.wait([
      store.download(item, item.media),
      store.download(item, item.media),
    ]);
    expect(results.map((r) => r.saved), [1, 1]);
    expect(saved, hasLength(1));
    expect(transport.requests, hasLength(1));
    expect(await File(saved.single).readAsBytes(), transport.image);
    expect(transport.requests.single.headers['Authorization'], isNull);
  });

  test(
      'different display fallback downloads stay distinct and duplicate media saves once',
      () async {
    var albumCalls = 0;
    final store = OnlineGalleryMediaStore(http,
        downloadDirectory: () async => Directory('${directory.path}/originals'),
        saveToAlbum: (_) async {
          albumCalls++;
          return true;
        });
    const first = OnlineGalleryMedia(
        id: 'a', displayUrl: 'https://cdn.example.test/a.png');
    const second = OnlineGalleryMedia(
        id: 'b', displayUrl: 'https://cdn.example.test/b.png');
    final result = await Future.wait([
      store.download(_item('one'), [first, first]),
      store.download(_item('one'), [second]),
    ]);
    expect(result.map((value) => value.saved), [1, 1]);
    expect(result.map((value) => value.paths.single).toSet(), hasLength(2));
    expect(albumCalls, 2);
  });

  test('invalid image response never reaches album and failed save is reported',
      () async {
    final validImage = transport.image;
    transport.image =
        Uint8List.fromList(utf8.encode('<html>rate limited</html>'));
    var albumCalls = 0;
    final store = OnlineGalleryMediaStore(http,
        downloadDirectory: () async => Directory('${directory.path}/originals'),
        saveToAlbum: (_) async {
          albumCalls++;
          return false;
        });
    final item = _item('one');
    final result = await store.download(item, item.media);
    expect(result.saved, 0);
    expect(result.failed, 1);
    expect(albumCalls, 0);
    transport.image = validImage;
    final rejected = await store.download(item, item.media);
    expect(rejected.saved, 0);
    expect(rejected.failed, 1);
    expect(albumCalls, 1);
  });

  test('non-HTTPS/private image URLs and redirect targets never fetch',
      () async {
    for (final url in [
      'http://example.test/a.png',
      'file:///a.png',
      'https://127.0.0.1/a.png',
      'https://localhost/a.png',
      'https://user:password@example.test/a.png'
    ]) {
      final item = OnlineGalleryItem(
          source: OnlineGallerySource.tagsGallery,
          id: 'invalid',
          title: 'Invalid',
          media: [OnlineGalleryMedia(id: 'image', downloadUrl: url)]);
      await expectLater(media.original(item, item.cover), throwsArgumentError);
    }
    expect(transport.requests, isEmpty);
    transport.redirect = 'https://127.0.0.1/private';
    await expectLater(
        http.json('https://source.example.test/api'), throwsStateError);
    expect(transport.requests, hasLength(1));
  });

  test(
      'repository enriches durable favorites and isolates safe/unsafe detail caches',
      () async {
    final adapter = _GalleryAdapter();
    final repository = _repository(adapter, prefs, media);
    final item = _item('one');
    final pair =
        await Future.wait([repository.detail(item), repository.detail(item)]);
    expect(pair.first.prompt, 'hydrated prompt');
    expect(adapter.detailCalls, 1);
    await repository.detail(item, safeOnly: false);
    expect(adapter.detailCalls, 2);
    await repository.setFavorite(item, true);
    expect((await repository.favorites()).single.prompt, 'hydrated prompt');
  });

  test(
      'saving style uses an existing persistent style repository and does not duplicate',
      () async {
    final adapter = _GalleryAdapter();
    final styles = _Styles();
    final repository = _repository(adapter, prefs, media, styles: styles);
    await repository.saveStyle(_item('one'));
    await repository.saveStyle(_item('one'));
    expect(styles.items, hasLength(1));
    expect(styles.items.single.prompt, 'exact weighted prompt');
    expect(await File(styles.sourcePath!).readAsBytes(), transport.image);
  });

  test('favorites hydrate using the browsing mode of the selected item',
      () async {
    final adapter = _GalleryAdapter();
    final repository = _repository(adapter, prefs, media);
    final page =
        await repository.search(const OnlineGalleryQuery(safeOnly: false));
    expect(page.items.single.metadata['safeOnly'], isFalse);
    await repository.setFavorite(page.items.single, true);
    expect(adapter.detailModes, [false]);
    expect((await repository.favorites()).single.metadata['safeOnly'], isFalse);
  });

  test(
      'cache clear gates new previews until existing writes and cleanup finish',
      () async {
    final release = Completer<void>();
    final started = Completer<void>();
    transport.block = release.future;
    transport.started = started;
    final first = media.preview(_item('one'), _item('one').cover);
    await started.future;
    final clearing = media.clearCache();
    const next = OnlineGalleryMedia(
        id: 'next', previewUrl: 'https://cdn.example.test/next.png');
    final after = media.preview(_item('two'), next);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(transport.requests, hasLength(1));
    release.complete();
    final previousPath = await first;
    await clearing;
    final nextPath = await after;
    expect(await File(previousPath!).exists(), isFalse);
    expect(await File(nextPath!).exists(), isTrue);
  });

  test('a detail finishing after cache clear cannot repopulate the old cache',
      () async {
    final adapter = _GalleryAdapter();
    final release = Completer<void>();
    adapter.block = release.future;
    final repository = _repository(adapter, prefs, media);
    final first = repository.detail(_item('one'));
    await Future<void>.delayed(Duration.zero);
    await repository.clearCache();
    release.complete();
    await first;
    await repository.detail(_item('one'));
    expect(adapter.detailCalls, 2);
  });

  test('source launch uses Android bridge and refuses private addresses',
      () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('worldpainter/online_gallery');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final repository = _repository(_GalleryAdapter(), prefs, media);
    await repository.openSource(_item('one'));
    expect(calls.single.method, 'openUrl');
    expect((calls.single.arguments as Map)['url'],
        'https://tags.gallery/artist/synthetic');
    await expectLater(
        repository
            .openSource(_item('one').copyWith(sourceUrl: 'https://localhost')),
        throwsArgumentError);
    expect(calls, hasLength(1));
  });

  test('source network errors do not expose credential-bearing request URLs',
      () async {
    final adapter = _GalleryAdapter()..networkFailure = true;
    final repository = _repository(adapter, prefs, media);
    await expectLater(
        repository.search(const OnlineGalleryQuery()),
        throwsA(predicate((error) =>
            error.toString().contains('网络') &&
            !error.toString().contains('synthetic-secret'))));
  });
}

OnlineGalleryItem _item(String id) => OnlineGalleryItem(
      source: OnlineGallerySource.tagsGallery,
      id: id,
      title: 'Synthetic reference',
      sourceUrl: 'https://tags.gallery/artist/synthetic',
      prompt: 'exact weighted prompt',
      media: const [
        OnlineGalleryMedia(
            id: 'image',
            previewUrl: 'https://cdn.example.test/image.png',
            displayUrl: 'https://cdn.example.test/image.png',
            downloadUrl: 'https://cdn.example.test/image.png',
            width: 8,
            height: 6)
      ],
    );

OnlineGalleryRepositoryImpl _repository(_GalleryAdapter adapter,
        SharedPreferences prefs, OnlineGalleryMediaStore media,
        {_Styles? styles}) =>
    OnlineGalleryRepositoryImpl(
      adapters: {
        for (final source in OnlineGallerySource.values) source: adapter
      },
      local: OnlineGalleryLocalStore(prefs),
      credentials: OnlineGalleryCredentialStore(),
      media: media,
      styles: ManageStylePresetsUseCase(styles ?? _Styles()),
    );

class _ImageTransport implements HttpClientAdapter {
  Uint8List image =
      Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 6)));
  final requests = <RequestOptions>[];
  String? redirect;
  Future<void>? block;
  Completer<void>? started;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (started?.isCompleted == false) started!.complete();
    if (block != null) await block;
    if (redirect != null) {
      return ResponseBody.fromString('', 302, headers: {
        'location': [redirect!]
      });
    }
    return ResponseBody.fromBytes(image, 200, headers: {
      'content-type': ['image/png'],
      'content-length': [image.length.toString()],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _GalleryAdapter implements GalleryAdapter {
  int detailCalls = 0;
  final List<bool> detailModes = [];
  bool networkFailure = false;
  Future<void>? block;
  @override
  Future<OnlineGalleryItem> detail(OnlineGalleryItem item,
      {bool safeOnly = true}) async {
    detailCalls++;
    detailModes.add(safeOnly);
    if (block != null) await block;
    await Future<void>.delayed(Duration.zero);
    return item.copyWith(prompt: 'hydrated prompt');
  }

  @override
  Future<OnlineGalleryPage> search(OnlineGalleryQuery query) async {
    if (networkFailure) {
      throw DioException(
          requestOptions: RequestOptions(
              path: 'https://example.test?api_key=synthetic-secret'));
    }
    return OnlineGalleryPage(items: [_item('one')]);
  }
}

class _Styles implements StylePresetRepository {
  final List<StylePreset> items = [];
  String? sourcePath;
  @override
  Future<List<StylePreset>> getAll() async => items;
  @override
  Future<StylePreset> createFromImage(
      {required String title,
      required String prompt,
      required String sourceImagePath}) async {
    sourcePath = sourceImagePath;
    final item = StylePreset(
        title: title,
        prompt: prompt,
        imagePath: sourceImagePath,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now());
    items.add(item);
    return item;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
