import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasStamina = tokenConfigured && staminaPercent != null;
    final double? percent =
        hasStamina ? staminaPercent!.clamp(0, 100).toDouble() : null;
    final staminaValue = percent == null
        ? '—'
        : '${percent.toStringAsFixed(percent == percent.roundToDouble() ? 0 : 1)}%';
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

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? colors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.chart_bar_alt_fill,
                  size: 16, color: colors.primary),
              const SizedBox(width: 7),
              Text(
                'NovelAI 用量',
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
          Row(
            children: [
              Expanded(
                child: _QuotaMetric(
                  label: tier == 3 ? 'Opus V5 体力' : 'V5 体力',
                  value: staminaValue,
                  valueColor: colors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _QuotaMetric(
                  label: 'Anlas',
                  value: tokenConfigured && anlas != null ? '$anlas' : '—',
                  valueColor: colors.onSurface,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          if (hasStamina) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent! / 100,
                minHeight: 5,
                backgroundColor: colors.onSurface.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isNegative ? colors.error : colors.primary,
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
                message: '生成张数取决于当前模型、画幅和步数',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '预计剩余 ',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                    Text(
                      '—',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
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
  final bool alignEnd;

  const _QuotaMetric({
    required this.label,
    required this.value,
    required this.valueColor,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
