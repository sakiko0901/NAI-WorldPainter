import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/services/app_update_install_guard.dart';
import 'package:nai_huishi/core/services/app_update_service.dart';
import 'package:nai_huishi/data/datasources/app_update_platform.dart';
import 'package:nai_huishi/data/datasources/remote/app_update_source.dart';
import 'package:nai_huishi/domain/entities/app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_update_manifest_test.dart' show manifestJson;

AppUpdateManifest _manifest([int code = 11]) =>
    AppUpdateManifest.fromJson(manifestJson(code: code));

InstalledAppInfo _installed([int code = 10]) => InstalledAppInfo(
      packageName: AppUpdateManifest.packageId,
      versionName: '1.2.4',
      versionCode: code,
      sdkInt: 34,
      supportedAbis: const ['arm64-v8a', 'armeabi-v7a'],
      signerSha256: ['a' * 64],
    );

AppUpdateDownload _state(AppUpdateDownloadStatus status,
        [AppUpdateManifest? manifest]) =>
    AppUpdateDownload(
      status: status,
      manifest: manifest ?? _manifest(),
      totalBytes: 100,
      downloadedBytes: status == AppUpdateDownloadStatus.ready ||
              status == AppUpdateDownloadStatus.downloaded
          ? 100
          : 10,
    );

class _Source extends AppUpdateSource {
  AppUpdateManifest result = _manifest();
  Object? error;
  Future<AppUpdateManifest> Function()? onFetch;
  int calls = 0;
  @override
  Future<AppUpdateManifest> fetchLatest() async {
    calls++;
    if (onFetch != null) return onFetch!();
    if (error != null) throw error!;
    return result;
  }
}

class _Platform extends AppUpdatePlatform {
  bool supported = true;
  InstalledAppInfo info = _installed();
  AppUpdateDownload state =
      const AppUpdateDownload(status: AppUpdateDownloadStatus.none);
  bool permission = true;
  Object? stateError;
  Future<AppUpdateDownload> Function(AppUpdateManifest)? onStart;
  Future<AppUpdateDownload> Function()? onVerify;
  Future<InstalledAppInfo> Function()? onInfo;
  int infoCalls = 0;
  int stateCalls = 0;
  int startCalls = 0;
  int cancelCalls = 0;
  int verifyCalls = 0;
  int installCalls = 0;
  int permissionPageCalls = 0;

  @override
  bool get isSupported => supported;
  @override
  Future<InstalledAppInfo> getInstalledInfo() async {
    infoCalls++;
    return onInfo == null ? info : await onInfo!();
  }

  @override
  Future<AppUpdateDownload> getDownloadState() async {
    stateCalls++;
    if (stateError != null) throw stateError!;
    return state;
  }

  @override
  Future<AppUpdateDownload> startDownload(AppUpdateManifest manifest) async {
    startCalls++;
    state = onStart == null
        ? _state(AppUpdateDownloadStatus.pending, manifest)
        : await onStart!(manifest);
    return state;
  }

  @override
  Future<AppUpdateDownload> cancelDownload() async {
    cancelCalls++;
    state = const AppUpdateDownload(status: AppUpdateDownloadStatus.none);
    return state;
  }

  @override
  Future<AppUpdateDownload> verifyDownload() async {
    verifyCalls++;
    state = onVerify == null
        ? _state(AppUpdateDownloadStatus.ready, state.manifest)
        : await onVerify!();
    return state;
  }

  @override
  Future<bool> canInstallPackages() async => permission;
  @override
  Future<void> openInstallPermission() async {
    permissionPageCalls++;
  }

  @override
  Future<void> installUpdate() async {
    installCalls++;
    state = state.withStatus(AppUpdateDownloadStatus.awaitingInstall);
  }
}

