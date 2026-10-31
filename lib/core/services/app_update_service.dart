import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/app_update_platform.dart';
import '../../data/datasources/remote/app_update_source.dart';
import '../../domain/entities/app_update.dart';
import 'app_update_install_guard.dart';

enum _UpdateAction { starting, cancelling, verifying, installing }

/// Application-scoped updater. Android owns the download and the verified APK;
/// this notifier only polls while foregrounded and never installs automatically.
class AppUpdateService extends ChangeNotifier with WidgetsBindingObserver {
  static const autoCheckPreferenceKey = 'app_update_v1.auto_check_enabled';
  static const lastCheckedPreferenceKey = 'app_update_v1.last_checked_at';
  static const ignoredVersionPreferenceKey = 'app_update_v1.ignored_version';

  final AppUpdateSource _source;
  final AppUpdatePlatform _platform;
  final SharedPreferences _preferences;
  final AppUpdateInstallGuard _installGuard;
  final DateTime Function() _now;
  final Duration _pollInterval;

  InstalledAppInfo? _installed;
  AppUpdateManifest? _manifest;
  AppUpdateDownload? _download;
  UpdatePhase _phase = UpdatePhase.idle;
  String? _message;
  bool _autoCheckEnabled = true;
  int _automaticPromptRevision = 0;
  AppUpdateManifest? _automaticPromptManifest;
  final Set<int> _automaticallyPromptedVersions = {};
  DateTime? _lastCheckedAt;
  int? _ignoredVersion;
  int? _manuallyAllowedVersion;
  bool _requiresUnsavedConfirmation = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _observing = false;
  bool _initialized = false;
  bool _ownsInstallGuard = false;
  bool _resumePending = false;
  int _epoch = 0;
  _UpdateAction? _action;
  Timer? _pollTimer;
  Future<void>? _initialization;
  Future<void>? _startupInitialization;
  bool _startupCheckPending = false;
  Future<void>? _checking;
  bool _checkingSilent = false;
  int _manualChecksPending = 0;
  Future<void>? _refreshing;
  Future<void>? _resuming;
  Future<AppUpdateDownload>? _starting;
  Future<AppUpdateDownload>? _verifying;

  AppUpdateService({
    required AppUpdateSource source,
    required AppUpdatePlatform platform,
    required SharedPreferences preferences,
    required AppUpdateInstallGuard installGuard,
    DateTime Function()? now,
    Duration pollInterval = const Duration(seconds: 1),
  })  : _source = source,
        _platform = platform,
        _preferences = preferences,
        _installGuard = installGuard,
        _now = now ?? DateTime.now,
        _pollInterval = pollInterval;

  InstalledAppInfo? get installed => _installed;
  AppUpdateManifest? get manifest => _manifest;
  AppUpdateDownload? get download => _download;
  UpdatePhase get phase => _phase;
  String? get message => _message;
  bool get autoCheckEnabled => _autoCheckEnabled;
  int get automaticPromptRevision => _automaticPromptRevision;
  AppUpdateManifest? get automaticPromptManifest => _automaticPromptManifest;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  bool get isSupported =>
      _platform.isSupported && _phase != UpdatePhase.unsupported;
  bool get canCheckForUpdates => _canCheckInstalledApp;
  bool get requiresUnsavedConfirmation => _requiresUnsavedConfirmation;
  bool get isBusy =>
      _action != null ||
      _phase == UpdatePhase.checking ||
      _phase == UpdatePhase.downloading ||
      _phase == UpdatePhase.verifying ||
      _phase == UpdatePhase.awaitingInstall;
  bool get hasUpdate =>
      _manifest != null &&
      _installed != null &&
      _manifest!.versionCode > _installed!.versionCode &&
      !_isIgnored(_manifest!) &&
      _phase != UpdatePhase.unsupported;

  bool get _hasBoundDownload =>
      _download != null &&
      _download!.status != AppUpdateDownloadStatus.none &&
      _download!.status != AppUpdateDownloadStatus.failed;

  // A release may be incompatible (for example a higher minSdk), while the
  // installed application remains eligible to check a later compatible release.
  bool get _canCheckInstalledApp =>
      _platform.isSupported &&
      _installed != null &&
      _installedIncompatibility(_installed!) == null;

