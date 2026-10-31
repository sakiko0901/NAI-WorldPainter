import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/app_update.dart';

Map<String, Object> manifestJson({int code = 11}) => {
      'schemaVersion': 1,
      'channel': 'stable',
      'packageName': AppUpdateManifest.packageId,
      'versionName': '1.2.5',
      'versionCode': code,
      'publishedAt': '2026-10-31T08:30:00Z',
      'releaseNotes': '修复问题\n支持更新',
      'releaseUrl':
          'https://github.com/sakiko0901/NAI-WorldPainter/releases/tag/v1.2.5-11',
      'apk': <String, Object>{
        'url':
            'https://github.com/sakiko0901/NAI-WorldPainter/releases/download/v1.2.5-11/app-release.apk',
        'sizeBytes': 100,
        'sha256': List.filled(64, 'a').join(),
        'abi': 'arm64-v8a',
        'minSdk': 21,
      },
    };

void main() {
  test('stable release survives serialization with its exact artifact identity',
      () {
    final value = AppUpdateManifest.fromJson(manifestJson());
    final roundtrip = AppUpdateManifest.fromJson(value.toJson());
    expect(roundtrip.sameArtifact(value), isTrue);
    expect(roundtrip.releaseNotes, '修复问题\n支持更新');
    expect(roundtrip.publishedAt, DateTime.utc(2026, 10, 31, 8, 30));
  });

  final invalid = <String, void Function(Map<String, Object>)>{
    'new schema': (json) => json['schemaVersion'] = 2,
    'string version code': (json) => json['versionCode'] = '11',
    'floating point version code': (json) => json['versionCode'] = 11.0,
    'version code overflow': (json) => json['versionCode'] = 0x80000000,
    'wrong package': (json) => json['packageName'] = 'com.other.app',
    'beta channel': (json) => json['channel'] = 'beta',
    'prerelease version': (json) => json['versionName'] = '1.2.5-beta',
    'unknown field': (json) => json['token'] = 'unexpected',
    'invalid day': (json) => json['publishedAt'] = '2026-02-30T00:00:00Z',
    'missing timezone': (json) => json['publishedAt'] = '2026-10-31T00:00:00',
    'userinfo': (json) => json['releaseUrl'] =
        'https://user@github.com/sakiko0901/NAI-WorldPainter/releases/tag/v1.2.5-11',
    'query': (json) => json['releaseUrl'] = '${json['releaseUrl']}?download=1',
    'fragment': (json) => json['releaseUrl'] = '${json['releaseUrl']}#x',
    'port': (json) => json['releaseUrl'] =
        'https://github.com:443/sakiko0901/NAI-WorldPainter/releases/tag/v1.2.5-11',
    'other repo': (json) => json['releaseUrl'] =
        'https://github.com/evil/NAI-WorldPainter/releases/tag/v1.2.5-11',
    'encoded slash': (json) => json['releaseUrl'] =
        'https://github.com/sakiko0901/NAI-WorldPainter/releases/tag/v1%2f2',
    'different release tag': (json) => (json['apk'] as Map)['url'] =
        'https://github.com/sakiko0901/NAI-WorldPainter/releases/download/v1.2.4/app-release.apk',
    'different file': (json) => (json['apk'] as Map)['url'] =
        'https://github.com/sakiko0901/NAI-WorldPainter/releases/download/v1.2.5-11/other.apk',
    'oversize APK': (json) =>
        (json['apk'] as Map)['sizeBytes'] = AppUpdateManifest.maxApkBytes + 1,
    'empty APK': (json) => (json['apk'] as Map)['sizeBytes'] = 0,
    'invalid hash': (json) => (json['apk'] as Map)['sha256'] = 'z' * 64,
    'other ABI': (json) => (json['apk'] as Map)['abi'] = 'x86_64',
    'bad SDK': (json) => (json['apk'] as Map)['minSdk'] = -1,
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key}', () {
      final json = manifestJson();
      entry.value(json);
      expect(() => AppUpdateManifest.fromJson(json), throwsFormatException);
    });
  }

  test('download state rejects unbound and impossible progress', () {
    expect(
        () => AppUpdateDownload.fromJson({
              'status': 'ready',
              'downloadedBytes': 100,
              'totalBytes': 100,
            }),
        throwsFormatException);
    expect(
        () => AppUpdateDownload.fromJson({
              'status': 'running',
              'downloadedBytes': 101,
              'totalBytes': 100,
              'manifest': manifestJson(),
            }),
        throwsFormatException);
    expect(
        () => AppUpdateDownload.fromJson({
              'status': 'unknown',
              'downloadedBytes': 0,
              'totalBytes': 0,
            }),
        throwsFormatException);
  });
}
