import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/services/app_update_install_guard.dart';
import 'package:nai_huishi/core/services/app_update_service.dart';
import 'package:nai_huishi/data/datasources/app_update_platform.dart';
import 'package:nai_huishi/data/datasources/remote/app_update_source.dart';
import 'package:nai_huishi/domain/entities/app_update.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/navigation/app_update_navigation_observer.dart';
import 'package:nai_huishi/presentation/pages/app_update_page.dart';
import 'package:nai_huishi/presentation/widgets/app_update_prompt_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _installed = InstalledAppInfo(
  packageName: AppUpdateManifest.packageId,
  versionName: '1.0.0',
  versionCode: 10,
  sdkInt: 35,
  supportedAbis: ['arm64-v8a'],
  signerSha256: ['test-signing-certificate'],
);

AppUpdateManifest _release(int code) => AppUpdateManifest(
      schemaVersion: 1,
      channel: 'stable',
      packageName: AppUpdateManifest.packageId,
      versionName: '1.0.0',
      versionCode: code,
      publishedAt: DateTime.utc(2026, 10, 31),
      releaseNotes: '改善使用体验。',
      releaseUrl: Uri.parse(
          'https://github.com/sakiko0901/NAI-WorldPainter/releases/tag/v1.0.0-$code'),
      apk: AppUpdateApk(
        url: Uri.parse(
            'https://github.com/sakiko0901/NAI-WorldPainter/releases/download/v1.0.0-$code/app-release.apk'),
        sizeBytes: 1024,
        sha256: 'a' * 64,
        abi: 'arm64-v8a',
        minSdk: 24,
      ),
    );

class _Source extends AppUpdateSource {
  final requests = <Completer<AppUpdateManifest>>[];

  @override
  Future<AppUpdateManifest> fetchLatest() {
    final request = Completer<AppUpdateManifest>();
    requests.add(request);
    return request.future;
  }
}

class _Platform extends AppUpdatePlatform {
  AppUpdateDownload state =
      const AppUpdateDownload(status: AppUpdateDownloadStatus.none);

  @override
  bool get isSupported => true;

  @override
  Future<InstalledAppInfo> getInstalledInfo() async => _installed;

  @override
  Future<AppUpdateDownload> getDownloadState() async => state;
}

