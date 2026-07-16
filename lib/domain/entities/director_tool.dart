import 'package:nai_huishi/core/constants/api_constants.dart';

enum DirectorToolType {
  declutter(
    label: '去杂物',
    description: '移除悬浮文字、气泡和误入镜物体',
    endpoint: ApiConstants.imageDirectorDeclutter,
  ),
  bgRemover(
    label: '背景移除',
    description: '移除背景并补全被前景遮挡的部分',
    endpoint: ApiConstants.imageDirectorBgRemover,
  ),
  lineart(
    label: '线稿提取',
    description: '提取画面中的线条结构',
    endpoint: ApiConstants.imageDirectorLineart,
  ),
  sketch(
    label: '草图化',
    description: '生成最早概念阶段的草图版本',
    endpoint: ApiConstants.imageDirectorSketch,
  ),
  colorize(
    label: '线稿上色',
    description: '根据提示词为线稿或图像重新上色',
    endpoint: ApiConstants.imageDirectorColorize,
  ),
  emotion(
    label: '情感迁移',
    description: '改变单角色正面图中的表情',
    endpoint: ApiConstants.imageDirectorEmotion,
  );

  final String label;
  final String description;
  final String endpoint;

  const DirectorToolType({
    required this.label,
    required this.description,
    required this.endpoint,
  });

  bool get usesPrompt => this == colorize || this == emotion;
  bool get usesDefry => this == colorize;
  bool get usesLevel => this == emotion;
  bool get consumesAnlas => this == colorize || this == emotion;
}
