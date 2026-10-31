import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/datasources/app_update_platform.dart';
import 'package:nai_huishi/domain/entities/app_update.dart';

import 'app_update_manifest_test.dart' show manifestJson;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app_update_contract_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('bridge sends the bound manifest under the native argument key',
      () async {
    MethodCall? call;
    messenger.setMockMethodCallHandler(channel, (value) async {
      call = value;
      return {
        'status': 'pending',
        'downloadedBytes': 0,
        'totalBytes': 100,
        'manifest': manifestJson()
      };
    });
    final platform = AppUpdatePlatform(channel: channel);
    final manifest = AppUpdateManifest.fromJson(manifestJson());
    final state = await platform.startDownload(manifest);
    expect(call!.method, 'startDownload');
    expect(call!.arguments, {'manifest': manifest.toJson()});
    expect(state.manifest!.sameArtifact(manifest), isTrue);
  });

  test('bridge rejects malformed native success data', () async {
    messenger.setMockMethodCallHandler(
        channel,
        (_) async =>
            {'status': 'ready', 'downloadedBytes': 0, 'totalBytes': 0});
    await expectLater(AppUpdatePlatform(channel: channel).verifyDownload(),
        throwsFormatException);
  });

  test('release page rejects arbitrary URLs without invoking native code',
      () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    await expectLater(
        AppUpdatePlatform(channel: channel)
            .openReleasePage(url: Uri.parse('https://evil.invalid/')),
        throwsFormatException);
    expect(calls, 0);
  });
}
