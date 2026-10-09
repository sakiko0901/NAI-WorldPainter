enum DirectorChannel {
  gateway7877,
  ikun,
  official,
}

enum DirectorToolType {
  declutter(
    label: '去杂物',
    description: '移除悬浮文字、气泡和误入镜物体',
    operation: 'director-declutter',
  ),
  bgRemover(
    label: '背景移除',
    description: '移除背景并补全被前景遮挡的部分',
    operation: 'director-bg-remover',
  ),
  lineart(
    label: '线稿提取',
    description: '提取画面中的线条结构',
    operation: 'director-lineart',
  ),
  sketch(
    label: '草图化',
    description: '生成最早概念阶段的草图版本',
    operation: 'director-sketch',
  ),
  colorize(
    label: '线稿上色',
    description: '根据提示词为线稿或图像重新上色',
    operation: 'director-colorize',
  ),
  emotion(
    label: '情感迁移',
    description: '改变单角色正面图中的表情',
    operation: 'director-emotion',
  );

  final String label;
  final String description;
  final String operation;

  String get officialOperation => switch (this) {
        DirectorToolType.declutter => 'declutter',
        DirectorToolType.bgRemover => 'bg-removal',
        DirectorToolType.lineart => 'lineart',
        DirectorToolType.sketch => 'sketch',
        DirectorToolType.colorize => 'colorize',
        DirectorToolType.emotion => 'emotion',
      };

  const DirectorToolType({
    required this.label,
    required this.description,
    required this.operation,
  });

  bool get usesPrompt => this == colorize || this == emotion;
  bool get usesDefry => this == colorize || this == emotion;
  bool get consumesAnlas =>
      this == bgRemover || this == colorize || this == emotion;
}
