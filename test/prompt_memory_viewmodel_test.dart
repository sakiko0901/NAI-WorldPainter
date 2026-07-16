import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:nai_huishi/domain/repositories/prompt_memory_repository.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_memories.dart';
import 'package:nai_huishi/presentation/viewmodels/prompt_memory_viewmodel.dart';

void main() {
  test(
      'promotePending upgrades the same row in place when trigger is unchanged',
      () async {
    final pendingRow = PromptMemory(
      id: 7,
      trigger: 'cat',
      content: 'a small cat',
      type: PromptMemoryType.other,
      source: PromptMemorySource.pendingLlmCandidate,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    final repo = _FakePromptMemoryRepository(
      memories: const [],
      pending: [pendingRow],
    );
    // findConflicts 默认会返回 pending 自身，复现原 bug 的关键路径。
    repo.conflictsForTrigger = {
      'cat': [pendingRow]
    };

    final vm = PromptMemoryViewModel(ManagePromptMemoriesUseCase(repo));
    await vm.load();

    await vm.promotePending(7);

    expect(repo.deletedIds, isEmpty, reason: '晋升不应删除候选行');
    expect(repo.savedMemories, hasLength(1));
    expect(repo.savedMemories.single.id, 7);
    expect(repo.savedMemories.single.source, PromptMemorySource.llmCandidate);
    expect(repo.savedMemories.single.trigger, 'cat');
    expect(repo.savedMemories.single.content, 'a small cat');

    expect(vm.pendingMemories, isEmpty);
    expect(vm.memories, hasLength(1));
    expect(vm.memories.single.id, 7);
    expect(vm.memories.single.source, PromptMemorySource.llmCandidate);
  });

  test('promotePending applies edited trigger and content on promotion',
      () async {
    final repo = _FakePromptMemoryRepository(
      memories: const [],
      pending: [
        PromptMemory(
          id: 7,
          trigger: 'cat',
          content: 'a small cat',
          type: PromptMemoryType.other,
          source: PromptMemorySource.pendingLlmCandidate,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ],
    );

    final vm = PromptMemoryViewModel(ManagePromptMemoriesUseCase(repo));
    await vm.load();

    await vm.promotePending(
      7,
      newTrigger: 'black cat',
      newContent: 'a small black cat',
    );

    expect(repo.savedMemories, hasLength(1));
    expect(repo.savedMemories.single.id, 7);
    expect(repo.savedMemories.single.trigger, 'black cat');
    expect(repo.savedMemories.single.content, 'a small black cat');
    expect(repo.savedMemories.single.source, PromptMemorySource.llmCandidate);
    expect(repo.deletedIds, isEmpty);
  });

  test('promotePending keeps the candidate when save fails', () async {
    final repo = _FakePromptMemoryRepository(
      memories: const [],
      pending: [
        PromptMemory(
          id: 7,
          trigger: 'cat',
          content: 'a small cat',
          type: PromptMemoryType.other,
          source: PromptMemorySource.pendingLlmCandidate,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ],
    )..saveThrows = true;

    final vm = PromptMemoryViewModel(ManagePromptMemoriesUseCase(repo));
    await vm.load();

    await vm.promotePending(7);

    expect(repo.deletedIds, isEmpty, reason: '保存失败时不应删除候选，避免标签直接消失');
    expect(repo.savedMemories, isEmpty);
    // 候选仍在 pending 列表，等待用户再次尝试
    expect(vm.pendingMemories, hasLength(1));
    expect(vm.pendingMemories.single.id, 7);
    expect(vm.memories, isEmpty);
  });
}

class _FakePromptMemoryRepository implements PromptMemoryRepository {
  _FakePromptMemoryRepository({
    required List<PromptMemory> memories,
    required List<PromptMemory> pending,
  }) : _rows = [...memories, ...pending];

  final List<PromptMemory> _rows;
  final List<int> deletedIds = [];
  final List<PromptMemory> savedMemories = [];
  Map<String, List<PromptMemory>> conflictsForTrigger = const {};
  bool saveThrows = false;

  @override
  Future<List<PromptMemory>> getAll() async => _rows
      .where((m) => m.source != PromptMemorySource.pendingLlmCandidate)
      .toList();

  @override
  Future<List<PromptMemory>> search(String query) async => getAll();

  @override
  Future<List<PromptMemory>> matchText(String text) async =>
      _rows.where((m) => m.isRetrievable).toList();

  @override
  Future<PromptMemory> save(PromptMemory memory) async {
    savedMemories.add(memory);
    if (memory.id == null) {
      final newId = (_rows.isEmpty ? 0 : _rows.last.id ?? 0) + 1;
      final saved = memory.copyWith(id: newId);
      _rows.add(saved);
      return saved;
    }
    final idx = _rows.indexWhere((m) => m.id == memory.id);
    if (idx >= 0) {
      _rows[idx] = memory;
    } else {
      _rows.add(memory);
    }
    return memory;
  }

  @override
  Future<PromptMemory> promotePending(
    int id, {
    String? newTrigger,
    String? newContent,
    PromptMemoryType? newType,
  }) async {
    if (saveThrows) throw Exception('disk full');
    final idx = _rows.indexWhere(
      (memory) =>
          memory.id == id &&
          memory.source == PromptMemorySource.pendingLlmCandidate,
    );
    if (idx < 0) throw StateError('missing pending');
    final current = _rows[idx];
    final promoted = current.copyWith(
      trigger: newTrigger?.trim(),
      content: newContent?.trim(),
      type: newType,
      source: PromptMemorySource.llmCandidate,
    );
    savedMemories.add(promoted);
    _rows[idx] = promoted;
    return promoted;
  }

  @override
  Future<void> delete(int id) async {
    deletedIds.add(id);
    _rows.removeWhere((m) => m.id == id);
  }

  @override
  Future<void> incrementHit(int id) async {}

  @override
  Future<List<PromptMemory>> findConflicts(String trigger) async {
    final t = trigger.trim();
    return List.of(conflictsForTrigger[t] ?? const []);
  }

  @override
  Future<List<PromptMemory>> listPending() async => _rows
      .where((m) => m.source == PromptMemorySource.pendingLlmCandidate)
      .toList();

  @override
  Future<List<PromptMemory>> listStale(
      {Duration olderThan = const Duration(days: 90)}) async {
    return const [];
  }
}
