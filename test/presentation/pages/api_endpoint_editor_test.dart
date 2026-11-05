import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/viewmodels/settings_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/api_endpoint_editor.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';

const _endpoint = ApiEndpoint(
  id: 'relay',
  name: 'My relay',
  baseUrl: 'https://relay.example/v1',
  apiKey: 'original-key',
  models: ['model-a', 'model-b'],
  protocol: 'imageGenerations',
  streamEnabled: false,
);

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

  Future<void> openEditor(
    WidgetTester tester, {
    ApiEndpoint? endpoint = _endpoint,
    Brightness brightness = Brightness.dark,
    bool blur = true,
    double keyboardHeight = 0,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(brightness, frostedGlassEnabled: blur),
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => ApiEndpointEditor(
                        provider: ImageProviderType.gpt,
                        endpoint: endpoint,
                      ),
                    ),
                    child: const Text('Open'),
                  ))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> enterModel(WidgetTester tester, int index, String text) async {
    final field = find.byKey(ValueKey('endpoint-model-$index'));
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets('edits, removes and adds model rows in $brightness',
        (tester) async {
      await openEditor(tester, brightness: brightness);
      expect(find.byType(FrostedSurface), findsOneWidget);
      await enterModel(
          tester, 0, '  renamed-model-with-a-long-provider-specific-name  ');
      final delete = find.byTooltip('删除模型 2');
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      final add = find.byKey(const ValueKey('endpoint-add-model'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await enterModel(tester, 1, ' new-model ');
      // Saving commits the text in the new row without a separate add action.
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(settings.saved!.models,
          ['renamed-model-with-a-long-provider-specific-name', 'new-model']);
      expect(settings.saved!.id, _endpoint.id);
      expect(settings.saved!.protocol, _endpoint.protocol);
      expect(settings.saved!.streamEnabled, isFalse);
      expect(settings.saved!.apiKey, 'original-key');
      expect(settings.added, isFalse);
      expect(find.byType(ApiEndpointEditor), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('duplicate model names block save and can be corrected',
      (tester) async {
    await openEditor(tester);
    await enterModel(tester, 1, ' model-a ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('模型名称重复'), findsNWidgets(2));
    expect(settings.saved, isNull);
    await enterModel(tester, 1, 'model-c');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(settings.saved!.models, ['model-a', 'model-c']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling model edits leaves the endpoint unchanged',
      (tester) async {
    await openEditor(tester);
    await enterModel(tester, 0, 'discard-me');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(settings.saved, isNull);
    expect(_endpoint.models, ['model-a', 'model-b']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new endpoint validates fields and skips empty model rows',
      (tester) async {
    await openEditor(tester, endpoint: null);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入渠道名称'), findsOneWidget);
    expect(find.text('请输入 Base URL'), findsOneWidget);
    expect(settings.saved, isNull);
    final name = find.byKey(const ValueKey('endpoint-name'));
    await tester.ensureVisible(name);
    await tester.enterText(name, ' New relay ');
    final url = find.byKey(const ValueKey('endpoint-url'));
    await tester.ensureVisible(url);
    await tester.enterText(url, 'https://relay.example');
    await enterModel(tester, 0, '  model-a ');
    final add = find.byKey(const ValueKey('endpoint-add-model'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(settings.added, isTrue);
    expect(settings.saved!.name, 'New relay');
    expect(settings.saved!.models, ['model-a']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard leaves save reachable with blur disabled',
      (tester) async {
    await openEditor(tester, keyboardHeight: 280, blur: false);
    await enterModel(tester, 1, 'keyboard-model');
    expect(tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
        isFalse);
    expect(tester.getBottomRight(find.text('保存')).dy, lessThan(440));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(settings.saved!.models, ['model-a', 'keyboard-model']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed save preserves the draft and allows retry',
      (tester) async {
    settings.fail = true;
    await openEditor(tester);
    await enterModel(tester, 1, 'retry-model');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(find.byType(ApiEndpointEditor), findsOneWidget);
    settings.fail = false;
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(settings.saved!.models, ['model-a', 'retry-model']);
    expect(tester.takeException(), isNull);
  });
}

class _SettingsFake extends ChangeNotifier implements SettingsViewModel {
  ApiEndpoint? saved;
  bool added = false;
  bool fail = false;

  @override
  Future<void> addEndpoint(
      ImageProviderType provider, ApiEndpoint endpoint) async {
    if (fail) throw StateError('Save failed');
    saved = endpoint;
    added = true;
  }

  @override
  Future<void> updateEndpoint(
      ImageProviderType provider, ApiEndpoint endpoint) async {
    if (fail) throw StateError('Save failed');
    saved = endpoint;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
