import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';

/// Shows only quota values returned by the official NovelAI account endpoint.
/// Image-count estimates stay unavailable because generation cost depends on
/// the selected model, canvas, and step count.
class ToolsQuotaCard extends StatelessWidget {
  final bool tokenConfigured;
  final bool isLoading;
  final bool hasError;
  final double? staminaPercent;
  final bool isNegative;
  final int? tier;
  final int? anlas;
  final VoidCallback? onRefresh;

  const ToolsQuotaCard({
    super.key,
    required this.tokenConfigured,
    required this.isLoading,
    required this.hasError,
    required this.staminaPercent,
    required this.isNegative,
    required this.tier,
    required this.anlas,
    this.onRefresh,
  });

  /// 体力条颜色（按 10000 点满额基准换算）：
  /// ≥ 65% 绿色，20%~64% 黄色，<20% 红色。
  static Color staminaColor(double percent, ColorScheme colors) {
    if (percent >= 65) return const Color(0xFF34C759);
    if (percent >= 20) return const Color(0xFFFFCC00);
    return colors.error;
  }

  /// 估算剩余张数：约 17 张 / 1% 体力（Normal 尺寸基准）。
  static int estimateImages(double percent) => (percent * 17).round();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasStamina = tokenConfigured && staminaPercent != null;
    final double? percent =
        hasStamina ? staminaPercent!.clamp(0, 100).toDouble() : null;
    final staminaValue = percent == null
        ? '—'
        : '${percent.toStringAsFixed(percent == percent.roundToDouble() ? 0 : 1)}%';
    final staminaBarColor =
        percent == null ? colors.primary : staminaColor(percent, colors);
    final estimate = percent == null ? null : estimateImages(percent);
    final String? accountStatus;
    if (isLoading) {
      accountStatus = '正在读取';
    } else if (hasError) {
      accountStatus = '查询失败';
    } else if (!tokenConfigured) {
      accountStatus = '官方 Token 未配置';
    } else if (!hasStamina && anlas == null) {
      accountStatus = '暂无可用额度';
    } else if (isNegative) {
      accountStatus = '免费体力已耗尽';
    } else if (tier != null && tier != 3) {
      accountStatus = '当前套餐非 Opus';
    } else {
      accountStatus = null;
    }

    return FrostedSurface(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.chart_bar_alt_fill,
                  size: 16, color: colors.primary),
              const SizedBox(width: 7),
              Text(
                'Opus 体力',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              if (isLoading)
                const SizedBox.square(
                  dimension: 16,
                  child: CupertinoActivityIndicator(radius: 8),
                )
              else
                IconButton(
                  key: const ValueKey('tools-quota-refresh'),
                  onPressed: tokenConfigured ? onRefresh : null,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  tooltip: '刷新用量',
                  icon: Icon(
                    CupertinoIcons.refresh,
                    size: 16,
                    color: tokenConfigured
                        ? colors.onSurfaceVariant
                        : colors.onSurfaceVariant.withValues(alpha: 0.45),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _QuotaMetric(
            label: tier == 3 ? 'Opus V5 体力' : 'V5 体力',
            value: staminaValue,
            valueColor:
                percent == null ? colors.onSurface : staminaBarColor,
          ),
          if (hasStamina) ...[
            const SizedBox(height: 10),
            // Anlas 显示在体力条右上角（与体力百分比同字号）
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'Anlas ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  tokenConfigured && anlas != null ? '$anlas' : '—',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent! / 100,
                minHeight: 5,
                backgroundColor: colors.onSurface.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isNegative ? colors.error : staminaBarColor,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                accountStatus ?? '用量已读取',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: hasError ? colors.error : colors.onSurfaceVariant,
                    ),
              ),
              Tooltip(
                message: '估算基准：Normal 画幅约 17 张 / 1% 体力，实际张数取决于模型、画幅和步数',
                child: Text(
                  estimate == null ? '预计剩余 —' : '预计剩余 约$estimate张',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuotaMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _QuotaMetric({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: valueColor,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
