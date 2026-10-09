import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/core/services/comic_asset_store.dart';
import 'package:nai_huishi/domain/entities/comic_project.dart';
import 'package:nai_huishi/domain/services/comic_task_builder.dart';

class ComicGenerationCoordinator {
  static const _uuid = Uuid();

  final GenerationQueue _queue;
  final ComicAssetStore _assetStore;
  final ComicTaskBuilder _taskBuilder;

  ComicGenerationCoordinator(
    this._queue,
    this._assetStore,
    this._taskBuilder,
  );

  Future<ComicProject> generatePanel(
    ComicProject project,
    String panelId, {
    int? count,
    void Function(ComicProject project)? onChanged,
  }) async {
    ComicPanel? panel;
    for (final item in project.panels) {
      if (item.id == panelId) {
        panel = item;
        break;
      }
    }
    if (panel == null) throw StateError('分镜不存在');
    var current = _replacePanel(
      project,
      panel.copyWith(status: ComicPanelStatus.generating),
    );
    onChanged?.call(current);
    final requested = (count ?? project.candidateCount).clamp(
      comicCandidateCountMin,
      comicCandidateCountMax,
    );
    for (var index = 0; index < requested; index++) {
      final candidateId = _uuid.v4();
      final task = _taskBuilder.build(
        project: current,
        panel: current.panels.where((item) => item.id == panelId).first,
        taskId: _uuid.v4(),
      );
      final snapshotPath =
          await _assetStore.taskSnapshotPath(project.id, candidateId);
      await File(snapshotPath)
          .writeAsString(jsonEncode(taskToJson(task)), flush: true);
      final queuedCandidate = ComicCandidate(
        id: candidateId,
        taskId: task.taskId,
        taskSnapshotPath: snapshotPath,
        createdAt: DateTime.now(),
      );
      current = _appendCandidate(current, panelId, queuedCandidate);
      onChanged?.call(current);

      final generatingCandidate = queuedCandidate.copyWith(
        status: ComicPanelStatus.generating,
      );
      current = _replaceCandidate(current, panelId, generatingCandidate);
      onChanged?.call(current);

      final result = await _queue.enqueueTransientAndWait(task);
      final candidate = result.status == 'success' && result.imagePath != null
          ? queuedCandidate.copyWith(
              imagePath: await _copyCandidateImage(
                project.id,
                panelId,
                candidateId,
                result.imagePath!,
              ),
              status: ComicPanelStatus.done,
              seed: result.seed,
              clearError: true,
            )
          : queuedCandidate.copyWith(
              status: ComicPanelStatus.failed,
              errorMessage: result.errorMessage ?? '生成失败',
            );
      current = _replaceCandidate(current, panelId, candidate);
      onChanged?.call(current);
    }
    final completedPanel =
        current.panels.where((item) => item.id == panelId).first;
    return _replacePanel(
      current,
      completedPanel.copyWith(
        status: completedPanel.candidates.any(
          (candidate) => candidate.status == ComicPanelStatus.done,
        )
            ? ComicPanelStatus.done
            : ComicPanelStatus.failed,
      ),
    );
  }

  Map<String, dynamic> taskToJson(dynamic task) => {
        'taskId': task.taskId,
        'model': task.model,
        'endpointId': task.endpointId,
        'protocol': task.protocol,
        'prompt': task.prompt,
        'negativePrompt': task.negativePrompt,
        'width': task.width,
        'height': task.height,
        'scale': task.scale,
        'cfgRescale': task.cfgRescale,
        'sampler': task.sampler,
        'noiseSchedule': task.noiseSchedule,
        'steps': task.steps,
        'seed': task.seed,
      };

  Future<String> _copyCandidateImage(
    String projectId,
    String panelId,
    String candidateId,
    String sourcePath,
  ) async {
    final source = File(sourcePath);
    if (!await source.exists()) throw StateError('生成图片不可用');
    final target =
        await _assetStore.candidatePath(projectId, panelId, candidateId);
    await source.copy(target);
    return target;
  }

  ComicProject _appendCandidate(
    ComicProject project,
    String panelId,
    ComicCandidate candidate,
  ) {
    final panel = project.panels.where((item) => item.id == panelId).first;
    return _replacePanel(
      project,
      panel.copyWith(candidates: [...panel.candidates, candidate]),
    );
  }

  ComicProject _replaceCandidate(
    ComicProject project,
    String panelId,
    ComicCandidate candidate,
  ) {
    final panel = project.panels.where((item) => item.id == panelId).first;
    final candidates = panel.candidates
        .map((item) => item.id == candidate.id ? candidate : item)
        .toList();
    return _replacePanel(
      project,
      panel.copyWith(
        candidates: candidates,
        selectedCandidateId: panel.selectedCandidateId ??
            (candidate.status == ComicPanelStatus.done ? candidate.id : null),
      ),
    );
  }

  ComicProject _replacePanel(ComicProject project, ComicPanel panel) =>
      project.copyWith(
        panels: project.panels
            .map((item) => item.id == panel.id ? panel : item)
            .toList(),
      );
}
