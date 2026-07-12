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
}
