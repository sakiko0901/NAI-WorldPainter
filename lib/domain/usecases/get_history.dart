import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';

class GetHistoryUseCase {
  final HistoryRepository _repo;

  GetHistoryUseCase(this._repo);

  Future<List<GenerationTask>> execute({int page = 0, int pageSize = 20}) {
    return _repo.getHistory(page: page, pageSize: pageSize);
  }

  Future<GenerationTask?> getTask(String taskId) {
    return _repo.getTask(taskId);
  }

  Future<List<GenerationTask>> getCompleted() =>
      _repo.getTasksByStatus(AppConstants.taskSuccess);

  Future<void> deleteTask(String taskId) {
    return _repo.deleteTask(taskId);
  }

  Future<void> clearHistory() {
    return _repo.clearHistory();
  }

  Future<List<GenerationTask>> getFavorites() {
    return _repo.getFavorites();
  }

  Future<GenerationTask> toggleFavorite(String taskId) {
    return _repo.toggleFavorite(taskId);
  }
}
