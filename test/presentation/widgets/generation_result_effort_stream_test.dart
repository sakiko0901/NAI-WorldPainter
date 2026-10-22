import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/generation_result_card.dart';

void main() {
  late Directory imageDirectory;
  late File historyImage;
  late Uint8List firstStreamFrame;
  late Uint8List nextStreamFrame;

  setUp(() async {
    imageDirectory = await Directory.systemTemp.createTemp('result-stream-');
    historyImage = File(
      '${imageDirectory.path}${Platform.pathSeparator}history.png',
    );
    final history = img.Image(width: 8, height: 4);
    img.fill(history, color: img.ColorRgba8(218, 77, 58, 255));
    await historyImage.writeAsBytes(img.encodePng(history));

    final first = img.Image(width: 8, height: 4);
    img.fill(first, color: img.ColorRgba8(39, 91, 219, 255));
    firstStreamFrame = Uint8List.fromList(img.encodePng(first));
    final next = img.Image(width: 8, height: 4);
    img.fill(next, color: img.ColorRgba8(34, 176, 123, 255));
    nextStreamFrame = Uint8List.fromList(img.encodePng(next));
  });

  tearDown(() async {
    if (await imageDirectory.exists()) {
      await imageDirectory.delete(recursive: true);
    }
  });

  testWidgets('High and Medium control dispatches both effort changes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final result = _result('effort-preview', historyImage.path, seed: 73);
    final changes = <GenerationEffort>[];
    var effort = GenerationEffort.high;
    final captureKey = GlobalKey();
    const captureEnabled = bool.fromEnvironment('FRONTEND_CAPTURE');
    if (captureEnabled) await _loadCaptureFonts();
    await _preloadHistoryImage(tester, historyImage);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildNaiHuishiTheme(Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: RepaintBoundary(
              key: captureKey,
              child: StatefulBuilder(
                builder: (context, setState) => GenerationResultCard(
                  task: result,
                  results: [result],
                  workspaceHeight: 260,
                  effort: effort,
                  onEffortChanged: (value) {
                    changes.add(value);
                    setState(() => effort = value);
                  },
                  onSelect: (_) {},
                  onPreview: () {},
                  onSave: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('High'), findsOneWidget);
    if (captureEnabled) {
      await _capture(tester, captureKey, 'result-effort-dark.png');
    }

    await tester.tap(find.text('High'));
    await tester.pumpAndSettle();
    expect(changes, [GenerationEffort.medium]);
    expect(find.text('Medium'), findsOneWidget);

    await tester.tap(find.text('Medium'));
    await tester.pumpAndSettle();
    expect(changes, [GenerationEffort.medium, GenerationEffort.high]);
    expect(find.text('High'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'historical selection stays visible during stream updates and actions stay scoped',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final history = _result('history', historyImage.path, seed: 41);
    final pending = _pendingResult('streaming-job');
    var selected = pending;
    var streamFrame = firstStreamFrame;
    var streamStep = 3;
    late StateSetter rebuild;
    final savedTaskIds = <String>[];
    final deletedTaskIds = <String>[];
    await _preloadHistoryImage(tester, historyImage);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildNaiHuishiTheme(Brightness.dark),
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: GenerationResultCard(
                  task: selected,
                  results: [history, pending],
                  generating: true,
                  workspaceHeight: 260,
                  streamPreviewBytes: streamFrame,
                  streamPreviewStep: streamStep,
                  onSelect: (task) => setState(() => selected = task),
                  onSave: () => savedTaskIds.add(selected.taskId),
                  onDelete: (task) => deletedTaskIds.add(task.taskId),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(
        find.byKey(const ValueKey('result-workspace-preview')), findsOneWidget);
    expect(find.text('流式预览 · 第 3 步'), findsOneWidget);

    final semantics = tester.ensureSemantics();
    await tester.tap(find.bySemanticsLabel('查看第 1 张结果'));
    semantics.dispose();
    await tester.pump();
    expect(selected.taskId, history.taskId);

    final fileImage = find.descendant(
      of: find.byKey(const ValueKey('result-image-viewer')),
      matching: find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is FileImage,
      ),
    );
    expect(fileImage, findsOneWidget);
    expect(
      (tester.widget<Image>(fileImage).image as FileImage).file.path,
      historyImage.path,
    );
    expect(
        find.byKey(const ValueKey('result-workspace-preview')), findsNothing);
    expect(find.text('Seed 41'), findsOneWidget);

    rebuild(() {
      streamFrame = nextStreamFrame;
      streamStep = 4;
    });
    await tester.pump();
    expect(
        find.byKey(const ValueKey('result-workspace-preview')), findsNothing);
    expect(
      (tester.widget<Image>(fileImage).image as FileImage).file.path,
      historyImage.path,
    );
    expect(find.text('Seed 41'), findsOneWidget);

    final deleteButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '删除当前图片',
    );
    expect(tester.widget<IconButton>(deleteButton).onPressed, isNull);
    await tester.tap(find.byTooltip('删除当前图片'));
    await tester.tap(find.byKey(const ValueKey('result-save-button')));
    await tester.pump();

    expect(deletedTaskIds, isEmpty,
        reason: 'deleting any workspace image is disabled during generation');
    expect(savedTaskIds, [history.taskId]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

GenerationTask _result(String id, String imagePath, {required int seed}) =>
    GenerationTask(
      taskId: id,
      model: 'nai-diffusion-5-full',
      prompt: 'silver hair',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0.25,
      sampler: 'k_euler',
      noiseSchedule: 'native',
      seed: seed,
      status: 'success',
      imagePath: imagePath,
      createdAt: DateTime(2026, 10, 16),
    );

GenerationTask _pendingResult(String id) => GenerationTask(
      taskId: id,
      model: 'nai-diffusion-5-full',
      prompt: 'silver hair',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0.25,
      sampler: 'k_euler',
      noiseSchedule: 'native',
      status: 'running',
      createdAt: DateTime(2026, 10, 16),
    );

Future<void> _preloadHistoryImage(WidgetTester tester, File image) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold()));
  await tester.runAsync(() => precacheImage(
        FileImage(image),
        tester.element(find.byType(Scaffold)),
      ));
}

Future<void> _loadCaptureFonts() async {
  final fontPath = Platform.environment['FRONTEND_QA_FONT'];
  if (fontPath != null) {
    final bytes = File(fontPath).readAsBytesSync();
    for (final family in ['Microsoft YaHei', 'Roboto']) {
      await (FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  }

  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    for (final font in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String filename,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/frontend-preview/$filename');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}
