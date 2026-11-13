import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../../domain/entities/app_update.dart';

enum AppUpdateExceptionReason {
  missingManifest,
  invalidManifest,
  timeout,
  connection,
  rateLimited,
  unavailable,
  invalidRedirect,
  unknown,
}

class AppUpdateException implements Exception {
  final String message;
  final AppUpdateExceptionReason reason;
  const AppUpdateException(this.message,
      {this.reason = AppUpdateExceptionReason.unknown});
  @override
  String toString() => message;
}

/// Never shares the app's authenticated Dio. Redirects are followed manually so
/// neither GitHub nor a compromised Location header can send requests elsewhere.
class AppUpdateSource {
  static final manifestUri = Uri.parse('https://github.com'
      '${AppUpdateManifest.repositoryPath}/releases/latest/download/update.json');
  static const _releaseApiPath =
      '/repos${AppUpdateManifest.repositoryPath}/releases';
  static final _latestReleaseApi =
      Uri.https('api.github.com', '$_releaseApiPath/latest');
  static const _primaryBudget = Duration(seconds: 8);
  static const maxManifestBytes = 128 * 1024;
  final Dio _dio;
  final Duration _requestTimeout;

  AppUpdateSource(
      {HttpClientAdapter? adapter,
      Duration requestTimeout = const Duration(seconds: 25)})
      : _requestTimeout = requestTimeout,
        _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
          followRedirects: false,
          maxRedirects: 0,
          responseType: ResponseType.stream,
          validateStatus: (status) => status != null,
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'NAI-WorldPainter-Updater/1'
          },
        )) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  Future<AppUpdateManifest> fetchLatest() async {
    final elapsed = Stopwatch()..start();
    try {
      return await _withTimeout(
        _fetchDirect,
        _requestTimeout < _primaryBudget ? _requestTimeout : _primaryBudget,
      );
    } on AppUpdateException catch (primary) {
      final remaining = _requestTimeout - elapsed.elapsed;
      if (remaining <= Duration.zero ||
          !const {
            AppUpdateExceptionReason.missingManifest,
            AppUpdateExceptionReason.timeout,
            AppUpdateExceptionReason.connection,
            AppUpdateExceptionReason.rateLimited,
            AppUpdateExceptionReason.unavailable,
          }.contains(primary.reason)) {
        rethrow;
      }
      try {
        return await _withTimeout(_fetchFromReleaseApi, remaining);
      } on AppUpdateException {
        throw primary;
      }
    }
  }

  Future<AppUpdateManifest> _withTimeout(
    Future<AppUpdateManifest> Function(CancelToken) fetch,
    Duration timeout,
  ) async {
    final cancel = CancelToken();
    try {
      return await fetch(cancel).timeout(timeout, onTimeout: () {
        cancel.cancel('Update check timed out');
        throw const AppUpdateException('检查更新超时，请稍后重试。',
            reason: AppUpdateExceptionReason.timeout);
      });
    } on AppUpdateException {
      rethrow;
    } on FormatException {
      throw const AppUpdateException('暂时无法获取版本信息（更新清单无效），请前往发布页查看。',
          reason: AppUpdateExceptionReason.invalidManifest);
    } on DioException {
      throw const AppUpdateException('无法连接更新服务，请检查网络后重试。',
          reason: AppUpdateExceptionReason.connection);
    } catch (_) {
      throw const AppUpdateException('检查更新失败，请稍后重试。');
    }
  }

  Future<AppUpdateManifest> _fetchDirect(CancelToken cancel) async {
    final bytes =
        await _readBytes(manifestUri, cancel, allowRedirect: _allowedRedirect);
    return AppUpdateManifest.fromJson(_decodeObject(bytes));
  }

  Future<AppUpdateManifest> _fetchFromReleaseApi(CancelToken cancel) async {
    final release = _decodeObject(await _readBytes(
      _latestReleaseApi,
      cancel,
      accept: 'application/vnd.github+json',
    ));
    final tag = release['tag_name'];
    final assets = release['assets'];
    if (tag is! String ||
        release['draft'] != false ||
        release['prerelease'] != false ||
        assets is! List) {
      throw const FormatException('Invalid latest release');
    }
    final uploaded = assets.whereType<Map>().where((asset) =>
        asset['state'] == 'uploaded' &&
        asset['id'] is int &&
        (asset['id'] as int) > 0);
    final manifestAsset =
        uploaded.where((asset) => asset['name'] == 'update.json').firstOrNull;
    if (manifestAsset == null) {
      throw const AppUpdateException('暂时无法获取版本信息（更新清单尚未发布），请稍后重试或前往发布页查看。',
          reason: AppUpdateExceptionReason.missingManifest);
    }
    final bytes = await _readBytes(
      Uri.https('api.github.com',
          '$_releaseApiPath/assets/${manifestAsset['id']}', {'download': '1'}),
      cancel,
      accept: 'application/octet-stream',
      allowRedirect: _allowedCdnRedirect,
    );
    final digest = manifestAsset['digest'];
    if (manifestAsset['size'] != bytes.length ||
        (digest != null && digest != 'sha256:${sha256.convert(bytes)}')) {
      throw const FormatException('Manifest asset does not match release');
    }
    final json = _decodeObject(bytes);
    final manifest = AppUpdateManifest.fromJson(json);
    if (manifest.releaseUrl.pathSegments.last != tag) {
      throw const FormatException('Manifest does not match latest release');
    }
    final apkAsset = uploaded
        .where((asset) =>
            asset['name'] == manifest.apk.url.pathSegments.last &&
            asset['browser_download_url'] == manifest.apkUrl &&
            asset['size'] == manifest.apk.sizeBytes &&
            asset['digest'] == 'sha256:${manifest.apk.sha256}')
        .firstOrNull;
    return AppUpdateManifest.fromJson(json,
        githubApkAssetId: apkAsset?['id'] as int?);
  }

  Map<Object?, Object?> _decodeObject(List<int> bytes) {
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (decoded is! Map) throw const FormatException('Invalid update JSON');
    return Map<Object?, Object?>.from(decoded);
  }

  Future<List<int>> _readBytes(
    Uri uri,
    CancelToken cancel, {
    String accept = 'application/json',
    bool Function(Uri)? allowRedirect,
  }) async {
    for (var redirects = 0; redirects <= 5; redirects++) {
      final response = await _dio.getUri<ResponseBody>(uri,
          cancelToken: cancel, options: Options(headers: {'Accept': accept}));
      final body = response.data;
      final status = response.statusCode;
      if (body == null) throw const FormatException('Empty update response');
      if (const {301, 302, 303, 307, 308}.contains(status)) {
        // Cancel, rather than buffering a redirect response body of arbitrary size.
        final subscription = body.stream.listen((_) {});
        await subscription.cancel();
        final location = response.headers.value('location');
        if (redirects == 5 || location == null) {
          throw const AppUpdateException('更新服务重定向异常，请稍后重试。',
              reason: AppUpdateExceptionReason.invalidRedirect);
        }
        final next = uri.resolve(location);
        if (allowRedirect == null || !allowRedirect(next)) {
          throw const AppUpdateException('更新服务地址无效，请前往发布页查看。',
              reason: AppUpdateExceptionReason.invalidRedirect);
        }
        uri = next;
        continue;
      }
      if (status != 200) {
        final subscription = body.stream.listen((_) {});
        await subscription.cancel();
        if (status == 404) {
          throw const AppUpdateException('暂时无法获取版本信息（更新清单尚未发布），请稍后重试或前往发布页查看。',
              reason: AppUpdateExceptionReason.missingManifest);
        }
        if (status == 403 || status == 429) {
          throw const AppUpdateException('更新服务请求受限，请稍后重试。',
              reason: AppUpdateExceptionReason.rateLimited);
        }
        throw const AppUpdateException('更新服务暂时不可用，请稍后重试。',
            reason: AppUpdateExceptionReason.unavailable);
      }
      final length =
          int.tryParse(response.headers.value('content-length') ?? '');
      if (length != null && (length < 0 || length > maxManifestBytes)) {
        final subscription = body.stream.listen((_) {});
        await subscription.cancel();
        throw const FormatException('Update manifest is too large');
      }
      final bytes = <int>[];
      await for (final chunk in body.stream) {
        if (bytes.length + chunk.length > maxManifestBytes) {
          cancel.cancel('Manifest size limit exceeded');
          throw const FormatException('Update manifest is too large');
        }
        bytes.addAll(chunk);
      }
      return bytes;
    }
    throw const AppUpdateException('更新服务重定向异常，请稍后重试。',
        reason: AppUpdateExceptionReason.invalidRedirect);
  }

  bool _safeHttps(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      (!uri.hasPort || uri.port == 443) &&
      !uri.toString().contains('\\');

  bool _allowedRedirect(Uri uri) {
    if (!_safeHttps(uri)) return false;
    if (uri.host == 'github.com') {
      if (uri.hasQuery || uri.path.contains('%')) return false;
      return uri.path == manifestUri.path ||
          RegExp('^${AppUpdateManifest.repositoryPath}/releases/download/'
                  r'[A-Za-z0-9][A-Za-z0-9._\-]{0,127}/update\.json$')
              .hasMatch(uri.path);
    }
    return _allowedCdnRedirect(uri);
  }

  bool _allowedCdnRedirect(Uri uri) {
    // Signed release-asset URLs carry GitHub's expiring query parameters.
    return _safeHttps(uri) &&
        const {
          'release-assets.githubusercontent.com',
          'objects.githubusercontent.com',
          'github-releases.githubusercontent.com',
        }.contains(uri.host);
  }

  void dispose() => _dio.close(force: true);
}
