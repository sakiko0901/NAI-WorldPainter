import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/agents/tools/get_memories_tool.dart';
import 'package:nai_huishi/domain/agents/tools/save_memory_tool.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:nai_huishi/domain/repositories/prompt_memory_repository.dart';
import 'package:nai_huishi/domain/services/prompt_memory_context.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_memories.dart';

void main() {
  group('SaveMemoryTool', () {
    test(
        'saves natural-language standard outfit and deduplicates aliases as pending',
        () async {
      final repository = _FakePromptMemoryRepository();
      final tool = SaveMemoryTool(ManagePromptMemoriesUseCase(repository));

      final result = await tool.call({
        'trigger': '纳西妲',
        'aliases': ['Nahida', '纳西妲', 'Lesser Lord Kusanali'],
        'content': '标准穿搭：白色连衣裙、绿色披肩与花朵发饰。',
        'type': 'character_outfit',
      });

      expect(result.success, isTrue);
      expect(repository.saved, hasLength(1));
      final saved = repository.saved.single;
      expect(saved.type, PromptMemoryType.characterOutfit);
      expect(saved.source, PromptMemorySource.pendingLlmCandidate);
      expect(
        PromptMemoryTriggers.parse(saved.trigger),
        ['纳西妲', 'Nahida', 'Lesser Lord Kusanali'],
      );
      expect(result.text, contains('待确认'));
      expect(result.text, contains('尚未生效'));
      expect(result.text, contains('记忆管理页'));
      expect(result.text, contains('临时换装'));
    });

    test(
        'accepts a reference-image recognition description as pending outfit text',
        () async {
      final repository = _FakePromptMemoryRepository();
      final tool = SaveMemoryTool(ManagePromptMemoriesUseCase(repository));

      final result = await tool.call({
        'trigger': '星野爱',
        'content': '参考图可见：黑色舞台连衣裙和红色发饰；鞋子被画面裁切，无法确认。',
        'type': 'character_outfit',
      });

      expect(result.success, isTrue);
      expect(repository.saved.single.content, contains('无法确认'));
      expect(repository.saved.single.source,
          PromptMemorySource.pendingLlmCandidate);
      expect(result.text, contains('待确认'));
    });

    test(
        'rejects invalid types, collection shapes and configured size limits safely',
        () async {
      final repository = _FakePromptMemoryRepository();
      final tool = SaveMemoryTool(ManagePromptMemoriesUseCase(repository));
      final invalidArguments = <Map<String, dynamic>>[
        {'trigger': 42, 'content': 'text'},
        {'trigger': 'name', 'content': null},
        {'trigger': ' | ; ', 'content': 'text'},
        {'trigger': 'name', 'content': 'text', 'type': 'unknown'},
        {'trigger': 'name', 'content': 'text', 'type': 7},
        {'trigger': 'name', 'content': 'text', 'aliases': 'alias'},
        {
          'trigger': 'name',
          'content': 'text',
          'aliases': ['ok', 2]
        },
        {
          'trigger': 'name',
          'content': 'text',
          'aliases': List<String>.generate(13, (index) => 'alias$index'),
        },
        {'trigger': List<String>.filled(513, 'x').join(), 'content': 'text'},
        {'trigger': 'name', 'content': List<String>.filled(6001, 'x').join()},
        {
          'trigger': List<String>.filled(500, 'x').join(),
          'aliases': [
            'an alias that pushes the combined trigger beyond the limit'
          ],
          'content': 'text',
        },
      ];

      for (final arguments in invalidArguments) {
        final result = await tool.call(arguments);
        expect(result.success, isFalse, reason: 'arguments: $arguments');
      }
      expect(repository.saved, isEmpty);
    });
  });

  group('GetMemoriesTool', () {
    test(
        'awaits hit-count updates and returns bounded facts with user-priority policy',
        () async {
      final gate = Completer<void>();
      final memory = PromptMemory(
        id: 3,
        trigger: 'Nahida | 纳西妲',
        content: '衣装描述 ' * 1000,
        type: PromptMemoryType.characterOutfit,
        source: PromptMemorySource.manual,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final repository = _FakePromptMemoryRepository(
        matches: [memory],
        incrementGate: gate,
      );
      final tool = GetMemoriesTool(ManagePromptMemoriesUseCase(repository));

      var completed = false;
      final pending = tool.call({'query': '纳西妲'}).then((result) {
        completed = true;
        return result;
      });
      await Future<void>.delayed(Duration.zero);

      expect(repository.incrementedIds, [3]);
      expect(completed, isFalse, reason: '工具应等待 hit_count 写入结束');
      gate.complete();
      final result = await pending;

      expect(result.success, isTrue);
      expect(result.text, contains(PromptMemoryContext.policy));
      expect(result.text, contains('用户已确认的本地记忆'));
      expect(result.text, isNot(contains('必须遵循')));
      expect(
          result.text.length,
          lessThanOrEqualTo(PromptMemoryContext.maxContextChars +
              PromptMemoryContext.policy.length +
              100));
    });

    test('returns a useful result when hit-count update fails', () async {
      final memory = PromptMemory(
        id: 4,
        trigger: 'cat',
        content: 'small cat',
        type: PromptMemoryType.fact,
        source: PromptMemorySource.manual,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final repository = _FakePromptMemoryRepository(
        matches: [memory],
        incrementThrows: true,
      );
      final result = await GetMemoriesTool(
        ManagePromptMemoriesUseCase(repository),
      ).call({'query': 'cat'});

      expect(result.success, isTrue);
      expect(result.text, contains('small cat'));
      expect(result.text, contains('命中计数未能更新'));
    });

    test('rejects non-string queries without throwing', () async {
      final tool = GetMemoriesTool(
        ManagePromptMemoriesUseCase(_FakePromptMemoryRepository()),
      );
      final result = await tool.call({
        'query': ['not', 'text']
      });
      expect(result.success, isFalse);
      expect(result.text, contains('query 必须是字符串'));
    });
  });
}

class _FakePromptMemoryRepository implements PromptMemoryRepository {
  _FakePromptMemoryRepository({
    this.matches = const [],
    this.incrementGate,
    this.incrementThrows = false,
  });

  final List<PromptMemory> matches;
  final Completer<void>? incrementGate;
  final bool incrementThrows;
  final List<PromptMemory> saved = [];
  final List<int> incrementedIds = [];

  @override
  Future<List<PromptMemory>> getAll() async => matches;

  @override
  Future<List<PromptMemory>> search(String query) async => matches;

  @override
  Future<List<PromptMemory>> matchText(String text) async => matches;

  @override
  Future<PromptMemory> save(PromptMemory memory) async {
    saved.add(memory);
    return memory.copyWith(id: saved.length);
  }

  @override
  Future<PromptMemory> promotePending(
    int id, {
    String? newTrigger,
    String? newContent,
    PromptMemoryType? newType,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> delete(int id) async {}

  @override
  Future<void> incrementHit(int id) async {
    incrementedIds.add(id);
    if (incrementThrows) throw StateError('read-only test fixture');
    await incrementGate?.future;
  }

  @override
  Future<List<PromptMemory>> findConflicts(String trigger) async => const [];

  @override
  Future<List<PromptMemory>> listPending() async => const [];

  @override
  Future<List<PromptMemory>> listStale(
          {Duration olderThan = const Duration(days: 90)}) async =>
      const [];
}
