import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/data/datasources/local/database_helper.dart';
import 'package:nai_huishi/data/datasources/local/llm_chat_local_datasource.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v22 migration preserves every session and complete message rows',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('llm-migration-');
    await databaseFactory.setDatabasesPath(directory.path);
    final path = p.join(directory.path, AppConstants.dbName);
    var db = await openDatabase(path, version: 22, onCreate: (db, _) async {
      await db.execute('''CREATE TABLE llm_sessions (
        id TEXT PRIMARY KEY, title TEXT NOT NULL,
        scope TEXT NOT NULL DEFAULT 'general', context_key TEXT,
        prompt_version TEXT NOT NULL DEFAULT 'v5',
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
      )''');
      await db.execute('''CREATE TABLE llm_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL,
        role TEXT NOT NULL, content TEXT NOT NULL, image_path TEXT,
        tool_calls TEXT, interaction_json TEXT, created_at INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES llm_sessions(id) ON DELETE CASCADE
      )''');
      await db.execute(
          'CREATE INDEX idx_llm_messages_session ON llm_messages(session_id, created_at)');
    });
    addTearDown(() async {
      await db.close();
      await directory.delete(recursive: true);
    });
    for (var i = 0; i < 3; i++) {
      await db.insert('llm_sessions', {
        'id': 'legacy-$i',
        'title': '原有标题 $i',
        'scope': i == 0 ? 'general' : 'comic',
        'context_key': i == 1 ? 'branch:legacy-0:1' : null,
        'prompt_version': i == 0 ? 'v4.5' : 'v5',
        'created_at': 1000 + i,
        'updated_at': 2000 + i,
      });
    }
    for (var i = 0; i < 4; i++) {
      await db.insert('llm_messages', {
        'session_id': 'legacy-${i % 2}',
        'role': i.isEven ? 'user' : 'assistant',
        'content': '原正文 $i\n${List.filled(300, '中文%_\\😀').join()}',
        'image_path': '["original-a.png","original-b.png"]',
        'tool_calls': '[{"legacy":"保留 $i"}]',
        'interaction_json': '{"legacy":"追问 $i"}',
        'created_at': 1500 + i,
      });
    }
    final sessions = await db.query('llm_sessions', orderBy: 'id');
    final messages = await db.query('llm_messages', orderBy: 'id');
    await db.close();

    db = await DatabaseHelper.instance.database;
    expect(await db.getVersion(), AppConstants.dbVersion);
    expect(AppConstants.dbVersion, greaterThan(22));
    expect(
      await db.query('llm_sessions', orderBy: 'id'),
      sessions.map((row) => {...row, 'pinned_at': null}).toList(),
    );
    expect(await db.query('llm_messages', orderBy: 'id'), messages);
    final local = LlmChatLocalDatasource(db);
    expect((await local.listSessions()).every((s) => !s.isPinned), isTrue);
    expect((await local.searchSessions('原正文')).map((r) => r.session.id),
        ['legacy-1', 'legacy-0']);
    await local.setSessionPinned('legacy-0', true);
    final pinned = (await local.getSession('legacy-0'))!;
    expect(pinned.createdAt.millisecondsSinceEpoch, 1000);
    expect(pinned.updatedAt.millisecondsSinceEpoch, 2000);

    await db.close();
    db = await openDatabase(path, version: AppConstants.dbVersion);
    expect(await LlmChatLocalDatasource(db).getSession('legacy-0'), pinned);
    expect(await db.query('llm_messages', orderBy: 'id'), messages);
  });
}
