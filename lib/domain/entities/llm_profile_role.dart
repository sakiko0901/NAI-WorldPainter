/// LLM 角色标记：用于在 [LlmRoleBinding] 中区分 2 种用途。
///
/// - main: Agent 主循环、工具调用、最终回复
/// - vision: 图片理解任务（多模态）
/// - aux: 保留备用，兼作旧 embedding 数据的兜底
enum LlmProfileRole {
  /// 主模型 — Agent 循环、通用对话、tool calling
  main,

  /// 识图模型 — vision 多模态任务（图片理解、分析）
  vision,

  /// 辅助/未指定 — 兼作旧 embedding 持久化值的兜底
  aux,
}

extension LlmProfileRoleExtension on LlmProfileRole {
  String get label {
    switch (this) {
      case LlmProfileRole.main:
        return '主模型';
      case LlmProfileRole.vision:
        return '识图模型';
      case LlmProfileRole.aux:
        return '辅助';
    }
  }

  String get description {
    switch (this) {
      case LlmProfileRole.main:
        return 'Agent 主循环使用，负责工具调用与最终回复';
      case LlmProfileRole.vision:
        return '图片理解任务使用，需支持 vision 输入';
      case LlmProfileRole.aux:
        return '未分配特定用途，保留备用';
    }
  }

  String get persistedValue {
    switch (this) {
      case LlmProfileRole.main:
        return 'main';
      case LlmProfileRole.vision:
        return 'vision';
      case LlmProfileRole.aux:
        return 'aux';
    }
  }

  static LlmProfileRole fromPersistedValue(String? v) {
    switch (v) {
      case 'main':
        return LlmProfileRole.main;
      case 'vision':
        return LlmProfileRole.vision;
      // 旧版本持久化的 'embedding' 值映射到 aux 兜底（嵌入模型已删除）
      case 'embedding':
      default:
        return LlmProfileRole.aux;
    }
  }
}