  Future<void> initialize() {
    if (_disposed) return Future<void>.value();
    return _startupInitialization ??= _initializeForStartup();
  }

  Future<void> _initializeForStartup() async {
    _startupCheckPending = true;
    await _ensureInitialized();
    await _checkAtStartup();
  }

  Future<void> _checkAtStartup() async {
    if (_disposed || !_startupCheckPending) return;
    if (!_autoCheckEnabled || !_canCheckInstalledApp) {
      _startupCheckPending = false;
      return;
    }
    // A process created in the background checks at its first foreground entry.
    if (!_initialized || !_foreground || _action != null || _ownsInstallGuard) {
      return;
    }
    _startupCheckPending = false;
    await _check(silent: true, forceInterval: true);
  }

  Future<void> _ensureInitialized() {
    if (_disposed) return Future<void>.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    final auto = _preferences.get(autoCheckPreferenceKey);
    _autoCheckEnabled = auto is bool ? auto : true;
    final ignored = _preferences.get(ignoredVersionPreferenceKey);
    _ignoredVersion =
        ignored is int && ignored > 0 && ignored <= 0x7fffffff ? ignored : null;
    final checked = _preferences.get(lastCheckedPreferenceKey);
    if (checked is int && checked >= 0 && checked <= 8640000000000000) {
      final date = DateTime.fromMillisecondsSinceEpoch(checked, isUtc: true);
      if (!date.isAfter(_now().add(const Duration(minutes: 5)))) {
        _lastCheckedAt = date;
      }
    }
    if (!_platform.isSupported) {
      _initialized = true;
      _phase = UpdatePhase.unsupported;
      _message = '当前平台不支持应用内更新，请前往发布页下载。';
      _emit();
      return;
    }
    final binding = WidgetsBinding.instance;
    _foreground = binding.lifecycleState == null ||
        binding.lifecycleState == AppLifecycleState.resumed;
    binding.addObserver(this);
    _observing = true;
    await _restoreNative(returningFromInstaller: true);
    _initialized = true;
  }

  Future<void> checkForUpdates({bool silent = false}) async {
    if (_disposed) return;
    if (!silent) {
      ++_manualChecksPending;
      _clearAutomaticPrompt();
    }
    try {
      await _ensureInitialized();
      if (_disposed || !_platform.isSupported) return;
      if (_installed == null) await refresh();
      await _check(silent: silent);
    } finally {
      if (!silent) --_manualChecksPending;
    }
  }

  Future<void> _check(
      {required bool silent, bool forceInterval = false}) async {
    if (_disposed || !_canCheckInstalledApp) return;
    if (!silent) _clearAutomaticPrompt();
    // A manual request waits out a silent request, then deliberately bypasses its
    // interval/ignored-version result. Silent requests share one in-flight check.
    final pending = _checking;
    if (pending != null) {
      final followSilentCheck = !silent && _checkingSilent;
      await pending;
      if (!followSilentCheck || _disposed) return;
      if (identical(_checking, pending)) _checking = null;
      return _check(silent: false);
    }
    if (silent &&
        (!_autoCheckEnabled ||
            !_foreground ||
            (!forceInterval &&
                _lastCheckedAt != null &&
                _now().difference(_lastCheckedAt!) <
                    const Duration(days: 1)))) {
      return;
    }
    if (_action != null || _ownsInstallGuard) return;
    final future = _performCheck(silent);
    _checkingSilent = silent;
    _checking = future;
    try {
      await future;
    } finally {
      if (identical(_checking, future)) _checking = null;
    }
  }

