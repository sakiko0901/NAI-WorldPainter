import 'package:nai_huishi/domain/entities/prompt_memory.dart';

abstract class PromptMemoryRepository {
  Future<List<PromptMemory>> getAll();
  Future<List<PromptMemory>> search(String query);
  Future<List<PromptMemory>> matchText(String text);
  Future<PromptMemory> save(PromptMemory memory);
  Future<void> delete(int id);
  Future<void> incrementHit(int id);
  Future<List<PromptMemory>> findConflicts(String trigger);
  Future<List<PromptMemory>> listPending();
  Future<List<PromptMemory>> listStale({Duration olderThan = const Duration(days: 90)});
}
