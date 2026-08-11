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
