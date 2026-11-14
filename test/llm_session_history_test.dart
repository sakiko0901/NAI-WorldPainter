import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/data/datasources/local/database_helper.dart';
import 'package:nai_huishi/data/datasources/local/llm_chat_local_datasource.dart';
import 'package:nai_huishi/data/datasources/remote/llm_api_service.dart';
import 'package:nai_huishi/data/repositories/llm_chat_repository_impl.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/domain/entities/llm_session.dart';
import 'package:nai_huishi/domain/entities/nai_prompt_version.dart';
import 'package:nai_huishi/domain/usecases/manage_llm_chat.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Database db;
  late LlmChatLocalDatasource local;
  late ManageLlmChatUseCase chat;

  void bindDatabase() {
    local = LlmChatLocalDatasource(db);
    chat = ManageLlmChatUseCase(
      LlmChatRepositoryImpl(local: local, api: LlmApiService(Dio())),
    );
  }

  Future<void> reopen() async {
    final path = db.path;
    await db.close();
    db = await databaseFactoryFfi.openDatabase(path);
    bindDatabase();
  }

  Future<LlmSession> seed(
    String id, {
    String title = '普通会话',
    int updated = 2000,
    int? pinned,
  }) async {
    final session = LlmSession(
      id: id,
      title: title,
      scope: 'comic',
      contextKey: 'context:$id',
      promptVersion: NaiPromptVersion.v5,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updated),
      pinnedAt:
          pinned == null ? null : DateTime.fromMillisecondsSinceEpoch(pinned),
    );
    await local.insertSession(session);
    return session;
  }

  Future<void> message(
    String id,
    String content, {
    int created = 3000,
    LlmMessageRole role = LlmMessageRole.user,
  }) async {
    await local.insertMessage(LlmMessage(
      sessionId: id,
      role: role,
      content: content,
      createdAt: DateTime.fromMillisecondsSinceEpoch(created),
    ));
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('llm-history-');
    await databaseFactory.setDatabasesPath(directory.path);
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await db.delete('llm_messages');
    await db.delete('llm_sessions');
    bindDatabase();
  });

  tearDownAll(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test('fresh database has a nullable integer pin column', () async {
    expect(db.path, p.join(directory.path, AppConstants.dbName));
    expect(await db.getVersion(), AppConstants.dbVersion);
    final columns = await db.rawQuery('PRAGMA table_info(llm_sessions)');
    final pin = columns.singleWhere((column) => column['name'] == 'pinned_at');
    expect(pin['type'], 'INTEGER');
    expect(pin['notnull'], 0);
    expect(pin['dflt_value'], isNull);
    final session = await chat.createSession(initialTitle: '新会话');
    expect((await local.getSession(session.id))!.isPinned, isFalse);
  });

  test('pin and unpin survive reopen without changing session data or messages',
      () async {
    final original = await seed('history');
    await message(original.id, '原有正文\n100%_完整保留');
    final messages = await db.query('llm_messages');

    await chat.setSessionPinned(original.id, true);
    final pinned = (await local.getSession(original.id))!;
    expect(pinned.pinnedAt, isNotNull);
    expect(pinned.copyWith(clearPinnedAt: true), original);
    await reopen();
    expect(await local.getSession(original.id), pinned);
    expect(await chat.findSessionByContextKey(original.contextKey!), pinned);

    await chat.setSessionPinned(original.id, true);
    expect(await local.getSession(original.id), pinned);
    await chat.setSessionPinned("missing' OR 1=1 --", false);
    expect(await local.getSession(original.id), pinned);
    await chat.setSessionPinned(original.id, false);
    await reopen();
    expect(await local.getSession(original.id), original);
    await chat.setSessionPinned(original.id, false);
    await chat.setSessionPinned('missing', true);
    expect(await local.getSession(original.id), original);
    expect(await db.query('llm_messages'), messages);
  });

  test(
      'all history queries sort by pin status then updated time, with stable ties',
      () async {
    await seed('unpinned-new', title: '共同', updated: 9000);
    await seed('pinned-old', title: '共同', updated: 2000, pinned: 9000);
    await seed('pinned-new', title: '共同', updated: 3000, pinned: 1000);
    await seed('tie-b', title: '共同');
    await seed('tie-a', title: '共同');
    const expected = [
      'pinned-new',
      'pinned-old',
      'unpinned-new',
      'tie-a',
      'tie-b'
    ];
    expect((await chat.listSessions()).map((s) => s.id), expected);
    for (final query in ['', ' \n\t ', '共同']) {
      final results = await chat.searchSessions(query);
      expect(results.map((r) => r.session.id), expected);
      expect(results.every((r) => r.snippet == null), isTrue);
    }
    await chat.setSessionPinned('pinned-new', false);
    expect((await chat.listSessions()).map((s) => s.id),
        ['pinned-old', 'unpinned-new', 'pinned-new', 'tie-a', 'tie-b']);
  });

  test('message and title updates preserve an independently changed pin',
      () async {
    final stale = await seed('history');
    await chat.setSessionPinned(stale.id, true);
    final pin = (await local.getSession(stale.id))!.pinnedAt;
    await local.updateSession(stale.copyWith(title: '旧快照修改标题'));
    expect((await local.getSession(stale.id))!.pinnedAt, pin);
    await chat.saveUserMessage(sessionId: stale.id, userText: '第一条用户消息');
    await chat.renameSession(stale.id, '重新命名');
    await chat.setSessionPromptVersion(stale.id, NaiPromptVersion.v45);
    await chat.saveAgentRunResult(sessionId: stale.id, assistantText: '助手回复');
    final updated = (await local.getSession(stale.id))!;
    expect(updated.pinnedAt, pin);
    expect(updated.title, '重新命名');
    expect(updated.createdAt, stale.createdAt);
    expect(updated.updatedAt.isAfter(stale.updatedAt), isTrue);
    await chat.setSessionPinned(stale.id, false);
    expect(await local.getSession(stale.id),
        updated.copyWith(clearPinnedAt: true));
    // An earlier pinned snapshot must not re-pin the session either.
    await local.updateSession(updated);
    expect((await local.getSession(stale.id))!.isPinned, isFalse);
  });

  test('search matches Chinese and ASCII case in titles and both message roles',
      () async {
    await seed('title', title: '角色设计 NaHiDa', updated: 5000);
    await seed('user', updated: 4000);
    await seed('assistant', updated: 3000, pinned: 100);
    await seed('neither', title: '空会话', updated: 6000);
    await message('title', '与关键词无关的正文');
    await message('user', '先前讨论：角色设计 NAHIDA');
    await message('assistant', '角色设计 nahida 的新方案',
        role: LlmMessageRole.assistant);
    for (final query in ['角色设计', 'nahida', 'NAHIDA', ' NaHiDa ']) {
      final results = await chat.searchSessions(query);
      expect(results.map((r) => r.session.id), ['assistant', 'title', 'user']);
      expect(results.first.snippet, '角色设计 nahida 的新方案');
      expect(results[1].snippet, isNull);
      expect(results.last.snippet, '先前讨论：角色设计 NAHIDA');
    }
    expect(await chat.searchSessions('不存在的关键词'), isEmpty);
  });

  test('search uses the newest matching message once per session', () async {
    await seed('history', title: '匹配标题');
    await message('history', '匹配 最早', created: 1000);
    await message('history', '匹配 同时第一条', created: 3000);
    await message('history', '匹配 同时第二条', created: 3000);
    await message('history', '匹配 后插入但更旧', created: 2000);
    await message('history', '最新但无关的消息', created: 4000);
    final result = (await chat.searchSessions('匹配')).single;
    expect(result.session.id, 'history');
    expect(result.snippet, '匹配 同时第二条');
    expect((await chat.searchSessions('')).single.snippet, isNull);
  });

  for (final keyword in ['%', '_', r'\', r'50%_\Done', "' OR 1=1 --", '?']) {
    test('search treats $keyword literally in titles and messages', () async {
      await seed('title', title: '前缀 $keyword 后缀', updated: 4000);
      await seed('body');
      await seed('decoy', title: '50xyzADone 普通标题', updated: 5000);
      await message('body', '正文 $keyword 尾部');
      await message('decoy', '50xyzADone 普通正文');
      final results = await chat.searchSessions(keyword);
      expect(results.map((r) => r.session.id), ['title', 'body']);
      expect(results.first.snippet, isNull);
      expect(results.last.snippet, contains(keyword));
    });
  }

  test('one SQL query returns bounded snippets around distant Unicode matches',
      () async {
    await seed('long');
    final prefix = List.filled(2000, '😀前').join();
    final suffix = List.filled(2000, '后😀').join();
    await message('long', '${prefix}MiXeD中文$suffix');
    final recording = _RecordingDatabase(db);
    final search = LlmChatLocalDatasource(recording);
    final result = (await search.searchSessions('mixed中文')).single;
    expect(result.snippet, contains('MiXeD中文'));
    expect(result.snippet!.runes.length, 160);
    expect(result.snippet!.runes.take(40).toList(),
        List.filled(20, '😀前').join().runes.toList());
    expect(recording.calls, hasLength(1));
    expect(recording.calls.single.arguments,
        ['mixed中文', '%mixed中文%', '%mixed中文%']);
    expect(recording.rows.single.keys, isNot(contains('content')));
    expect(recording.rows.single['snippet'], result.snippet);
  });

  test(
      'snippets handle a match at the beginning or end without splitting emoji',
      () async {
    await seed('begin');
    await seed('end');
    await message('begin', '目标😀${List.filled(300, '后').join()}');
    await message('end', '${List.filled(300, '😀前').join()}目标😀');
    final results = await chat.searchSessions('目标');
    expect(results.first.snippet!.startsWith('目标😀'), isTrue);
    expect(results.first.snippet!.runes.length, 160);
    expect(results.last.snippet!.endsWith('目标😀'), isTrue);
    expect(results.last.snippet!.runes.length, 43);
  });
}

class _RecordingDatabase implements Database {
  _RecordingDatabase(this.inner);

  final Database inner;
  final calls = <({String sql, List<Object?>? arguments})>[];
  List<Map<String, Object?>> rows = [];

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    calls.add((sql: sql, arguments: arguments));
    return rows = await inner.rawQuery(sql, arguments);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
