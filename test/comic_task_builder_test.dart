import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/comic_project.dart';
import 'package:nai_huishi/domain/services/comic_task_builder.dart';

void main() {
  final now = DateTime(2026, 8, 11);
  final project = ComicProject(
    id: 'project',
    title: '漫画',
    model: 'nai-v4.5-full',
    protocol: 'image-generations',
    globalPrompt: 'masterpiece, comic',
    negativePrompt: 'lowres',
    resolution: '832x1216',
    sampler: 'k_euler',
    noiseSchedule: 'native',
    createdAt: now,
    updatedAt: now,
  );

  test('任务合并全局、分镜和 TEXT 台词', () {
    final task = ComicTaskBuilder().build(
      project: project,
      panel: const ComicPanel(
        id: 'panel',
        index: 1,
        title: '开场',
        prompt: '1girl, classroom',
        rect: ComicRect(x: 0, y: 0, width: 1, height: 1),
        dialogues: [
          ComicDialogue(id: 'first', text: '你好'),
          ComicDialogue(id: 'second', text: '不应写入', generateText: false),
        ],
      ),
      taskId: 'task',
    );

    expect(task.taskId, 'task');
    expect(task.prompt, contains('masterpiece, comic, 1girl, classroom'));
    expect(task.prompt, contains('\n\nTEXT: 你好'));
    expect(task.prompt, isNot(contains('不应写入')));
    expect(task.negativePrompt, 'lowres');
    expect(task.width, 832);
    expect(task.height, 1216);
  });
}
