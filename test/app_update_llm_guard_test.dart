import 'package:nai_huishi/domain/entities/llm_session.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/services/app_update_install_guard.dart';
import 'package:nai_huishi/domain/agents/agent_event.dart';
import 'package:nai_huishi/domain/entities/llm_interaction.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';

import 'support/chat_memory_fake.dart';

/// Hold the repository writes while checking ownership of the update guard.
class _GatedRepository extends FakeLlmChatRepository {
  final forkEntered = Completer<void>();
  final replaceEntered = Completer<void>();
  final answerEntered = Completer<void>();
  Completer<void>? forkGate;
  Completer<void>? replaceGate;
  Completer<void>? answerGate;
  int forkCalls = 0;
  int replaceCalls = 0;
  int answerCalls = 0;
  bool failReplace = false;
  final _replacements = <int, LlmMessage>{};

  @override
  Future<List<LlmMessage>> listMessages(String sessionId) async =>
      (await super.listMessages(sessionId))
          .map((message) => _replacements[message.id] ?? message)
          .toList();

  @override
  Future<LlmSession> forkSession(String sessionId, int messageId,
      {bool includeMessage = false}) async {
    forkCalls++;
    if (!forkEntered.isCompleted) forkEntered.complete();
    await forkGate?.future;
    return super
        .forkSession(sessionId, messageId, includeMessage: includeMessage);
  }

  @override
  Future<LlmMessage> saveAgentRunResult({
    required String sessionId,
    required String assistantText,
    String? toolCallsJson,
    List<AgentEvent>? agentTimeline,
    LlmInteraction? interaction,
    int? replaceReplyId,
    DateTime? replyPosition,
    bool keepReplyContent = false,
  }) async {
    if (replaceReplyId != null) {
      replaceCalls++;
      if (!replaceEntered.isCompleted) replaceEntered.complete();
      await replaceGate?.future;
      if (failReplace) throw StateError('database replacement failed');
    }
    return super.saveAgentRunResult(
      sessionId: sessionId,
      assistantText: assistantText,
      toolCallsJson: toolCallsJson,
      agentTimeline: agentTimeline,
      interaction: interaction,
      replaceReplyId: replaceReplyId,
      replyPosition: replyPosition,
      keepReplyContent: keepReplyContent,
    );
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
    final write = edit ? 'branch creation' : 'in-place reply replacement';
    test('$action blocks installation during $write', () async {
      final h = await start();
      final vm = h.viewModel;
      final sessionId = vm.activeSessionId!;
      final gate = Completer<void>();
      if (edit) {
        repository.forkGate = gate;
      } else {
        repository.replaceGate = gate;
      }
      final pending =
          edit ? vm.editAndResend(0, '修改后的问题') : vm.retryFromIndex(0);
      expect(guard.tryBeginInstall(), isFalse,
          reason: 'Protection must be acquired before the first await');
      await (edit
          ? repository.forkEntered.future
          : repository.replaceEntered.future);
      expect(vm.isSending, isTrue);
      expect(guard.tryBeginInstall(), isFalse);
      expect(await repository.listMessages(vm.activeSessionId!), hasLength(2));
      gate.complete();
      await pending;
      final saved = await repository.listMessages(vm.activeSessionId!);
      expect(repository.forkCalls, edit ? 1 : 0);
      expect(repository.replaceCalls, edit ? 0 : 1);
      expect(vm.activeSessionId == sessionId, !edit);
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
        '$action refuses before $write when installation already owns the lock',
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
      expect(repository.forkCalls, 0);
      expect(repository.replaceCalls, 0);
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

  test('reply replacement failure releases the activity and preserves history',
      () async {
    final h = await start();
    final vm = h.viewModel;
    repository.replaceGate = Completer<void>();
    repository.failReplace = true;
    final before = await repository.listMessages(vm.activeSessionId!);
    final pending = vm.retryFromIndex(0);

    await repository.replaceEntered.future;
    expect(guard.tryBeginInstall(), isFalse);
    repository.replaceGate!.complete();
    await pending;
    expect(vm.errorMessage, contains('重试失败'));
    expect(await repository.listMessages(vm.activeSessionId!), before);
    expect(guard.tryBeginInstall(), isTrue);
    expect(h.api.mainCalls, hasLength(1));
  });
}
