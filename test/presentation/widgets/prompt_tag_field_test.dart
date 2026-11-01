import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/services/tag_completion_service.dart';
import 'package:nai_huishi/domain/entities/tag_completion.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/prompt_tag_field.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';

const candidates = [
  TagCompletion(tag: 'blue_hair', translation: '蓝色头发', count: 1200000),
  TagCompletion(tag: 'blue_eyes', translation: '蓝色眼睛', count: 2000000),
];

class FakeCompletion extends TagCompletionService {
  final calls = <String>[];
  Future<List<TagCompletion>> Function(String)? respond;
  @override
  Future<void> initialize() async {}
  @override
  Future<List<TagCompletion>> search(String query,
      {bool artistOnly = false}) async {
    calls.add(query);
    if (respond == null) return candidates;
    return respond!(query);
  }

  @override
  Future<List<TagCompletion>> online(String query,
          {bool related = false, CancelToken? cancelToken}) async =>
      related ? [const TagCompletion(tag: 'long_hair', translation: '长发')] : [];
}

void main() {
  late TextEditingController controller;
  late FakeCompletion service;
  late List<String> changes;
  setUp(() {
    controller = TextEditingController();
    service = FakeCompletion();
    changes = [];
  });
  tearDown(() {
    controller.dispose();
    service.dispose();
  });
  Future<void> mount(WidgetTester tester,
      {double keyboard = 0, double scale = 1}) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildNaiHuishiTheme(Brightness.dark),
        home: MediaQuery(
            data: MediaQueryData(
                size: const Size(800, 600),
                viewInsets: EdgeInsets.only(bottom: keyboard),
                textScaler: TextScaler.linear(scale)),
            child: Scaffold(
                body: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 50, 24, 12),
                    child: Column(children: [
                      PromptTagField(
                          controller: controller,
                          service: service,
                          minLines: 3,
                          maxLines: 6,
                          onChanged: changes.add),
                      const Text('outside')
                    ]))))));
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
  }

  testWidgets('tap inserts and preserves input focus; callback runs once',
      (tester) async {
    await mount(tester);
    await type(tester, '{{blue h}}');
    // Put the cursor inside the closing weight delimiters, then edit there.
    controller.value = const TextEditingValue(
        text: '{{blue ha}}', selection: TextSelection.collapsed(offset: 9));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    await tester.tap(find.text('blue hair'));
    await tester.pump();
    expect(controller.text, '{{blue hair}}, ');
    expect(changes.where((s) => s == '{{blue hair}}, ').length, 1);
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        true);
    expect(find.byKey(const ValueKey('tag-completion-panel')), findsNothing);
  });

  testWidgets('IME composition waits until committed', (tester) async {
    await mount(tester);
    await tester.tap(find.byType(TextField));
    controller.value = const TextEditingValue(
        text: '蓝色',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2));
    await tester.pump(const Duration(milliseconds: 200));
    expect(service.calls, isEmpty);
    controller.value = controller.value.copyWith(composing: TextRange.empty);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(service.calls, ['蓝色']);
  });

  testWidgets('old async response cannot reopen a dismissed or changed query',
      (tester) async {
    final first = Completer<List<TagCompletion>>();
    service.respond =
        (q) => q == 'blue' ? first.future : Future.value([candidates.last]);
    await mount(tester);
    await type(tester, 'blue');
    await type(tester, 'eyes');
    expect(find.text('blue eyes'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    first.complete(candidates);
    await tester.pump();
    expect(find.byKey(const ValueKey('tag-completion-panel')), findsNothing);
  });

  testWidgets('hardware arrows and Tab select without inserting a tab',
      (tester) async {
    await mount(tester);
    await type(tester, 'blue');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.text, 'blue eyes, ');
  });

  testWidgets('disabled completion and disposed queries remain quiet',
      (tester) async {
    service.enabled = false;
    await mount(tester);
    await type(tester, 'blue');
    expect(service.calls, isEmpty);
    service.enabled = true;
    final pending = Completer<List<TagCompletion>>();
    service.respond = (_) => pending.future;
    await type(tester, 'blue h');
    await tester.pumpWidget(const SizedBox());
    pending.complete(candidates);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('related suggestions preserve source weights', (tester) async {
    service.onlineEnabled = true;
    await mount(tester);
    await type(tester, '{{blue hair}}');
    controller.value = const TextEditingValue(
        text: '{{blue hair}} ', selection: TextSelection.collapsed(offset: 11));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    await tester.tap(find.text('相关'));
    await tester.pump();
    await tester.tap(find.text('long hair'));
    await tester.pump();
    expect(controller.text, '{{blue hair}}, long hair, ');
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('completion can be undone and Shift Enter remains a newline',
      (tester) async {
    await mount(tester);
    await type(tester, 'blue');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.text, 'blue hair, ');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.text, 'blue');
    await type(tester, 'blue h');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(controller.text, 'blue h\n');
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('phone keyboard layout ${brightness.name} at $scale',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        final capture = GlobalKey();
        final captureImages =
            Platform.environment['NAI_COMPLETION_SCREENSHOTS'] == '1';
        if (captureImages) {
          await tester.runAsync(() async {
            final file = File('C:/Windows/Fonts/msyh.ttc');
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              await (FontLoader('Microsoft YaHei')
                    ..addFont(Future.value(ByteData.sublistView(bytes))))
                  .load();
            }
          });
        }
        final theme = buildNaiHuishiTheme(brightness);
        await tester.pumpWidget(RepaintBoundary(
            key: capture,
            child: MaterialApp(
                theme: captureImages
                    ? theme.copyWith(
                        textTheme: theme.textTheme
                            .apply(fontFamily: 'Microsoft YaHei'))
                    : theme,
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: Scaffold(
                    appBar: AppBar(title: const Text('创作')),
                    body:
                        ListView(padding: const EdgeInsets.all(16), children: [
                      FrostedSurface(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('正向提示词'),
                                const SizedBox(height: 12),
                                PromptTagField(
                                    controller: controller,
                                    service: service,
                                    minLines: 6,
                                    maxLines: 14,
                                    style: TextStyle(
                                        fontFamily: captureImages
                                            ? 'Microsoft YaHei'
                                            : null,
                                        fontSize: 14),
                                    decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        filled: false)),
                              ])),
                    ])))));
        await type(tester, '1girl, blue');
        await tester.pump(const Duration(milliseconds: 300));
        final panel = find.byKey(const ValueKey('tag-completion-panel'));
        expect(panel, findsOneWidget);
        final rect = tester.getRect(panel);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(390));
        expect(rect.bottom, lessThanOrEqualTo(544));
        expect(tester.takeException(), isNull);
        if (captureImages && scale == 1) {
          await tester.runAsync(() async {
            final boundary = capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
                'build/frontend-preview/tag-completion-${brightness.name}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.text('blue hair'));
        await tester.pump();
        expect(controller.text, '1girl, blue hair, ');
      });
    }
  }
}
