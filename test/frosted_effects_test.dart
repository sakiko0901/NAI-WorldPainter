import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/theme_appearance_page.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_sessions_panel.dart';
import 'package:nai_huishi/presentation/widgets/studio_background.dart';

import 'support/chat_memory_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('frosted theme setting', () {
    test('is enabled by default and can be disabled in both brightnesses', () {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final defaultTheme = _theme(brightness);
        final disabledTheme = _theme(brightness, enabled: false);

        expect(defaultTheme.brightness, brightness);
        expect(defaultTheme.extension<FrostedTheme>()!.blurEnabled, isTrue);
        expect(disabledTheme.brightness, brightness);
        expect(disabledTheme.extension<FrostedTheme>()!.blurEnabled, isFalse);
      }
    });

    test('copyWith and lerp carry the blur setting', () {
      final enabled = FrostedTheme.forBrightness(Brightness.dark);
      final disabled = enabled.copyWith(blurEnabled: false);

      expect(disabled.blurEnabled, isFalse);
      expect(disabled.copyWith().blurEnabled, isFalse);
      expect(enabled.copyWith().blurEnabled, isTrue);
      expect(enabled.lerp(disabled, 0.01).blurEnabled, isFalse);
      expect(disabled.lerp(enabled, 0.99).blurEnabled, isTrue);
    });
  });

  testWidgets('FrostedSurface responds to off/on theme changes',
      (tester) async {
    Widget surfaceApp(bool enabled) => _app(
          brightness: Brightness.dark,
          enabled: enabled,
          home: const Scaffold(
            body: Center(child: FrostedSurface(child: _CounterChild())),
          ),
        );

    await tester.pumpWidget(surfaceApp(true));
    var filters =
        tester.widgetList<BackdropFilter>(find.byType(BackdropFilter));
    expect(filters, hasLength(1));
    expect(filters.single.enabled, isTrue);
    await tester.tap(find.byKey(const ValueKey('counter-increment')));
    await tester.pump();
    expect(find.text('count: 1'), findsOneWidget);

    await tester.pumpWidget(surfaceApp(false));
    await tester.pumpAndSettle();
    filters = tester.widgetList<BackdropFilter>(find.byType(BackdropFilter));
    expect(filters, hasLength(1));
    expect(filters.single.enabled, isFalse);
    expect(find.text('count: 1'), findsOneWidget);

    await tester.pumpWidget(surfaceApp(true));
    await tester.pumpAndSettle();
    filters = tester.widgetList<BackdropFilter>(find.byType(BackdropFilter));
    expect(filters, hasLength(1));
    expect(filters.single.enabled, isTrue);
    expect(find.text('count: 1'), findsOneWidget);
  });

  testWidgets('zero blur and high contrast keep their no-filter behavior',
      (tester) async {
    await tester.pumpWidget(_app(
      brightness: Brightness.light,
      enabled: true,
      home: const Scaffold(
        body: Center(child: FrostedSurface(blur: 0, child: Text('zero blur'))),
      ),
    ));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('zero blur'), findsOneWidget);

    final highContrastTheme = _theme(Brightness.light);
    await tester.pumpWidget(MaterialApp(
      theme: highContrastTheme,
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(800, 800),
          highContrast: true,
        ),
        child: const Scaffold(
          body: Center(child: FrostedSurface(child: Text('high contrast'))),
        ),
      ),
    ));

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('high contrast'), findsOneWidget);
    final decoration = tester.widget<DecoratedBox>(
      find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox && widget.decoration is BoxDecoration,
      ),
    );
    expect(
      (decoration.decoration as BoxDecoration).color,
      highContrastTheme.colorScheme.surface,
    );
  });

  testWidgets('StudioBackground skips its image layer but keeps the gradient',
      (tester) async {
    final image = MemoryImage(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
    ));
    Widget backgroundApp(bool enabled) => _app(
          brightness: Brightness.dark,
          enabled: enabled,
          home: SizedBox.expand(child: StudioBackground(image: image)),
        );

    await tester.pumpWidget(backgroundApp(false));
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(Image), findsNothing);
    final gradientBox = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).gradient != null,
    );
    expect(gradientBox, findsOneWidget);

    await tester.pumpWidget(backgroundApp(true));
    await tester.pumpAndSettle();
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(backgroundApp(false));
    await tester.pumpAndSettle();
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(gradientBox, findsOneWidget);
  });

  testWidgets('appearance switch updates itself and calls back immediately',
      (tester) async {
    final changes = <bool>[];
    final switchFinder = find.byKey(const ValueKey('frosted-glass-switch'));

    await tester.pumpWidget(_app(
      brightness: Brightness.dark,
      enabled: true,
      home: ThemeAppearancePage(
        appearanceMode: AppearanceMode.dark,
        onAppearanceChanged: (_) {},
        frostedGlassEnabled: true,
        onFrostedGlassChanged: changes.add,
      ),
    ));

    await tester.ensureVisible(switchFinder);
    expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
    await tester.tap(switchFinder);
    await tester.pump();
    expect(changes, [false]);
    expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pump();
    expect(changes, [false, true]);
    expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);

    await tester.pumpWidget(_app(
      brightness: Brightness.dark,
      enabled: true,
      home: ThemeAppearancePage(
        appearanceMode: AppearanceMode.dark,
        onAppearanceChanged: (_) {},
        frostedGlassEnabled: true,
      ),
    ));
    expect(tester.widget<SwitchListTile>(switchFinder).onChanged, isNull);
  });

  testWidgets('chat sessions panel disables its filter with frosted glass off',
      (tester) async {
    final harness = createChatMemoryHarness();
    addTearDown(harness.dispose);

    Future<void> openPanel(bool enabled) async {
      await tester.pumpWidget(_app(
        brightness: Brightness.dark,
        enabled: enabled,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const ValueKey('open-chat-sessions'),
                onPressed: () => showChatSessionsPanel(
                  context,
                  vm: harness.viewModel,
                ),
                child: const Text('open chat sessions'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('open-chat-sessions')));
      await tester.pumpAndSettle();
    }

    await openPanel(true);
    var filters =
        tester.widgetList<BackdropFilter>(find.byType(BackdropFilter));
    expect(filters, hasLength(1));
    expect(filters.single.enabled, isTrue);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    await openPanel(false);
    filters = tester.widgetList<BackdropFilter>(find.byType(BackdropFilter));
    expect(filters, hasLength(1));
    expect(filters.single.enabled, isFalse);
  });
}

ThemeData _theme(Brightness brightness, {bool enabled = true}) =>
    buildNaiHuishiTheme(
      brightness,
      useGoogleFonts: false,
      frostedGlassEnabled: enabled,
    );

Widget _app({
  required Brightness brightness,
  required bool enabled,
  required Widget home,
}) =>
    MaterialApp(
      theme: _theme(brightness, enabled: enabled),
      home: home,
    );

class _CounterChild extends StatefulWidget {
  const _CounterChild();

  @override
  State<_CounterChild> createState() => _CounterChildState();
}

class _CounterChildState extends State<_CounterChild> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('count: $_count'),
          TextButton(
            key: const ValueKey('counter-increment'),
            onPressed: () => setState(() => _count++),
            child: const Text('increment'),
          ),
        ],
      );
}
