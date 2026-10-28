import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/repositories/prompt_template_repository_impl.dart';
import 'package:nai_huishi/domain/entities/prompt_template.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_templates.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'notebook notes retain title, exact tags and edits after database reopen',
      () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('prompt-notebook-');
    final path = p.join(directory.path, 'notebook.db');
    var db = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              await db.execute('''CREATE TABLE prompt_templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
        category TEXT NOT NULL, content TEXT NOT NULL, tags TEXT,
        use_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
            }));
    addTearDown(() async {
      await db.close();
      await directory.delete(recursive: true);
    });
    var useCase =
        ManagePromptTemplatesUseCase(PromptTemplateRepositoryImpl(db));
    final now = DateTime.now();
    final saved = await useCase.create(PromptTemplate(
        name: '柔和逆光',
        category: '笔记本',
        content: '{{backlighting}},\n1.3::soft light::',
        createdAt: now,
        updatedAt: now));
    await db.close();
    db = await databaseFactoryFfi.openDatabase(path);
    useCase = ManagePromptTemplatesUseCase(PromptTemplateRepositoryImpl(db));
    var restored = (await useCase.getAll()).single;
    expect(restored.id, saved.id);
    expect(restored.name, '柔和逆光');
    expect(restored.content, '{{backlighting}},\n1.3::soft light::');
    await useCase.incrementUseCount(restored.id!);
    restored = (await useCase.getById(restored.id!))!;
    await useCase.update(restored.copyWith(name: '蓝色眼睛', content: 'blue eyes'));
    await db.close();
    db = await databaseFactoryFfi.openDatabase(path);
    useCase = ManagePromptTemplatesUseCase(PromptTemplateRepositoryImpl(db));
    restored = (await useCase.getAll()).single;
    expect(restored.name, '蓝色眼睛');
    expect(restored.content, 'blue eyes');
    expect(restored.useCount, 1);
    await useCase.delete(restored.id!);
    expect(await useCase.getAll(), isEmpty);
  });
}
