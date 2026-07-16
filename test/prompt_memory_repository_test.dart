import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/datasources/local/database_helper.dart';
import 'package:nai_huishi/data/repositories/prompt_memory_repository_impl.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late PromptMemoryRepositoryImpl repository;

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    db = await DatabaseHelper.instance.database;
    await db.delete('prompt_memories');
    repository = PromptMemoryRepositoryImpl(db);
  });

  tearDown(() async {
    await db.delete('prompt_memories');
  });

  test('matchText keeps n characters and matches normalized English tags',
      () async {
    final now = DateTime.now();
    await repository.save(PromptMemory(
      trigger: '长发',
      content: 'Long Hair, Green Eyes',
      type: PromptMemoryType.characterFeature,
      source: PromptMemorySource.manual,
      createdAt: now,
      updatedAt: now,
    ));

    final matches = await repository.matchText('long hair green eyes');

    expect(matches, hasLength(1));
    expect(matches.single.content, 'long_hair, green_eyes');
  });

  test('matchText tolerates natural language with one matching token',
      () async {
    final now = DateTime.now();
    await repository.save(PromptMemory(
      trigger: '纳西妲',
      content: 'green_eyes, long_hair',
      type: PromptMemoryType.characterFeature,
      source: PromptMemorySource.manual,
      createdAt: now,
      updatedAt: now,
    ));

    final matches = await repository.matchText('请记住纳西妲应该使用 green eyes');

    expect(matches, hasLength(1));
  });

  test('promotePending normalizes tags and removes the candidate', () async {
    final now = DateTime.now();
    final pending = await repository.save(PromptMemory(
      trigger: '角色特征',
      content: 'Long Hair, GREEN EYES',
      type: PromptMemoryType.other,
      source: PromptMemorySource.pendingLlmCandidate,
      createdAt: now,
      updatedAt: now,
    ));

    final promoted = await repository.promotePending(
      pending.id!,
      newType: PromptMemoryType.characterFeature,
    );

    expect(promoted.content, 'long_hair, green_eyes');
    expect(promoted.source, PromptMemorySource.llmCandidate);
    expect(await repository.listPending(), isEmpty);
    expect((await repository.getAll()).single.id, pending.id);
  });

  test('promotePending keeps an invalid legacy tag candidate', () async {
    final now = DateTime.now();
    final pending = await repository.save(PromptMemory(
      trigger: '角色特征',
      content: '绿色眼睛',
      type: PromptMemoryType.other,
      source: PromptMemorySource.pendingLlmCandidate,
      createdAt: now,
      updatedAt: now,
    ));

    await expectLater(
      repository.promotePending(
        pending.id!,
        newType: PromptMemoryType.characterFeature,
      ),
      throwsArgumentError,
    );

    final candidates = await repository.listPending();
    expect(candidates.single.id, pending.id);
    expect(candidates.single.content, '绿色眼睛');
  });

  test('promotePending allows natural language for non-tag memories', () async {
    final now = DateTime.now();
    final pending = await repository.save(PromptMemory(
      trigger: '偏好',
      content: '用户喜欢暖色调',
      type: PromptMemoryType.other,
      source: PromptMemorySource.pendingLlmCandidate,
      createdAt: now,
      updatedAt: now,
    ));

    final promoted = await repository.promotePending(
      pending.id!,
      newType: PromptMemoryType.preference,
    );

    expect(promoted.content, '用户喜欢暖色调');
    expect(promoted.type, PromptMemoryType.preference);
  });
}
