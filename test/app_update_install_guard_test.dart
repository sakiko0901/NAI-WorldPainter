import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/core/services/app_update_install_guard.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/repositories/generation_repository.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_input_bar.dart';

void main() {
  test('every active task must finish before the install lock is acquired', () {
    final guard = AppUpdateInstallGuard();
    addTearDown(guard.dispose);
    final finishGeneration = guard.beginActivity('生成尚未完成');
    final finishDirector = guard.beginActivity('导演处理尚未完成');
    expect(guard.tryBeginInstall(), isFalse);
    finishGeneration();
    finishGeneration();
    expect(guard.blockReason, '导演处理尚未完成');
    finishDirector();
    expect(guard.tryBeginInstall(), isTrue);
    expect(() => guard.beginActivity('新的任务'), throwsStateError);
    expect(guard.tryBeginInstall(), isFalse);
    guard.endInstall();
    expect(guard.blockReason, isNull);
  });

  test('discard consent permits temporary edits but never overrides busy work',
      () {
    final guard = AppUpdateInstallGuard();
    addTearDown(guard.dispose);
    final owner = Object();
    guard.registerUnsaved(owner, () => '尚有临时图层');
    expect(guard.unsavedWarning, '尚有临时图层');
    expect(guard.tryBeginInstall(), isFalse);
    final finish = guard.beginActivity('图片正在写入');
    expect(guard.tryBeginInstall(allowDiscardUnsaved: true), isFalse);
    finish();
    expect(guard.tryBeginInstall(allowDiscardUnsaved: true), isTrue);
    guard.endInstall();
    guard.unregisterUnsaved(owner);
    expect(guard.tryBeginInstall(), isTrue);
  });

  test('broken state checks fail closed and disappear after owner disposal',
      () {
    final guard = AppUpdateInstallGuard();
    addTearDown(guard.dispose);
    final owner = Object();
    guard.register(owner, () => throw StateError('disposed state'));
    expect(guard.tryBeginInstall(), isFalse);
    guard.unregister(owner);
    expect(guard.tryBeginInstall(), isTrue);
  });

  test('the real serial queue blocks install and refuses new jobs under lock',
      () async {
    final guard = AppUpdateInstallGuard();
    final repository = _ControlledRepository();
    final queue =
        GenerationQueue(repository, _UnusedHistory(), updateGuard: guard);
    addTearDown(guard.dispose);
    addTearDown(queue.dispose);
    final task = GenerationTask(
      taskId: 'update-guard-test',
      model: 'test',
      prompt: '',
      width: 8,
      height: 8,
      scale: 5,
      cfgRescale: 0,
      sampler: 'test',
      noiseSchedule: 'native',
      status: 'pending',
      createdAt: DateTime(2026),
    );
    final completion = queue.enqueueTransientAndWait(task);
    expect(guard.tryBeginInstall(), isFalse);
    repository.completion.complete(task.copyWith(status: 'success'));
    await completion;
    await Future<void>.delayed(Duration.zero);
    expect(guard.tryBeginInstall(), isTrue);
    expect(
        () => queue.enqueueTransientAndWait(task), throwsA(isA<Exception>()));
    await expectLater(queue.enqueueTransient(task), throwsA(isA<Exception>()));
    expect(repository.submissions, 1);
    guard.endInstall();
  });

  testWidgets('unsent assistant text warns until sent, cleared or unmounted',
      (tester) async {
    final guard = AppUpdateInstallGuard();
    final controller = TextEditingController(text: 'unsent draft');
    addTearDown(controller.dispose);
    addTearDown(guard.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatInputBar(
      controller: controller,
      updateGuard: guard,
      isSending: false,
      onSend: (_, {imageBase64, textAttachment}) {},
    ))));
    expect(guard.unsavedWarning, contains('未发送'));
    expect(guard.tryBeginInstall(), isFalse);
    controller.clear();
    await tester.pump();
    expect(guard.unsavedWarning, isNull);
    controller.text = 'another draft';
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(guard.unsavedWarning, isNull);
  });
}

class _ControlledRepository implements GenerationRepository {
  final completion = Completer<GenerationTask>();
  int submissions = 0;
  @override
  Future<GenerationTask> submitGeneration(GenerationTask task) {
    submissions++;
    return completion.future;
  }

  @override
  void setStreamPreviewHandler(String taskId, dynamic onFrame) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedHistory implements HistoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
