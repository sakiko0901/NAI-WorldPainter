import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../domain/entities/app_update.dart';

class AppUpdateException implements Exception {
  final String message;
  const AppUpdateException(this.message);
  @override
  String toString() => message;
}

/// Never shares the app's authenticated Dio. Redirects are followed manually so
/// neither GitHub nor a compromised Location header can send requests elsewhere.
class AppUpdateSource {
  static final manifestUri = Uri.parse('https://github.com'
      '${AppUpdateManifest.repositoryPath}/releases/latest/download/update.json');
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
    final cancel = CancelToken();
    try {
      return await _fetch(cancel).timeout(_requestTimeout, onTimeout: () {
        cancel.cancel('Update check timed out');
        throw const AppUpdateException('检查更新超时，请稍后重试。');
      });
    } on AppUpdateException {
      rethrow;
    } on FormatException {
      throw const AppUpdateException('更新清单无效，请前往发布页查看。');
    } on DioException {
      throw const AppUpdateException('无法连接更新服务，请检查网络后重试。');
    } catch (_) {
      throw const AppUpdateException('检查更新失败，请稍后重试。');
    }
  }

  Future<AppUpdateManifest> _fetch(CancelToken cancel) async {
    var uri = manifestUri;
    for (var redirects = 0; redirects <= 5; redirects++) {
      final response =
          await _dio.getUri<ResponseBody>(uri, cancelToken: cancel);
      final body = response.data;
      final status = response.statusCode;
      if (body == null) throw const FormatException('Empty update response');
      if (const {301, 302, 303, 307, 308}.contains(status)) {
        // Cancel, rather than buffering a redirect response body of arbitrary size.
        final subscription = body.stream.listen((_) {});
        await subscription.cancel();
        final location = response.headers.value('location');
        if (redirects == 5 || location == null) {
          throw const AppUpdateException('更新服务重定向异常，请稍后重试。');
        }
        final next = uri.resolve(location);
        if (!_allowedRedirect(next)) {
          throw const AppUpdateException('更新服务地址无效，请前往发布页查看。');
        }
        uri = next;
        continue;
      }
      if (status != 200) {
        final subscription = body.stream.listen((_) {});
        await subscription.cancel();
        if (status == 404) {
          throw const AppUpdateException('暂未找到更新清单，请前往发布页查看。');
        }
        if (status == 403 || status == 429) {
          throw const AppUpdateException('更新服务请求受限，请稍后重试。');
        }
        throw const AppUpdateException('更新服务暂时不可用，请稍后重试。');
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
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      if (decoded is! Map) throw const FormatException('Invalid manifest');
      return AppUpdateManifest.fromJson(Map<Object?, Object?>.from(decoded));
    }
    throw const AppUpdateException('更新服务重定向异常，请稍后重试。');
  }

  bool _allowedRedirect(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 443) ||
        uri.toString().contains('\\')) {
      return false;
    }
    if (uri.host == 'github.com') {
      if (uri.hasQuery || uri.path.contains('%')) return false;
      return uri.path == manifestUri.path ||
          RegExp('^${AppUpdateManifest.repositoryPath}/releases/download/'
                  r'[A-Za-z0-9][A-Za-z0-9._\-]{0,127}/update\.json$')
              .hasMatch(uri.path);
    }
    // Signed release-asset URLs carry GitHub's expiring query parameters.
    return const {
      'release-assets.githubusercontent.com',
      'objects.githubusercontent.com',
      'github-releases.githubusercontent.com',
    }.contains(uri.host);
  }

  void dispose() => _dio.close(force: true);
}
