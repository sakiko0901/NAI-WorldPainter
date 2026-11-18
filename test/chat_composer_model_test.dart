import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/navigation/app_destination.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_drawer.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/model_selection_sheet.dart';
import 'package:nai_huishi/presentation/widgets/studio_navigation_bar.dart';

import 'support/chat_memory_fake.dart';

const _preview = String.fromEnvironment('UI_PREVIEW_DIR');
const _font = String.fromEnvironment('UI_PREVIEW_FONT');
final _input = find.byKey(const ValueKey('chat-composer-input'));
final _model = find.byKey(const ValueKey('chat-composer-model'));
final _surface = find.byKey(const ValueKey('chat-composer-surface'));

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (_preview.isEmpty) return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_preview).create(recursive: true);
    await File('$_preview/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (_font.isEmpty) return;
    await (FontLoader('Preview')
          ..addFont(File(_font).readAsBytes().then(ByteData.sublistView)))
        .load();
    for (final entry in {
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'packages/cupertino_icons/CupertinoIcons':
          'packages/cupertino_icons/assets/CupertinoIcons.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value)))
          .load();
    }
  });

  Future<(ChatMemoryHarness, GlobalKey)> open(WidgetTester tester,
      {Brightness brightness = Brightness.dark,
      bool emptyProviders = false}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final h = createChatMemoryHarness();
    await tester.runAsync(h.viewModel.ensureInitialized);
    await h.viewModel.setProviders(emptyProviders
        ? []
        : [
            for (final p in h.viewModel.providers)
              p.copyWith(models: [...p.models, 'main-alternate']),
          ]);
    sl.registerSingleton<LlmChatViewModel>(h.viewModel);
    addTearDown(() async {
      await sl.reset();
      h.dispose();
    });
    var theme = buildNaiHuishiTheme(brightness);
    if (_font.isNotEmpty) {
      theme = theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'Preview'));
    }
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: Builder(
              builder: (context) => Scaffold(
                    body: ChatDrawer(embedded: true, onClose: () {}),
                    bottomNavigationBar:
                        MediaQuery.viewInsetsOf(context).bottom > 0
                            ? null
                            : StudioNavigationBar(
                                selected: AppDestination.assistant,
                                onSelected: (_) {}),
                  )),
        )));
    await tester.pumpAndSettle();
    return (h, key);
  }

  for (final brightness in Brightness.values) {
    testWidgets(
        'composer and settings share the main model and keep drafts $brightness',
        (tester) async {
      final (h, key) = await open(tester, brightness: brightness);
      expect(tester.getSize(_surface).height, 56);
      expect(_model, findsNothing);
      await _capture(tester, key, 'composer-rest-${brightness.name}');
      await tester.tap(_input);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.getSize(_surface).height, greaterThan(100));
      expect(tester.getRect(_surface).bottom, lessThanOrEqualTo(544));
      expect(
          find.descendant(of: _model, matching: find.text('main-test-model')),
          findsOneWidget);
      await tester.enterText(_input, '黄昏的海边，风吹起头发。\n想要柔和的逆光，保留一点细碎反光。');
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(_input).controller!;
      final draft = controller.text;
      await _capture(tester, key, 'composer-expanded-${brightness.name}');
      await tester.tap(_model);
      // Opening the selector dismisses the composing keyboard on a device.
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(find.byType(ModelSelectionSheet), findsOneWidget);
      await tester.tap(find.text('main-alternate').hitTestable());
      await tester.pumpAndSettle();
      expect(h.viewModel.mainBinding.model, 'main-alternate');
      expect(h.viewModel.mainConfig.model, 'main-alternate');
      expect(controller.text, draft);
      expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isTrue);
      expect(find.descendant(of: _model, matching: find.text('main-alternate')),
          findsOneWidget);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      expect(find.text('助手设置'), findsOneWidget);
      await tester.tap(find.text('main-alternate').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('main-test-model').hitTestable());
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('助手设置'))).pop();
      await tester.pumpAndSettle();
      expect(
          find.descendant(of: _model, matching: find.text('main-test-model')),
          findsOneWidget);
      expect(controller.text, draft);
      controller.clear();
      await tester.pumpAndSettle();
      expect(_model, findsNothing);
      expect(tester.getSize(_surface).height, 56);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unconfigured composer opens assistant model settings',
      (tester) async {
    await open(tester, emptyProviders: true);
    await tester.tap(_input);
    await tester.pumpAndSettle();
    expect(find.descendant(of: _model, matching: find.text('选择模型')),
        findsOneWidget);
    await tester.tap(_model);
    await tester.pumpAndSettle();
    expect(find.text('助手设置'), findsOneWidget);
    expect(find.text('主模型'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
