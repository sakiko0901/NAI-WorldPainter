import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:nai_huishi/data/repositories/character_reference_catalog_repository.dart';
import 'package:nai_huishi/domain/entities/character_reference_asset.dart';
import 'package:path/path.dart' as p;

const _pages =
    'https://2786886095.github.io/novelai-image-desktop/reference-catalog';
const _media =
    'https://media.githubusercontent.com/media/2786886095/novelai-reference-assets/main';
const _precise = '$_media/assets/precise.png';
const _thumbnail = '$_media/thumbnails/thumbnail.webp';
const _alternate = '$_media/assets/alternate.png';
const _missing = '$_media/assets/missing.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Transport transport;
  late Dio dio;
  late Uint8List png;

  CharacterReferenceCatalogRepository open() =>
      CharacterReferenceCatalogRepository(
        dio: dio,
        supportDirectory: () async => directory,
        cacheDirectory: () async =>
            Directory(p.join(directory.path, 'temporary')),
      );

  CharacterReferenceAsset asset({
    List<String> originals = const [_precise],
    List<String> thumbnails = const [_thumbnail],
  }) =>
      CharacterReferenceAsset(
        id: '../../中文/雨夜',
        game: '崩坏：星穹铁道',
        category: '角色立绘',
        name: '阿哈',
        variant: '雨夜',
        width: 2,
        height: 3,
        bytes: png.length,
        thumbnailUrls: thumbnails,
        downloadUrls: originals,
        checksum: sha256.convert(png).toString(),
      );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('character_catalog_');
    transport = _Transport();
    dio = Dio()..httpClientAdapter = transport;
    png = image.encodePng(image.Image(width: 2, height: 3));
  });

  tearDown(() async {
    dio.close(force: true);
    await directory.delete(recursive: true);
  });

  test(
      'loads the secondary index, searches aliases and reopens the offline snapshot',
      () async {
    final [primary, secondary] =
        CharacterReferenceCatalogRepository.catalogSources;
    transport.routes[primary] = () => _text(200, '<html>unavailable</html>');
    transport.routes[secondary] = () => _json(_catalog([
          _row(png, '角色/雨夜', '雨夜'),
          _row(png, '角色/异色', '异色'),
        ]));
    final repository = open();

    final results = await repository.load();
    expect(transport.requests, [primary, secondary]);
    expect(results.map((item) => item.variant), ['雨夜', '异色']);
    final first = results.first;
    expect(first.game, '崩坏：星穹铁道');
    expect(first.matches('  HONKAI   阿哈 雨夜   서치 '), isTrue);
    expect(first.matches('阿哈 异色'), isFalse);
    expect(first.downloadUrls, [_precise]);
    expect(first.thumbnailUrls, [_thumbnail]);
    expect(first.checksum, sha256.convert(png).toString());

    transport.requests.clear();
    transport.routes.clear();
    expect((await open().load()).map((item) => item.id),
        results.map((item) => item.id));
    expect(transport.requests, isEmpty);
    expect((await open().load(refresh: true)).first.id, first.id);
    expect(transport.requests, [primary, secondary]);
  });

  test('reads plain and gzip-base64 game chunks from a federated index',
      () async {
    final primary = CharacterReferenceCatalogRepository.catalogSources.first;
    transport.routes[primary] = () => _json({
          'schema': 'langbai-reference-catalog/federated-v1',
          'chunks': [
            {'url': 'first.json'},
            {'url': 'second.json'},
          ],
        });
    transport.routes['$_pages/first.json'] = () => _json({
          'encoding': 'gzip-base64',
          'payload': base64.encode(gzip.encode(utf8.encode(jsonEncode(_catalog([
            _row(png, 'first', '雨夜'),
          ]))))),
        });
    transport.routes['$_pages/second.json'] = () => _json(_catalog([
          _row(png, 'second', '异色'),
        ]));

    expect((await open().load()).map((item) => item.id), ['first', 'second']);
    expect(transport.requests,
        containsAll([primary, '$_pages/first.json', '$_pages/second.json']));
  });

  test(
      'rejects unsafe redirects and invalid preview streams, then caches the valid mirror',
      () async {
    const foreign =
        'https://raw.githubusercontent.com/someone-else/project/main/image.png';
    const oversized = '$_media/thumbnails/large.webp';
    final canceled = Completer<void>();
    transport.routes[_thumbnail] =
        () => ResponseBody.fromString('', 302, headers: {
              'location': [foreign]
            });
    transport.routes[oversized] = () {
      final body = StreamController<Uint8List>(onCancel: canceled.complete);
      body.add(Uint8List(1024 * 1024 + 1));
      return ResponseBody(body.stream, 200, headers: {
        'content-type': ['image/webp']
      });
    };
    final repository = open();
    expect(
        await repository
            .previewPath(asset(thumbnails: [_thumbnail, oversized])),
        isNull);
    await canceled.future.timeout(const Duration(seconds: 2));
    expect(transport.requests, [_thumbnail, oversized]);

    transport.routes[_alternate] = () => _image(png);
    final candidates = asset(thumbnails: [_thumbnail, _alternate]);
    final preview = await repository.previewPath(candidates);
    expect(await File(preview!).readAsBytes(), png);
    final attempted = transport.requests.length;
    expect(await open().previewPath(candidates), preview);
    expect(transport.requests, hasLength(attempted));
  });

  test(
      'verifies image integrity, coalesces download requests, and retains the file offline',
      () async {
    final damaged = Uint8List.fromList(png)..[png.length - 1] ^= 1;
    final started = Completer<void>();
    final release = Completer<void>();
    transport.routes[_precise] = () => _image(damaged);
    transport.routes[_alternate] = () async {
      started.complete();
      await release.future;
      return _image(png);
    };
    final candidate = asset(originals: [_precise, _alternate]);
    final progress = <(int, int)>[];
    final download =
        open().download(candidate, onProgress: (a, b) => progress.add((a, b)));
    await started.future;
    final duplicate = open().download(candidate);
    release.complete();
    final [first, second] = await Future.wait([download, duplicate]);

    expect(transport.requests, [_precise, _alternate]);
    expect(first.path, second.path);
    expect(first.path, endsWith('image.png'));
    expect(p.isWithin(directory.path, first.path), isTrue);
    expect(await File(first.path).readAsBytes(), png);
    expect(progress.last, (png.length, png.length));
    expect((await open().listSaved()).single.asset.id, candidate.id);
  });

  test('cancels active downloads and permits retry without incomplete files',
      () async {
    final started = Completer<void>();
    final stream = StreamController<Uint8List>();
    transport.routes[_precise] = () {
      started.complete();
      return ResponseBody(stream.stream, 200, headers: {
        'content-type': ['image/png']
      });
    };
    final repository = open();
    final cancel = CancelToken();
    final pending = repository.download(asset(), cancelToken: cancel);
    final canceled = expectLater(
        pending,
        throwsA(isA<DioException>()
            .having(CancelToken.isCancel, 'is cancelled', isTrue)));
    await started.future;
    cancel.cancel('test stop');
    await canceled;
    await stream.close();
    expect(await repository.listSaved(), isEmpty);

    transport.routes[_precise] = () => _image(png);
    expect(
        await File((await repository.download(asset())).path).exists(), isTrue);
  });

  test(
      'remove waits for a failed save and forged paths cannot delete other files',
      () async {
    final started = Completer<void>();
    final release = Completer<void>();
    transport.routes[_missing] = () async {
      started.complete();
      await release.future;
      return _text(404, 'missing');
    };
    final repository = open();
    final candidate = asset(originals: [_missing]);
    final download = repository.download(candidate);
    final failed = expectLater(download, throwsA(isA<HttpException>()));
    await started.future;
    final key = sha256.convert(utf8.encode(candidate.id)).toString();
    final expectedPath = p.join(directory.path, 'character_reference_catalog',
        'saved', key, 'image.png');
    final removal = repository
        .remove(SavedCharacterReference(asset: candidate, path: expectedPath));
    release.complete();
    await Future.wait([removal, failed]);
    expect(await repository.listSaved(), isEmpty);

    final external =
        await File(p.join(directory.path, 'image.png')).writeAsBytes(png);
    await expectLater(
        repository.remove(
            SavedCharacterReference(asset: candidate, path: external.path)),
        throwsArgumentError);
    expect(await external.readAsBytes(), png);
  });

  test(
      'imports original local bytes with detected dimensions, checks and removes its own copy',
      () async {
    final bytes = image.encodeJpg(image.Image(width: 7, height: 9));
    final source =
        await File(p.join(directory.path, 'role.dat')).writeAsBytes(bytes);
    final repository = open();
    final imported = await repository.importLocal(
        path: source.path, name: ' 姬子 ', game: '星穹铁道');
    final again =
        await open().importLocal(path: source.path, name: '姬子', game: '星穹铁道');
    final invalid = await File(p.join(directory.path, 'html.png'))
        .writeAsString('<html>login</html>');

    expect(imported.asset.name, '姬子');
    expect(imported.asset.id, startsWith('local:'));
    expect(imported.asset.matches('姬子 星穹铁道 本地导入'), isTrue);
    expect((imported.asset.width, imported.asset.height), (7, 9));
    expect(imported.path, endsWith('.jpg'));
    expect(imported.path, again.path);
    expect(await File(imported.path).readAsBytes(), bytes);
    await expectLater(repository.importLocal(path: invalid.path, name: '错误图'),
        throwsFormatException);
    expect((await open().listSaved()).single.path, imported.path);
    expect(transport.requests, isEmpty);

    await open().remove(imported);
    expect(await open().listSaved(), isEmpty);
    expect(await source.readAsBytes(), bytes);
  });
}

