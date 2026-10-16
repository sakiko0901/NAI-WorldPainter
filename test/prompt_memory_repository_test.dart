import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/models/prompt_memory_model.dart';
import 'package:nai_huishi/data/repositories/prompt_memory_repository_impl.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDirectory;
  late String databasePath;
  late Database db;
  late PromptMemoryRepositoryImpl repository;

  Future<PromptMemory> readMemory(int id) async => PromptMemoryModel.fromDb(
        (await db.query('prompt_memories', where: 'id = ?', whereArgs: [id]))
            .single,
      );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp('prompt-memory-');
    databasePath = p.join(testDirectory.path, 'memory.db');
    db = await _openMemoryDatabase(databasePath);
    repository = PromptMemoryRepositoryImpl(db);
  });

  tearDown(() async {
    await db.close();
    await testDirectory.delete(recursive: true);
  });

  test('matchText keeps n characters and matches normalized English tags',
      () async {
    await repository.save(_memory(
      trigger: '长发',
      content: 'Long Hair, Green Eyes',
      type: PromptMemoryType.characterFeature,
    ));
    final matches = await repository.matchText('long hair green eyes');
    expect(matches, hasLength(1));
    expect(matches.single.content, 'long_hair, green_eyes');
  });

  test('matchText tolerates natural language with one matching token',
      () async {
    await repository.save(_memory(
      trigger: '纳西妲',
      content: 'green_eyes, long_hair',
      type: PromptMemoryType.characterFeature,
    ));
    expect(await repository.matchText('请记住纳西妲应该使用 green eyes'), hasLength(1));
  });

  test('persists aliases across repository instances and a database reopen',
      () async {
    final saved = await repository.save(_memory(
      trigger: '纳西妲 | Lesser Lord Kusanali | Nahida',
      content: '绿色礼服，白色披肩，金色发饰',
      type: PromptMemoryType.characterOutfit,
    ));

    await db.close();
    db = await _openMemoryDatabase(databasePath);
    repository = PromptMemoryRepositoryImpl(db);

    final chinese = await repository.matchText('请保持纳西妲的标准穿搭');
    final english = await repository.matchText('Keep Nahida\'s default outfit');
    final multiWord = await repository.matchText('Lesser Lord Kusanali outfit');

    expect(chinese.map((memory) => memory.id), contains(saved.id));
    expect(english.map((memory) => memory.id), contains(saved.id));
    expect(multiWord.map((memory) => memory.id), contains(saved.id));
    expect(chinese.single.content, '绿色礼服，白色披肩，金色发饰');
  });

  test('matches an English canonical character label with punctuation',
      () async {
    final saved = await repository.save(_memory(
      trigger: '流萤 | firefly_(honkai:_star_rail)',
      content: '银白色短外套，黑色百褶裙',
      type: PromptMemoryType.characterOutfit,
    ));

    final matches = await repository
        .matchText('Use Firefly_(Honkai:_Star_Rail) standard outfit');
    final exactCanonicalName =
        await repository.matchText('firefly_(honkai:_star_rail)');

    expect(matches.map((memory) => memory.id), contains(saved.id));
    expect(exactCanonicalName.map((memory) => memory.id), contains(saved.id));
  });

  test('outfits require a character alias and never match by clothing alone',
      () async {
    final nahida = await repository.save(_memory(
      trigger: '纳西妲 | Nahida',
      content: '白色礼服，绿色披肩',
      type: PromptMemoryType.characterOutfit,
    ));
    final raiden = await repository.save(_memory(
      trigger: '雷电将军 | Raiden Shogun',
      content: '白色礼服，紫色披肩',
      type: PromptMemoryType.characterOutfit,
    ));
    await repository.save(_memory(
      trigger: 'Furina',
      content: '白色礼服，蓝色帽子',
      type: PromptMemoryType.characterOutfit,
      source: PromptMemorySource.pendingLlmCandidate,
    ));
    await repository.save(_memory(
      trigger: 'Nahida',
      content: '白色礼服，隐藏项目数据',
      type: PromptMemoryType.characterOutfit,
      scope: PromptMemoryScope.project,
    ));

    expect(await repository.matchText('白色礼服'), isEmpty);
    expect(
      (await repository.matchText('纳西妲的服装')).map((memory) => memory.id),
      [nahida.id],
    );
    expect(
      (await repository.matchText('Raiden Shogun')).map((memory) => memory.id),
      [raiden.id],
    );
  });

  test('uses the longest alias first and prefers outfit for the same alias',
      () async {
    final broad = await repository.save(_memory(
      trigger: '火',
      content: 'red_hair',
      type: PromptMemoryType.characterFeature,
    ));
    final name = await repository.save(_memory(
      trigger: '火神',
      content: 'mavuika',
      type: PromptMemoryType.characterName,
    ));
    final outfit = await repository.save(_memory(
      trigger: '火神 | Mavuika',
      content: '黑色外套，红色长发',
      type: PromptMemoryType.characterOutfit,
    ));

    final matches = await repository.matchText('请保留火神的标准造型');

    expect(matches.take(3).map((memory) => memory.id), [
      outfit.id,
      name.id,
      broad.id,
    ]);
  });

  test('caps explicit-trigger results at five and keeps outfits first',
      () async {
    final memories = <PromptMemory>[];
    for (var index = 0; index < 6; index++) {
      memories.add(await repository.save(_memory(
        trigger: '角色$index',
        content: '标准衣服$index',
        type: PromptMemoryType.characterOutfit,
      )));
    }
    await repository.save(_memory(
      trigger: '角色0',
      content: '普通角色事实',
      type: PromptMemoryType.fact,
    ));

    final matches = await repository.matchText('角色0，角色1，角色2，角色3，角色4，角色5');

    expect(matches, hasLength(5));
    expect(
        matches
            .every((memory) => memory.type == PromptMemoryType.characterOutfit),
        isTrue);
    expect(
      matches.every((memory) => memories.any((saved) => saved.id == memory.id)),
      isTrue,
    );
  });

  test(
      'promoting a candidate atomically supersedes only the same character outfit',
      () async {
    final oldOutfit = await repository.save(_memory(
      trigger: '纳西妲 | Nahida',
      content: '旧版绿色礼服',
      type: PromptMemoryType.characterOutfit,
    ));
    final feature = await repository.save(_memory(
      trigger: '纳西妲 | Nahida',
      content: 'green_eyes, long_hair',
      type: PromptMemoryType.characterFeature,
    ));
    final name = await repository.save(_memory(
      trigger: '纳西妲 | Nahida',
      content: 'nahida',
      type: PromptMemoryType.characterName,
    ));
    final otherOutfit = await repository.save(_memory(
      trigger: '雷电将军 | Raiden',
      content: '紫色外套',
      type: PromptMemoryType.characterOutfit,
    ));
    final candidate = await repository.save(_memory(
      trigger: '小吉祥草王 | nahida',
      content: '改版白色礼服与金色胸针',
      type: PromptMemoryType.characterOutfit,
      source: PromptMemorySource.pendingLlmCandidate,
    ));

    expect(await repository.matchText('Nahida'), isNot(contains(candidate)));
    expect(
      (await readMemory(oldOutfit.id!)).supersededBy,
      isNull,
      reason: 'pending candidate must not replace an active outfit',
    );

    final promoted = await repository.promotePending(candidate.id!);
    final archivedOld = await readMemory(oldOutfit.id!);
    final unchangedFeature = await readMemory(feature.id!);
    final unchangedName = await readMemory(name.id!);
    final unchangedOther = await readMemory(otherOutfit.id!);

    expect(promoted.source, PromptMemorySource.llmCandidate);
    expect(promoted.content, '改版白色礼服与金色胸针');
    expect(promoted.trigger, contains('纳西妲'));
    expect(archivedOld.supersededBy, candidate.id);
    expect(unchangedFeature.supersededBy, isNull);
    expect(unchangedName.supersededBy, isNull);
    expect(unchangedOther.supersededBy, isNull);
    expect((await readMemory(oldOutfit.id!)).content, '旧版绿色礼服');
  });

  test(
      'active outfit save supersedes overlapping aliases but preserves history',
      () async {
    final old = await repository.save(_memory(
      trigger: 'Nahida | 纳西妲',
      content: '旧标准穿搭',
      type: PromptMemoryType.characterOutfit,
    ));
    final replacement = await repository.save(_memory(
      trigger: '小吉祥草王, nahida',
      content: '新标准穿搭',
      type: PromptMemoryType.characterOutfit,
    ));

    expect((await readMemory(old.id!)).supersededBy, replacement.id);
    expect((await readMemory(old.id!)).content, '旧标准穿搭');
    expect(replacement.trigger, contains('纳西妲'));
  });

  test('saving a pending row as active also supersedes its matching outfit',
      () async {
    final old = await repository.save(_memory(
      trigger: '流萤 | Firefly',
      content: '旧标准穿搭',
      type: PromptMemoryType.characterOutfit,
    ));
    final candidate = await repository.save(_memory(
      trigger: 'Firefly',
      content: '新标准穿搭',
      type: PromptMemoryType.characterOutfit,
      source: PromptMemorySource.pendingLlmCandidate,
    ));

    final activated = await repository.save(candidate.copyWith(
      source: PromptMemorySource.llmCandidate,
    ));

    expect((await readMemory(old.id!)).supersededBy, candidate.id);
    expect(activated.source, PromptMemorySource.llmCandidate);
    expect(activated.trigger, contains('流萤'));
  });

  test('failed alias union leaves candidate and previous outfit unchanged',
      () async {
    final old = await repository.save(_memory(
      trigger: '共享 | ${'旧' * 300}',
      content: '旧标准穿搭',
      type: PromptMemoryType.characterOutfit,
    ));
    final candidate = await repository.save(_memory(
      trigger: '共享 | ${'新' * 300}',
      content: '新标准穿搭',
      type: PromptMemoryType.characterOutfit,
      source: PromptMemorySource.pendingLlmCandidate,
    ));

    await expectLater(
      repository.promotePending(candidate.id!),
      throwsArgumentError,
    );

    expect((await readMemory(old.id!)).supersededBy, isNull);
    expect((await readMemory(candidate.id!)).source,
        PromptMemorySource.pendingLlmCandidate);
  });

  test('editing a confirmed record can explicitly remove an incorrect alias',
      () async {
    final memory = await repository.save(_memory(
      trigger: '纳西妲 | WrongName | Nahida',
      content: '白色披肩',
      type: PromptMemoryType.characterOutfit,
    ));
    await repository.save(memory.copyWith(trigger: '纳西妲 | Nahida'));
    expect(await repository.matchText('draw WrongName'), isEmpty);
    expect(await repository.matchText('画纳西妲'), hasLength(1));
  });

  test('editing an archived outfit cannot supersede the active version',
      () async {
    final archived = await repository.save(_memory(
      trigger: 'Nahida',
      content: 'archived version',
      type: PromptMemoryType.characterOutfit,
    ));
    final staleArchived = archived;
    final current = await repository.save(_memory(
      trigger: 'Nahida',
      content: 'current version',
      type: PromptMemoryType.characterOutfit,
    ));

    await repository
        .save(staleArchived.copyWith(content: 'edited archived version'));

    expect((await readMemory(archived.id!)).supersededBy, current.id);
    expect((await readMemory(current.id!)).supersededBy, isNull);
  });

  test('rejects empty and oversized outfit fields without inserting a row',
      () async {
    final now = DateTime.now();
    Future<PromptMemory> outfit(
            {required String trigger, required String content}) =>
        repository.save(PromptMemory(
          trigger: trigger,
          content: content,
          type: PromptMemoryType.characterOutfit,
          source: PromptMemorySource.manual,
          createdAt: now,
          updatedAt: now,
        ));

    await expectLater(
        outfit(trigger: '  ', content: '服装'), throwsArgumentError);
    await expectLater(
        outfit(trigger: ' | ; ', content: '服装'), throwsArgumentError);
    await expectLater(
        outfit(trigger: '角色', content: '  '), throwsArgumentError);
    await expectLater(
      outfit(trigger: '角' * 513, content: '服装'),
      throwsArgumentError,
    );
    await expectLater(
      outfit(trigger: '角色', content: '衣' * 6001),
      throwsArgumentError,
    );
    expect(await db.query('prompt_memories'), isEmpty);
  });

  test('promotePending normalizes tags and removes the candidate', () async {
    final pending = await repository.save(_memory(
      trigger: '角色特征',
      content: 'Long Hair, GREEN EYES',
      type: PromptMemoryType.other,
      source: PromptMemorySource.pendingLlmCandidate,
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
    final pending = await repository.save(_memory(
      trigger: '角色特征',
      content: '绿色眼睛',
      type: PromptMemoryType.other,
      source: PromptMemorySource.pendingLlmCandidate,
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
    final pending = await repository.save(_memory(
      trigger: '偏好',
      content: '用户喜欢暖色调',
      type: PromptMemoryType.other,
      source: PromptMemorySource.pendingLlmCandidate,
    ));

    final promoted = await repository.promotePending(
      pending.id!,
      newType: PromptMemoryType.preference,
    );

    expect(promoted.content, '用户喜欢暖色调');
    expect(promoted.type, PromptMemoryType.preference);
  });

  test('falls back to LIKE when the FTS table is unavailable', () async {
    await db.close();
    final noFtsPath = p.join(testDirectory.path, 'without-fts.db');
    db = await _openMemoryDatabase(noFtsPath, createFts: false);
    repository = PromptMemoryRepositoryImpl(db);
    await repository.save(_memory(
      trigger: 'background',
      content: 'pastel flowers',
      type: PromptMemoryType.other,
    ));

    final matches = await repository.matchText('soft pastel flowers');

    expect(matches, hasLength(1));
    expect(matches.single.content, 'pastel flowers');
    await repository.save(_memory(
      trigger: '纳西妲 | Nahida',
      content: '白色披肩和绿色连衣裙',
      type: PromptMemoryType.characterOutfit,
    ));
    expect(
        (await repository.matchText('画纳西妲的标准穿搭')).single.content, '白色披肩和绿色连衣裙');
  });

  test('caps query characters and token count before matching', () async {
    await repository.save(_memory(
      trigger: 'BeyondLimit',
      content: 'character alias',
      type: PromptMemoryType.characterOutfit,
    ));

    final overTokenLimit = [
      ...List.generate(32, (index) => 'token$index'),
      'BeyondLimit',
    ].join(' ');
    final overCharacterLimit = '${'x' * 2048} BeyondLimit';

    expect(await repository.matchText(overTokenLimit), isEmpty);
    expect(await repository.matchText(overCharacterLimit), isEmpty);
    expect(await repository.matchText('BeyondLimit ${'noise ' * 1000}'),
        hasLength(1));
  });
}

PromptMemory _memory({
  int? id,
  required String trigger,
  required String content,
  PromptMemoryType type = PromptMemoryType.other,
  PromptMemorySource source = PromptMemorySource.manual,
  PromptMemoryScope scope = PromptMemoryScope.user,
  int? supersededBy,
}) {
  final now = DateTime.now();
  return PromptMemory(
    id: id,
    trigger: trigger,
    content: content,
    type: type,
    source: source,
    scope: scope,
    supersededBy: supersededBy,
    createdAt: now,
    updatedAt: now,
  );
}

Future<Database> _openMemoryDatabase(
  String path, {
  bool createFts = true,
}) async =>
    openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE prompt_memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            trigger TEXT NOT NULL,
            content TEXT NOT NULL,
            type TEXT NOT NULL,
            source TEXT NOT NULL,
            scope TEXT NOT NULL DEFAULT 'user',
            hit_count INTEGER NOT NULL DEFAULT 0,
            last_hit_at INTEGER,
            weight REAL NOT NULL DEFAULT 1.0,
            superseded_by INTEGER,
            embedding BLOB,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        if (!createFts) return;
        try {
          await db.execute('''
            CREATE VIRTUAL TABLE prompt_memories_fts USING fts5(
              "trigger", content, content='prompt_memories', content_rowid='id'
            )
          ''');
          await db.execute('''
            CREATE TRIGGER prompt_memories_ai AFTER INSERT ON prompt_memories BEGIN
              INSERT INTO prompt_memories_fts(rowid, "trigger", content)
              VALUES (new.id, new."trigger", new.content);
            END
          ''');
          await db.execute('''
            CREATE TRIGGER prompt_memories_ad AFTER DELETE ON prompt_memories BEGIN
              INSERT INTO prompt_memories_fts(prompt_memories_fts, rowid, "trigger", content)
              VALUES('delete', old.id, old."trigger", old.content);
            END
          ''');
          await db.execute('''
            CREATE TRIGGER prompt_memories_au AFTER UPDATE ON prompt_memories BEGIN
              INSERT INTO prompt_memories_fts(prompt_memories_fts, rowid, "trigger", content)
              VALUES('delete', old.id, old."trigger", old.content);
              INSERT INTO prompt_memories_fts(rowid, "trigger", content)
              VALUES (new.id, new."trigger", new.content);
            END
          ''');
        } catch (_) {
          // Some SQLite builds omit FTS5; repository tests also exercise that fallback.
        }
      },
    );
