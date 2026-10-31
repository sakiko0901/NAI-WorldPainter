import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/services/app_update_install_guard.dart';
import 'package:nai_huishi/core/services/app_update_service.dart';
import 'package:nai_huishi/domain/entities/app_update.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/navigation/app_update_navigation_observer.dart';
import 'package:nai_huishi/presentation/pages/app_update_page.dart';
import 'package:nai_huishi/presentation/widgets/app_update_prompt_host.dart';

const _installed = InstalledAppInfo(
  packageName: AppUpdateManifest.packageId,
  versionName: '1.0.0',
  versionCode: 10,
  sdkInt: 35,
  supportedAbis: ['arm64-v8a'],
  signerSha256: ['test-only'],
);

AppUpdateManifest _release({int code = 11, String? notes}) => AppUpdateManifest(
      schemaVersion: 1,
      channel: 'stable',
      packageName: _installed.packageName,
      versionName: '1.1.0',
      versionCode: code,
      publishedAt: DateTime.utc(2026, 10, 31),
      releaseNotes: notes ?? '<script>plain text</script>\n改善使用体验。',
      releaseUrl: Uri.parse(
          'https://github.com/sakiko0901/NAI-WorldPainter/releases/tag/v1.1.0-$code'),
      apk: AppUpdateApk(
        url: Uri.parse(
            'https://github.com/sakiko0901/NAI-WorldPainter/releases/download/v1.1.0-$code/app-release.apk'),
        sizeBytes: 1024,
        sha256: 'a' * 64,
        abi: 'arm64-v8a',
        minSdk: 24,
      ),
    );

class _Service extends ChangeNotifier implements AppUpdateService {
  @override
  InstalledAppInfo? installed = _installed;
  @override
  AppUpdateManifest? manifest;
  @override
  AppUpdateManifest? automaticPromptManifest;
  @override
  int automaticPromptRevision = 0;
  @override
  UpdatePhase phase = UpdatePhase.idle;
  @override
  bool autoCheckEnabled = true;
  @override
  bool isBusy = false;
  bool updateAvailable = true;
  final acknowledgements = <int>[];
  final ignored = <int>[];
  int checks = 0;
  int downloads = 0;
  int installs = 0;

  @override
  bool get hasUpdate => updateAvailable && manifest != null;
  @override
  AppUpdateDownload? get download => null;
  @override
  String? get message => null;
  @override
  DateTime? get lastCheckedAt => null;
  @override
  bool get canCheckForUpdates => true;

  void offer([AppUpdateManifest? candidate]) {
    manifest = candidate ?? _release();
    automaticPromptManifest = manifest;
    automaticPromptRevision++;
    phase = UpdatePhase.available;
    notifyListeners();
  }

  void change() => notifyListeners();

  @override
  void acknowledgeAutomaticPrompt(int versionCode) {
    acknowledgements.add(versionCode);
    if (automaticPromptManifest?.versionCode == versionCode) {
      automaticPromptManifest = null;
      notifyListeners();
    }
  }

  @override
  Future<void> ignoreVersion() async {
    ignored.add(manifest!.versionCode);
    automaticPromptManifest = null;
    updateAvailable = false;
    phase = UpdatePhase.idle;
    notifyListeners();
  }

  @override
  Future<void> checkForUpdates({bool silent = false}) async => checks++;
  @override
  Future<void> startDownload() async => downloads++;
  @override
  Future<void> installUpdate({bool allowDiscardUnsaved = false}) async =>
      installs++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Guard extends ChangeNotifier implements AppUpdateInstallGuard {
  @override
  String? blockReason;
  @override
  String? unsavedWarning;
  @override
  bool isInstalling = false;

  void change() => notifyListeners();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Service service;
  late _Guard guard;
  late GlobalKey<NavigatorState> navigatorKey;
  late AppUpdateNavigationObserver observer;

  setUp(() {
    service = _Service();
    guard = _Guard();
    navigatorKey = GlobalKey<NavigatorState>();
    observer = AppUpdateNavigationObserver();
  });

  tearDown(() {
    observer.dispose();
    service.dispose();
    guard.dispose();
  });

  Future<void> host(
    WidgetTester tester, {
    Widget? home,
    Brightness brightness = Brightness.dark,
    double textScale = 1,
    double keyboard = 0,
  }) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [observer],
      theme: buildNaiHuishiTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: AppUpdatePromptHost(
          service: service,
          guard: guard,
          navigatorKey: navigatorKey,
          rootRouteCurrent: observer.rootRouteCurrent,
          child: child!,
        ),
      ),
      home: home ?? const Scaffold(body: Text('主页')),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> flush(WidgetTester tester) async {
    await tester.pump();
    await tester.pumpAndSettle();
  }

  final dialog = find.byKey(const ValueKey('automatic-update-dialog'));

