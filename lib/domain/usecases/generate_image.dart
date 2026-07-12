import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:uuid/uuid.dart';

class GenerateImageUseCase {
  final HistoryRepository _historyRepo;

  GenerateImageUseCase(this._historyRepo);

  /// 提交生成任务（通过队列）
  Future<GenerationTask> execute(
      GenerationQueue queue, GenerationTask task) async {
    final taskWithId =
        task.taskId.isEmpty ? task.copyWith(taskId: const Uuid().v4()) : task;

    final savedTask = await _historyRepo.saveTask(taskWithId);
    await queue.enqueue(savedTask);
    return savedTask;
  }
}
