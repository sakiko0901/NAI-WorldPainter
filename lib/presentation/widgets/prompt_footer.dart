import 'package:flutter/material.dart';
import 'package:nai_huishi/presentation/widgets/emphasis_controller.dart';

class PromptFooter extends StatelessWidget {
  const PromptFooter({
    super.key,
    required this.transparentBackground,
    required this.onTransparentBackgroundChanged,
  });

  final bool transparentBackground;
  final ValueChanged<bool>? onTransparentBackgroundChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              toggled: transparentBackground,
              child: TextButton.icon(
                onPressed: onTransparentBackgroundChanged == null
                    ? null
                    : () =>
                        onTransparentBackgroundChanged!(!transparentBackground),
                style: TextButton.styleFrom(
                  foregroundColor: transparentBackground
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
                icon: Icon(
                  transparentBackground
                      ? Icons.layers_outlined
                      : Icons.layers_clear_outlined,
                  size: 16,
                ),
                label: const Text('透明背景', style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: ValueListenableBuilder<bool>(
              valueListenable: EmphasisController.enabled,
              builder: (context, highlighted, _) => Semantics(
                toggled: highlighted,
                child: TextButton.icon(
                  onPressed: () =>
                      EmphasisController.enabled.value = !highlighted,
                  style: TextButton.styleFrom(
                    foregroundColor:
                        highlighted ? colors.primary : colors.onSurfaceVariant,
                  ),
                  icon: const Icon(Icons.format_color_text, size: 16),
                  label: const Text('强调高亮', style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