  testWidgets('only a valid automatic event presents and consumes a prompt',
      (tester) async {
    await host(tester);
    service.offer();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await flush(tester);
    expect(dialog, findsOneWidget);
    expect(find.text('发现新版本'), findsOneWidget);
    expect(service.acknowledgements, [11]);
    expect(service.checks, 0);
    expect(service.downloads, 0);
    expect(service.installs, 0);
    await tester.tap(find.byKey(const ValueKey('automatic-update-later')));
    await flush(tester);
    expect(dialog, findsNothing);
  });

  testWidgets('manual available state does not trigger an automatic prompt',
      (tester) async {
    await host(tester);
    service.manifest = _release();
    service.phase = UpdatePhase.available;
    service.change();
    await flush(tester);
    expect(dialog, findsNothing);
    expect(service.acknowledgements, isEmpty);
  });

  for (final reason in [
    'unknown',
    'failed',
    'same-version',
    'ignored',
    'auto-off',
    'stale'
  ]) {
    testWidgets('$reason candidates cannot prompt', (tester) async {
      await host(tester);
      service.offer();
      switch (reason) {
        case 'unknown':
          service.installed = null;
        case 'failed':
          service.phase = UpdatePhase.failed;
        case 'same-version':
          service.manifest = _release(code: 10);
          service.automaticPromptManifest = service.manifest;
        case 'ignored':
          service.updateAvailable = false;
        case 'auto-off':
          service.autoCheckEnabled = false;
        case 'stale':
          service.manifest = _release(code: 12);
      }
      service.change();
      await flush(tester);
      expect(dialog, findsNothing);
      expect(service.acknowledgements, isEmpty);
    });
  }

  testWidgets('each version is shown once per host session', (tester) async {
    await host(tester);
    service.offer();
    await flush(tester);
    await tester.tap(find.byKey(const ValueKey('automatic-update-later')));
    await flush(tester);
    service.offer();
    await flush(tester);
    expect(dialog, findsNothing);
    service.offer(_release(code: 12));
    await flush(tester);
    expect(dialog, findsOneWidget);
    expect(service.acknowledgements, [11, 12]);
  });

  testWidgets('busy callback changes are retried only while pending',
      (tester) async {
    guard.blockReason = '任务进行中';
    await host(tester);
    service.offer();
    await flush(tester);
    expect(dialog, findsNothing);
    expect(service.acknowledgements, isEmpty);
    await tester.pump(const Duration(seconds: 4));
    expect(dialog, findsNothing);
    guard.blockReason =
        null; // Deliberately no notification, like real callbacks.
    await tester.pump(const Duration(seconds: 1));
    await flush(tester);
    expect(dialog, findsOneWidget);
  });

  testWidgets('dirty work waits and a guard event retries immediately',
      (tester) async {
    guard.unsavedWarning = '未发送的消息';
    await host(tester);
    service.offer();
    await flush(tester);
    expect(dialog, findsNothing);
    guard.unsavedWarning = null;
    guard.change();
    await flush(tester);
    expect(dialog, findsOneWidget);
  });

  testWidgets('another page must finish closing before the prompt',
      (tester) async {
    await host(tester);
    navigatorKey.currentState!.push<void>(MaterialPageRoute(
      builder: (_) => const Scaffold(body: Text('其他页面')),
    ));
    await flush(tester);
    service.offer();
    await flush(tester);
    expect(dialog, findsNothing);
    navigatorKey.currentState!.pop();
    await tester.pump();
    expect(dialog, findsNothing);
    await tester.pumpAndSettle();
    expect(dialog, findsOneWidget);
  });

  testWidgets('other modals are not interrupted', (tester) async {
    await host(tester);
    showDialog<void>(
      context: navigatorKey.currentState!.overlay!.context,
      builder: (_) => const AlertDialog(title: Text('其他对话框')),
    );
    await flush(tester);
    service.offer();
    await flush(tester);
    expect(dialog, findsNothing);
    navigatorKey.currentState!.pop();
    await flush(tester);
    expect(dialog, findsOneWidget);
  });

  testWidgets('local history such as a drawer also prevents interruption',
      (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    await host(tester,
        home: Scaffold(
          key: scaffoldKey,
          drawer: const Drawer(child: Text('抽屉')),
          body: const Text('主页'),
        ));
    scaffoldKey.currentState!.openDrawer();
    await flush(tester);
    expect(observer.rootRouteCurrent.value, isTrue);
    expect(navigatorKey.currentState!.canPop(), isTrue);
    service.offer();
    await flush(tester);
    expect(dialog, findsNothing);
    scaffoldKey.currentState!.closeDrawer();
    await flush(tester);
    await tester.pump(const Duration(seconds: 5));
    await flush(tester);
    expect(dialog, findsOneWidget);
  });

  testWidgets('editable focus delays the prompt until focus leaves',
      (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await host(tester, home: Scaffold(body: TextField(focusNode: node)));
    node.requestFocus();
    await flush(tester);
    service.offer();
    await flush(tester);
    expect(dialog, findsNothing);
    node.unfocus();
    await flush(tester);
    expect(dialog, findsOneWidget);
  });

  testWidgets('visible keyboard insets delay the prompt', (tester) async {
    await host(tester, keyboard: 200);
    service.offer();
    await flush(tester);
    expect(dialog, findsNothing);
    await host(tester, keyboard: 0);
    expect(dialog, findsOneWidget);
  });