  Future<void> _performCheck(bool silent) async {
    final epoch = _epoch;
    final previousPhase = _phase;
    final previousMessage = _message;
    final protected = _hasBoundDownload;
    final checkedAt = _now().toUtc();
    _lastCheckedAt = checkedAt;
    if (!protected) {
      _phase = UpdatePhase.checking;
      _message = null;
      _emit();
    }
    // Persist attempt time even after a network failure, so foregrounding does
    // not hammer GitHub. This never implies a successful/latest-version result.
    await _saveInt(lastCheckedPreferenceKey, checkedAt.millisecondsSinceEpoch);
    if (!_current(epoch)) return;
    try {
      final latest = (await _source.fetchLatest()).validated();
      if (!_current(epoch)) return;
      if (protected || _hasBoundDownload) {
        _emit();
        return;
      }
      _manifest = latest;
      _manuallyAllowedVersion = silent ? null : latest.versionCode;
      _requiresUnsavedConfirmation = false;
      _message = null;
      final incompatibility = _incompatibility(latest);
      if (incompatibility != null) {
        _phase = UpdatePhase.unsupported;
        _message = incompatibility;
      } else if (latest.versionCode <= _installed!.versionCode) {
        _phase = UpdatePhase.upToDate;
      } else {
        _phase = _isIgnored(latest) ? UpdatePhase.idle : UpdatePhase.available;
        if (_isIgnored(latest)) _message = '已忽略此版本，手动检查可再次查看。';
      }
      if (silent) {
        if (_autoCheckEnabled &&
            _manualChecksPending == 0 &&
            _phase == UpdatePhase.available) {
          if (_automaticallyPromptedVersions.add(latest.versionCode)) {
            _automaticPromptManifest = latest;
            ++_automaticPromptRevision;
          } else if (_automaticPromptManifest?.versionCode !=
              latest.versionCode) {
            _clearAutomaticPrompt(notify: false);
          }
        } else {
          _clearAutomaticPrompt(notify: false);
        }
      }
    } catch (error) {
      if (!_current(epoch)) return;
      if (protected || _hasBoundDownload) {
        // A foreground poll may have reached ready while this request ran.
      } else if (silent) {
        _phase = previousPhase;
        _message = previousMessage;
      } else {
        _phase = UpdatePhase.failed;
        _message =
            error is AppUpdateException ? error.message : '检查更新失败，请稍后重试。';
      }
    }
    _emit();
  }

  Future<void> startDownload() async {
    await _ensureInitialized();
    if (_disposed || _action != null || _hasBoundDownload || !hasUpdate) return;
    final candidate = _manifest!;
    final incompatible = _incompatibility(candidate);
    if (incompatible != null) {
      _phase = UpdatePhase.unsupported;
      _message = incompatible;
      _emit();
      return;
    }
    final epoch = ++_epoch;
    _clearAutomaticPrompt(notify: false);
    _action = _UpdateAction.starting;
    _requiresUnsavedConfirmation = false;
    _phase = UpdatePhase.downloading;
    _message = null;
    _download = AppUpdateDownload(
        status: AppUpdateDownloadStatus.pending,
        totalBytes: candidate.apk.sizeBytes,
        manifest: candidate);
    _emit();
    Future<AppUpdateDownload>? request;
    try {
      request = _platform.startDownload(candidate.validated());
      _starting = request;
      final state = await request;
      if (!_current(epoch)) return;
      _validateState(state, expected: candidate);
      if (state.status == AppUpdateDownloadStatus.none) {
        throw const FormatException('Download did not start');
      }
      _applyState(state);
    } catch (_) {
      if (_current(epoch)) {
        _phase = UpdatePhase.failed;
        _download = AppUpdateDownload(
            status: AppUpdateDownloadStatus.failed, manifest: candidate);
        _message = '无法开始下载，请稍后重试或前往发布页下载。';
      }
    } finally {
      if (identical(_starting, request)) _starting = null;
      _endAction(epoch);
    }
    if (_current(epoch)) await _verifyIfDownloaded();
  }

  Future<void> cancelDownload() async {
    await _ensureInitialized();
    if (_disposed ||
        _action == _UpdateAction.cancelling ||
        _action == _UpdateAction.installing ||
        _ownsInstallGuard ||
        _phase == UpdatePhase.awaitingInstall) {
      return;
    }
    final start = _starting;
    final verification = _verifying;
    final epoch = ++_epoch;
    _action = _UpdateAction.cancelling;
    _stopPolling();
    _message = '正在取消下载…';
    _emit();
    try {
      // Cancel after a pending native start/verify has settled. A late callback
      // can neither recreate the Dart state nor leave an orphan native download.
      if (start != null) {
        try {
          await start;
        } catch (_) {}
      }
      if (verification != null) {
        try {
          await verification;
        } catch (_) {}
      }
      if (!_current(epoch)) return;
      await _platform.cancelDownload();
      if (!_current(epoch)) return;
      _download = const AppUpdateDownload(status: AppUpdateDownloadStatus.none);
      _phase = hasUpdate ? UpdatePhase.available : UpdatePhase.idle;
      _requiresUnsavedConfirmation = false;
      _message = '已取消下载。';
    } catch (_) {
      if (_current(epoch)) {
        _message = '取消下载失败，请稍后重试。';
      }
    } finally {
      _endAction(epoch);
    }
  }