void main() {
  late _Source source;
  late _Platform platform;
  late AppUpdateInstallGuard guard;
  late AppUpdateService service;
  late GlobalKey<NavigatorState> navigatorKey;
  late AppUpdateNavigationObserver observer;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    source = _Source();
    platform = _Platform();
    guard = AppUpdateInstallGuard();
    now = DateTime.utc(2026, 11, 1, 9);
    service = AppUpdateService(
      source: source,
      platform: platform,
      preferences: await SharedPreferences.getInstance(),
      installGuard: guard,
      now: () => now,
    );
    navigatorKey = GlobalKey<NavigatorState>();
    observer = AppUpdateNavigationObserver();
  });

  tearDown(() {
    observer.dispose();
    service.dispose();
    guard.dispose();
  });

  Future<void> host(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [observer],
      theme: buildNaiHuishiTheme(Brightness.dark),
      builder: (context, child) => AppUpdatePromptHost(
        service: service,
        guard: guard,
        navigatorKey: navigatorKey,
        rootRouteCurrent: observer.rootRouteCurrent,
        child: child!,
      ),
      home: const Scaffold(body: Text('主页')),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openPage(WidgetTester tester) async {
    unawaited(navigatorKey.currentState!.push<void>(MaterialPageRoute(
      builder: (_) => AppUpdatePage(service: service),
    )));
    await tester.pumpAndSettle();
  }

  final currentNotice = find.byKey(const ValueKey('automatic-update-current'));
  final automaticDialog = find.byKey(const ValueKey('automatic-update-dialog'));
  final manualFeedback =
      find.byKey(const ValueKey('app-update-check-feedback'));

  testWidgets('a real completed startup equality stays silent', (tester) async {
    await host(tester);
    final startup = service.initialize();
    await tester.pumpAndSettle();
    expect(source.requests, hasLength(1));
    expect(service.isChecking, isTrue);
    expect(currentNotice, findsNothing);

    now = now.add(const Duration(seconds: 5));
    source.requests.single.complete(_release(10));
    await tester.pumpAndSettle();
    await startup;

    expect(service.isChecking, isFalse);
    expect(service.isLastCheckResultStale, isFalse);
    expect(service.lastCheckResult!.origin, AppUpdateCheckOrigin.startup);
    expect(service.lastCheckResult!.completedAt, now);
    expect(currentNotice, findsNothing);
    expect(automaticDialog, findsNothing);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await service.refresh();
    await tester.pumpAndSettle();
    expect(source.requests, hasLength(1));
    expect(currentNotice, findsNothing);
    expect(manualFeedback, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'startup equality is dropped instead of waiting behind a snack bar',
      (tester) async {
    await host(tester);
    ScaffoldMessenger.of(navigatorKey.currentState!.overlay!.context)
        .showSnackBar(const SnackBar(
      content: Text('已有操作反馈'),
      duration: Duration(seconds: 10),
    ));
    await tester.pumpAndSettle();
    final startup = service.initialize();
    await tester.pumpAndSettle();
    source.requests.single.complete(_release(10));
    await tester.pumpAndSettle();
    await startup;
    expect(find.text('已有操作反馈'), findsOneWidget);
    expect(currentNotice, findsNothing);

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(currentNotice, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a silent failed recheck exposes failure without replaying success',
      (tester) async {
    await host(tester);
    final startup = service.initialize();
    await tester.pumpAndSettle();
    source.requests.single.complete(_release(10));
    await tester.pumpAndSettle();
    await startup;
    final successfulAt = service.lastSuccessfulCheckAt;
    expect(currentNotice, findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await openPage(tester);

    now = now.add(const Duration(days: 1));
    final recheck = service.checkForUpdates(silent: true);
    await tester.pumpAndSettle();
    expect(source.requests, hasLength(2));
    source.requests.last.completeError(const AppUpdateException(
      '无法连接更新服务，请检查网络后重试。',
      reason: AppUpdateExceptionReason.connection,
    ));
    await tester.pumpAndSettle();
    await recheck;

    expect(service.lastCheckResult!.outcome, AppUpdateCheckOutcome.failed);
    expect(service.lastCheckResult!.origin, AppUpdateCheckOrigin.resume);
    expect(service.lastSuccessfulCheckAt, successfulAt);
    expect(service.lastCheckedAt, now);
    expect(service.isChecking, isFalse);
    expect(service.isLastCheckResultStale, isFalse);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('app-update-status-title')))
            .data,
        '检查失败');
    expect(find.byKey(const ValueKey('app-update-previous-result')),
        findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('（检查失败）'),
      160,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('app-update-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('（检查失败）'), findsOneWidget);
    expect(currentNotice, findsNothing);
    expect(manualFeedback, findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a restored failure without an artifact retries a real check',
      (tester) async {
    platform.state = const AppUpdateDownload(
      status: AppUpdateDownloadStatus.failed,
      reason: '更新任务记录已损坏，请重新下载。',
    );
    await service.setAutoCheckEnabled(false);
    await service.initialize();
    await host(tester);
    await openPage(tester);
    expect(service.manifest, isNull);
    expect(source.requests, isEmpty);

    await tester.tap(find.byKey(const ValueKey('app-update-retry')));
    await tester.pumpAndSettle();
    expect(source.requests, hasLength(1));
    source.requests.single.complete(_release(11));
    await tester.pumpAndSettle();
    expect(service.lastCheckResult!.origin, AppUpdateCheckOrigin.manual);
    expect(service.phase, UpdatePhase.available);
    expect(find.byKey(const ValueKey('app-update-download')), findsOneWidget);
    expect(manualFeedback, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a manual page check shared by startup produces only manual feedback',
      (tester) async {
    await host(tester);
    await openPage(tester);
    await tester.tap(find.byKey(const ValueKey('app-update-check')));
    await tester.pumpAndSettle();
    expect(source.requests, hasLength(1));
    expect(service.isChecking, isTrue);
    final startup = service.initialize();
    await tester.pumpAndSettle();
    expect(source.requests, hasLength(1));

    source.requests.single.complete(_release(10));
    await tester.pumpAndSettle();
    await startup;
    expect(service.lastCheckResult!.origin, AppUpdateCheckOrigin.manual);
    expect(service.isChecking, isFalse);
    expect(manualFeedback, findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(currentNotice, findsNothing);
    expect(automaticDialog, findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await service.refresh();
    await tester.pumpAndSettle();
    expect(source.requests, hasLength(1));
    expect(find.byType(SnackBar), findsNothing);
    expect(automaticDialog, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'manual intent suppresses a startup result before the real recheck',
      (tester) async {
    await host(tester);
    final startup = service.initialize();
    await tester.pumpAndSettle();
    final manual = service.checkForUpdates();
    await tester.pumpAndSettle();
    expect(source.requests, hasLength(1));

    source.requests.first.complete(_release(10));
    await tester.pumpAndSettle();
    await startup;
    expect(source.requests, hasLength(2));
    expect(service.isChecking, isTrue);
    expect(currentNotice, findsNothing);
    expect(automaticDialog, findsNothing);

    source.requests.last.complete(_release(11));
    await tester.pumpAndSettle();
    await manual;
    expect(service.lastCheckResult!.origin, AppUpdateCheckOrigin.manual);
    expect(service.hasUpdate, isTrue);
    expect(service.automaticPromptManifest, isNull);
    await openPage(tester);
    expect(currentNotice, findsNothing);
    expect(automaticDialog, findsNothing);
    expect(manualFeedback, findsNothing);
    expect(find.text('发现新版本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
