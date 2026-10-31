import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/services/app_update_service.dart';
import 'package:nai_huishi/domain/entities/app_update.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/app_update_page.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';

const _installed = InstalledAppInfo(
  packageName: 'com.test.worldpainter',
  versionName: '1.0.0',
  versionCode: 10,
  sdkInt: 35,
  supportedAbis: ['arm64-v8a'],
  signerSha256: ['test-signing-certificate'],
);

final _manifest = AppUpdateManifest(
  schemaVersion: 1,
  channel: 'stable',
  packageName: _installed.packageName,
  versionName: '1.1.0',
  versionCode: 11,
  publishedAt: DateTime.utc(2026, 10, 30, 8),
  releaseNotes: '# 更新说明\n<script>alert("unsafe")</script>\n修复问题并改善体验。',
  releaseUrl: Uri.parse('https://example.com/releases/1.1.0'),
  apk: AppUpdateApk(
    url: Uri.parse('https://example.com/releases/app.apk'),
    sizeBytes: 2 * 1024 * 1024,
    sha256: '0' * 64,
    abi: 'arm64-v8a',
    minSdk: 23,
  ),
);

class _UpdaterFake extends ChangeNotifier implements AppUpdateService {
  @override
  InstalledAppInfo? installed = _installed;
  @override
  AppUpdateManifest? manifest;
  @override
  AppUpdateManifest? automaticPromptManifest;
  @override
  int automaticPromptRevision = 0;
  @override
  AppUpdateDownload? download;
  @override
  UpdatePhase phase = UpdatePhase.idle;
  @override
  String? message;
  @override
  bool autoCheckEnabled = true;
  @override
  DateTime? lastCheckedAt;
  @override
  bool requiresUnsavedConfirmation = false;
  bool hasUnsavedWork = false;
  final installAllowDiscard = <bool>[];

  int checks = 0;
  int downloads = 0;
  int cancellations = 0;
  int ignores = 0;
  int installs = 0;
  int releaseOpens = 0;
  int refreshes = 0;
  int initializations = 0;
  bool disposed = false;
  bool? checkCapability;
  final acknowledgedVersions = <int>[];
  bool notifyWhenAcknowledged = false;

  @override
  bool get hasUpdate => manifest != null && phase != UpdatePhase.upToDate;
  @override
  bool get isBusy =>
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.verifying ||
      phase == UpdatePhase.checking;
  @override
  bool get isSupported => phase != UpdatePhase.unsupported;
  @override
  bool get canCheckForUpdates => checkCapability ?? isSupported;

  @override
  void acknowledgeAutomaticPrompt(int versionCode) {
    acknowledgedVersions.add(versionCode);
    if (notifyWhenAcknowledged) notifyListeners();
  }

  void receive(UpdatePhase next, {String? notice}) {
    phase = next;
    message = notice;
    notifyListeners();
  }

  void progress(int received, int total) {
    download = AppUpdateDownload(
      status: AppUpdateDownloadStatus.running,
      downloadedBytes: received,
      totalBytes: total,
      manifest: manifest,
    );
    notifyListeners();
  }

  @override
  Future<void> initialize() async => initializations++;
  @override
  Future<void> checkForUpdates({bool silent = false}) async => checks++;
  @override
  Future<void> startDownload() async => downloads++;
  @override
  Future<void> cancelDownload() async => cancellations++;
  @override
  Future<void> ignoreVersion() async => ignores++;
  @override
  Future<void> installUpdate({bool allowDiscardUnsaved = false}) async {
    installs++;
    installAllowDiscard.add(allowDiscardUnsaved);
    requiresUnsavedConfirmation = hasUnsavedWork && !allowDiscardUnsaved;
    notifyListeners();
  }

