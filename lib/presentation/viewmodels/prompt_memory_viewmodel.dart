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
  }) async {
    final now = DateTime.now();
    final memory = PromptMemory(
      id: id,
      trigger: trigger,
      content: content,
      type: type,
      source: source,
      createdAt: now,
      updatedAt: now,
    );
    if (id == null) {
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

  /// 晋升 pending 候选为正式记忆
  Future<void> promotePending(int id,
      {String? newContent, String? newTrigger}) async {
    final pending = pendingMemories.where((m) => m.id == id).firstOrNull;
    if (pending == null) return;
    final trigger = (newTrigger ?? pending.trigger).trim();
    final content = (newContent ?? pending.content).trim();

    // 晋升时也检测冲突
    final conflicts = await _useCase.findConflicts(trigger);
    if (conflicts.isEmpty) {
      await _useCase.save(pending.copyWith(
        source: PromptMemorySource.llmCandidate,
        trigger: trigger,
        content: content,
        updatedAt: DateTime.now(),
      ));
      await load();
      return;
    }
    // 有冲突：把 pending 升级为新记忆，由 UI 弹窗处理
    final newMemory = pending.copyWith(
      source: PromptMemorySource.llmCandidate,
      trigger: trigger,
      content: content,
    );
    // 注意：此时 pending 仍在表中，UI 层若选 replace/merge 会在 resolveConflict 中
    // 把新记忆保存为正式行（新 id），旧的 pending 行需要单独删除
    // 简化处理：先删除 pending，再走 resolveConflict
    await _useCase.delete(id);
    final conflictsAfterDelete = await _useCase.findConflicts(trigger);
    if (conflictsAfterDelete.isEmpty) {
      await _useCase.save(newMemory);
    } else {
      // 把冲突信息暂存，由 UI 触发 resolveConflict
      // 这里只能处理一个冲突，多冲突场景由 UI 提示
      await _resolvePromoteWithConflict(
        existing: conflictsAfterDelete.first,
        newMemory: newMemory,
      );
    }
    await load();
  }

  Future<void> _resolvePromoteWithConflict({
    required PromptMemory existing,
    required PromptMemory newMemory,
  }) async {
    // 默认 coexist，UI 可后续手动调整
    await resolveConflict(
      strategy: MemoryConflictStrategy.coexist,
      existing: existing,
      newMemory: newMemory,
    );
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
