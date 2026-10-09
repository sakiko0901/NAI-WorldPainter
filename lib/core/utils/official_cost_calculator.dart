import 'dart:math' as math;

/// NovelAI 官方渠道 Anlas 消耗计算。
/// 公式与官方 Web 前端一致（参考 novelai_local_web 的 calculate_nai_cost）：
/// base = ceil(coeff1 × pixels + coeff2 × pixels × steps)
/// SMEA ×1.2 / SMEA+DYN ×1.4；V5 家族模型 ×1.5；
/// 单张 = max(ceil(base × strength), 2)；单张上限 140。
class OfficialCostCalculator {
  OfficialCostCalculator._();

  static const double _coeff1 = 2951823174884865e-21;
  static const double _coeff2 = 5.753298233447344e-7;
  static const int maxCostPerImage = 140;

  /// 是否为 V5 家族模型（含 inpainting）。
  static bool isV5Family(String model) {
    final normalized = model.trim().toLowerCase();
    return normalized.contains('nai-diffusion-5');
  }

  /// 计算单张生成消耗的 Anlas。
  ///
  /// [strength]：图生图 / 局部重绘传对应强度，文生图传 1。
  /// [upscaledEnhance]：V5 Max 放大重绘，按放大后的宽高计费（传入的
  /// width/height 应已是放大后的目标尺寸）。
  static int calculateCost({
    required int width,
    required int height,
    required int steps,
    required String model,
    double strength = 1.0,
    bool smea = false,
    bool smeaDyn = false,
  }) {
    final pixels = math.max(width * height, 65536);
    var base = _coeff1 * pixels + _coeff2 * pixels * steps;
    if (smea) base *= smeaDyn ? 1.4 : 1.2;
    if (isV5Family(model)) base *= 1.5;
    final perImage =
        math.max((base * strength.clamp(0.01, 1.0)).ceil(), 2);
    return math.min(perImage, maxCostPerImage);
  }
}
