import 'package:flutter/foundation.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_memories.dart';

class PromptMemoryViewModel extends ChangeNotifier {
  final ManagePromptMemoriesUseCase _useCase;

  PromptMemoryViewModel(this._useCase);

  List<PromptMemory> memories = [];
  List<PromptMemory> pendingMemories = [];
  bool isLoading = false;
  String? errorMessage;

  int get pendingCount => pendingMemories.length;

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    try {
      memories = await _useCase.getAll();
      pendingMemories = await _useCase.listPending();
      errorMessage = null;
    } catch (e) {
      errorMessage = '加载记忆失败: $e';
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> search(String query) async {
    memories = await _useCase.search(query);
    notifyListeners();
  }

  /// 保存。返回冲突列表（若 trigger 已存在），由 UI 决定策略后调 resolveConflict。
  /// 如果没冲突，直接保存。
  Future<List<PromptMemory>> saveOrFindConflicts({
    int? id,
    required String trigger,
    required String content,
    PromptMemoryType type = PromptMemoryType.other,
    PromptMemorySource source = PromptMemorySource.manual,
    int? supersededBy,
  }) async {
    final now = DateTime.now();
    final memory = PromptMemory(
      id: id,
      trigger: trigger,
      content: content,
      type: type,
      source: source,
      supersededBy: supersededBy,
      createdAt: now,
      updatedAt: now,
    );
    // 标准穿搭由仓库按角色名原子替换旧穿搭，避免进入通用冲突策略。
    if (id == null && type != PromptMemoryType.characterOutfit) {
      final conflicts = await _useCase.findConflicts(trigger);
      if (conflicts.isNotEmpty) {
        return conflicts;
      }
    }
    await _useCase.save(memory);
    await load();
    return const [];
  }

  /// 按策略处理冲突。
  /// [strategy] replace=旧记忆被覆盖；merge=合并内容；coexist=并存。
  /// [existingId] 冲突的旧记忆 id；[newMemory] 待保存的新记忆。
  Future<void> resolveConflict({
    required MemoryConflictStrategy strategy,
    required PromptMemory existing,
    required PromptMemory newMemory,
  }) async {
    switch (strategy) {
      case MemoryConflictStrategy.replace:
        final saved = await _useCase.save(newMemory);
        if (saved.id != null && existing.id != null) {
          await _useCase.save(existing.copyWith(supersededBy: saved.id));
        }
        break;
      case MemoryConflictStrategy.merge:
        final mergedContent =
            '${newMemory.content.trim()}\n---\n${existing.content.trim()}';
        final merged = newMemory.copyWith(content: mergedContent);
        final saved = await _useCase.save(merged);
        if (saved.id != null && existing.id != null) {
          await _useCase.save(existing.copyWith(supersededBy: saved.id));
        }
        break;
      case MemoryConflictStrategy.coexist:
        await _useCase.save(newMemory);
        break;
    }
    await load();
  }

  Future<void> delete(int id) async {
    await _useCase.delete(id);
    await load();
  }

  /// 晋升 pending 候选为正式记忆。
  /// 策略：把同一条 pending 行原地 UPDATE 为 llmCandidate，保留原 id。
  /// 不再“先删 pending 再 save”，避免 findConflicts 包含自身时落入空操作分支
  /// （save 携带已不存在的 id → UPDATE 命中 0 行 → 候选消失且未晋升）。
  /// 保存失败时设置 errorMessage 而非抛出，保证候选行不被删除，等待用户重试。
  Future<bool> promotePending(
    int id, {
    String? newContent,
    String? newTrigger,
    PromptMemoryType? newType,
  }) async {
    if (!pendingMemories.any((memory) => memory.id == id)) {
      errorMessage = '候选记忆已不存在';
      notifyListeners();
      return false;
    }

    try {
      await _useCase.promotePending(
        id,
        newTrigger: newTrigger,
        newContent: newContent,
        newType: newType,
      );
      errorMessage = null;
      await load();
      return true;
    } catch (e) {
      final message = e is ArgumentError ? e.message : e;
      errorMessage = '保存记忆失败: $message';
      notifyListeners();
      return false;
    }
  }

  Future<void> rejectPending(int id) async {
    await _useCase.delete(id);
    await load();
  }

  Future<List<PromptMemory>> listStale() => _useCase.listStale();

  Future<void> batchDelete(List<int> ids) async {
    for (final id in ids) {
      await _useCase.delete(id);
    }
    await load();
  }
}
