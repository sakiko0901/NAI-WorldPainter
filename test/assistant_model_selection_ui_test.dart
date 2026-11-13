import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/llm_profile_role.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_settings_sheet.dart';
import 'support/chat_memory_fake.dart';

void main() {
  const output = String.fromEnvironment('ASSISTANT_PREVIEW_DIR');
  const font = String.fromEnvironment('ASSISTANT_PREVIEW_FONT');
  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets(
        'model settings toggle persists and picker fits keyboard $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final h = createChatMemoryHarness();
      addTearDown(h.dispose);
      await tester.runAsync(h.viewModel.ensureInitialized);
      var theme = buildNaiHuishiTheme(brightness);
      if (font.isNotEmpty) {
        await tester.runAsync(() async {
          final loader = FontLoader('Preview')
            ..addFont(File(font)
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes)));
          await loader.load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          await (FontLoader('packages/cupertino_icons/CupertinoIcons')
                ..addFont(rootBundle.load(
                    'packages/cupertino_icons/assets/CupertinoIcons.ttf')))
              .load();
        });
        theme = theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'Preview'));
      }
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () =>
                            showChatSettingsSheet(context, h.viewModel),
                        child: const Text('设置')))),
          )));
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        if (output.isEmpty) return;
        await tester.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
          final bytes =
              (await image.toByteData(format: ui.ImageByteFormat.png))!
                  .buffer
                  .asUint8List();
          await Directory(output).create(recursive: true);
          await File('$output/$name-${brightness.name}.png')
              .writeAsBytes(bytes);
          image.dispose();
        });
      }

      await capture('models');
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      expect(h.viewModel.streamingFor(LlmProfileRole.main), isFalse);
      expect(
          h.viewModel.providers.single.streaming['main-test-model'], isFalse);
      await tester.tap(find.text('main-test-model'));
      await tester.pumpAndSettle();
      await capture('picker');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'no-matching-model');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的模型'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'vision');
      await tester.pumpAndSettle();
      await tester.tap(find.text('vision-test-model').hitTestable());
      await tester.pumpAndSettle();
      expect(h.viewModel.mainBinding.model, 'vision-test-model');
      expect(tester.takeException(), isNull);
    });
  }
}
