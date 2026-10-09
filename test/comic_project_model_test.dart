import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/comic_project.dart';

void main() {
  final now = DateTime(2026, 8, 11);
  final project = ComicProject(
    id: 'project',
    title: '测试漫画',
    model: 'nai-v4.5-full',
    protocol: 'image-generations',
    panels: [
      ComicPanel(
        id: 'panel',
        index: 1,
        title: '开场',
        prompt: '1girl, classroom',
        rect: const ComicRect(x: 0.1, y: 0.1, width: 0.8, height: 0.4),
        dialogues: const [
          ComicDialogue(id: 'dialogue', speaker: '少女', text: '你好'),
        ],
        candidates: [
          ComicCandidate(
            id: 'candidate',
            taskId: 'task',
            imagePath: '/tmp/image.png',
            status: ComicPanelStatus.done,
            createdAt: now,
          ),
        ],
        selectedCandidateId: 'candidate',
        overlays: const [
          ComicOverlay(
            id: 'bubble',
            type: ComicOverlayType.bubble,
            rect: ComicRect(x: 0.2, y: 0.2, width: 0.3, height: 0.2),
            text: '你好',
          ),
        ],
        status: ComicPanelStatus.done,
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );

  test('漫画工程往返保留候选、台词和本地对话图层', () {
    final restored = ComicProject.fromJson(project.toJson());

    expect(restored.title, '测试漫画');
    expect(
        restored.panels.single.selectedCandidate?.imagePath, '/tmp/image.png');
    expect(restored.panels.single.dialogues.single.text, '你好');
    expect(
        restored.panels.single.overlays.single.type, ComicOverlayType.bubble);
  });

  test('v1 漫画工程可读并在保存时升级为 v2', () {
    final restored = ComicProject.fromJson({
      ...project.toJson(),
      'schemaVersion': 1,
    });

    expect(restored.toJson()['schemaVersion'], comicProjectSchemaVersion);
    expect(restored.panels.single.overlays.single.bubbleShape,
        ComicBubbleShape.rectangle);
  });

  test('候选数量和扩展图层数据可稳定保存', () {
    final overlay = const ComicOverlay(
      id: 'cover',
      type: ComicOverlayType.whiteCover,
      rect: ComicRect(x: 0, y: 0, width: 1, height: 1),
      bubbleShape: ComicBubbleShape.oval,
      fontFamily: 'serif',
      brushStrokes: [
        ComicBrushStroke(
          width: 0.06,
          points: [ComicPoint(x: 0.1, y: 0.2), ComicPoint(x: 0.2, y: 0.3)],
        ),
      ],
    );
    final restored = ComicProject.fromJson(
      project.copyWith(candidateCount: 99, panels: [
        project.panels.single.copyWith(overlays: [overlay]),
      ]).toJson(),
    );

    expect(restored.candidateCount, comicCandidateCountMax);
    expect(restored.panels.single.overlays.single.fontFamily, 'serif');
    expect(restored.panels.single.overlays.single.brushStrokes.single.points,
        hasLength(2));
  });

  test('漫画工程拒绝未知 schema', () {
    expect(
      () => ComicProject.fromJson(const {'schemaVersion': 99}),
      throwsFormatException,
    );
  });
}
