import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/studio_alert_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  test('appearance mode parses and maps brightness', () {
    expect(AppearanceMode.parse('light'), AppearanceMode.light);
    expect(AppearanceMode.parse('dark'), AppearanceMode.dark);
    expect(AppearanceMode.parse('coffeePaper'), AppearanceMode.coffeePaper);
    expect(AppearanceMode.parse('unknown'), AppearanceMode.dark);
    expect(AppearanceMode.light.brightness, Brightness.light);
    expect(AppearanceMode.dark.brightness, Brightness.dark);
    expect(AppearanceMode.coffeePaper.brightness, Brightness.light);
  });

  test('dark theme uses neutral grays for surfaces and selection', () {
    final theme = buildNaiHuishiTheme(Brightness.dark, useGoogleFonts: false);

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF1A1A1A));
    expect(theme.colorScheme.primary, const Color(0xFFE3E3E3));
    final colors = theme.colorScheme;
    final glass = theme.extension<FrostedTheme>()!;
    expect(glass.selection, colors.primary);
    expect(glass.panel, colors.surface);
    expect(theme.cupertinoOverrideTheme?.primaryColor, colors.primary);
    expect(theme.dialogTheme.backgroundColor, colors.surfaceContainerHigh);
    expect(theme.popupMenuTheme.color, colors.surfaceContainerHigh);
    for (final (foreground, background) in [
      (colors.onSurface, colors.surface),
      (colors.onSurfaceVariant, colors.surfaceContainerHighest),
      (colors.onPrimary, colors.primary),
      (colors.onPrimaryContainer, colors.primaryContainer),
      (glass.onSelection, glass.selection),
    ]) {
      final first = foreground.computeLuminance() + 0.05;
      final second = background.computeLuminance() + 0.05;
      expect(
          first > second ? first / second : second / first, greaterThan(4.5));
    }
    expect(theme.navigationBarTheme.height, 52);
  });

  test('light theme uses silver white and muted secondary colors', () {
    final theme = buildNaiHuishiTheme(Brightness.light, useGoogleFonts: false);

    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFEDF0F4));
    expect(theme.colorScheme.primary, const Color(0xFF7488A3));
    expect(theme.colorScheme.secondary, const Color(0xFF8F839A));
    expect(theme.colorScheme.tertiary, const Color(0xFF718F81));
    expect(theme.colorScheme.error, const Color(0xFFFF6B6B));
  });

  test('coffee paper has its own surfaces and readable color pairs', () {
    final theme = buildNaiHuishiAppearanceTheme(AppearanceMode.coffeePaper);
    final colors = theme.colorScheme;
    final glass = theme.extension<FrostedTheme>()!;
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFFAF9F5));
    expect(colors.surface, const Color(0xFFFFFFFF));
    expect(colors.onSurface, const Color(0xFF141413));
    expect(colors.primary, const Color(0xFFBA5432));
    expect(glass.appearanceMode, AppearanceMode.coffeePaper);
    expect(glass.panel, colors.surface);
    expect(glass.selection, colors.primaryContainer);
    expect(theme.inputDecorationTheme.fillColor, glass.field);
    expect(theme.canvasColor, colors.surfaceContainerLowest);
    expect(theme.cupertinoOverrideTheme?.primaryColor, colors.primary);
    expect(theme.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
        Brightness.dark);

    for (final (foreground, background) in [
      (colors.onSurface, colors.surface),
      (colors.onSurfaceVariant, glass.field),
      (colors.primary, theme.scaffoldBackgroundColor),
      (colors.onPrimary, colors.primary),
      (glass.onSelection, glass.selection),
      (colors.error, colors.surfaceContainerLowest),
      (colors.onInverseSurface, colors.inverseSurface),
    ]) {
      final foregroundLuminance = foreground.computeLuminance();
      final backgroundLuminance = background.computeLuminance();
      final ratio = (foregroundLuminance + 0.05) / (backgroundLuminance + 0.05);
      expect(ratio >= 1 ? ratio : 1 / ratio, greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('coffee paper is applied to alerts, sheets and popup menus',
      (tester) async {
    final theme = buildNaiHuishiAppearanceTheme(AppearanceMode.coffeePaper);
    bool? confirmed;
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () async {
                  confirmed = await showStudioAlertDialog<bool>(
                    context: context,
                    builder: (ctx) => StudioAlertDialog(
                      title: const Text('确认删除'),
                      content: const Text('删除选中的记录？'),
                      actions: [
                        CupertinoDialogAction(
                          isDestructiveAction: true,
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('打开对话框'),
              ),
              TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const SizedBox(
                    height: 120,
                    child: Center(child: Text('底部面板')),
                  ),
                ),
                child: const Text('打开面板'),
              ),
              PopupMenuButton<String>(
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'item', child: Text('菜单选项')),
                ],
              ),
            ],
          ),
        ),
      ),
    ));

    final paperSurface = find.byWidgetPredicate((widget) =>
        widget is Material &&
        widget.color == theme.colorScheme.surfaceContainerLowest);
    final barrierColor = theme.colorScheme.scrim.withValues(alpha: 0.30);
    await tester.tap(find.text('打开对话框'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.ancestor(of: find.text('确认删除'), matching: paperSurface),
        findsOneWidget);
    expect(ModalRoute.of(tester.element(find.text('确认删除')))!.barrierColor,
        barrierColor);
    final destructive =
        tester.widget<TextButton>(find.widgetWithText(TextButton, '删除'));
    expect(destructive.style?.foregroundColor?.resolve({}),
        theme.colorScheme.error);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);

    await tester.tap(find.text('打开面板'));
    await tester.pumpAndSettle();
    expect(find.ancestor(of: find.text('底部面板'), matching: paperSurface),
        findsOneWidget);
    expect(ModalRoute.of(tester.element(find.text('底部面板')))!.barrierColor,
        barrierColor);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.ancestor(of: find.text('菜单选项'), matching: paperSurface),
        findsOneWidget);
    await tester.tap(find.text('菜单选项'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
