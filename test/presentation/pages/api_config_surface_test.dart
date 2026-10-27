import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/api_config_page.dart';
import 'package:nai_huishi/presentation/viewmodels/settings_viewmodel.dart';

void main() {
  late _SettingsFake settings;

  setUp(() async {
    await sl.reset();
    settings = _SettingsFake();
    sl.registerSingleton<SettingsViewModel>(settings);
  });

  tearDown(() async {
    await sl.reset();
    settings.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'relay card keeps its surface during interaction in $brightness',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final theme = buildNaiHuishiTheme(brightness);
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const ApiConfigPage(),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'GPT'));
      await tester.pumpAndSettle();

      final title = find.text(settings.endpoint.name);
      _expectCardSurface(tester, title, theme, active: false);
      expect(find.widgetWithText(ChoiceChip, 'model-b'), findsNothing);
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      _expectCardSurface(tester, title, theme, active: false);

      final model = find.widgetWithText(ChoiceChip, 'model-b');
      expect(tester.widget<ChoiceChip>(model).selected, isFalse);
      await tester.ensureVisible(model);
      await tester.tap(model);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(settings.selectedProvider, ImageProviderType.gpt);
      expect(settings.selectedEndpointId, settings.endpoint.id);
      expect(settings.selectedModel, 'model-b');
      expect(tester.widget<ChoiceChip>(model).selected, isTrue);
      _expectCardSurface(tester, title, theme, active: true);

      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(model, findsNothing);
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(model).selected, isTrue);
      _expectCardSurface(tester, title, theme, active: true);
      // Let the selection toast leave its overlay before the page is disposed.
      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

void _expectCardSurface(
  WidgetTester tester,
  Finder title,
  ThemeData theme, {
  required bool active,
}) {
  final card = find.ancestor(
    of: title,
    matching: find.byWidgetPredicate(
      (widget) => widget is Container && widget.decoration is BoxDecoration,
    ),
  );
  expect(card, findsOneWidget);
  final decoration =
      tester.widget<Container>(card).decoration! as BoxDecoration;
  expect(decoration.color, theme.cardTheme.color);
  expect(decoration.borderRadius, BorderRadius.circular(20));
  expect(
    decoration.border,
    Border.all(
      color: active
          ? theme.colorScheme.primary.withValues(alpha: .5)
          : theme.colorScheme.onSurface.withValues(alpha: .08),
    ),
  );
}

class _SettingsFake extends ChangeNotifier implements SettingsViewModel {
  final endpoint = const ApiEndpoint(
    id: 'gpt-relay',
    name: 'GPT relay',
    baseUrl: 'https://relay.example/v1',
    apiKey: 'test-key',
    models: ['model-a', 'model-b'],
  );
  ImageProviderType? selectedProvider;
  String? selectedEndpointId;
  String? selectedModel;

  @override
  Future<void> loadSettings() async {}

  @override
  List<ApiEndpoint> endpoints(ImageProviderType provider) =>
      provider == ImageProviderType.gpt ? [endpoint] : [];

  @override
  String? activeEndpointId(ImageProviderType provider) =>
      provider == selectedProvider ? selectedEndpointId : null;

  @override
  String? activeModel(ImageProviderType provider) =>
      provider == selectedProvider ? selectedModel : null;

  @override
  Future<void> setActive(
      ImageProviderType provider, String endpointId, String? model) async {
    selectedProvider = provider;
    selectedEndpointId = endpointId;
    selectedModel = model;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