  Future<void> ignoreVersion() async {
    await _ensureInitialized();
    if (_disposed ||
        _manifest == null ||
        _hasBoundDownload ||
        _action != null) {
      return;
    }
    ++_epoch;
    _ignoredVersion = _manifest!.versionCode;
    _clearAutomaticPrompt(notify: false);
    _manuallyAllowedVersion = null;
    _phase = UpdatePhase.idle;
    _message = '已忽略此版本，手动检查可再次查看。';
    _emit();
    await _saveInt(ignoredVersionPreferenceKey, _ignoredVersion!);
  }

  Future<void> setAutoCheckEnabled(bool enabled) async {
    await _ensureInitialized();
    if (_disposed) return;
    _autoCheckEnabled = enabled;
    if (!enabled) _clearAutomaticPrompt(notify: false);
    _emit();
    try {
      await _preferences.setBool(autoCheckPreferenceKey, enabled);
    } catch (_) {}
  }

  Future<void> installUpdate({bool allowDiscardUnsaved = false}) {
    if (!_initialized && !_disposed) {
      return _ensureInitialized()
          .then((_) => installUpdate(allowDiscardUnsaved: allowDiscardUnsaved));
    }
    return _installUpdate(allowDiscardUnsaved: allowDiscardUnsaved);
  }

  Future<void> _installUpdate({required bool allowDiscardUnsaved}) async {
    if (_disposed ||
        _action != null ||
        _ownsInstallGuard ||
        (_phase != UpdatePhase.ready &&
            _phase != UpdatePhase.permissionRequired) ||
        _manifest == null ||
        _download?.status != AppUpdateDownloadStatus.ready) {
      return;
    }

    _requiresUnsavedConfirmation = false;
    final hardBlock = _installGuard.blockReason;
    if (hardBlock != null) {
      _message = hardBlock;
      _emit();
      return;
    }
    final warning = _installGuard.unsavedWarning;
    if (!allowDiscardUnsaved && warning != null) {
      _requiresUnsavedConfirmation = true;
      _message = warning;
      _emit();
      return;
    }
    if (!_installGuard.tryBeginInstall(
        allowDiscardUnsaved: allowDiscardUnsaved)) {
      _message = _installGuard.blockReason ?? '请先保存当前临时工作区后重试。';
      _emit();
      return;
    }
    _ownsInstallGuard = true;
    final epoch = ++_epoch;
    final wasPermissionRequired = _phase == UpdatePhase.permissionRequired;
    final candidate = _manifest!;
    _action = _UpdateAction.installing;
    _phase = UpdatePhase.verifying;
    _message = '正在重新校验安装包…';
    _emit();
    var keepLock = false;
    Future<AppUpdateDownload>? request;
    try {
      request = _platform.verifyDownload();
      _verifying = request;
      final verified = await request;
      if (!_current(epoch)) return;
      _validateState(verified, expected: candidate);
      if (verified.status != AppUpdateDownloadStatus.ready) {
        _download = verified;
        _phase = UpdatePhase.failed;
        _message = '安装包校验失败，请重新下载。';
        return;
      }
      _download = verified;
      final allowed = await _platform.canInstallPackages();
      if (!_current(epoch)) return;
      if (!allowed) {
        _phase = UpdatePhase.permissionRequired;
        _message = '请允许此应用安装更新，然后返回继续安装。';
        // The first click explains the permission; a second explicit click opens
        // Android settings. Returning never launches the installer automatically.
        if (wasPermissionRequired) await _platform.openInstallPermission();
        return;
      }
      await _platform.installUpdate();
      if (!_current(epoch)) return;
      _download = verified.withStatus(AppUpdateDownloadStatus.awaitingInstall);
      _phase = UpdatePhase.awaitingInstall;
      _message = '请在系统安装界面完成更新。';
      keepLock = true;
    } catch (_) {
      if (_current(epoch)) {
        _phase = _download?.status == AppUpdateDownloadStatus.ready
            ? UpdatePhase.ready
            : UpdatePhase.failed;
        _message = '无法打开安装界面，请重试或前往发布页下载。';
      }
    } finally {
      if (identical(_verifying, request)) _verifying = null;
      if (!keepLock) _releaseInstallGuard();
      _endAction(epoch);
    }
  }

