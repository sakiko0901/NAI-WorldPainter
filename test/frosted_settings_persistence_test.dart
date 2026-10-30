import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/datasources/local/official_novelai_token_store.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/app.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/home_page.dart';
import 'package:nai_huishi/presentation/pages/settings_page.dart';
import 'package:nai_huishi/presentation/pages/theme_appearance_page.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/settings_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/frontend_generation_fake.dart';

void main() {
  late FrontendGenerationFake generation;
  late _SettingsFake settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await sl.reset();
    generation = FrontendGenerationFake();
    settings = _SettingsFake();
    sl.registerSingleton<GenerationViewModel>(generation);
    sl.registerSingleton<SettingsViewModel>(settings);
    sl.registerSingleton<OfficialNovelAiTokenStore>(_NoTokenStore());
  });

  tearDown(() async {
    await sl.reset();
    generation.dispose();
    settings.dispose();
  });

  testWidgets(
      'tools switch persists, survives theme changes and app recreation',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const NaiHuishiApp());
    await tester.pumpAndSettle();
    expect(_glass(tester).blurEnabled, isTrue);
    expect(_activeFilters(), findsWidgets);

    await _openAppearance(tester);
    await tester.tap(find.byKey(const ValueKey('frosted-glass-switch')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('frosted_glass_enabled'), isFalse);
    expect(_glass(tester).blurEnabled, isFalse);
    expect(_activeFilters(), findsNothing);

    await tester.tap(find.text('亮色'));
    await tester.pumpAndSettle();
    expect(prefs.getString('appearance_mode'), 'light');
    expect(_glass(tester).blurEnabled, isFalse);
    expect(_activeFilters(), findsNothing);

    await tester.tap(find.byIcon(CupertinoIcons.chevron_left));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创作').last);
    await tester.pumpAndSettle();
    expect(find.text('生成图片'), findsOneWidget);
    expect(_activeFilters(), findsNothing);

    // Recreate the application state; only the persisted setting survives.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const NaiHuishiApp());
    await tester.pumpAndSettle();
    expect(_glass(tester).blurEnabled, isFalse);
    expect(_activeFilters(), findsNothing);
    await _openAppearance(tester);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('frosted-glass-switch')),
          )
          .value,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('frosted-glass-switch')));
    await tester.pumpAndSettle();
    expect(prefs.getBool('frosted_glass_enabled'), isTrue);
    expect(_glass(tester).blurEnabled, isTrue);
    expect(_activeFilters(), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved disabled setting is restored on the creation page',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'frosted_glass_enabled': false,
      'appearance_mode': 'dark',
    });
    await tester.pumpWidget(const NaiHuishiApp());
    await tester.pumpAndSettle();
    expect(_glass(tester).blurEnabled, isFalse);
    expect(_activeFilters(), findsNothing);
    expect(find.text('生成图片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

FrostedTheme _glass(WidgetTester tester) =>
    FrostedTheme.of(tester.element(find.byType(HomePage, skipOffstage: false)));

Finder _activeFilters() => find.byWidgetPredicate(
      (widget) => widget is BackdropFilter && widget.enabled,
      skipOffstage: false,
    );

Future<void> _openAppearance(WidgetTester tester) async {
  await tester.tap(find.text('工具').last);
  await tester.pumpAndSettle();
  final entry = find.text('亮色、暗色与毛玻璃效果');
  await tester.scrollUntilVisible(
    entry,
    300,
    scrollable: find.descendant(
      of: find.byType(SettingsPage),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(entry);
  await tester.pumpAndSettle();
  expect(find.byType(ThemeAppearancePage), findsOneWidget);
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
