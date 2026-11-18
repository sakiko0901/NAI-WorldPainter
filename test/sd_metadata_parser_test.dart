import 'package:shared_preferences/shared_preferences.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/datasources/remote/wd_tagger_api_service.dart';
import 'package:nai_huishi/presentation/viewmodels/image_tag_viewmodel.dart';
import 'support/chat_memory_fake.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/datasources/local/sd_metadata_parser.dart';
import 'package:nai_huishi/domain/entities/image_tag_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('SD mode analyzes the selected file and restores its cached result',
      () async {
    SharedPreferences.setMockInitialValues({});
    sl.registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance());
    addTearDown(() => sl.unregister<SharedPreferences>());
    final useCase = FakeAnalyzeImageTagsUseCase(const WdTaggerResult());
    final vm = ImageTagViewModel(useCase: useCase);
    await vm.setMode(TagAnalysisMode.sdMetadata);
    await vm.setImagePath('test/fixtures/sd_metadata/webui.jpg');
    await vm.analyze();
    expect(vm.error, isNull);
    expect(vm.result?.metadata?['Steps'], '24');
    final restored = ImageTagViewModel(useCase: useCase);
    await restored.loadCache();
    expect(restored.mode, TagAnalysisMode.sdMetadata);
    expect(restored.result, vm.result);
  });
  for (final ext in ['png', 'jpg', 'webp']) {
    test('reads WebUI parameters from $ext', () async {
      final bytes =
          await File('test/fixtures/sd_metadata/webui.$ext').readAsBytes();
      final result = SdMetadataParser.parseBytes(bytes)!;
      expect(result.source, TagSource.sdMetadata);
      expect(result.general.map((tag) => tag.tag),
          ['海边', '(red, blue:1.2)\nnight']);
      expect(result.selectedNegativeTags, 'fog, blur');
      expect(result.metadata!['Seed'], '123');
      expect(result.metadata!['Extra'], '"a, b: c"');
      expect(ImageTagResult.fromJson(result.toJson()), result);
    });
  }
  test('negative prompt is optional and unrelated text is ignored', () {
    expect(
        SdMetadataParser.parseParameters('cat\nSteps: 2, Seed: 0')!
            .negativeEntries,
        isEmpty);
    expect(SdMetadataParser.parseParameters('ordinary photograph'), isNull);
  });
}
