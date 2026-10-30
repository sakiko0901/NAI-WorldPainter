import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/datasources/local/official_novelai_token_store.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/generate_page.dart';
import 'package:nai_huishi/presentation/pages/home_page.dart';
import 'package:nai_huishi/presentation/pages/settings_page.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/settings_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_drawer.dart';
import 'package:nai_huishi/presentation/widgets/studio_navigation_bar.dart';

import 'support/chat_memory_fake.dart';
import 'support/frontend_generation_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FrontendGenerationFake generation;
  late ChatMemoryHarness chat;
  late _SettingsFake settings;
  setUp(() async {
    generation = FrontendGenerationFake();
    chat = createChatMemoryHarness();
    await chat.viewModel.ensureInitialized();
    settings = _SettingsFake();
    sl.registerSingleton<GenerationViewModel>(generation);
    sl.registerSingleton<LlmChatViewModel>(chat.viewModel);
    sl.registerSingleton<SettingsViewModel>(settings);
    sl.registerSingleton<OfficialNovelAiTokenStore>(_NoTokenStore());
  });
  tearDown(() async {
    await sl.reset();
    generation.dispose();
    settings.dispose();
    chat.dispose();
  });

  Widget host(
          {Brightness brightness = Brightness.dark,
          double scale = 1,
          Key? captureKey}) =>
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildNaiHuishiTheme(brightness),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: HomePage(
              appearanceMode: AppearanceMode.dark, onAppearanceChanged: (_) {}),
        ),
      );
  Finder nav(String name) => find.byKey(ValueKey('navigation-$name'));
  Finder scrollFor(Type type) => find
      .descendant(of: find.byType(type), matching: find.byType(Scrollable))
      .first;

  void viewport(WidgetTester tester, {double width = 393}) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 852);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
  }

  testWidgets(
      'all destinations retain drafts and scroll; rapid switching settles',
      (tester) async {
    viewport(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final createState = tester.state(find.byType(GeneratePage));
    final editor = find.byType(TextField).first;
    await tester.ensureVisible(editor);
    await tester.enterText(editor, 'my creation draft');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final createOffset =
        tester.state<ScrollableState>(scrollFor(GeneratePage)).position.pixels;
    final selection = find.byKey(const ValueKey('navigation-selection'));
    final startLeft = tester.getTopLeft(selection).dx;
    await tester.tap(nav('tools'));
    await tester.pump();
    expect(tester.getTopLeft(selection).dx, greaterThan(startLeft));
    final selectedLeft = tester.getTopLeft(selection).dx;
    expect(tester.getCenter(selection).dx,
        closeTo(tester.getCenter(nav('tools')).dx, .01));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getTopLeft(selection).dx, selectedLeft);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(selection).dx, selectedLeft);
    expect(tester.getCenter(selection).dx,
        closeTo(tester.getCenter(nav('tools')).dx, .01));
    await tester.drag(scrollFor(SettingsPage), const Offset(0, -240));
    await tester.pumpAndSettle();
    final toolsOffset =
        tester.state<ScrollableState>(scrollFor(SettingsPage)).position.pixels;
    await tester.tap(nav('assistant'));
    await tester.pumpAndSettle();
    final chatState = tester.state(find.byType(ChatDrawer));
    await tester.enterText(find.byType(TextField).last, 'my assistant draft');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(nav('create'));
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tap(nav('tools'));
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tap(nav('create'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(GeneratePage)), same(createState));
    expect(generation.prompt, 'my creation draft');
    expect(
        tester.state<ScrollableState>(scrollFor(GeneratePage)).position.pixels,
        createOffset);
    await tester.tap(nav('tools'));
    await tester.pumpAndSettle();
    expect(
        tester.state<ScrollableState>(scrollFor(SettingsPage)).position.pixels,
        toolsOffset);
    await tester.tap(nav('assistant'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(ChatDrawer)), same(chatState));
    expect(find.text('my assistant draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'bottom bar fits ${brightness.name}, large text and system insets',
        (tester) async {
      viewport(tester, width: 320);
      await tester.pumpWidget(host(brightness: brightness, scale: 2));
      await tester.pumpAndSettle();
      final barTop = tester.getTopLeft(find.byType(StudioNavigationBar)).dy;
      expect(
          tester
              .getBottomRight(find.byKey(const ValueKey('generation-summary')))
              .dy,
          lessThanOrEqualTo(barTop));
      for (final name in ['tools', 'assistant', 'create']) {
        await tester.tap(nav(name));
        await tester.pumpAndSettle();
        expect(nav(name).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.byType(StudioNavigationBar), findsNothing);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(nav('create').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('capture navigation on all three destinations', (tester) async {
    if (!const bool.fromEnvironment('NAVIGATION_CAPTURE')) return;
    await tester.runAsync(() async {
      final font = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
      for (final family in ['Microsoft YaHei', 'Roboto']) {
        await (FontLoader(family)
              ..addFont(Future.value(ByteData.sublistView(font))))
            .load();
      }
      final manifest =
          jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
      for (final family in manifest.cast<Map<String, dynamic>>()) {
        final loader = FontLoader(family['family'] as String);
        for (final item
            in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
          loader.addFont(rootBundle.load(item['asset'] as String));
        }
        await loader.load();
      }
    });
    viewport(tester);
    final key = GlobalKey();
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(host(brightness: brightness, captureKey: key));
      await tester.pumpAndSettle();
      for (final name in ['create', 'assistant', 'tools']) {
        await tester.tap(nav(name));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file =
              File('build/navigation-preview/$name-${brightness.name}.png');
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });
}

class _SettingsFake extends ChangeNotifier implements SettingsViewModel {
  @override
  List<ApiEndpoint> endpoints(ImageProviderType provider) => const [];
  @override
  Future<void> loadSettings() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoTokenStore extends OfficialNovelAiTokenStore {
  @override
  Future<String?> read() async => null;
}
