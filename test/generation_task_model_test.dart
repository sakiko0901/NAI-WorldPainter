import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/models/generation_task_model.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';

void main() {
  GenerationTask task({int steps = 28}) => GenerationTask(
        taskId: 'task-1',
        model: 'nai-model',
        prompt: 'test',
        width: 832,
        height: 1216,
        scale: 5,
        cfgRescale: 0,
        sampler: 'k_euler',
        noiseSchedule: 'native',
        steps: steps,
        status: 'success',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );

  test('GenerationTask defaults steps to 28 and copyWith updates it', () {
    final original = task();
    expect(original.steps, 28);
    expect(original.copyWith(steps: 35).steps, 35);
  });

  test('GenerationTaskModel maps steps through entity and database', () {
    final model = GenerationTaskModel.fromEntity(task(steps: 32));
    expect(model.steps, 32);
    expect(model.toDb()['steps'], 32);
    expect(model.toEntity().steps, 32);

    final restored = GenerationTaskModel.fromDb(model.toDb());
    expect(restored.steps, 32);
  });

  test('GenerationTaskModel uses 28 for legacy database rows', () {
    final row = GenerationTaskModel.fromEntity(task()).toDb()..remove('steps');
    expect(GenerationTaskModel.fromDb(row).steps, 28);
  });

  test('Vibe reference defaults to 0.3 and keeps explicit legacy strength', () {
    expect(const CharacterReferenceImage(path: 'reference.png').strength, 0.3);
    expect(
      CharacterReferenceImage.fromJson(const {'path': 'reference.png'})
          .strength,
      0.3,
    );
    expect(
      CharacterReferenceImage.fromJson(
        const {'path': 'reference.png', 'strength': 0.6},
      ).strength,
      0.6,
    );
  });

  test('角色精细参考经历史模型往返后保留归属和参数', () {
    final original = task().copyWith(
      characters: const [
        CharacterSpec(
          prompt: 'girl',
          referenceImages: [
            CharacterReferenceImage(
              path: 'character.png',
              strength: 0.6,
              informationExtracted: 0.4,
            ),
          ],
        ),
      ],
    );

    final restored = GenerationTaskModel.fromDb(
      GenerationTaskModel.fromEntity(original).toDb(),
    ).toEntity();

    final reference = restored.characters!.single.referenceImages.single;
    expect(reference.path, 'character.png');
    expect(reference.strength, 0.6);
    expect(reference.informationExtracted, 0.4);
  });

  test('ikun 图生图和局部重绘历史往返保留接口状态', () {
    final original = task().copyWith(
      endpointId: 'ikun',
      protocol: 'image-generations',
      size: '832x1216',
      mode: GenerationMode.inpainting,
      sourceImagePath: 'source.png',
      maskImagePath: 'mask.png',
      inpaintStrength: 0.8,
      img2imgSourceImagePath: 'img2img.png',
      img2imgStrength: 0.45,
      responseFormat: 'b64_json',
      providerType: ImageProviderType.novelAi,
      disabledOriginalImage: true,
      colorCorrect: false,
      vibeReferences: const [
        CharacterReferenceImage(
          path: 'vibe.png',
          strength: 0.4,
          informationExtracted: 0.7,
          vibeLibraryId: 9,
          thumbnailPath: 'vibe-thumb.jpg',
          title: 'vibe',
        ),
      ],
    );

    final restored = GenerationTaskModel.fromDb(
      GenerationTaskModel.fromEntity(original).toDb(),
    ).toEntity();

    expect(restored.endpointId, 'ikun');
    expect(restored.protocol, 'image-generations');
    expect(restored.size, '832x1216');
    expect(restored.mode, GenerationMode.inpainting);
    expect(restored.sourceImagePath, 'source.png');
    expect(restored.maskImagePath, 'mask.png');
    expect(restored.inpaintStrength, 0.8);
    expect(restored.img2imgSourceImagePath, 'img2img.png');
    expect(restored.img2imgStrength, 0.45);
    expect(restored.responseFormat, 'b64_json');
    expect(restored.providerType, ImageProviderType.novelAi);
    expect(restored.disabledOriginalImage, isTrue);
    expect(restored.colorCorrect, isFalse);
    expect(restored.vibeReferences, original.vibeReferences);
  });

  test('legacy history uses safe defaults for interface state', () {
    final row = GenerationTaskModel.fromEntity(task()).toDb()
      ..remove('size')
      ..remove('mode')
      ..remove('source_image_path')
      ..remove('mask_image_path')
      ..remove('inpaint_strength')
      ..remove('img2img_source_image_path')
      ..remove('img2img_strength')
      ..remove('response_format')
      ..remove('provider_type')
      ..remove('disabled_original_image')
      ..remove('color_correct')
      ..remove('vibe_references');

    final restored = GenerationTaskModel.fromDb(row).toEntity();

    expect(restored.mode, GenerationMode.textToImage);
    expect(restored.providerType, ImageProviderType.novelAi);
    expect(restored.disabledOriginalImage, isFalse);
    expect(restored.colorCorrect, isTrue);
    expect(restored.vibeReferences, isEmpty);
    expect(restored.sourceImagePath, isNull);
    expect(restored.maskImagePath, isNull);
    expect(restored.img2imgSourceImagePath, isNull);
  });

  test('legacy Precise history ignores fidelity when reserialized', () {
    final row = GenerationTaskModel.fromEntity(task()).toDb()
      ..['precise_references'] = jsonEncode([
        {
          'path': 'reference.png',
          'reference_type': 'character',
          'strength': 0.8,
          'fidelity': 0.4,
        },
      ]);

    final restored = GenerationTaskModel.fromDb(row);

    expect(restored.preciseReferences, hasLength(1));
    expect(restored.preciseReferences.single.path, 'reference.png');
    expect(restored.preciseReferences.single.referenceType, 'character');
    expect(restored.preciseReferences.single.strength, 0.8);
    final saved = jsonDecode(restored.toDb()['precise_references'] as String)
        as List<dynamic>;
    expect(saved.single, isNot(contains('fidelity')));
  });
}