  Future<void> openReleasePage() async {
    if (_disposed) return;
    try {
      await _platform.openReleasePage(url: _manifest?.releaseUrl);
    } catch (_) {
      if (_disposed) return;
      _message = '无法打开发布页，请稍后重试。';
      _emit();
    }
  }

  Future<void> refresh() async {
    await _ensureInitialized();
    if (_disposed || _action != null || !_platform.isSupported) return;
    final pending = _refreshing;
    if (pending != null) return pending;
    final future = _restoreNative();
    _refreshing = future;
    try {
      await future;
    } finally {
      if (identical(_refreshing, future)) _refreshing = null;
    }
  }

  Future<void> _restoreNative({bool returningFromInstaller = false}) async {
    if (_disposed || _action != null) return;
    final epoch = _epoch;
    final permissionWasRequired = _phase == UpdatePhase.permissionRequired;
    final awaiting = _phase == UpdatePhase.awaitingInstall || _ownsInstallGuard;
    try {
      final installed = await _platform.getInstalledInfo();
      if (!_current(epoch)) return;
      _installed = installed;
      final unsupportedInstalled = _installedIncompatibility(installed);
      if (unsupportedInstalled != null) {
        _phase = UpdatePhase.unsupported;
        _message = unsupportedInstalled;
        return;
      }
      final state = await _platform.getDownloadState();
      if (!_current(epoch)) return;
      _validateState(state);
      final candidate = state.manifest ?? _manifest;
      if (candidate != null && candidate.versionCode <= installed.versionCode) {
        if (state.status != AppUpdateDownloadStatus.none) {
          await _platform.cancelDownload();
          if (!_current(epoch)) return;
        }
        _manifest = candidate;
        _download =
            const AppUpdateDownload(status: AppUpdateDownloadStatus.none);
        _phase = UpdatePhase.upToDate;
        _message = null;
        _releaseInstallGuard();
        return;
      }
      if (candidate != null && _incompatibility(candidate) != null) {
        _phase = UpdatePhase.unsupported;
        _message = _incompatibility(candidate);
        return;
      }
      if (awaiting && !returningFromInstaller) {
        // A foreground poll is not evidence that the installer was dismissed.
        return;
      }
      if (_hasBoundDownload &&
          state.manifest != null &&
          _manifest != null &&
          !_manifest!.sameArtifact(state.manifest!)) {
        throw const FormatException('Native download changed its artifact');
      }
      if (returningFromInstaller &&
          state.status == AppUpdateDownloadStatus.awaitingInstall) {
        _applyState(state.withStatus(AppUpdateDownloadStatus.ready));
        _message = '安装尚未完成，可再次安装。';
      } else {
        _applyState(state);
        if (awaiting && returningFromInstaller && _phase == UpdatePhase.ready) {
          _message = '安装尚未完成，可再次安装。';
        }
      }
      if (permissionWasRequired && _phase == UpdatePhase.ready) {
        final allowed = await _platform.canInstallPackages();
        if (!_current(epoch)) return;
        if (!allowed) {
          _phase = UpdatePhase.permissionRequired;
          _message = '请允许此应用安装更新，然后返回继续安装。';
        }
      }
      if (returningFromInstaller) _releaseInstallGuard();
    } on MissingPluginException {
      if (!_current(epoch)) return;
      _phase = UpdatePhase.unsupported;
      _message = '当前安装版本不支持应用内更新，请前往发布页下载。';
      _releaseInstallGuard();
    } on FormatException {
      if (!_current(epoch)) return;
      // Only malformed persisted state is reset. Network/native transient errors
      // below never delete a previously verified APK.
      if (!_hasBoundDownload) {
        try {
          await _platform.cancelDownload();
        } catch (_) {}
        if (!_current(epoch)) return;
        _download =
            const AppUpdateDownload(status: AppUpdateDownloadStatus.none);
        _phase = UpdatePhase.failed;
      }
      _message = '更新记录损坏，请重新检查或下载更新。';
      if (returningFromInstaller) _releaseInstallGuard();
    } catch (_) {
      if (!_current(epoch)) return;
      if (!_hasBoundDownload) _phase = UpdatePhase.failed;
      if (awaiting && returningFromInstaller && _download != null) {
        _download = _download!.withStatus(AppUpdateDownloadStatus.ready);
        _phase = UpdatePhase.ready;
        _message = '暂时无法确认安装结果，请重试安装或重新检查。';
      } else {
        _message = '无法读取更新状态，请稍后重试。';
      }
      if (returningFromInstaller) _releaseInstallGuard();
    } finally {
      if (_current(epoch)) {
        if (returningFromInstaller) _releaseInstallGuard();
        _emit();
        _schedulePolling();
      }
    }
    if (_current(epoch)) await _verifyIfDownloaded();
  }

