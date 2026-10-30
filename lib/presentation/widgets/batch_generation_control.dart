import 'package:flutter/material.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';

/// Shared compact batch control for generation and inpainting.
class BatchGenerationControl extends StatelessWidget {
  const BatchGenerationControl({
    super.key,
    required this.value,
    required this.onChanged,
    required this.sliderKey,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final Key sliderKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: [
        Row(children: [
          Text('批量生成',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          const Spacer(),
          Text('$value 张',
              style: TextStyle(
                  fontSize: 12,
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        SizedBox(
          height: 36,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16)),
            child: Slider(
              key: sliderKey,
              value: value
                  .toDouble()
                  .clamp(1, AppConstants.maxBatchCount.toDouble()),
              min: 1,
              max: AppConstants.maxBatchCount.toDouble(),
              divisions: AppConstants.maxBatchCount - 1,
              semanticFormatterCallback: (value) => '${value.round()} 张',
              onChanged: onChanged == null
                  ? null
                  : (value) => onChanged!(value.round()),
            ),
          ),
        ),
      ]),
    );
  }
}
