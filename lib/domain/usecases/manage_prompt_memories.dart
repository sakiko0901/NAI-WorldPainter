import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:nai_huishi/domain/repositories/prompt_memory_repository.dart';

class ManagePromptMemoriesUseCase {
  final PromptMemoryRepository _repo;

  ManagePromptMemoriesUseCase(this._repo);

  Future<List<PromptMemory>> getAll() => _repo.getAll();
  Future<List<PromptMemory>> search(String query) => _repo.search(query);
  Future<List<PromptMemory>> matchText(String text) => _repo.matchText(text);
  Future<PromptMemory> save(PromptMemory memory) => _repo.save(memory);
  Future<PromptMemory> promotePending(
    int id, {
    String? newTrigger,
    String? newContent,
    PromptMemoryType? newType,
  }) =>
      _repo.promotePending(
        id,
        newTrigger: newTrigger,
        newContent: newContent,
        newType: newType,
      );
  Future<void> delete(int id) => _repo.delete(id);
  Future<void> incrementHit(int id) => _repo.incrementHit(id);
  Future<List<PromptMemory>> findConflicts(String trigger) =>
      _repo.findConflicts(trigger);
  Future<List<PromptMemory>> listPending() => _repo.listPending();
  Future<List<PromptMemory>> listStale(
          {Duration olderThan = const Duration(days: 90)}) =>
      _repo.listStale(olderThan: olderThan);
}

/// 冲突处理策略。由 UI 层选择后传给 ViewModel。
enum MemoryConflictStrategy { replace, merge, coexist }
