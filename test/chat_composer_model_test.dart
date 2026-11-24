import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/llm_profile_role.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_role_binding.dart';
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
final _menu = find.byKey(const ValueKey('chat-model-thinking-menu'));
final _slider = find.byKey(const ValueKey('chat-thinking-slider'));

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

Future<List<Color>> _sampleThinkingTrack(
    WidgetTester tester, GlobalKey key, Rect slider,
    {List<Offset>? points}) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final samplePoints = (points ??
          [
            for (final fraction in [.26, .46])
              Offset(
                  slider.left + slider.width * fraction, slider.center.dy + 8),
          ])
      .map(boundary.globalToLocal);
  final colors = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      return samplePoints.map((point) {
        final offset = 4 * (point.dy.round() * image.width + point.dx.round());
        return Color.fromARGB(
          255,
          pixels.getUint8(offset),
          pixels.getUint8(offset + 1),
          pixels.getUint8(offset + 2),
        );
      }).toList();
    } finally {
      image.dispose();
    }
  });
  return colors!;
}

Future<({int first, int last, int height})> _measureThinkingRail(
    WidgetTester tester, GlobalKey key, Rect slider) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final bounds = boundary.globalToLocal(slider.topLeft) & slider.size;
  final rail = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final x = bounds.center.dx.round();
      final y = bounds.center.dy.round();
      final background = 4 * ((y - 18) * image.width + x);

      bool isRail(int x, int y) {
        final offset = 4 * (y * image.width + x);
        return [0, 1, 2].any((channel) =>
            (pixels.getUint8(offset + channel) -
                    pixels.getUint8(background + channel))
                .abs() >
            15);
      }

      final centerRow = [
        for (var column = bounds.left.ceil();
            column < bounds.right.floor();
            column++)
          if (isRail(column, y)) column,
      ];
      final height = [
        for (var row = y - 16; row <= y + 16; row++)
          if (isRail(x, row)) row,
      ].length;
      return (first: centerRow.first, last: centerRow.last, height: height);
    } finally {
      image.dispose();
    }
  });
  return rail!;
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
        textTheme: theme.textTheme.apply(fontFamily: 'Preview'),
        chipTheme: theme.chipTheme.copyWith(
          labelStyle:
              theme.chipTheme.labelStyle?.copyWith(fontFamily: 'Preview'),
        ),
      );
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(_menu, findsOneWidget);
      await tester.pumpAndSettle();
      expect(
          tester.getRect(_menu).bottom, lessThan(tester.getRect(_surface).top));
      expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isTrue);
      final track = tester.getRect(_slider);
      final sliderTheme = SliderTheme.of(tester.element(_slider));
      expect(sliderTheme.trackHeight, 28);
      expect(sliderTheme.thumbColor, const Color(0xfffcfcff));
      await tester.tapAt(track.center + const Offset(22, 0));
      await tester.pumpAndSettle();
      expect(h.viewModel.mainConfig.thinkingLevel, LlmThinkingLevel.medium);
      await _capture(
          tester, key, 'composer-thinking-normal-${brightness.name}');
      await tester.tapAt(Offset(track.right - 20, track.center.dy));
      await tester.pumpAndSettle();
      expect(h.viewModel.mainConfig.thinkingLevel, LlmThinkingLevel.high);
      await _capture(tester, key, 'composer-thinking-${brightness.name}');

      await tester.tap(find.byKey(const ValueKey('chat-model-menu-choose')));
      await tester.pumpAndSettle();
      expect(find.byType(ModelSelectionSheet), findsOneWidget);
      expect(
          find.descendant(
              of: _menu, matching: find.byType(ModelSelectionSheet)),
          findsOneWidget);
      expect(
          find.descendant(
              of: _menu, matching: find.byIcon(Icons.check_rounded)),
          findsOneWidget);
      expect(
          tester.getRect(_menu).bottom, lessThan(tester.getRect(_surface).top));
      await _capture(tester, key, 'composer-model-picker-${brightness.name}');
      await tester.tap(find.text('main-alternate').hitTestable());
      await tester.pumpAndSettle();
      expect(h.viewModel.mainBinding.model, 'main-alternate');
      expect(h.viewModel.mainConfig.model, 'main-alternate');
      expect(h.viewModel.mainConfig.thinkingLevel, LlmThinkingLevel.automatic);
      await tester.tapAt(const Offset(16, 100));
      await tester.pumpAndSettle();
      expect(_menu, findsNothing);
      expect(controller.text, draft);
      expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isTrue);
      expect(find.descendant(of: _model, matching: find.text('main-alternate')),
          findsOneWidget);

      FocusManager.instance.primaryFocus?.unfocus();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      expect(find.text('助手设置'), findsOneWidget);
      await tester.tap(find.text('main-alternate').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('main-test-model').hitTestable());
      await tester.pumpAndSettle();
      expect(h.viewModel.mainConfig.thinkingLevel, LlmThinkingLevel.high);
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

  testWidgets('dark thinking slider changes from blue to Ultra and back',
      (tester) async {
    final (h, key) = await open(tester);
    final provider = h.viewModel.providers.single;
    const model = 'gpt-6.2-sol';
    await h.viewModel.setProviders([
      provider.copyWith(
        protocol: LlmApiProtocol.openAi,
        baseUrl: LlmApiProtocol.openAi.defaultBaseUrl,
        models: [...provider.models, model],
      ),
    ]);
    await h.viewModel.setRoleBinding(
      LlmProfileRole.main,
      LlmRoleBinding(providerId: provider.id, model: model),
    );
    await tester.tap(_input);
    await tester.pumpAndSettle();
    await tester.tap(_model);
    await tester.pumpAndSettle();

    final track = tester.getRect(_slider);
    final slider = tester.widget<Slider>(_slider);
    expect(slider.divisions, 5);
    expect(slider.semanticFormatterCallback!(slider.max), '思考等级：Ultra');
    final sliderBox = tester.renderObject<RenderBox>(_slider);
    final sliderTheme = SliderTheme.of(tester.element(_slider));
    final rail = sliderTheme.trackShape!.getPreferredRect(
      parentBox: sliderBox,
      sliderTheme: sliderTheme,
      isEnabled: true,
      isDiscrete: true,
    );
    final ticks = [
      for (var i = 0; i < slider.divisions!; i++)
        sliderBox.localToGlobal(Offset(
          rail.left +
              rail.height / 2 +
              i * (rail.width - rail.height) / slider.divisions!,
          rail.center.dy,
        )),
    ];
    final tickProbes = [
      for (final tick in ticks) ...[tick, tick.translate(0, 8)],
    ];

    await tester.tapAt(Offset(track.left + track.width * .6, track.center.dy));
    await tester.pumpAndSettle();
    expect(h.viewModel.mainConfig.thinkingLevel, LlmThinkingLevel.high);
    final normalColors = await _sampleThinkingTrack(tester, key, track);
    expect(normalColors, [const Color(0xff3a82ee), const Color(0xff3a82ee)]);
    final normalTicks =
        await _sampleThinkingTrack(tester, key, track, points: tickProbes);
    expect(normalTicks[0], isNot(normalTicks[1]));
    await _capture(tester, key, 'thinking-blue-dark');

    await tester.tapAt(Offset(track.right - 20, track.center.dy));
    await tester.pumpAndSettle();
    expect(h.viewModel.mainConfig.thinkingLevel, LlmThinkingLevel.max);
    expect(find.descendant(of: _menu, matching: find.text('Ultra')),
        findsOneWidget);
    expect(find.descendant(of: _model, matching: find.text('Ultra')),
        findsOneWidget);
    final peakColors = await _sampleThinkingTrack(tester, key, track);
    expect(peakColors.last.r, greaterThan(peakColors.first.r));
    expect(peakColors.last.b, greaterThan(peakColors.last.r));
    expect(peakColors.last.r, greaterThan(peakColors.last.g));
    final peakTicks =
        await _sampleThinkingTrack(tester, key, track, points: tickProbes);
    for (var i = 0; i < peakTicks.length; i += 2) {
      expect(peakTicks[i], peakTicks[i + 1]);
    }
    await _capture(tester, key, 'thinking-ultra-dark');

    await tester.tapAt(Offset(track.left + track.width * .6, track.center.dy));
    await tester.pumpAndSettle();
    expect(h.viewModel.mainConfig.thinkingLevel, LlmThinkingLevel.high);
    expect(await _sampleThinkingTrack(tester, key, track), normalColors);
    expect(tester.takeException(), isNull);
  });

  for (final reduceMotion in [false, true]) {
    testWidgets(
        'thinking rail stretches at either end until release (reduce: $reduceMotion)',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: reduceMotion);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final (h, key) = await open(tester);
      await tester.tap(_input);
      await tester.pumpAndSettle();
      await tester.tap(_model);
      await tester.pumpAndSettle();

      final track = tester.getRect(_slider);
      final slider = tester.widget<Slider>(_slider);
      for (final end in [-1, 1]) {
        final isLeft = end < 0;
        final level =
            isLeft ? LlmThinkingLevel.automatic : LlmThinkingLevel.high;
        await h.viewModel.setModelThinkingLevel(h.viewModel.mainBinding, level);
        await tester.pumpAndSettle();
        final idle = await _measureThinkingRail(tester, key, track);
        expect(idle.height, closeTo(28, 1));

        final endpoint = Offset(
            isLeft ? track.left + 34 : track.right - 34, track.center.dy);
        final gesture = await tester.startGesture(endpoint);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        final held = await _measureThinkingRail(tester, key, track);
        expect(held.height, idle.height);

        await gesture.moveBy(Offset(22.0 * end, 0));
        await tester.pumpAndSettle();
        final shortPull = await _measureThinkingRail(tester, key, track);
        await gesture.moveBy(Offset(21.0 * end, 0));
        await tester.pumpAndSettle();
        final longPull = await _measureThinkingRail(tester, key, track);
        if (reduceMotion) {
          expect(longPull.height, held.height);
          expect(longPull, shortPull);
        } else {
          expect(shortPull.height, lessThan(held.height));
          expect(longPull.height, lessThanOrEqualTo(shortPull.height));
          if (isLeft) {
            expect(longPull.first, lessThan(shortPull.first));
          } else {
            expect(longPull.last, greaterThan(shortPull.last));
          }
          await _capture(
              tester, key, 'thinking-pull-${isLeft ? 'left' : 'right'}');
        }
        expect(tester.getRect(_slider), track);
        expect(tester.widget<Slider>(_slider).value, isLeft ? 0 : slider.max);

        await tester.pump(const Duration(milliseconds: 450));
        expect(await _measureThinkingRail(tester, key, track), longPull);
        await gesture.up();
        await tester.pump();
        if (!reduceMotion) {
          expect((await _measureThinkingRail(tester, key, track)).height,
              lessThan(idle.height));
        }
        await tester.pumpAndSettle();
        expect(await _measureThinkingRail(tester, key, track), idle);
        expect(h.viewModel.mainConfig.thinkingLevel, level);
      }
    });
  }

  testWidgets(
      'Gemini Flash-Lite thinking can be dragged and reset with a short keyboard',
      (tester) async {
    final (h, _) = await open(tester);
    await h.viewModel.setProviders([
      for (final provider in h.viewModel.providers)
        provider.copyWith(
          protocol: LlmApiProtocol.gemini,
          name: 'Gemini',
          baseUrl: LlmApiProtocol.gemini.defaultBaseUrl,
          models: [...provider.models, 'gemini-3.1-flash-lite'],
        ),
    ]);
    await h.viewModel.setRoleBinding(
      LlmProfileRole.main,
      LlmRoleBinding(
          providerId: h.viewModel.providers.single.id,
          model: 'gemini-3.1-flash-lite'),
    );
    tester.view.physicalSize = const Size(360, 720);
    tester.view.viewInsets = const FakeViewPadding(bottom: 305);
    await tester.tap(_input);
    await tester.pumpAndSettle();
    await tester.tap(_model);
    await tester.pumpAndSettle();
    expect(tester.getRect(_menu).bottom, lessThan(415));
    final slider = tester.widget<Slider>(_slider);
    expect(slider.divisions, 4);
    expect(slider.semanticFormatterCallback!(1), '思考等级：极低');
    expect(slider.semanticFormatterCallback!(slider.max), '思考等级：高');
    final rect = tester.getRect(_slider);
    final gesture =
        await tester.startGesture(Offset(rect.left + 20, rect.center.dy));
    await gesture.moveTo(Offset(rect.center.dx, rect.center.dy));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.widget<Slider>(_slider).value, greaterThan(0));
    expect(h.viewModel.mainConfig.thinkingLevel, LlmThinkingLevel.automatic);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(h.viewModel.mainConfig.thinkingLevel,
        isNot(LlmThinkingLevel.automatic));
    await tester.tapAt(Offset(rect.right - 20, rect.center.dy));
    await tester.pumpAndSettle();
    expect(h.viewModel.mainConfig.thinkingLevel, LlmThinkingLevel.high);
    expect(
        find.descendant(of: _menu, matching: find.text('高')), findsOneWidget);
    expect(
        find.descendant(of: _menu, matching: find.text('Ultra')), findsNothing);
    await tester.tap(find.byTooltip('恢复自动思考'));
    await tester.pumpAndSettle();
    expect(h.viewModel.mainConfig.thinkingLevel, LlmThinkingLevel.automatic);
    expect(tester.widget<Slider>(_slider).value, 0);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('inline model list scrolls and searches without leaving the menu',
      (tester) async {
    final (h, _) = await open(tester);
    await h.viewModel.setProviders([
      for (final p in h.viewModel.providers)
        p.copyWith(
            models: [...p.models, for (var i = 1; i <= 18; i++) 'model-$i']),
    ]);
    await tester.tap(_input);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await tester.tap(_model);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-model-menu-choose')));
    await tester.pumpAndSettle();
    final list = find.descendant(of: _menu, matching: find.byType(ListView));
    expect(
        tester.getRect(_menu).bottom, lessThan(tester.getRect(_surface).top));
    final controller = tester.widget<ListView>(list).controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));
    await tester.drag(list, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    await tester.tap(find.byTooltip('搜索模型'));
    await tester.pumpAndSettle();
    final search = find.descendant(of: _menu, matching: find.byType(TextField));
    await tester.enterText(search, 'model-18');
    await tester.pumpAndSettle();
    expect(find.text('model-1').hitTestable(), findsNothing);
    final match = find.descendant(of: list, matching: find.text('model-18'));
    await tester.tap(match.hitTestable());
    await tester.pumpAndSettle();
    expect(h.viewModel.mainBinding.model, 'model-18');
    expect(_menu, findsOneWidget);
    expect(_slider.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
