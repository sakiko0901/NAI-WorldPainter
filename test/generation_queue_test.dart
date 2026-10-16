import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/nai_model.dart';
import 'package:nai_huishi/domain/repositories/generation_repository.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';

void main() {
  test('可等待 transient 队列返回终态且不写入历史', () async {
    final history = _History();
    final queue = GenerationQueue(_Repository(), history);
    addTearDown(queue.dispose);
    final task = _task('transient');

    final completed = await queue.enqueueTransientAndWait(task);

    expect(completed.status, 'success');
    expect(completed.imagePath, '/tmp/transient.png');
    expect(history.updated, isEmpty);
  });

  test('取消可等待 transient 任务会完成 Future', () async {
    final queue = GenerationQueue(_Repository(), _History());
    addTearDown(queue.dispose);
    final first = queue.enqueueTransientAndWait(_task('first'));
    final second = queue.enqueueTransientAndWait(_task('second'));

    expect(queue.cancel('second'), isTrue);
    final cancelled = await second;
    await first;

    expect(cancelled.status, 'failed');
    expect(cancelled.errorMessage, '任务已取消');
  });
}

GenerationTask _task(String id) => GenerationTask(
      taskId: id,
      model: 'model',
      prompt: 'prompt',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0,
      sampler: 'k_euler',
      noiseSchedule: 'native',
      status: 'pending',
      createdAt: DateTime(2026),
    );

class _Repository implements GenerationRepository {
  @override
  Future<GenerationTask> submitGeneration(GenerationTask task) async =>
      task.copyWith(status: 'success', imagePath: '/tmp/${task.taskId}.png');

  @override
  void setStreamPreviewHandler(
      String taskId, void Function(Uint8List bytes, int? step)? onFrame) {}

  @override
  Future<List<NaiModel>> fetchModels() async => const [];

  @override
  Future<void> cancelTask(String taskId) async {}
}

class _History implements HistoryRepository {
  final updated = <GenerationTask>[];

  @override
  Future<GenerationTask> updateTask(GenerationTask task) async {
    updated.add(task);
    return task;
  }

  @override
  Future<GenerationTask> saveTask(GenerationTask task) async => task;

  @override
  Future<List<GenerationTask>> getHistory({
    int page = 0,
    int pageSize = 20,
  }) async =>
      [];

  @override
  Future<void> trimHistory({int keep = 30}) async {}

  @override
  Future<GenerationTask?> getTask(String taskId) async => null;

  @override
  Future<void> deleteTask(String taskId) async {}

  @override
  Future<void> clearHistory() async {}

  @override
  Future<int> getTaskCount() async => 0;

  @override
  Future<List<GenerationTask>> getTasksByStatus(String status) async => [];

  @override
  Future<GenerationTask> toggleFavorite(String taskId) async => _task(taskId);

  @override
  Future<List<GenerationTask>> getFavorites() async => [];
}