  @override
  Future<void> openReleasePage() async => releaseOpens++;
  @override
  Future<void> refresh() async => refreshes++;
  @override
  Future<void> setAutoCheckEnabled(bool enabled) async {
    autoCheckEnabled = enabled;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpPage(
  WidgetTester tester,
  _UpdaterFake updater, {
  Brightness brightness = Brightness.dark,
  double textScale = 1,
  double keyboardHeight = 0,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildNaiHuishiTheme(brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        viewInsets: EdgeInsets.only(bottom: keyboardHeight),
      ),
      child: child!,
    ),
    home: AppUpdatePage(service: updater),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      160,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('app-update-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late _UpdaterFake updater;

  setUp(() => updater = _UpdaterFake());
  tearDown(() {
    if (!updater.disposed) updater.dispose();
  });

  testWidgets('manual checks and automatic preference dispatch to the service',
      (tester) async {
    await _pumpPage(tester, updater);
    expect(find.text('软件更新'), findsOneWidget);
    expect(updater.initializations, 0);
    expect(updater.checks, 0);

    await _tap(tester, 'app-update-check');
    expect(updater.checks, 1);
    await _tap(tester, 'app-update-auto-check');
    expect(updater.autoCheckEnabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('candidate details stay plain text and actions use the service',
      (tester) async {
    updater.manifest = _manifest;
    updater.phase = UpdatePhase.available;
    await _pumpPage(tester, updater);

    await _tap(tester, 'app-update-download');
    await _tap(tester, 'app-update-ignore');
    expect(updater.downloads, 1);
    expect(updater.ignores, 1);
    expect(find.text('1.0.0（10）'), findsOneWidget);
    expect(find.text('1.1.0（11）'), findsOneWidget);
    expect(find.text('2.0 MB'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('app-update-release-notes')),
    );
    final notes = tester.widget<SelectableText>(
      find.byKey(const ValueKey('app-update-release-notes')),
    );
    expect(notes.data, _manifest.releaseNotes);
    await _tap(tester, 'app-update-release');
    expect(updater.releaseOpens, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a late automatic event is acknowledged without a notification loop',
      (tester) async {
    await _pumpPage(tester, updater);
    expect(updater.acknowledgedVersions, isEmpty);
    updater.manifest = _manifest;
    updater.automaticPromptManifest = _manifest;
    updater.automaticPromptRevision = 1;
    updater.notifyWhenAcknowledged = true;
    updater.receive(UpdatePhase.available);
    await tester.pumpAndSettle();
    expect(updater.acknowledgedVersions, [11]);
    updater.notifyListeners();
    await tester.pumpAndSettle();
    expect(updater.acknowledgedVersions, [11]);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('download progress is determinate and cancellation is explicit',
      (tester) async {
    updater.manifest = _manifest;
    updater.phase = UpdatePhase.downloading;
    updater.progress(1024 * 1024, 2 * 1024 * 1024);
    await _pumpPage(tester, updater);
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('app-update-progress')),
    );
    expect(indicator.value, 0.5);
    expect(find.text('50% · 1.0 MB / 2.0 MB'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final notesBefore = tester.widget<SelectableText>(
      find.byKey(const ValueKey('app-update-release-notes')),
    );
    updater.progress(1572864, 2 * 1024 * 1024);
    await tester.pumpAndSettle();
    expect(find.text('75% · 1.5 MB / 2.0 MB'), findsOneWidget);
    expect(
      identical(
        notesBefore,
        tester.widget<SelectableText>(
          find.byKey(const ValueKey('app-update-release-notes')),
        ),
      ),
      isTrue,
    );
    await _tap(tester, 'app-update-cancel');
    expect(updater.cancellations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving and reopening keeps the application owned download',
      (tester) async {
    updater.manifest = _manifest;
    updater.phase = UpdatePhase.downloading;
    updater.progress(10, 100);
    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => AppUpdatePage(service: updater),
            )),
            child: const Text('打开更新'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(updater.disposed, isFalse);
    expect(updater.cancellations, 0);
    expect(updater.phase, UpdatePhase.downloading);

    updater.progress(75, 100);
    await tester.tap(find.text('打开更新'));
    await tester.pumpAndSettle();
    expect(find.text('75% · 75 B / 100 B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'fresh native models with new bytes only rebuild download progress',
      (tester) async {
    updater.manifest = _manifest;
    updater.phase = UpdatePhase.downloading;
    updater.progress(10, 100);
    await _pumpPage(tester, updater);
    final statusBefore = tester.widget<FrostedSurface>(
      find.byKey(const ValueKey('app-update-status')),
    );
    final detailsBefore = tester.widget<FrostedSurface>(
      find.byKey(const ValueKey('app-update-details')),
    );
    var progressBefore = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('app-update-progress')),
    );

    for (final received in [20, 35, 50]) {
      // Mirror getInstalledInfo/getDownloadState deserializing new objects.
      updater.installed = InstalledAppInfo(
        packageName: _installed.packageName,
        versionName: _installed.versionName,
        versionCode: _installed.versionCode,
        sdkInt: _installed.sdkInt,
        supportedAbis: List.of(_installed.supportedAbis),
        signerSha256: List.of(_installed.signerSha256),
      );
      updater.manifest = AppUpdateManifest(
        schemaVersion: _manifest.schemaVersion,
        channel: _manifest.channel,
        packageName: _manifest.packageName,
        versionName: _manifest.versionName,
        versionCode: _manifest.versionCode,
        publishedAt: DateTime.parse(_manifest.publishedAt.toIso8601String()),
        releaseNotes: _manifest.releaseNotes,
        releaseUrl: Uri.parse(_manifest.releaseUrl.toString()),
        apk: AppUpdateApk(
          url: Uri.parse(_manifest.apk.url.toString()),
          sizeBytes: _manifest.apk.sizeBytes,
          sha256: _manifest.apk.sha256,
          abi: _manifest.apk.abi,
          minSdk: _manifest.apk.minSdk,
        ),
      );
      updater.progress(received, 100);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FrostedSurface>(
          find.byKey(const ValueKey('app-update-status')),
        ),
        same(statusBefore),
      );
      expect(
        tester.widget<FrostedSurface>(
          find.byKey(const ValueKey('app-update-details')),
        ),
        same(detailsBefore),
      );
      final progressNow = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('app-update-progress')),
      );
      expect(progressNow, isNot(same(progressBefore)));
      expect(progressNow.value, received / 100);
      progressBefore = progressNow;
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('failures never appear as latest and provide retry and release',
      (tester) async {
    updater.phase = UpdatePhase.failed;
    updater.message = '检查更新失败，请稍后重试。';
    await _pumpPage(tester, updater);
    expect(find.text('已是最新版本'), findsNothing);
    expect(find.text(updater.message!), findsOneWidget);
    await _tap(tester, 'app-update-retry');
    await _tap(tester, 'app-update-release-fallback');
    expect(updater.checks, 1);
    expect(updater.releaseOpens, 1);
  });

  testWidgets('install permission and reconciliation require explicit actions',
      (tester) async {
    updater.manifest = _manifest;
    updater.phase = UpdatePhase.ready;
    await _pumpPage(tester, updater);
    expect(updater.installs, 0);
    await _tap(tester, 'app-update-install');
    expect(updater.installs, 1);

    updater.receive(UpdatePhase.permissionRequired);
    await tester.pumpAndSettle();
    expect(updater.installs, 1);
    await _tap(tester, 'app-update-permission');
    expect(updater.installs, 2);
    updater.receive(UpdatePhase.ready);
    await tester.pumpAndSettle();
    expect(updater.installs, 2);
    expect(find.byKey(const ValueKey('app-update-install')), findsOneWidget);

    updater.receive(UpdatePhase.awaitingInstall);
    await tester.pumpAndSettle();
    expect(updater.installs, 2);
    await _tap(tester, 'app-update-refresh');
    expect(updater.refreshes, 1);
  });

  testWidgets('busy installation keeps the candidate and displays the notice',
      (tester) async {
    updater.manifest = _manifest;
    updater.phase = UpdatePhase.ready;
    updater.message = '请先保存正在编辑的内容，再安装更新。';
    await _pumpPage(tester, updater);
    expect(find.text(updater.message!), findsOneWidget);
    expect(find.byKey(const ValueKey('app-update-install')), findsOneWidget);
    expect(find.text('1.1.0（11）'), findsOneWidget);
  });

  testWidgets('unsaved confirmation opens only after an explicit install tap',
      (tester) async {
    updater.manifest = _manifest;
    updater.phase = UpdatePhase.ready;
    updater.hasUnsavedWork = true;
    updater.requiresUnsavedConfirmation = true;
    updater.message = 'AI 助手有未发送的消息和附件；局部重绘工作区有未保存内容。';
    await _pumpPage(tester, updater);
    expect(find.text('安装前保存工作区'), findsNothing);

    await _tap(tester, 'app-update-install');
    expect(find.text('安装前保存工作区'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining(updater.message!),
      ),
      findsOneWidget,
    );
    expect(updater.installAllowDiscard, [false]);
    await _tap(tester, 'app-update-discard-confirm');
    expect(updater.installAllowDiscard, [false, true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported packages show a release fallback without install',
      (tester) async {
    updater.phase = UpdatePhase.unsupported;
    await _pumpPage(tester, updater);
    expect(find.text('暂不支持应用内更新'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-update-install')), findsNothing);
    expect(find.byKey(const ValueKey('app-update-recheck')), findsNothing);
    await _tap(tester, 'app-update-release-fallback');
    expect(updater.releaseOpens, 1);
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('app-update-auto-check')),
    );
    expect(toggle.onChanged, isNull);
  });

  testWidgets('an incompatible candidate still allows checking and preferences',
      (tester) async {
    updater.manifest = _manifest;
    updater.phase = UpdatePhase.unsupported;
    updater.checkCapability = false;
    await _pumpPage(tester, updater);
    expect(find.byKey(const ValueKey('app-update-recheck')), findsNothing);
    updater.checkCapability = true;
    updater.receive(UpdatePhase.unsupported);
    await tester.pumpAndSettle();
    expect(find.text('此更新不兼容当前设备'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-update-download')), findsNothing);
    await _tap(tester, 'app-update-recheck');
    expect(updater.checks, 1);
    await _tap(tester, 'app-update-auto-check');
    expect(updater.autoCheckEnabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'save first and later return without installing or clearing state',
      (tester) async {
    updater.manifest = _manifest;
    updater.phase = UpdatePhase.ready;
    updater.hasUnsavedWork = true;
    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => AppUpdatePage(service: updater),
            )),
            child: const Text('打开更新'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开更新'));
    await tester.pumpAndSettle();
    await _tap(tester, 'app-update-install');
    await _tap(tester, 'app-update-save-first');
    expect(find.text('打开更新'), findsOneWidget);
    expect(updater.installAllowDiscard, [false]);
    expect(updater.phase, UpdatePhase.ready);
    expect(updater.manifest, same(_manifest));

    await tester.tap(find.text('打开更新'));
    await tester.pumpAndSettle();
    expect(find.text('安装前保存工作区'), findsNothing);
    await _tap(tester, 'app-update-later');
    expect(find.text('打开更新'), findsOneWidget);
    expect(updater.installAllowDiscard, [false]);
    expect(updater.disposed, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('320dp with large text and keyboard is usable in $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      updater.manifest = _manifest;
      updater.phase = UpdatePhase.available;
      await _pumpPage(
        tester,
        updater,
        brightness: brightness,
        textScale: 2,
        keyboardHeight: 220,
      );
      await _tap(tester, 'app-update-download');
      expect(updater.downloads, 1);
      await _tap(tester, 'app-update-release');
      expect(updater.releaseOpens, 1);
      await _tap(tester, 'app-update-auto-check');
      expect(updater.autoCheckEnabled, isFalse);

      updater.hasUnsavedWork = true;
      updater.receive(UpdatePhase.ready);
      await tester.pumpAndSettle();
      tester
          .state<ScrollableState>(find
              .descendant(
                of: find.byKey(const ValueKey('app-update-scroll')),
                matching: find.byType(Scrollable),
              )
              .first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await _tap(tester, 'app-update-install');
      await _tap(tester, 'app-update-discard-confirm');
      expect(updater.installAllowDiscard, [false, true]);
      expect(tester.takeException(), isNull);
    });
  }
}
