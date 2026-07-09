import 'package:nai_huishi/domain/entities/generation_task.dart';

/// 提示词框访问器抽象。
/// 由 [GenerationViewModel] 实现，让 Agent 工具能读写 4 个提示词框 + 多角色框的内容。
abstract class PromptBoxAccessor {
  String get positive;
  String get negative;
  String get inpaintPositive;
  String get inpaintNegative;

  /// 多角色列表（最多 6 个）。每个角色含 prompt/uc/enabled。
  /// agent 读写角色框时通过此列表 + writeCharacterPrompt 实现。
  List<CharacterSpec> get characters;

  /// 当前提示词框版本号。每次用户手改或工具写入后递增，便于 LLM 检测变化。
  int get version;

  /// 当前是否处于局部重绘模式。true=inpainting（inpaint 框可写），
  /// false=textToImage（inpaint 框被保护，写入会被拒绝）。
  bool get isInpaintingMode;

  /// 写入指定框。target 取值：
  /// - positive / negative / inpaint_positive / inpaint_negative（4 个主框）
  /// - character_1 / character_2 / ... / character_6（多角色 prompt 框）
  /// - character_1_uc / character_2_uc / ...（多角色负向框）
  /// append=true 追加，false 替换。返回新版本号。
  /// 若 target 是 inpaint_* 但当前不是局部重绘模式，会抛出 [InpaintModeGuardError]。
  /// 若 target 是 character_N 但 N 超出当前角色数，会自动补齐到 N 个角色（中间补空角色）。
  Future<int> writePrompt({
    required String target,
    required String content,
    required bool append,
  });
}

/// 当 agent 尝试在非局部重绘模式下写入 inpaint 框时抛出。
class InpaintModeGuardError implements Exception {
  final String target;
  InpaintModeGuardError(this.target);
  @override
  String toString() =>
      '当前不是局部重绘模式，禁止写入 $target 框。如需修改局部重绘提示词，请先让用户切换到局部重绘模式。';
}
