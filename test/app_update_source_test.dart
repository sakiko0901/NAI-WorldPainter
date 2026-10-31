import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/datasources/remote/app_update_source.dart';

import 'app_update_manifest_test.dart' show manifestJson;

class _Adapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  _Adapter(this.respond);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json() =>
    ResponseBody.fromString(jsonEncode(manifestJson()), 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });

void main() {
  test('uses only the fixed URL and an unauthenticated independent request',
      () async {
    final adapter = _Adapter((_) async => _json());
    final source = AppUpdateSource(adapter: adapter);
    addTearDown(source.dispose);
    expect((await source.fetchLatest()).versionCode, 11);
    final request = adapter.requests.single;
    expect(request.uri, AppUpdateSource.manifestUri);
    expect(request.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('authorization')));
    expect(request.followRedirects, isFalse);
    expect(request.responseType, ResponseType.stream);
  });

  test('follows an allowed GitHub release CDN redirect', () async {
    final adapter = _Adapter((options) async => options.uri.host == 'github.com'
        ? ResponseBody.fromString('', 302, headers: {
            'location': [
              'https://release-assets.githubusercontent.com/github-production-release-asset/123/update.json?sig=secret'
            ],
          })
        : _json());
    final source = AppUpdateSource(adapter: adapter);
    addTearDown(source.dispose);
    expect((await source.fetchLatest()).versionCode, 11);
    expect(adapter.requests.length, 2);
  });

  for (final url in [
    'https://github.com.evil.invalid/update.json',
    'https://evil.invalid/update.json',
    'http://release-assets.githubusercontent.com/update.json',
    'https://user@release-assets.githubusercontent.com/update.json',
    'https://github.com/other/repo/releases/download/v1/update.json',
    'https://release-assets.githubusercontent.com:8443/update.json',
  ]) {
    test('rejects redirect to $url before requesting it', () async {
      final adapter =
          _Adapter((_) async => ResponseBody.fromString('', 302, headers: {
                'location': [url]
              }));
      final source = AppUpdateSource(adapter: adapter);
      addTearDown(source.dispose);
      await expectLater(
          source.fetchLatest(), throwsA(isA<AppUpdateException>()));
      expect(adapter.requests.length, 1);
    });
  }

  for (final status in [404, 403, 429, 500]) {
    test('HTTP $status is a failure, not an up-to-date response', () async {
      final source = AppUpdateSource(
          adapter: _Adapter(
              (_) async => ResponseBody.fromString('not a manifest', status)));
      addTearDown(source.dispose);
      await expectLater(
          source.fetchLatest(), throwsA(isA<AppUpdateException>()));
    });
  }

  test('rejects oversized bodies with and without content length', () async {
    for (final knownLength in [true, false]) {
      final source = AppUpdateSource(
          adapter: _Adapter((_) async => ResponseBody(
              Stream.fromIterable([
                Uint8List(AppUpdateSource.maxManifestBytes),
                Uint8List(1),
              ]),
              200,
              headers: knownLength
                  ? {
                      'content-length': [
                        '${AppUpdateSource.maxManifestBytes + 1}'
                      ]
                    }
                  : {})));
      await expectLater(
          source.fetchLatest(), throwsA(isA<AppUpdateException>()));
      source.dispose();
    }
  });

  test('redirect loops stop after the bounded number of requests', () async {
    final adapter =
        _Adapter((_) async => ResponseBody.fromString('', 302, headers: {
              'location': [AppUpdateSource.manifestUri.toString()]
            }));
    final source = AppUpdateSource(adapter: adapter);
    addTearDown(source.dispose);
    await expectLater(source.fetchLatest(), throwsA(isA<AppUpdateException>()));
    expect(adapter.requests.length, 6);
  });

  test('total timeout also bounds a never-finishing response', () async {
    final stalled = Completer<ResponseBody>();
    final source = AppUpdateSource(
        adapter: _Adapter((_) => stalled.future),
        requestTimeout: const Duration(milliseconds: 10));
    addTearDown(source.dispose);
    await expectLater(source.fetchLatest(), throwsA(isA<AppUpdateException>()));
    stalled.complete(_json());
  });
}
