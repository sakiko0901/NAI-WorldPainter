/// The updater accepts one release format from one repository. These checks also
/// apply to manifests restored from Android's persisted download state.
class AppUpdateManifest {
  static const packageId = 'com.naihuishi.nai_huishi';
  static const repositoryPath = '/sakiko0901/NAI-WorldPainter';
  static const maxApkBytes = 512 * 1024 * 1024;

  static bool isStableVersion(String value) =>
      value.length <= 64 &&
      RegExp(r'^\d+\.\d+\.\d+(?:\.\d+)?$').hasMatch(value);

  final int schemaVersion;
  final String channel;
  final String packageName;
  final String versionName;
  final int versionCode;
  final DateTime publishedAt;
  final String releaseNotes;
  final Uri releaseUrl;
  final AppUpdateApk apk;

  const AppUpdateManifest({
    required this.schemaVersion,
    required this.channel,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.publishedAt,
    required this.releaseNotes,
    required this.releaseUrl,
    required this.apk,
  });

  String get apkUrl => apk.url.toString();
  String get releasePageUrl => releaseUrl.toString();

  factory AppUpdateManifest.fromJson(Map<Object?, Object?> json) {
    _keys(json, const {
      'schemaVersion',
      'channel',
      'packageName',
      'versionName',
      'versionCode',
      'publishedAt',
      'releaseNotes',
      'releaseUrl',
      'apk',
    });
    final schema = _integer(json, 'schemaVersion', 1, 1);
    final channel = _text(json, 'channel', 16);
    final packageName = _text(json, 'packageName', 128);
    if (channel != 'stable' || packageName != packageId) {
      throw const FormatException('Unsupported update channel or package');
    }
    final versionName = _text(json, 'versionName', 64);
    if (!isStableVersion(versionName)) {
      throw const FormatException('Invalid stable version name');
    }
    final versionCode = _integer(json, 'versionCode', 1, 0x7fffffff);
    final publishedAt = _timestamp(_text(json, 'publishedAt', 40));
    final notes = _text(json, 'releaseNotes', 64 * 1024,
        allowEmpty: true, allowNewlines: true);
    final releaseUrl = _githubUrl(_text(json, 'releaseUrl', 1024));
    const prefix = '$repositoryPath/releases/tag/';
    if (!releaseUrl.path.startsWith(prefix)) {
      throw const FormatException('Invalid release URL');
    }
    final tag = releaseUrl.path.substring(prefix.length);
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._\-]{0,127}$').hasMatch(tag) ||
        RegExp(r'(^|[._\-])(preview|alpha|beta|rc|dev|canary|test)([._\-]|\d|$)',
                caseSensitive: false)
            .hasMatch(tag)) {
      throw const FormatException('Invalid release tag');
    }
    final apkJson = json['apk'];
    if (apkJson is! Map) throw const FormatException('Missing APK metadata');
    final apk = AppUpdateApk.fromJson(Map<Object?, Object?>.from(apkJson));
    if (apk.url.path !=
        '$repositoryPath/releases/download/$tag/app-release.apk') {
      throw const FormatException('APK must belong to the same release');
    }
    return AppUpdateManifest(
      schemaVersion: schema,
      channel: channel,
      packageName: packageName,
      versionName: versionName,
      versionCode: versionCode,
      publishedAt: publishedAt,
      releaseNotes: notes,
      releaseUrl: releaseUrl,
      apk: apk,
    );
  }

  Map<String, Object> toJson() => {
        'schemaVersion': schemaVersion,
        'channel': channel,
        'packageName': packageName,
        'versionName': versionName,
        'versionCode': versionCode,
        'publishedAt': publishedAt.toUtc().toIso8601String(),
        'releaseNotes': releaseNotes,
        'releaseUrl': releaseUrl.toString(),
        'apk': apk.toJson(),
      };

  /// Revalidate even manually constructed models before crossing the bridge.
  AppUpdateManifest validated() => AppUpdateManifest.fromJson(toJson());

  bool sameArtifact(AppUpdateManifest other) =>
      packageName == other.packageName &&
      versionCode == other.versionCode &&
      apk.url == other.apk.url &&
      apk.sizeBytes == other.apk.sizeBytes &&
      apk.sha256 == other.apk.sha256;
}

class AppUpdateApk {
  final Uri url;
  final int sizeBytes;
  final String sha256;
  final String abi;
  final int minSdk;

  const AppUpdateApk({
    required this.url,
    required this.sizeBytes,
    required this.sha256,
    required this.abi,
    required this.minSdk,
  });

  factory AppUpdateApk.fromJson(Map<Object?, Object?> json) {
    _keys(json, const {'url', 'sizeBytes', 'sha256', 'abi', 'minSdk'});
    final abi = _text(json, 'abi', 32);
    if (abi != 'arm64-v8a') throw const FormatException('Unsupported APK ABI');
    return AppUpdateApk(
      url: _githubUrl(_text(json, 'url', 1024)),
      sizeBytes: _integer(json, 'sizeBytes', 1, AppUpdateManifest.maxApkBytes),
      sha256: _hash(_text(json, 'sha256', 64)),
      abi: abi,
      minSdk: _integer(json, 'minSdk', 21, 100),
    );
  }

  Map<String, Object> toJson() => {
        'url': url.toString(),
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        'abi': abi,
        'minSdk': minSdk,
      };
}

class InstalledAppInfo {
  final String packageName;
  final String versionName;
  final int versionCode;
  final int sdkInt;
  final List<String> supportedAbis;
  final List<String> signerSha256;