  testWidgets('backgrounding cancels retries and resume re-evaluates',
      (tester) async {
    await host(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    service.offer();
    await tester.pump(const Duration(seconds: 6));
    expect(dialog, findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flush(tester);
    expect(dialog, findsOneWidget);
  });

  testWidgets('ignore dispatches only for the version currently shown',
      (tester) async {
    await host(tester);
    service.offer();
    await flush(tester);
    await tester.tap(find.byKey(const ValueKey('automatic-update-ignore')));
    await flush(tester);
    expect(service.ignored, [11]);
    expect(service.downloads, 0);
    expect(service.installs, 0);
  });

  testWidgets('ignore cannot accidentally ignore a newer candidate',
      (tester) async {
    await host(tester);
    service.offer();
    await flush(tester);
    service.manifest = _release(code: 12);
    service.change();
    await tester.tap(find.byKey(const ValueKey('automatic-update-ignore')));
    await flush(tester);
    expect(service.ignored, isEmpty);
  });

  testWidgets('view opens the existing update page without downloading',
      (tester) async {
    await host(tester);
    service.offer();
    await flush(tester);
    await tester.tap(find.byKey(const ValueKey('automatic-update-view')));
    await flush(tester);
    expect(find.byType(AppUpdatePage), findsOneWidget);
    expect(service.downloads, 0);
    expect(service.installs, 0);
  });

  testWidgets('manual update-page entry consumes a deferred prompt',
      (tester) async {
    guard.blockReason = '任务进行中';
    await host(tester);
    service.offer();
    await flush(tester);
    navigatorKey.currentState!.push<void>(MaterialPageRoute(
      builder: (_) => AppUpdatePage(service: service),
    ));
    await flush(tester);
    expect(service.acknowledgements, [11]);
    navigatorKey.currentState!.pop();
    guard.blockReason = null;
    await flush(tester);
    await tester.pump(const Duration(seconds: 5));
    await flush(tester);
    expect(dialog, findsNothing);
  });

  testWidgets('invalidated candidates stop pending retries', (tester) async {
    guard.blockReason = '任务进行中';
    await host(tester);
    service.offer();
    await flush(tester);
    service.automaticPromptManifest = null;
    service.change();
    guard.blockReason = null;
    await tester.pump(const Duration(seconds: 10));
    await flush(tester);
    expect(dialog, findsNothing);
    expect(service.acknowledgements, isEmpty);
  });

  testWidgets('manual page consumes an automatic result arriving after entry',
      (tester) async {
    await host(tester);
    navigatorKey.currentState!.push<void>(MaterialPageRoute(
      builder: (_) => AppUpdatePage(service: service),
    ));
    await flush(tester);
    expect(service.manifest, isNull);
    expect(service.acknowledgements, isEmpty);

    service.offer();
    await flush(tester);
    expect(find.text('1.1.0（11）'), findsOneWidget);
    expect(service.acknowledgements, [11]);
    expect(service.automaticPromptManifest, isNull);
    expect(dialog, findsNothing);

    navigatorKey.currentState!.pop();
    await flush(tester);
    expect(dialog, findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 6));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    service.change();
    await flush(tester);
    expect(service.manifest!.versionCode, 11);
    expect(dialog, findsNothing);
    expect(service.acknowledgements, [11]);
  });

  testWidgets(
      'covered manual page waits until visible before consuming a result',
      (tester) async {
    await host(tester);
    navigatorKey.currentState!.push<void>(MaterialPageRoute(
      builder: (_) => AppUpdatePage(service: service),
    ));
    await flush(tester);
    showDialog<void>(
      context: navigatorKey.currentState!.overlay!.context,
      builder: (_) => const AlertDialog(title: Text('其他对话框')),
    );
    await flush(tester);
    service.offer();
    await flush(tester);
    expect(service.acknowledgements, isEmpty);
    expect(service.automaticPromptManifest, isNotNull);

    navigatorKey.currentState!.pop();
    await flush(tester);
    expect(service.acknowledgements, [11]);
    expect(service.automaticPromptManifest, isNull);
    navigatorKey.currentState!.pop();
    await flush(tester);
    expect(dialog, findsNothing);
  });

  testWidgets('disposing the host cancels a pending retry', (tester) async {
    guard.blockReason = '任务进行中';
    await host(tester);
    service.offer();
    await flush(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    guard.blockReason = null;
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('plain text preview fits 320dp and large text in $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await host(tester, brightness: brightness, textScale: 2);
      service.offer(
          _release(notes: '<script>plain text</script>\n${'说明🙂' * 600}'));
      await flush(tester);
      final notes = tester
          .widget<Text>(find.byKey(const ValueKey('automatic-update-notes')));
      expect(notes.data!.startsWith('<script>plain text</script>'), isTrue);
      expect(notes.data!.runes.length, 1200);
      expect(find.byType(SingleChildScrollView), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('automatic-update-later')));
      await flush(tester);
      expect(dialog, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