  void _validateState(AppUpdateDownload state, {AppUpdateManifest? expected}) {
    final manifest = state.manifest;
    if (state.status != AppUpdateDownloadStatus.none &&
        state.status != AppUpdateDownloadStatus.failed &&
        manifest == null) {
      throw const FormatException('Download has no manifest');
    }
    if (manifest != null) {
      manifest.validated();
      if (expected != null && !expected.sameArtifact(manifest)) {
        throw const FormatException('Download artifact mismatch');
      }
    }
    if (state.downloadedBytes < 0 ||
        state.totalBytes < 0 ||
        state.downloadedBytes > AppUpdateManifest.maxApkBytes ||
        state.totalBytes > AppUpdateManifest.maxApkBytes ||
        (state.totalBytes > 0 && state.downloadedBytes > state.totalBytes)) {
      throw const FormatException('Invalid native progress');
    }
  }

  void _applyState(AppUpdateDownload state) {
    _download = state;
    if (state.manifest != null) _manifest = state.manifest;
    _message = null;
    switch (state.status) {
      case AppUpdateDownloadStatus.none:
        _phase = hasUpdate ? UpdatePhase.available : UpdatePhase.idle;
      case AppUpdateDownloadStatus.pending:
      case AppUpdateDownloadStatus.running:
      case AppUpdateDownloadStatus.paused:
        _phase = UpdatePhase.downloading;
        if (state.status == AppUpdateDownloadStatus.paused) {
          _message = '下载已暂停，系统将在条件允许时继续。';
        }
      case AppUpdateDownloadStatus.downloaded:
        _phase = UpdatePhase.verifying;
      case AppUpdateDownloadStatus.ready:
        _phase = UpdatePhase.ready;
      case AppUpdateDownloadStatus.awaitingInstall:
        _phase = UpdatePhase.awaitingInstall;
      case AppUpdateDownloadStatus.failed:
        _phase = UpdatePhase.failed;
        _message = '更新下载或校验失败，请重新下载。';
    }
  }

  Future<void> _verifyIfDownloaded() async {
    if (_disposed ||
        _action != null ||
        _download?.status != AppUpdateDownloadStatus.downloaded) {
      return;
    }
    final candidate = _download!.manifest!;
    final epoch = ++_epoch;
    _action = _UpdateAction.verifying;
    _phase = UpdatePhase.verifying;
    _emit();
    Future<AppUpdateDownload>? request;
    try {
      request = _platform.verifyDownload();
      _verifying = request;
      final state = await request;
      if (!_current(epoch)) return;
      _validateState(state, expected: candidate);
      if (state.status != AppUpdateDownloadStatus.ready &&
          state.status != AppUpdateDownloadStatus.failed) {
        throw const FormatException('Unexpected verification result');
      }
      _applyState(state);
    } catch (_) {
      if (_current(epoch)) {
        _phase = UpdatePhase.failed;
        _download = AppUpdateDownload(
            status: AppUpdateDownloadStatus.failed, manifest: candidate);
        _message = '安装包校验失败，请重新下载。';
      }
    } finally {
      if (identical(_verifying, request)) _verifying = null;
      _endAction(epoch);
    }
  }

