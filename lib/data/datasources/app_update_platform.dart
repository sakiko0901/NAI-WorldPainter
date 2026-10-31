import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/app_update.dart';

/// A small, typed boundary to Android's persistent DownloadManager updater.
class AppUpdatePlatform {
  final MethodChannel _channel;

  AppUpdatePlatform({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('worldpainter/app_update');

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<InstalledAppInfo> getInstalledInfo() async =>
      InstalledAppInfo.fromJson(await _map('getInstalledInfo'));

  Future<AppUpdateDownload> startDownload(AppUpdateManifest manifest) async =>
      AppUpdateDownload.fromJson(await _map(
          'startDownload', {'manifest': manifest.validated().toJson()}));

  Future<AppUpdateDownload> getDownloadState() async =>
      AppUpdateDownload.fromJson(await _map('getDownloadState'));

  Future<AppUpdateDownload> cancelDownload() async =>
      AppUpdateDownload.fromJson(await _map('cancelDownload'));

  Future<AppUpdateDownload> verifyDownload() async =>
      AppUpdateDownload.fromJson(await _map('verifyDownload'));

  Future<bool> canInstallPackages() async {
    final result = await _channel.invokeMethod<Object?>('canInstallPackages');
    if (result is! bool) {
      throw const FormatException('Invalid permission state');
    }
    return result;
  }

  Future<void> openInstallPermission() =>
      _channel.invokeMethod<void>('openInstallPermission');

  Future<void> installUpdate() => _channel.invokeMethod<void>('installUpdate');

  Future<void> openReleasePage({Uri? url}) async {
    if (url != null && !_isReleasePage(url)) {
      throw const FormatException('Invalid release page');
    }
    await _channel.invokeMethod<void>(
        'openReleasePage', url == null ? null : {'url': url.toString()});
  }

  Future<Map<Object?, Object?>> _map(String method,
      [Map<String, Object>? arguments]) async {
    final result = await _channel.invokeMethod<Object?>(method, arguments);
    if (result is! Map) {
      throw const FormatException('Invalid native update state');
    }
    return Map<Object?, Object?>.from(result);
  }

  bool _isReleasePage(Uri url) =>
      url.scheme == 'https' &&
      url.host == 'github.com' &&
      url.userInfo.isEmpty &&
      !url.hasPort &&
      !url.hasQuery &&
      !url.hasFragment &&
      (url.path == '${AppUpdateManifest.repositoryPath}/releases/latest' ||
          RegExp('^${AppUpdateManifest.repositoryPath}/releases/tag/'
                  r'[A-Za-z0-9][A-Za-z0-9._\-]{0,127}$')
              .hasMatch(url.path));
}
