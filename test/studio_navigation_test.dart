import 'package:nai_huishi/presentation/widgets/studio_animated_icon.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/presentation/navigation/app_destination.dart';
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

  testWidgets('idle bubble fades and tapping the current tab restores it',
      (tester) async {
    viewport(tester);
    await tester.pumpWidget(host());
    final fade = find
        .ancestor(
            of: find.byKey(const ValueKey('navigation-selection')),
            matching: find.byType(AnimatedOpacity))
        .first;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(fade).opacity, 0);
    await tester.tap(nav('create'));
    await tester.pump();
    expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(fade).opacity, 0);
  });

  testWidgets('selecting each navigation icon runs its internal motion',
      (tester) async {
    viewport(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    for (final name in ['assistant', 'tools', 'create']) {
      await tester.tap(nav(name));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      final paint = tester.widget<CustomPaint>(find.descendant(
          of: nav(name),
          matching: find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is StudioIconPainter)));
      final clock = (paint.painter! as StudioIconPainter).clock;
      expect(clock.value, inExclusiveRange(0, .59));
      await tester.pumpAndSettle();
      expect(clock.value, 1);
    }
  });

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
    final startWidth = tester.getSize(selection).width;
    await tester.tap(nav('tools'));
    await tester.pump();
    expect(tester.getTopLeft(selection).dx, closeTo(startLeft, .01));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getTopLeft(selection).dx, greaterThan(startLeft));
    expect(tester.getSize(selection).width, greaterThan(startWidth));
    expect(tester.getCenter(selection).dx,
        lessThan(tester.getCenter(nav('tools')).dx));
    await tester.pumpAndSettle();
    expect(tester.getSize(selection).width, closeTo(startWidth, .01));
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

  testWidgets(
      'assistant composer stays anchored as keyboard crosses navigation',
      (tester) async {
    viewport(tester);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(host(scale: 1.5));
    await tester.tap(nav('assistant'));
    await tester.pumpAndSettle();
    final surface = find.byKey(const ValueKey('chat-composer-surface'));
    final restingBottom = tester.getRect(surface).bottom;
    final navHeight = tester.getSize(find.byType(StudioNavigationBar)).height;
    await tester.tap(find.byKey(const ValueKey('chat-composer-input')));
    for (final inset in [8.0, 48.0, 100.0, 300.0, 100.0, 48.0, 8.0, 0.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      tester.view.padding =
          FakeViewPadding(top: 24, bottom: (24 - inset).clamp(0, 24));
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.getRect(surface).bottom,
          closeTo(restingBottom - (inset - navHeight).clamp(0, 300), .01),
          reason: 'keyboard inset $inset');
    }
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

  testWidgets('navigation retargets continuously and respects reduced motion',
      (tester) async {
    viewport(tester);
    var destination = AppDestination.create;
    var reduceMotion = false;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(
            bottomNavigationBar: StudioNavigationBar(
              selected: destination,
              onSelected: (next) => setState(() => destination = next),
            ),
          ),
        );
      }),
    ));
    final selection = find.byKey(const ValueKey('navigation-selection'));
    final initialWidth = tester.getSize(selection).width;
    await tester.tap(nav('tools'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final moving = tester.getRect(selection);
    await tester.tap(nav('create'));
    await tester.pump();
    expect(tester.getRect(selection), moving);
    await tester.pumpAndSettle();
    expect(tester.getCenter(selection).dx,
        closeTo(tester.getCenter(nav('create')).dx, .01));
    expect(tester.getSize(selection).width, closeTo(initialWidth, .01));
    update(() => reduceMotion = true);
    await tester.pumpAndSettle();
    await tester.tap(nav('assistant'));
    await tester.pump();
    expect(tester.getCenter(selection).dx,
        closeTo(tester.getCenter(nav('assistant')).dx, .01));
    expect(tester.getSize(selection).width, closeTo(initialWidth, .01));
    expect(tester.takeException(), isNull);
  });

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
    Future<void> captureFrame(String name) async {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/navigation-preview/$name.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final brightness in Brightness.values) {
      await tester.pumpWidget(host(brightness: brightness, captureKey: key));
      await tester.pumpAndSettle();
      for (final name in ['assistant', 'tools', 'create']) {
        await tester.tap(nav(name));
        await tester.pump();
        for (var frame = 0; frame <= 44; frame++) {
          if (frame > 0) await tester.pump(const Duration(milliseconds: 20));
          await captureFrame(
              '$name-${brightness.name}-entrance-${frame.toString().padLeft(2, '0')}');
        }
        await captureFrame('$name-${brightness.name}-moving');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await captureFrame('$name-${brightness.name}');
      }
    }
  });

  testWidgets('assistant keeps the tools ambient background through its footer',
      (tester) async {
    viewport(tester);
    final key = GlobalKey();
    await tester.pumpWidget(host(captureKey: key));
    await tester.pumpAndSettle();
    Future<ByteData> capturePixels(String destination) async {
      await tester.tap(nav(destination));
      await tester.pumpAndSettle();
      return (await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final pixels =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return pixels;
      }))!;
    }

    final tools = await capturePixels('tools');
    final assistant = await capturePixels('assistant');
    // Compare the actual destinations where neither has foreground controls.
    // Covers the page and both sides of the composer's background reveal.
    for (final y in [180, 320, 500, 680, 720, 750]) {
      for (final x in [2, 390]) {
        for (var channel = 0; channel < 3; channel++) {
          final offset = (y * 393 + x) * 4 + channel;
          expect(assistant.getUint8(offset), closeTo(tools.getUint8(offset), 1),
              reason: 'same ambient colour at ($x, $y), channel $channel');
        }
      }
    }
    expect(tester.takeException(), isNull);
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