Map<String, Object> _catalog(List<Map<String, Object>> rows) => {
      'schema': 'langbai-reference-catalog/v1',
      'games': [
        {
          'id': '星穹铁道',
          'names': {'zh-CN': '崩坏：星穹铁道', 'en-US': 'Honkai: Star Rail'}
        },
      ],
      'assets': rows,
    };

Map<String, Object> _row(Uint8List png, String id, String variant) => {
      'id': id,
      'game': '星穹铁道',
      'category': '角色立绘',
      'roleId': 'Aha test role',
      'names': {'zh-CN': '阿哈', 'en-US': 'Aha'},
      'searchAliases': ['서치'],
      'variant': variant,
      'width': 2,
      'height': 3,
      'bytes': png.length,
      'downloadUrl':
          'https://gitee.com/langbai666/novelai-ref-test/raw/main/image.png',
      'downloadMirrors': {
        'github': _precise,
        'malicious': 'https://127.0.0.1/test.png'
      },
      'thumbnailMirrors': {'github': _thumbnail},
      'files': {
        'original': {'url': _alternate},
        'precise': {'sha256': sha256.convert(png).toString()},
      },
    };

ResponseBody _json(Object data) =>
    ResponseBody.fromString(jsonEncode(data), 200, headers: {
      'content-type': ['application/json']
    });
ResponseBody _text(int status, String data) =>
    ResponseBody.fromString(data, status, headers: {
      'content-type': ['text/html; charset=utf-8']
    });
ResponseBody _image(Uint8List data) =>
    ResponseBody.fromBytes(data, 200, headers: {
      'content-type': ['image/png'],
      'content-length': ['${data.length}'],
    });

class _Transport implements HttpClientAdapter {
  final requests = <String>[];
  final routes = <String, FutureOr<ResponseBody> Function()>{};

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final url = options.uri.toString();
    requests.add(url);
    final response = routes[url];
    return response == null ? _text(404, 'missing') : await response();
  }

  @override
  void close({bool force = false}) {}
}