  const InstalledAppInfo({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.sdkInt,
    required this.supportedAbis,
    required this.signerSha256,
  });

  factory InstalledAppInfo.fromJson(Map<Object?, Object?> json) {
    return InstalledAppInfo(
      packageName: _text(json, 'packageName', 128),
      versionName: _text(json, 'versionName', 64),
      versionCode: _integer(json, 'versionCode', 1, 0x7fffffff),
      sdkInt: _integer(json, 'sdkInt', 1, 100),
      supportedAbis: _strings(json['supportedAbis'], 'supportedAbis'),
      signerSha256: List.unmodifiable(
        _strings(json['signerSha256'], 'signerSha256').map(_hash),
      ),
    );
  }
}

enum AppUpdateDownloadStatus {
  none,
  pending,
  running,
  paused,
  downloaded,
  ready,
  failed,
  awaitingInstall,
}

class AppUpdateDownload {
  final AppUpdateDownloadStatus status;
  final int downloadedBytes;
  final int totalBytes;
  final String? reason;
  final AppUpdateManifest? manifest;

  const AppUpdateDownload({
    required this.status,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.reason,
    this.manifest,
  });

  bool get isActive =>
      status == AppUpdateDownloadStatus.pending ||
      status == AppUpdateDownloadStatus.running ||
      status == AppUpdateDownloadStatus.paused;

  double? get progress =>
      totalBytes <= 0 ? null : (downloadedBytes / totalBytes).clamp(0.0, 1.0);

  factory AppUpdateDownload.fromJson(Map<Object?, Object?> json) {
    final statusText = _text(json, 'status', 32);
    final status = AppUpdateDownloadStatus.values.where(
      (status) => status.name == statusText,
    );
    if (status.isEmpty) throw const FormatException('Invalid download status');
    final downloaded =
        _integer(json, 'downloadedBytes', 0, AppUpdateManifest.maxApkBytes);
    final total =
        _integer(json, 'totalBytes', 0, AppUpdateManifest.maxApkBytes);
    if (total > 0 && downloaded > total) {
      throw const FormatException('Invalid download progress');
    }
    final manifestJson = json['manifest'];
    final manifest = manifestJson == null
        ? null
        : manifestJson is Map
            ? AppUpdateManifest.fromJson(
                Map<Object?, Object?>.from(manifestJson))
            : throw const FormatException('Invalid download manifest');
    final value = status.single;
    if (value != AppUpdateDownloadStatus.none &&
        value != AppUpdateDownloadStatus.failed &&
        manifest == null) {
      throw const FormatException('Download is missing its bound manifest');
    }
    final reason = json['reason'];
    if (reason != null && (reason is! String || reason.length > 2048)) {
      throw const FormatException('Invalid download reason');
    }
    return AppUpdateDownload(
      status: value,
      downloadedBytes: downloaded,
      totalBytes: total,
      reason: reason as String?,
      manifest: manifest,
    );
  }

  AppUpdateDownload withStatus(AppUpdateDownloadStatus status) =>
      AppUpdateDownload(
        status: status,
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
        reason: reason,
        manifest: manifest,
      );
}

enum UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  verifying,
  ready,
  permissionRequired,
  awaitingInstall,
  failed,
  unsupported,
}

void _keys(Map<Object?, Object?> map, Set<String> expected) {
  if (map.length != expected.length ||
      !map.keys.every((key) => key is String && expected.contains(key))) {
    throw const FormatException('Invalid update fields');
  }
}

int _integer(Map<Object?, Object?> map, String key, int min, int max) {
  final value = map[key];
  if (value is! int || value < min || value > max) {
    throw FormatException('Invalid $key');
  }
  return value;
}

String _text(Map<Object?, Object?> map, String key, int max,
    {bool allowEmpty = false, bool allowNewlines = false}) {
  final value = map[key];
  if (value is! String ||
      (!allowEmpty && value.trim().isEmpty) ||
      value.length > max ||
      (allowNewlines
              ? RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]')
              : RegExp(r'[\x00-\x1f\x7f]'))
          .hasMatch(value)) {
    throw FormatException('Invalid $key');
  }
  return value;
}

String _hash(String hash) {
  if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash)) {
    throw const FormatException('Invalid SHA-256');
  }
  return hash.toLowerCase();
}

List<String> _strings(Object? value, String key) {
  if (value is! List ||
      value.length > 32 ||
      value.any(
          (item) => item is! String || item.isEmpty || item.length > 128)) {
    throw FormatException('Invalid $key');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

Uri _githubUrl(String value) {
  final uri = Uri.tryParse(value);
  if (!value.startsWith('https://github.com/') ||
      uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'github.com' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.hasFragment ||
      value.contains('\\') ||
      uri.path.contains('%') ||
      uri.path.contains('//')) {
    throw const FormatException('Invalid GitHub update URL');
  }
  return uri;
}

DateTime _timestamp(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(value);
  if (match == null) throw const FormatException('Invalid publication date');
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final zone = match[7]!;
  if (year < 1970 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > DateTime.utc(year, month + 1, 0).day ||
      int.parse(match[4]!) > 23 ||
      int.parse(match[5]!) > 59 ||
      int.parse(match[6]!) > 59 ||
      (zone != 'Z' &&
          (int.parse(zone.substring(1, 3)) > 14 ||
              int.parse(zone.substring(4, 6)) > 59 ||
              (zone.substring(1, 3) == '14' &&
                  zone.substring(4, 6) != '00')))) {
    throw const FormatException('Invalid publication date');
  }
  return DateTime.parse(value).toUtc();
}