  String? _incompatibility(AppUpdateManifest candidate) {
    final installed = _installed;
    if (installed == null) return '暂时无法读取当前版本，请稍后重试。';
    if (installed.packageName != candidate.packageName) {
      return '更新包与当前应用不匹配，请前往发布页查看。';
    }
    if (!installed.supportedAbis.contains(candidate.apk.abi)) {
      return '当前设备不支持此更新包，请前往发布页查看。';
    }
    if (installed.sdkInt < candidate.apk.minSdk) {
      return '当前 Android 版本不支持此更新包，请前往发布页查看。';
    }
    return null;
  }

  String? _installedIncompatibility(InstalledAppInfo installed) {
    if (installed.packageName != AppUpdateManifest.packageId ||
        !installed.supportedAbis.contains('arm64-v8a')) {
      return '当前应用或设备不支持此更新包，请前往发布页查看。';
    }
    if (!AppUpdateManifest.isStableVersion(installed.versionName)) {
      return '预览版本不支持正式版应用内更新，请前往发布页查看。';
    }
    return null;
  }

  bool _isIgnored(AppUpdateManifest candidate) =>
      !_hasBoundDownload &&
      _ignoredVersion == candidate.versionCode &&
      _manuallyAllowedVersion != candidate.versionCode;

  /// Called only when the application-level prompt was actually shown.
  void acknowledgeAutomaticPrompt(int versionCode) {
    if (_disposed || _automaticPromptManifest?.versionCode != versionCode) {
      return;
    }
    _clearAutomaticPrompt();
  }

  void _clearAutomaticPrompt({bool notify = true}) {
    if (_disposed || _automaticPromptManifest == null) return;
    _automaticPromptManifest = null;
    if (notify) _emit();
  }

  bool _current(int epoch) => !_disposed && _epoch == epoch;

  Future<void> _saveInt(String key, int value) async {
    try {
      await _preferences.setInt(key, value);
    } catch (_) {}
  }

  void _endAction(int epoch) {
    if (!_current(epoch)) return;
    _action = null;
    _emit();
    _schedulePolling();
    if (_resumePending && _foreground) {
      unawaited(_resume());
    } else if (_startupCheckPending && _foreground) {
      // Let a just-downloaded APK enter its verification action before retrying.
      unawaited(Future<void>.microtask(_checkAtStartup));
    }
  }

  void _releaseInstallGuard() {
    if (!_ownsInstallGuard) return;
    _ownsInstallGuard = false;
    _installGuard.endInstall();
  }

  void _schedulePolling() {
    if (_disposed ||
        !_foreground ||
        _pollTimer != null ||
        _action != null ||
        _download?.isActive != true) {
      return;
    }
    _pollTimer = Timer(_pollInterval, () {
      _pollTimer = null;
      if (_disposed || !_foreground) return;
      unawaited(refresh().whenComplete(_schedulePolling));
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _stopPolling();
      return;
    }
    _resumePending = true;
    unawaited(_resume());
  }

  Future<void> _resume() {
    if (_disposed || !_foreground || _action != null) {
      return Future<void>.value();
    }
    final pending = _resuming;
    if (pending != null) return pending;
    final future = _performResume();
    _resuming = future;
    return future.whenComplete(() {
      if (identical(_resuming, future)) _resuming = null;
    });
  }

  Future<void> _performResume() async {
    _resumePending = false;
    final pending = _refreshing;
    if (pending != null) await pending;
    if (_disposed || !_foreground || _action != null) return;
    await _restoreNative(returningFromInstaller: true);
    if (_disposed || !_foreground) return;
    if (_startupCheckPending) {
      await _checkAtStartup();
    } else {
      await _check(silent: true);
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_epoch;
    _stopPolling();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _releaseInstallGuard();
    _source.dispose();
    // Android's DownloadManager intentionally continues after this notifier dies.
    super.dispose();
  }
}