Future<void> _drain() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Source source;
  late _Platform platform;
  late SharedPreferences preferences;
  late AppUpdateInstallGuard guard;
  late AppUpdateService service;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      AppUpdateService.autoCheckPreferenceKey: false,
    });
    preferences = await SharedPreferences.getInstance();
    source = _Source();
    platform = _Platform();
    guard = AppUpdateInstallGuard();
    now = DateTime.utc(2026, 10, 31, 12);
    service = AppUpdateService(
        source: source,
        platform: platform,
        preferences: preferences,
        installGuard: guard,
        now: () => now);
  });

  tearDown(() {
    service.dispose();
    guard.dispose();
  });

  test(
      'initialize is idempotent and unsupported platforms never contact GitHub',
      () async {
    platform.supported = false;
    await Future.wait([service.initialize(), service.initialize()]);
    expect(service.phase, UpdatePhase.unsupported);
    expect(platform.infoCalls, 0);
    await service.checkForUpdates();
    expect(source.calls, 0);
  });

  test(
      'default enabled foreground checks once a day; manual bypasses interval and ignore',
      () async {
    await preferences.remove(AppUpdateService.autoCheckPreferenceKey);
    await service.initialize();
    expect(source.calls, 1);
    expect(service.phase, UpdatePhase.available);
    await service.ignoreVersion();
    expect(service.hasUpdate, isFalse);
    expect(service.phase, UpdatePhase.idle);
    await service.checkForUpdates(silent: true);
    expect(source.calls, 1);
    await service.checkForUpdates();
    expect(source.calls, 2);
    expect(service.hasUpdate, isTrue);
    expect(service.phase, UpdatePhase.available);
    expect(
        preferences.getInt(AppUpdateService.ignoredVersionPreferenceKey), 11);
    expect(preferences.getInt(AppUpdateService.lastCheckedPreferenceKey),
        now.millisecondsSinceEpoch);
    now = now.add(const Duration(days: 1));
    await service.checkForUpdates(silent: true);
    expect(source.calls, 3);
    expect(service.hasUpdate, isFalse);
  });

  test('cold startup bypasses the persisted interval exactly once', () async {
    await preferences.setBool(AppUpdateService.autoCheckPreferenceKey, true);
    await preferences.setInt(AppUpdateService.lastCheckedPreferenceKey,
        now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch);
    final check = Completer<AppUpdateManifest>();
    source.onFetch = () => check.future;
    final first = service.initialize();
    final second = service.initialize();
    await _drain();
    expect(source.calls, 1);
    check.complete(_manifest());
    await Future.wait([first, second]);
    await service.initialize();
    expect(source.calls, 1);
    expect(service.automaticPromptRevision, 1);
    expect(service.automaticPromptManifest!.versionCode, 11);
    expect(platform.startCalls, 0);
    expect(platform.installCalls, 0);
  });

  test('another cold process checks again even on the same day', () async {
    await preferences.setBool(AppUpdateService.autoCheckPreferenceKey, true);
    await service.initialize();
    final firstSource = source;
    service.dispose();
    source = _Source();
    platform = _Platform();
    service = AppUpdateService(
        source: source,
        platform: platform,
        preferences: preferences,
        installGuard: guard,
        now: () => now);
    await service.initialize();
    expect(firstSource.calls, 1);
    expect(source.calls, 1);
    expect(service.automaticPromptRevision, 1);
  });

  test(
      'startup remains an automatic check after an earlier manual initialization',
      () async {
    await preferences.setBool(AppUpdateService.autoCheckPreferenceKey, true);
    await service.checkForUpdates();
    expect(source.calls, 1);
    expect(service.automaticPromptRevision, 0);
    await service.initialize();
    expect(source.calls, 2);
    expect(service.automaticPromptRevision, 1);
    await service.initialize();
    expect(source.calls, 2);
  });

  test('startup respects the disabled automatic-check preference', () async {
    await service.initialize();
    expect(source.calls, 0);
    expect(service.automaticPromptRevision, 0);
    await service.checkForUpdates();
    expect(source.calls, 1,
        reason: 'Manual checks still bypass this preference');
    expect(service.automaticPromptRevision, 0);
    expect(service.automaticPromptManifest, isNull);
  });

  test('a background startup defers its single forced check until foreground',
      () async {
    await preferences.setBool(AppUpdateService.autoCheckPreferenceKey, true);
    await preferences.setInt(
        AppUpdateService.lastCheckedPreferenceKey, now.millisecondsSinceEpoch);
    platform.onInfo = () async {
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      return _installed();
    };
    await service.initialize();
    expect(source.calls, 0);
    platform.onInfo = null;
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _drain();
    expect(source.calls, 1);
    expect(service.automaticPromptRevision, 1);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _drain();
    expect(source.calls, 1);
  });

  test(
      'resume remains daily throttled and a version is prompted once per process',
      () async {
    await preferences.setBool(AppUpdateService.autoCheckPreferenceKey, true);
    await service.initialize();
    service.acknowledgeAutomaticPrompt(11);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _drain();
    expect(source.calls, 1);
    now = now.add(const Duration(days: 1));
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _drain();
    expect(source.calls, 2);
    expect(service.automaticPromptRevision, 1);
    expect(service.automaticPromptManifest, isNull);
    source.result = _manifest(12);
    now = now.add(const Duration(days: 1));
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _drain();
    expect(source.calls, 3);
    expect(service.automaticPromptRevision, 2);
    expect(service.automaticPromptManifest!.versionCode, 12);
    source.result = _manifest(11);
    now = now.add(const Duration(days: 1));
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _drain();
    expect(service.automaticPromptRevision, 2);
    expect(service.automaticPromptManifest, isNull);
  });

  test(
      'ignored startup candidates never produce a prompt; manual checks still reveal them',
      () async {
    await preferences.setBool(AppUpdateService.autoCheckPreferenceKey, true);
    await preferences.setInt(AppUpdateService.ignoredVersionPreferenceKey, 11);
    await service.initialize();
    expect(source.calls, 1);
    expect(service.hasUpdate, isFalse);
    expect(service.automaticPromptRevision, 0);
    expect(service.automaticPromptManifest, isNull);
    await service.checkForUpdates();
    expect(service.phase, UpdatePhase.available);
    expect(service.hasUpdate, isTrue);
    expect(service.automaticPromptRevision, 0);
  });

  test(
      'automatic startup failure is quiet while a later manual failure is visible',
      () async {
    await preferences.setBool(AppUpdateService.autoCheckPreferenceKey, true);
    source.error = const AppUpdateException('更新服务请求受限。');
    await service.initialize();
    expect(source.calls, 1);
    expect(service.phase, UpdatePhase.idle);
    expect(service.message, isNull);
    expect(service.automaticPromptRevision, 0);
    expect(service.lastCheckedAt, now);
    await service.checkForUpdates();
    expect(service.phase, UpdatePhase.failed);
    expect(service.message, '更新服务请求受限。');
    expect(service.automaticPromptRevision, 0);
  });

  for (final status in [
    AppUpdateDownloadStatus.running,
    AppUpdateDownloadStatus.ready
  ]) {
    test('startup preserves a bound $status without prompting or reinstalling',
        () async {
      await preferences.setBool(AppUpdateService.autoCheckPreferenceKey, true);
      platform.state = _state(status);
      source.result = _manifest(12);
      await service.initialize();
      expect(source.calls, 1);
      expect(service.manifest!.versionCode, 11);
      expect(service.download!.status, status);
      expect(service.automaticPromptRevision, 0);
      expect(service.automaticPromptManifest, isNull);
      expect(platform.startCalls, 0);
      expect(platform.installCalls, 0);
      expect(platform.cancelCalls, 0);
      source.error = const AppUpdateException('网络失败');
      now = now.add(const Duration(days: 1));
      await service.checkForUpdates(silent: true);
      expect(service.download!.status, status);
      expect(service.automaticPromptRevision, 0);
    });
  }

  test(
      'acknowledgement consumes only the matching prompt and does not change download state',
      () async {
    await preferences.setBool(AppUpdateService.autoCheckPreferenceKey, true);
    await service.initialize();
    final download = service.download;
    service.acknowledgeAutomaticPrompt(12);
    expect(service.automaticPromptManifest!.versionCode, 11);
    service.acknowledgeAutomaticPrompt(11);
    expect(service.automaticPromptManifest, isNull);
    expect(service.automaticPromptRevision, 1);
    expect(identical(service.download, download), isTrue);
    expect(service.phase, UpdatePhase.available);
    now = now.add(const Duration(days: 1));
    await service.checkForUpdates(silent: true);
    expect(service.automaticPromptRevision, 1);
    expect(service.automaticPromptManifest, isNull);
  });

  for (final action in ['manual', 'ignore', 'disable', 'download']) {
    test('$action invalidates the unconsumed automatic prompt', () async {
      await preferences.setBool(AppUpdateService.autoCheckPreferenceKey, true);
      await service.initialize();
      expect(service.automaticPromptManifest, isNotNull);
      switch (action) {
        case 'manual':
          final check = Completer<AppUpdateManifest>();
          source.onFetch = () => check.future;
          final manual = service.checkForUpdates();
          expect(service.automaticPromptManifest, isNull,
              reason: 'Clear before the asynchronous manual request starts');
          check.complete(_manifest(12));
          await manual;
        case 'ignore':
          await service.ignoreVersion();
        case 'disable':
          await service.setAutoCheckEnabled(false);
        case 'download':
          await service.startDownload();
      }
      expect(service.automaticPromptManifest, isNull);
      expect(service.automaticPromptRevision, 1);
    });
  }

  test(
      'manual intent suppresses every intermediate prompt from an older automatic check',
      () async {
    await preferences.setBool(AppUpdateService.autoCheckPreferenceKey, true);
    final automatic = Completer<AppUpdateManifest>();
    final manual = Completer<AppUpdateManifest>();
    source.onFetch = () => source.calls == 1 ? automatic.future : manual.future;
    final emittedPrompts = <int>[];
    service.addListener(() {
      if (service.automaticPromptManifest != null ||
          service.automaticPromptRevision != 0) {
        emittedPrompts.add(service.automaticPromptRevision);
      }
    });
    final initializing = service.initialize();
    await _drain();
    expect(source.calls, 1);
    final checkingManually = service.checkForUpdates();
    await _drain();
    automatic.complete(_manifest(11));
    await _drain();
    expect(source.calls, 2);
    expect(service.automaticPromptRevision, 0);
    expect(service.automaticPromptManifest, isNull);
    expect(emittedPrompts, isEmpty);
    manual.complete(_manifest(12));
    await Future.wait([initializing, checkingManually]);
    expect(service.manifest!.versionCode, 12);
    expect(service.automaticPromptRevision, 0);
    expect(service.automaticPromptManifest, isNull);
    expect(emittedPrompts, isEmpty,
        reason:
            'No transient automatic event may reach an application listener');
  });

  for (final verify in [false, true]) {
    test(
        'a startup deferred by an active ${verify ? 'verification' : 'start'} checks after the action finishes',
        () async {
      await preferences.setBool(AppUpdateService.autoCheckPreferenceKey, true);
      await service.checkForUpdates();
      final start = Completer<AppUpdateDownload>();
      final verified = Completer<AppUpdateDownload>();
      platform.onStart = (_) => start.future;
      platform.onVerify = () => verified.future;
      final downloading = service.startDownload();
      await _drain();
      await service.initialize();
      expect(source.calls, 1);
      start.complete(_state(verify
          ? AppUpdateDownloadStatus.downloaded
          : AppUpdateDownloadStatus.running));
      if (verify) {
        await _drain();
        expect(service.phase, UpdatePhase.verifying);
        expect(source.calls, 1);
        verified.complete(_state(AppUpdateDownloadStatus.ready));
      }
      await downloading;
      await _drain();
      expect(source.calls, 2,
          reason:
              'A completed action should retry the startup check without waiting for resume');
      expect(service.automaticPromptRevision, 0,
          reason: 'The existing bound download must suppress the prompt');
      expect(platform.installCalls, 0);
    });
  }

  test('disabling auto while a startup request is pending prevents a prompt',
      () async {
    await preferences.setBool(AppUpdateService.autoCheckPreferenceKey, true);
    final check = Completer<AppUpdateManifest>();
    source.onFetch = () => check.future;
    final starting = service.initialize();
    await _drain();
    await service.setAutoCheckEnabled(false);
    check.complete(_manifest());
    await starting;
    expect(service.automaticPromptRevision, 0);
    expect(service.automaticPromptManifest, isNull);
    expect(platform.startCalls, 0);
    expect(platform.installCalls, 0);
  });

  test(
      'HTTP/network failure is not up to date and silent failure keeps a valid candidate',
      () async {
    await service.initialize();
    source.error = const AppUpdateException('暂未找到更新清单，请前往发布页查看。');
    await service.checkForUpdates();
    expect(service.phase, UpdatePhase.failed);
    expect(service.phase, isNot(UpdatePhase.upToDate));
    source.error = null;
    await service.checkForUpdates();
    expect(service.phase, UpdatePhase.available);
    await service.setAutoCheckEnabled(true);
    now = now.add(const Duration(days: 1));
    source.error = const AppUpdateException('无法连接更新服务。');
    await service.checkForUpdates(silent: true);
    expect(service.phase, UpdatePhase.available);
    expect(service.manifest!.versionCode, 11);
    expect(service.hasUpdate, isTrue);
  });

  test(
      'checks cannot replace the manifest bound to a download or completed APK',
      () async {
    platform.state = _state(AppUpdateDownloadStatus.running);
    await service.initialize();
    source.result = _manifest(12);
    await service.checkForUpdates();
    expect(service.phase, UpdatePhase.downloading);
    expect(service.manifest!.versionCode, 11);
    platform.state = _state(AppUpdateDownloadStatus.ready);
    await service.refresh();
    source.error = const AppUpdateException('限流');
    await service.checkForUpdates();
    expect(service.phase, UpdatePhase.ready);
    expect(service.manifest!.versionCode, 11);
    expect(platform.cancelCalls, 0);
  });

  for (final kind in ['platform', 'package', 'ABI', 'preview']) {
    test('$kind unsupported at initialization and resume never requests GitHub',
        () async {
      await preferences.setBool(AppUpdateService.autoCheckPreferenceKey, true);
      final info = _installed();
      if (kind == 'platform') {
        platform.supported = false;
      } else {
        platform.info = InstalledAppInfo(
          packageName: kind == 'package' ? 'other.package' : info.packageName,
          versionName: kind == 'preview' ? '1.2.5-preview' : info.versionName,
          versionCode: info.versionCode,
          sdkInt: info.sdkInt,
          supportedAbis: kind == 'ABI' ? const ['x86_64'] : info.supportedAbis,
          signerSha256: info.signerSha256,
        );
      }
      await service.initialize();
      expect(service.phase, UpdatePhase.unsupported);
      expect(source.calls, 0);
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _drain();
      await service.checkForUpdates();
      expect(source.calls, 0);
    });
  }

  test(
      'an incompatible release does not disable checking a later compatible release',
      () async {
    await service.initialize();
    final incompatible = manifestJson();
    (incompatible['apk'] as Map)['minSdk'] = 35;
    source.result = AppUpdateManifest.fromJson(incompatible);
    await service.checkForUpdates();
    expect(service.phase, UpdatePhase.unsupported);
    expect(source.calls, 1);
    source.result = _manifest();
    await service.checkForUpdates();
    expect(source.calls, 2);
    expect(service.phase, UpdatePhase.available);
    expect(service.hasUpdate, isTrue);
  });

  test('concurrent manual checks share one request', () async {
    await service.initialize();
    final check = Completer<AppUpdateManifest>();
    source.onFetch = () => check.future;
    final first = service.checkForUpdates();
    final second = service.checkForUpdates();
    await _drain();
    expect(source.calls, 1);
    check.complete(_manifest());
    await Future.wait([first, second]);
    expect(source.calls, 1);
    expect(service.phase, UpdatePhase.available);
  });

  test('a delayed check cannot revert a download which becomes ready',
      () async {
    platform.state = _state(AppUpdateDownloadStatus.running);
    await service.initialize();
    final check = Completer<AppUpdateManifest>();
    source.onFetch = () => check.future;
    final checking = service.checkForUpdates();
    await _drain();
    platform.state = _state(AppUpdateDownloadStatus.ready);
    await service.refresh();
    expect(service.phase, UpdatePhase.ready);
    check.complete(_manifest(12));
    await checking;
    expect(service.phase, UpdatePhase.ready);
    expect(service.manifest!.versionCode, 11);
  });

  test('download completion verifies automatically but never installs',
      () async {
    platform.state = _state(AppUpdateDownloadStatus.downloaded);
    await service.initialize();
    expect(platform.verifyCalls, 1);
    expect(platform.installCalls, 0);
    expect(service.phase, UpdatePhase.ready);
    expect(guard.isInstalling, isFalse);
  });

  test(
      'busy is a hard block; unsaved work needs an explicit separate confirmation',
      () async {
    platform.state = _state(AppUpdateDownloadStatus.ready);
    await service.initialize();
    final activity = guard.beginActivity('正在导出图片');
    guard.registerUnsaved('editor', () => '尚有未保存的编辑');
    await service.installUpdate(allowDiscardUnsaved: true);
    expect(service.phase, UpdatePhase.ready);
    expect(service.message, contains('正在导出'));
    expect(platform.verifyCalls, 0);
    activity();
    await service.installUpdate();
    expect(service.requiresUnsavedConfirmation, isTrue);
    expect(platform.verifyCalls, 0);
    await service.installUpdate(allowDiscardUnsaved: true);
    expect(platform.verifyCalls, 1);
    expect(platform.installCalls, 1);
    expect(service.phase, UpdatePhase.awaitingInstall);
  });

  test(
      'guard acquisition is synchronous and spans verify, intent and resume reconciliation',
      () async {
    platform.state = _state(AppUpdateDownloadStatus.ready);
    await service.initialize();
    final verify = Completer<AppUpdateDownload>();
    platform.onVerify = () => verify.future;
    final installing = service.installUpdate();
    expect(guard.isInstalling, isTrue);
    expect(() => guard.beginActivity('new job'), throwsStateError);
    await service.installUpdate();
    expect(platform.verifyCalls, 1);
    verify.complete(_state(AppUpdateDownloadStatus.ready));
    await installing;
    expect(service.phase, UpdatePhase.awaitingInstall);
    expect(guard.isInstalling, isTrue);
    expect(platform.installCalls, 1);
    await service.refresh();
    expect(guard.isInstalling, isTrue);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _drain();
    expect(guard.isInstalling, isFalse);
    expect(service.phase, UpdatePhase.ready);
    expect(platform.installCalls, 1);
  });

  test('permission return only restores ready; a later explicit click installs',
      () async {
    platform.state = _state(AppUpdateDownloadStatus.ready);
    platform.permission = false;
    await service.initialize();
    await service.installUpdate();
    expect(service.phase, UpdatePhase.permissionRequired);
    expect(guard.isInstalling, isFalse);
    expect(platform.permissionPageCalls, 0);
    await service.installUpdate();
    expect(platform.permissionPageCalls, 1);
    expect(guard.isInstalling, isFalse);
    platform.permission = true;
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _drain();
    expect(service.phase, UpdatePhase.ready);
    expect(platform.installCalls, 0);
    await service.installUpdate();
    expect(platform.installCalls, 1);
  });

  test(
      'an installer intent is not success; installed version is reconciled on resume',
      () async {
    platform.state = _state(AppUpdateDownloadStatus.ready);
    await service.initialize();
    await service.installUpdate();
    expect(service.installed!.versionCode, 10);
    expect(service.phase, UpdatePhase.awaitingInstall);
    platform.info = _installed(11);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _drain();
    expect(service.phase, UpdatePhase.upToDate);
    expect(service.hasUpdate, isFalse);
    expect(guard.isInstalling, isFalse);
    expect(platform.cancelCalls, 1);
  });

  test('cancel waits for a delayed start and discards its late callback',
      () async {
    await service.initialize();
    await service.checkForUpdates();
    final start = Completer<AppUpdateDownload>();
    platform.onStart = (_) => start.future;
    final starting = service.startDownload();
    await _drain();
    final cancelling = service.cancelDownload();
    await _drain();
    expect(platform.cancelCalls, 0);
    start.complete(_state(AppUpdateDownloadStatus.running));
    await Future.wait([starting, cancelling]);
    expect(platform.cancelCalls, 1);
    expect(service.download!.status, AppUpdateDownloadStatus.none);
    expect(service.phase, UpdatePhase.available);
  });

  test('cancel waits for verification and does not resurrect the verified file',
      () async {
    await service.initialize();
    await service.checkForUpdates();
    platform.onStart = (_) async => _state(AppUpdateDownloadStatus.downloaded);
    final verify = Completer<AppUpdateDownload>();
    platform.onVerify = () => verify.future;
    final starting = service.startDownload();
    await _drain();
    expect(service.phase, UpdatePhase.verifying);
    final cancelling = service.cancelDownload();
    await _drain();
    verify.complete(_state(AppUpdateDownloadStatus.ready));
    await Future.wait([starting, cancelling]);
    expect(service.phase, UpdatePhase.available);
    expect(service.download!.status, AppUpdateDownloadStatus.none);
    expect(platform.installCalls, 0);
  });

  test(
      'damaged persisted state is reset, a transient error preserves a verified APK',
      () async {
    platform.stateError = const FormatException('corrupt saved manifest');
    await service.initialize();
    expect(platform.cancelCalls, 1);
    expect(service.phase, UpdatePhase.failed);
    platform.stateError = null;
    platform.state = _state(AppUpdateDownloadStatus.ready);
    await service.refresh();
    platform.stateError = StateError('service unavailable');
    await service.refresh();
    expect(service.phase, UpdatePhase.ready);
    expect(service.download!.status, AppUpdateDownloadStatus.ready);
    expect(platform.cancelCalls, 1);
  });

  test('dispose suppresses late checks and leaves Android downloads alone',
      () async {
    await service.initialize();
    final check = Completer<AppUpdateManifest>();
    source.onFetch = () => check.future;
    var notifications = 0;
    service.addListener(() {
      notifications++;
    });
    final checking = service.checkForUpdates();
    await _drain();
    service.dispose();
    final before = notifications;
    check.complete(_manifest());
    await checking;
    expect(notifications, before);
    expect(platform.cancelCalls, 0);
  });

  testWidgets(
      'foreground polls active DownloadManager state; background pauses Dart polling',
      (tester) async {
    platform.state = _state(AppUpdateDownloadStatus.running);
    await service.initialize();
    final initialCalls = platform.stateCalls;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(platform.stateCalls, greaterThan(initialCalls));
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    final backgroundCalls = platform.stateCalls;
    await tester.pump(const Duration(seconds: 5));
    expect(platform.stateCalls, backgroundCalls);
    expect(platform.cancelCalls, 0);
    platform.state = _state(AppUpdateDownloadStatus.downloaded);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(service.phase, UpdatePhase.ready);
    expect(platform.verifyCalls, 1);
  });
}
