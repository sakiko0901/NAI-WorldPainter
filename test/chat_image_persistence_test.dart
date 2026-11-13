import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nai_huishi/data/datasources/local/llm_chat_local_datasource.dart';
import 'package:nai_huishi/data/datasources/remote/llm_api_service.dart';
import 'package:nai_huishi/data/repositories/llm_chat_repository_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('multiple attachments survive reload and are cleaned with their message',
      () async {
    sqfliteFfiInit();
    final directory =
        await Directory.systemTemp.createTemp('chat-images-test-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      await db.execute(
          'CREATE TABLE llm_sessions (id TEXT PRIMARY KEY, title TEXT, scope TEXT, context_key TEXT, prompt_version TEXT, created_at INTEGER, updated_at INTEGER)');
      await db.execute(
          'CREATE TABLE llm_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT, role TEXT, content TEXT, image_path TEXT, tool_calls TEXT, interaction_json TEXT, created_at INTEGER)');
      final local = LlmChatLocalDatasource(db);
      final repo =
          LlmChatRepositoryImpl(local: local, api: LlmApiService(Dio()));
      final session = await repo.createSession();
      final id = await repo.saveUserMessage(
          sessionId: session.id,
          userText: '两张参考图',
          imageBase64s: ['AQIDBA==', 'BQYHCA==']);
      final reloaded = (await local.listMessages(session.id)).single;
      expect(reloaded.allImagePaths, hasLength(2));
      expect(reloaded.imagePath, reloaded.allImagePaths.first);
      expect(await File(reloaded.allImagePaths[0]).readAsBytes(), [1, 2, 3, 4]);
      expect(await File(reloaded.allImagePaths[1]).readAsBytes(), [5, 6, 7, 8]);
      await repo.saveAgentRunResult(
          sessionId: session.id, assistantText: '已识别');
      final nextId =
          await repo.saveUserMessage(sessionId: session.id, userText: '修改构图');
      final branch = await repo.forkSession(session.id, nextId);
      expect(branch.parentSessionId, session.id);
      final branchMessages = await repo.listMessages(branch.id);
      expect(branchMessages, hasLength(2));
      expect(branchMessages.first.allImagePaths, isNot(reloaded.allImagePaths));
      await repo.deleteMessagesFrom(id, session.id);
      for (final path in branchMessages.first.allImagePaths) {
        expect(await File(path).exists(), isTrue);
      }
      await repo.deleteSession(branch.id);
      for (final path in branchMessages.first.allImagePaths) {
        expect(await File(path).exists(), isFalse);
      }
      expect(await local.listMessages(session.id), isEmpty);
      for (final path in reloaded.allImagePaths) {
        expect(await File(path).exists(), isFalse);
      }
    } finally {
      await db.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    }
  });
}
