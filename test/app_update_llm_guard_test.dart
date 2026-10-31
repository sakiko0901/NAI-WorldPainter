import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/services/app_update_install_guard.dart';
import 'package:nai_huishi/domain/entities/llm_interaction.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';

import 'support/chat_memory_fake.dart';

/// These gates sit at repository awaits which used to happen before send's
/// update guard, including the destructive truncation of conversation history.
class _GatedRepository extends FakeLlmChatRepository {
  final deleteEntered = Completer<void>();
  final answerEntered = Completer<void>();
  Completer<void>? deleteGate;
  Completer<void>? answerGate;
  int deleteCalls = 0;
  int answerCalls = 0;
  bool failDelete = false;
  final _deletedIds = <int>{};
  final _replacements = <int, LlmMessage>{};

  @override
  Future<List<LlmMessage>> listMessages(String sessionId) async =>
      (await super.listMessages(sessionId))
          .where((message) => !_deletedIds.contains(message.id))
          .map((message) => _replacements[message.id] ?? message)
          .toList();

  @override
  Future<void> deleteMessagesFrom(int messageId, String sessionId) async {
    deleteCalls++;
    if (!deleteEntered.isCompleted) deleteEntered.complete();
    await deleteGate?.future;
    if (failDelete) throw StateError('database deletion failed');
    for (final message in await super.listMessages(sessionId)) {
      if (message.id! >= messageId) _deletedIds.add(message.id!);
    }
  }

  @override
  Future<LlmMessage?> answerInteraction({
    required String sessionId,
    required int messageId,
    required String interactionId,
    String? optionId,
    String? customAnswer,
  }) async {
    answerCalls++;
    if (!answerEntered.isCompleted) answerEntered.complete();
    await answerGate?.future;
    final question = (await listMessages(sessionId))
        .firstWhere((message) => message.id == messageId);
    final interaction = question.interaction!;
    if (interaction.id != interactionId) return null;
    final answered = optionId == null
        ? interaction.answerCustom(customAnswer!)
        : interaction.answerOption(optionId);
    _replacements[messageId] = question.copyWith(interaction: answered);
    final id = await super
        .saveUserMessage(sessionId: sessionId, userText: answered.answerText!);
    return (await listMessages(sessionId))
        .firstWhere((message) => message.id == id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppUpdateInstallGuard guard;
  late _GatedRepository repository;
  ChatMemoryHarness? harness;

  setUp(() {
    guard = AppUpdateInstallGuard();
    repository = _GatedRepository();
    harness = null;
  });

  tearDown(() {
    harness?.dispose();
    guard.dispose();
  });

  Future<ChatMemoryHarness> start({bool question = false}) async {
    final session = await repository.createSession();
    if (question) {
      await repository.saveAgentRunResult(
        sessionId: session.id,
        assistantText: '请选择构图',
        interaction: LlmInteraction(
          id: 'choose-composition',
          question: '请选择构图',
          options: const [LlmInteractionOption(id: 'wide', label: '全景')],
          createdAt: DateTime(2026, 10, 31),
        ),
      );
    } else {
      await repository.saveUserMessage(sessionId: session.id, userText: '原始问题');
      await repository.saveAgentRunResult(
          sessionId: session.id, assistantText: '原始回答');
    }
    final created =
        createChatMemoryHarness(chatRepository: repository, updateGuard: guard);
    harness = created;
    await created.viewModel.ensureInitialized();
    return created;
  }

  for (final edit in [false, true]) {
    final action = edit ? 'editAndResend' : 'retryFromIndex';
    test('$action blocks installation throughout the history deletion await',
        () async {
      final h = await start();
      final vm = h.viewModel;
      repository.deleteGate = Completer<void>();
      final pending =
          edit ? vm.editAndResend(0, '修改后的问题') : vm.retryFromIndex(0);
      expect(guard.tryBeginInstall(), isFalse,
          reason: 'Protection must be acquired before the first await');
      await repository.deleteEntered.future;
      expect(vm.isSending, isFalse,
          reason: 'This is the old unprotected preparation window');
      expect(guard.tryBeginInstall(), isFalse);
      expect(await repository.listMessages(vm.activeSessionId!), hasLength(2));
      repository.deleteGate!.complete();
      await pending;
      final saved = await repository.listMessages(vm.activeSessionId!);
      expect(repository.deleteCalls, 1);
      expect(h.api.mainCalls, hasLength(1));
      expect(
          saved
              .where((message) => message.role == LlmMessageRole.user)
              .single
              .content,
          edit ? '修改后的问题' : '原始问题');
      expect(guard.tryBeginInstall(), isTrue,
          reason:
              'The activity must be released after persistence and response');
    });

    test(
        '$action refuses before deleting history when installation already owns the lock',
        () async {
      final h = await start();
      final vm = h.viewModel;
      final before = await repository.listMessages(vm.activeSessionId!);
      expect(guard.tryBeginInstall(), isTrue);
      if (edit) {
        await vm.editAndResend(0, '不应落盘的新问题');
      } else {
        await vm.retryFromIndex(0);
      }
      expect(repository.deleteCalls, 0);
      expect(await repository.listMessages(vm.activeSessionId!), before);
      expect(h.api.mainCalls, isEmpty);
      expect(vm.errorMessage, contains('安装更新'));
    });
  }

  test(
      'answerInteraction protects the answer write and sends the committed answer once',
      () async {
    final h = await start(question: true);
    final vm = h.viewModel;
    final question = vm.messages.single;
    repository.answerGate = Completer<void>();
    final pending = vm.answerInteraction(message: question, optionId: 'wide');
    expect(guard.tryBeginInstall(), isFalse);
    await repository.answerEntered.future;
    expect(guard.tryBeginInstall(), isFalse);
    expect(
        (await repository.listMessages(vm.activeSessionId!))
            .single
            .interaction!
            .isAnswered,
        isFalse);
    repository.answerGate!.complete();
    await pending;
    final saved = await repository.listMessages(vm.activeSessionId!);
    expect(saved.first.interaction!.isAnswered, isTrue);
    expect(saved.where((message) => message.role == LlmMessageRole.user),
        hasLength(1));
    expect(h.api.mainCalls, hasLength(1));
    expect(guard.tryBeginInstall(), isTrue);
  });

  test(
      'answerInteraction leaves the question unanswered when installation is locked',
      () async {
    final h = await start(question: true);
    final vm = h.viewModel;
    expect(guard.tryBeginInstall(), isTrue);
    await vm.answerInteraction(message: vm.messages.single, optionId: 'wide');
    expect(repository.answerCalls, 0);
    expect(
        (await repository.listMessages(vm.activeSessionId!))
            .single
            .interaction!
            .isAnswered,
        isFalse);
    expect(h.api.mainCalls, isEmpty);
  });

  test(
      'repository preparation failure releases the activity and preserves history',
      () async {
    final h = await start();
    final vm = h.viewModel;
    repository.deleteGate = Completer<void>();
    repository.failDelete = true;
    final before = await repository.listMessages(vm.activeSessionId!);
    final pending = vm.retryFromIndex(0);
    final failure = expectLater(pending, throwsStateError);
    await repository.deleteEntered.future;
    expect(guard.tryBeginInstall(), isFalse);
    repository.deleteGate!.complete();
    await failure;
    expect(await repository.listMessages(vm.activeSessionId!), before);
    expect(guard.tryBeginInstall(), isTrue);
    expect(h.api.mainCalls, isEmpty);
  });
}
