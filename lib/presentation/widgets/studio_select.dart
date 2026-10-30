import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared geometry for generation fields, popup edges and selected rows.
const studioSelectRadius = 16.0;

class StudioSelectOption<T> {
  final T value;
  final String label;
  final Widget? leading;
  const StudioSelectOption(this.value, this.label, {this.leading});
}

class StudioSelect<T> extends StatelessWidget {
  final String id;
  final String label;
  final T? value;
  final List<StudioSelectOption<T>> options;
  final ValueChanged<T>? onChanged;
  const StudioSelect(
      {super.key,
      required this.id,
      required this.label,
      required this.value,
      required this.options,
      required this.onChanged});

  Future<void> _open(BuildContext context) async {
    if (onChanged == null || options.isEmpty) return;
    final box = context.findRenderObject()! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final media = MediaQuery.of(context);
    final selectedKey = GlobalKey();
    final next = await showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭$label选项',
      barrierColor: Colors.black.withValues(alpha: 0.22),
      transitionDuration: media.disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 180),
      pageBuilder: (menuContext, _, __) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final selectedContext = selectedKey.currentContext;
          if (selectedContext != null) {
            Scrollable.ensureVisible(selectedContext, alignment: 0.5);
          }
        });
        final colors = Theme.of(menuContext).colorScheme;
        final menuMedia = MediaQuery.of(menuContext);
        return CustomSingleChildLayout(
          delegate: _StudioSelectMenuLayout(
              anchor: rect,
              safeTop: menuMedia.padding.top + 12,
              safeBottom:
                  menuMedia.padding.bottom + menuMedia.viewInsets.bottom + 12),
          child: Material(
            key: ValueKey('$id-menu'),
            color: colors.surfaceContainerHigh,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(studioSelectRadius),
                side: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.5))),
            clipBehavior: Clip.antiAlias,
            child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(6),
                children: [
                  for (final option in options)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Semantics(
                        selected: option.value == value,
                        child: Material(
                          key: option.value == value ? selectedKey : null,
                          color: option.value == value
                              ? colors.primary.withValues(alpha: 0.16)
                              : Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(studioSelectRadius),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: ValueKey('$id-option-${option.value}'),
                            borderRadius:
                                BorderRadius.circular(studioSelectRadius),
                            onTap: () =>
                                Navigator.pop(menuContext, option.value),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                child: Row(children: [
                                  if (option.leading != null) ...[
                                    option.leading!,
                                    const SizedBox(width: 12)
                                  ],
                                  Expanded(
                                      child: Text(option.label,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 14,
                                              color: colors.onSurface,
                                              fontWeight: option.value == value
                                                  ? FontWeight.w600
                                                  : FontWeight.w400))),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                      width: 18,
                                      child: option.value == value
                                          ? Icon(Icons.check_rounded,
                                              size: 18, color: colors.primary)
                                          : null),
                                ])),
                          ),
                        ),
                      ),
                    ),
                ]),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) => FadeTransition(
          opacity:
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          child: child),
    );
    if (next != null && context.mounted) onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        options.where((option) => option.value == value).firstOrNull;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      enabled: onChanged != null,
      child: Material(
        key: ValueKey('$id-field'),
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(studioSelectRadius),
            side: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.4))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(studioSelectRadius),
          onTap: onChanged == null || options.isEmpty
              ? null
              : () => _open(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  if (selected?.leading != null) ...[
                    selected!.leading!,
                    const SizedBox(width: 12)
                  ],
                  Expanded(
                      child: Text(selected?.label ?? value?.toString() ?? '请选择',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              color: onChanged == null
                                  ? colors.onSurfaceVariant
                                  : colors.onSurface))),
                  const SizedBox(width: 8),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 20, color: colors.onSurfaceVariant),
                ])),
          ),
        ),
      ),
    );
  }
}

/// Positions the menu using its measured size, including variable text height.
class _StudioSelectMenuLayout extends SingleChildLayoutDelegate {
  final Rect anchor;
  final double safeTop;
  final double safeBottom;
  static const gap = 4.0;
  const _StudioSelectMenuLayout(
      {required this.anchor, required this.safeTop, required this.safeBottom});

  bool _below(Size size) =>
      size.height - safeBottom - anchor.bottom >= anchor.top - safeTop;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final size = constraints.biggest;
    final available = _below(size)
        ? size.height - safeBottom - anchor.bottom - gap
        : anchor.top - safeTop - gap;
    final width = math.min(anchor.width, math.max(1.0, size.width - 24));
    return BoxConstraints(
        minWidth: width,
        maxWidth: width,
        maxHeight: math.max(1.0, math.min(400.0, available)));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = anchor.left
        .clamp(12.0, math.max(12.0, size.width - childSize.width - 12));
    final top = (_below(size)
            ? anchor.bottom + gap
            : anchor.top - childSize.height - gap)
        .clamp(safeTop,
            math.max(safeTop, size.height - safeBottom - childSize.height));
    return Offset(left.toDouble(), top.toDouble());
  }

  @override
  bool shouldRelayout(_StudioSelectMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      safeTop != oldDelegate.safeTop ||
      safeBottom != oldDelegate.safeBottom;
}

class ResolutionGlyph extends StatelessWidget {
  final String resolution;
  const ResolutionGlyph(this.resolution, {super.key});
  @override
  Widget build(BuildContext context) {
    final dimensions = resolution.split('x').map(double.tryParse).toList();
    final ratio = dimensions.length == 2 &&
            dimensions[0] != null &&
            dimensions[1] != null &&
            dimensions[1]! > 0
        ? (dimensions[0]! / dimensions[1]!).clamp(0.15, 6.0)
        : 1.0;
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
        width: 32,
        height: 28,
        child: Center(
            child: Container(
          width: ratio >= 1 ? 28 : 24 * ratio,
          height: ratio >= 1 ? 28 / ratio : 24,
          decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: colors.primary, width: 1.3)),
        )));
  }
}
