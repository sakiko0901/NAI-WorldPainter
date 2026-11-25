import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/data/datasources/local/database_helper.dart';
import 'package:nai_huishi/data/datasources/local/llm_chat_local_datasource.dart';
import 'package:nai_huishi/data/datasources/remote/llm_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/wd_tagger_api_service.dart';
import 'package:nai_huishi/data/repositories/llm_chat_repository_impl.dart';
import 'package:nai_huishi/data/repositories/history_repository_impl.dart';
import 'package:nai_huishi/domain/agents/tool_registry.dart';
import 'package:nai_huishi/domain/agents/tools/ask_user_tool.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/domain/entities/llm_response.dart';
import 'package:nai_huishi/domain/entities/llm_session.dart';
import 'package:nai_huishi/domain/entities/nai_prompt_version.dart';
import 'package:nai_huishi/domain/entities/tool_call.dart';
import 'package:nai_huishi/domain/usecases/get_history.dart';
import 'package:nai_huishi/domain/usecases/manage_llm_chat.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_memories.dart';
import 'package:nai_huishi/domain/usecases/manage_settings.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/chat_memory_fake.dart';
import 'support/frontend_generation_fake.dart';

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
    await db.delete('generation_history');
    bindDatabase();
  });

  tearDownAll(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  LlmChatViewModel assistant(
    RecordingLlmApiService api,
    FrontendGenerationFake generation,
    ToolRegistry tools,
  ) {
    final history = HistoryRepositoryImpl(db);
    LlmChatViewModel.apiServiceSingleton = api;
    LlmChatViewModel.toolRegistrySingleton = tools;
    final viewModel = LlmChatViewModel(
      manageChat: chat,
      manageSettings:
          ManageSettingsUseCase(FakeSettingsRepository(systemPrompt: '测试助手')),
      memories: ManagePromptMemoriesUseCase(
          FakePromptMemoryRepository(memories: [], readFails: false)),
      genVm: generation,
      analyzeImageTags: FakeAnalyzeImageTagsUseCase(
          const WdTaggerResult(generalTags: {}, characterTags: {})),
      getHistory: GetHistoryUseCase(history),
      saveImage: SaveImageUseCase(history),
    );
    addTearDown(viewModel.dispose);
    return viewModel;
  }

  test('keeps streamed prose and resumes with the persisted choice details',
      () async {
    final api = RecordingLlmApiService(
      visionDescription: '',
      visionFails: false,
      mainResponses: const [
        LlmResponse(
          content: '先保留风衣和街景。',
          toolCalls: [
            ToolCall(id: 'missing', name: 'unknown_tool', arguments: {}),
          ],
          finishReason: 'tool_calls',
        ),
        LlmResponse(
          content: '再比较这四套灯光。',
          toolCalls: [
            ToolCall(id: 'q', name: 'ask_user', arguments: {
              'question': '选择哪套灯光？',
              'options': [
                {'id': 'a', 'label': '白昼'},
                {'id': 'b', 'label': '阴天'},
                {'id': 'c', 'label': '夜景', 'value': '霓虹侧逆光加湿路反射'},
                {'id': 'd', 'label': '昏暮'},
              ],
            }),
          ],
          finishReason: 'tool_calls',
        ),
      ],
    );
    final generation = FrontendGenerationFake();
    addTearDown(generation.dispose);
    final vm =
        assistant(api, generation, ToolRegistry()..register(AskUserTool()));
    await vm.ensureInitialized();
    await vm.sendUserMessage('给我四个灯光方案');
    expect(api.streamRequests, 2);
    final sessionId = vm.activeSessionId!;
    final reply = vm.messages.last;
    const prose = '先保留风衣和街景。\n\n再比较这四套灯光。\n\n选择哪套灯光？';
    expect(reply.content, prose);
    expect(reply.interaction!.options, hasLength(4));
    await vm.createNewSession();
    await vm.selectSession(sessionId);
    expect(vm.messages.last.content, prose);

    await vm.answerInteraction(message: vm.messages.last, optionId: 'c');

    final request = api.mainCalls.last;
    final previousReply =
        request.messages.singleWhere((m) => m['role'] == 'assistant');
    expect(
        previousReply['content'],
        allOf(
          contains(prose),
          contains('白昼'),
          contains('阴天'),
          contains('夜景（霓虹侧逆光加湿路反射）（用户已选择）'),
          contains('昏暮'),
        ));
    expect(request.lastUserText, contains('我选择：夜景（霓虹侧逆光加湿路反射）'));
    await reopen();
    final stored = await chat.listMessages(sessionId);
    expect(stored, hasLength(4));
    expect(stored[1].content, prose);
    expect(stored[1].interaction!.selectedOption!.label, '夜景');
    expect(stored[2].content, request.lastUserText);
  });

  for (final direct in [true, false]) {
    test('opens current, latest and matching history pixels (direct=$direct)',
        () async {
      Future<String> writePng(String name, int red) async {
        final image = img.Image(width: 16, height: 12);
        image.setPixelRgb(0, 0, red, 10, 20);
        final file = File(p.join(directory.path, '$name.png'));
        await file.writeAsBytes(img.encodePng(image));
        return file.path;
      }

      final latest = frontendResult(
          id: 'workspace-new', imagePath: await writePng('workspace-new', 200));
      final selected = frontendResult(
        id: 'workspace-selected',
        imagePath: await writePng('workspace-selected', 135),
      );
      final historicalPath = await writePng('history-older', 80);
      String? imageUrl;
      if (!direct) {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          request.response.headers.contentType = ContentType('image', 'png');
          await request.response.addStream(File(historicalPath).openRead());
          await request.response.close();
        });
        imageUrl = 'http://127.0.0.1:${server.port}/result.png';
        const channel = MethodChannel('plugins.flutter.io/path_provider');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
            channel, (_) async => directory.path);
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      }
      final history = frontendResult(
        id: 'history-older',
        imagePath: direct ? historicalPath : null,
      ).copyWith(prompt: 'winter, pine forest', imageUrl: imageUrl);
      final gallery = HistoryRepositoryImpl(db);
      await gallery.saveTask(history);
      await gallery.toggleFavorite(history.taskId);
      final generation = FrontendGenerationFake()
        ..receive(selected)
        ..receive(latest)
        ..selectResult(selected.taskId);
      addTearDown(generation.dispose);
      final api = RecordingLlmApiService(
        visionDescription: '识图模型观察到树林和白雪。',
        visionFails: false,
        mainResponses: const [
          LlmResponse(
              content: '',
              toolCalls: [
                ToolCall(
                    id: 'list',
                    name: 'list_generation_images',
                    arguments: {
                      'source': 'history',
                      'query': 'winter forest',
                    }),
              ],
              finishReason: 'tool_calls'),
          LlmResponse(
              content: '',
              toolCalls: [
                ToolCall(id: 'new', name: 'view_generation_image', arguments: {
                  'source': 'latest',
                }),
                ToolCall(id: 'pick', name: 'view_generation_image', arguments: {
                  'source': 'current',
                }),
                ToolCall(id: 'old', name: 'view_generation_image', arguments: {
                  'source': 'history',
                  'task_id': 'history-older',
                  'focus': '树林',
                }),
              ],
              finishReason: 'tool_calls'),
        ],
      );
      final vm = assistant(api, generation, ToolRegistry());
      await vm.ensureInitialized();
      await vm.setMultimodal(direct);
      await HttpOverrides.runWithHttpOverrides(
        () => vm.sendUserMessage('比较刚生成的图、工作台选中的图和历史的冬日树林图'),
        _RealHttpOverrides(),
      );

      expect(vm.errorMessage, isNull);
      expect(api.mainCalls, hasLength(3));
      expect(
          api.mainCalls[1].messages.last['content'], contains('history-older'));
      final finalRequest = api.mainCalls.last.messages;
      final toolMessages = finalRequest.where((m) => m['role'] == 'tool');
      expect(
          toolMessages.map((m) => m['content']),
          containsAll([
            contains('workspace-new'),
            contains('workspace-selected'),
            contains('history-older'),
          ]));
      List<int> imageRed(CapturedLlmCall call) {
        return call.messages
            .where((m) => m['content'] is List)
            .expand((m) => m['content'] as List)
            .where((part) => part['type'] == 'image_url')
            .map<int>((part) {
          final url = part['image_url']['url'] as String;
          expect(url, startsWith('data:image/png;base64,'));
          return img
              .decodePng(base64Decode(url.split(',').last))!
              .getPixel(0, 0)
              .r
              .toInt();
        }).toList();
      }

      if (direct) {
        expect(finalRequest.last['role'], 'user');
        expect(imageRed(api.mainCalls.last), [200, 135, 80]);
        expect(api.visionCalls, isEmpty);
      } else {
        expect(imageRed(api.mainCalls.last), isEmpty);
        expect(api.visionCalls.expand(imageRed), [200, 135, 80]);
        expect(toolMessages.last['content'], contains('识图模型观察到树林和白雪。'));
      }
      final saved = (await chat.listMessages(vm.activeSessionId!)).last;
      expect(saved.modelContextContent,
          allOf(contains('workspace-new'), contains('history-older')));
      expect(saved.toolCallsJson, isNot(contains('base64')));
      expect((await gallery.getFavorites()).single.taskId, history.taskId);
      expect((await gallery.getTask(history.taskId))!.imagePath,
          history.imagePath);
      expect(
          directory.listSync().where(
              (item) => p.basename(item.path).startsWith('assistant-image-')),
          isEmpty);
    });
  }

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

class _RealHttpOverrides extends HttpOverrides {}

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
