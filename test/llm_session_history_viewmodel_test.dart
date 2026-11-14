import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/llm_session.dart';
import 'package:nai_huishi/domain/entities/llm_session_search_result.dart';

import 'support/chat_memory_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('session pin participates in equality and can be copied or cleared', () {
    final session = LlmSession(
      id: 'session',
      title: '标题',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
    );
    expect(session.isPinned, isFalse);
    final pin = DateTime(2026, 1, 3);
    final pinned = session.copyWith(pinnedAt: pin);
    expect(pinned, isNot(session));
    expect(pinned.isPinned, isTrue);
    expect(pinned.copyWith(title: '新标题').pinnedAt, pin);
    expect(pinned.updatedAt, session.updatedAt);
    expect(pinned.copyWith(clearPinnedAt: true), session);
    expect(LlmSessionSearchResult(session: pinned).snippet, isNull);
  });

  test('pin refreshes session order and listeners without changing active chat',
      () async {
    final repository = FakeLlmChatRepository();
    final older = await repository.createSession(initialTitle: '旧会话');
    final newer = await repository.createSession(initialTitle: '新会话');
    await repository.saveUserMessage(sessionId: newer.id, userText: '当前正文');
    final harness = createChatMemoryHarness(chatRepository: repository);
    addTearDown(harness.dispose);
    final vm = harness.viewModel;
    await vm.ensureInitialized();
    final originalMessages = vm.messages;
    var notifications = 0;
    vm.addListener(() => notifications++);

    await vm.setSessionPinned(older.id, true);
    expect(notifications, 1);
    expect(vm.sessions.map((s) => s.id), [older.id, newer.id]);
    expect(vm.sessions.first.isPinned, isTrue);
    expect(vm.sessions.first.updatedAt, older.updatedAt);
    expect(vm.activeSessionId, newer.id);
    expect(vm.messages, originalMessages);

    await vm.setSessionPinned(older.id, false);
    expect(notifications, 2);
    expect(vm.sessions, [newer, older]);
    expect(vm.activeSessionId, newer.id);
    expect(vm.messages, originalMessages);
  });

  test('new active sessions stay below pinned history in the session list',
      () async {
    final harness = createChatMemoryHarness();
    addTearDown(harness.dispose);
    final vm = harness.viewModel;
    await vm.ensureInitialized();
    final pinnedId = vm.activeSessionId!;
    await vm.setSessionPinned(pinnedId, true);
    await vm.createNewSession();
    expect(vm.sessions.first.id, pinnedId);
    expect(vm.sessions.last.id, vm.activeSessionId);
    expect(vm.activeSession!.isPinned, isFalse);
    expect((await vm.searchSessions('')).map((r) => r.session), vm.sessions);
  });

  test('search finds inactive message text and leaves loaded chat untouched',
      () async {
    final repository = FakeLlmChatRepository();
    final history = await repository.createSession(initialTitle: '历史');
    await repository.saveUserMessage(
      sessionId: history.id,
      userText: r'角色 NaHiDa 50%_\',
    );
    final current = await repository.createSession(initialTitle: '当前');
    final harness = createChatMemoryHarness(chatRepository: repository);
    addTearDown(harness.dispose);
    final vm = harness.viewModel;
    await vm.ensureInitialized();
    final originalSessions = vm.sessions;
    final originalMessages = vm.messages;
    var notifications = 0;
    vm.addListener(() => notifications++);
    for (final query in ['角色', 'NAHIDA', '%', '_', r'\']) {
      final result = (await vm.searchSessions(query)).single;
      expect(result.session.id, history.id);
      expect(result.snippet, r'角色 NaHiDa 50%_\');
    }
    expect(await vm.searchSessions('不存在'), isEmpty);
    expect((await vm.searchSessions(' \t')).map((r) => r.session),
        originalSessions);
    expect(vm.sessions, originalSessions);
    expect(vm.activeSessionId, current.id);
    expect(vm.messages, originalMessages);
    expect(notifications, 0);
  });
}
