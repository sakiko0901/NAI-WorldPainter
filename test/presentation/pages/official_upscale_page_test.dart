import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/official_upscale_page.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';

import '../../support/frontend_generation_fake.dart';

class _UpscaleGenerationFake extends FrontendGenerationFake {
  final requests = <(String, int)>[];

  @override
  Future<String> upscaleFileWithOfficial(String inputPath, int scale) async {
    requests.add((inputPath, scale));
    return inputPath;
  }
}

class _SaveImageFake implements SaveImageUseCase {
  @override
  Future<bool> saveToGallery(String filePath) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _UpscaleGenerationFake generation;

  setUp(() {
    generation = _UpscaleGenerationFake();
    sl.registerSingleton<GenerationViewModel>(generation);
    sl.registerSingleton<SaveImageUseCase>(_SaveImageFake());
  });

  tearDown(() async {
    await sl.reset();
    generation.dispose();
  });

  testWidgets('uses the selected initial file and chosen official scale', (
    tester,
  ) async {
    final sourcePath = File('assets/style_presets/style_001.jpg').absolute.path;
    expect(File(sourcePath).existsSync(), isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildNaiHuishiTheme(Brightness.dark),
        home: OfficialUpscalePage(initialImagePath: sourcePath),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('原图'), findsOneWidget);
    await tester.tap(find.text('4×'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('official-upscale-run')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('开始 4× 放大'));
    await tester.pumpAndSettle();
    expect(find.text('开始 4× 官方 Upscale？'), findsOneWidget);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(generation.requests, [(sourcePath, 4)]);
    expect(find.text('放大结果'), findsOneWidget);
    expect(find.text('保存到相册'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
