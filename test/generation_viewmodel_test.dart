import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/repositories/generation_repository.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/domain/repositories/settings_repository.dart';
import 'package:nai_huishi/domain/usecases/generate_image.dart';
import 'package:nai_huishi/domain/usecases/manage_settings.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate completes only after successful result is displayable',
      () async {
    final image = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'generation_viewmodel_result.png',
    );
    await image.writeAsBytes(const [1, 2, 3]);
    addTearDown(() => image.deleteSync());

    final history = _MemoryHistoryRepository();
    final queue = GenerationQueue(
      _SuccessfulGenerationRepository(image.path),
      history,
    );
    addTearDown(queue.dispose);
    final saveStarted = Completer<void>();
    final allowSave = Completer<void>();
    final saveImage = _DelayedSaveImageUseCase(
      history,
      saveStarted: saveStarted,
      allowSave: allowSave,
    );
    final viewModel = GenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: saveImage,
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    viewModel.prompt = '1girl';
    viewModel.selectedModel = 'model';

    var generateCompleted = false;
    final generateFuture = viewModel.generate().then((_) {
      generateCompleted = true;
    });

    await saveStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(generateCompleted, isFalse);
    expect(viewModel.sessionResults, isEmpty);

    allowSave.complete();
    await generateFuture;

    expect(viewModel.isGenerating, isFalse);
    expect(viewModel.sessionResults, hasLength(1));
    expect(viewModel.sessionResults.single.status, 'success');
    expect(viewModel.lastCompletedTask?.taskId,
        viewModel.sessionResults.single.taskId);
    expect(saveImage.executeCount, 1);
  });

  test('502 failure ends loading even when history update fails', () async {
    final history = _FailingUpdateHistoryRepository();
    final queue = GenerationQueue(_BadGatewayGenerationRepository(), history);
    addTearDown(queue.dispose);
    final viewModel = GenerationViewModel(
      generateImage: GenerateImageUseCase(history),
      manageSettings: ManageSettingsUseCase(_SettingsRepository()),
      saveImage: SaveImageUseCase(history),
      queue: queue,
    );
    addTearDown(viewModel.dispose);
    viewModel.prompt = '1girl';
    viewModel.selectedModel = 'model';

    await viewModel.generate().timeout(const Duration(seconds: 2));

    expect(viewModel.isGenerating, isFalse);
    expect(viewModel.errorMessage, contains('All connection attempts failed'));
  });
}

class _DelayedSaveImageUseCase extends SaveImageUseCase {
  _DelayedSaveImageUseCase(
    super.historyRepo, {
    required this.saveStarted,
    required this.allowSave,
  });

  final Completer<void> saveStarted;
  final Completer<void> allowSave;
  int executeCount = 0;

  @override
  Future<String> execute(GenerationTask task) async {
    executeCount++;
    if (!saveStarted.isCompleted) saveStarted.complete();
    await allowSave.future;
    return task.imagePath!;
  }
}

class _SuccessfulGenerationRepository implements GenerationRepository {
  _SuccessfulGenerationRepository(this.imagePath);

  final String imagePath;

  @override
  Future<GenerationTask> submitGeneration(GenerationTask task) async =>
      task.copyWith(
        status: 'success',
        imagePath: imagePath,
        completedAt: DateTime.now(),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingHistoryRepository implements HistoryRepository {
  _ThrowingHistoryRepository(this.message);

  final String message;

  @override
  Future<GenerationTask> saveTask(GenerationTask task) async =>
      throw Exception(message);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BadGatewayGenerationRepository implements GenerationRepository {
  @override
  Future<GenerationTask> submitGeneration(GenerationTask task) async =>
      throw ApiException(
        message: '服务器错误 (502)：上游请求失败: All connection attempts failed',
        statusCode: 502,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingUpdateHistoryRepository extends _MemoryHistoryRepository {
  @override
  Future<GenerationTask> updateTask(GenerationTask task) async {
    if (task.status == 'failed') {
      throw Exception('history update failed');
    }
    return super.updateTask(task);
  }
}

class _MemoryHistoryRepository implements HistoryRepository {
  final Map<String, GenerationTask> tasks = {};

  @override
  Future<GenerationTask> saveTask(GenerationTask task) async {
    tasks[task.taskId] = task;
    return task;
  }

  @override
  Future<GenerationTask> updateTask(GenerationTask task) async {
    tasks[task.taskId] = task;
    return task;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SettingsRepository implements SettingsRepository {
  @override
  Future<String?> getSelectedModelDraft() async => 'model';

  @override
  Future<String?> getDefaultModel() async => 'model';

  @override
  Future<String> getSelectedResolutionDraft() async => '832x1216';

  @override
  Future<String> getSelectedSamplerDraft() async => 'k_euler';

  @override
  Future<double> getScaleDraft() async => 5;

  @override
  Future<double> getCfgRescaleDraft() async => 0;

  @override
  Future<int> getStepsDraft() async => 28;

  @override
  Future<bool> getStepsLocked() async => false;

  @override
  Future<String> getSelectedNoiseScheduleDraft() async => 'native';

  @override
  Future<String> getPromptDraft() async => '';

  @override
  Future<String> getNegativePromptDraft() async => '';

  @override
  Future<String> getInpaintPromptDraft() async => '';

  @override
  Future<String> getInpaintNegativePromptDraft() async => '';

  @override
  Future<List<CharacterSpec>> getCharactersDraft() async => const [];

  @override
  Future<List<CharacterReferenceImage>> getVibeReferencesDraft() async =>
      const [];

  @override
  Future<int> getBatchCount() async => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
