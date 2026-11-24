import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:nai_huishi/domain/entities/llm_profile_role.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_role_binding.dart';
import 'package:nai_huishi/domain/services/llm_thinking.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';

import 'model_selection_sheet.dart';

const _thinkingTrackHeight = 28.0;
const _thinkingOverlayRadius = 20.0;

class ChatModelMenuAnchor {
  final key = GlobalKey();
  final link = LayerLink();
}

Future<void> showChatModelMenu(
  BuildContext context, {
  required LlmChatViewModel vm,
  required ChatModelMenuAnchor composer,
}) {
  final reducedMotion = MediaQuery.disableAnimationsOf(context);
  final colors = Theme.of(context).colorScheme;
  return showGeneralDialog<void>(
    context: context,
    requestFocus: false,
    barrierDismissible: true,
    barrierLabel: '关闭模型设置',
    barrierColor: colors.scrim.withValues(alpha: .16),
    transitionDuration:
        reducedMotion ? Duration.zero : const Duration(milliseconds: 190),
    pageBuilder: (_, animation, __) => LayoutBuilder(
      builder: (context, constraints) {
        final insets = MediaQuery.viewInsetsOf(context);
        final padding = MediaQuery.paddingOf(context);
        final availableHeight =
            constraints.maxHeight - insets.bottom - padding.top;
        final composerBox = composer.key.currentContext?.findRenderObject();
        final anchorTop = composerBox is RenderBox && composerBox.hasSize
            ? composerBox.localToGlobal(Offset.zero).dy - padding.top
            : 0.0;
        final anchored = anchorTop >= 220 && composer.link.leaderSize != null;
        final availableWidth =
            composer.link.leaderSize?.width ?? constraints.maxWidth;
        final menuHeight = anchored ? anchorTop - 16 : availableHeight - 16;
        final card = SlideTransition(
          position: animation.drive(Tween(
            begin: const Offset(0, .045),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic))),
          child: SizedBox(
            width: (availableWidth - 8).clamp(0, 362),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: menuHeight.clamp(0, 390)),
              child: _ChatModelMenu(vm: vm),
            ),
          ),
        );
        final Widget surface;
        if (!anchored) {
          surface = Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: insets.bottom + 8),
              child: card,
            ),
          );
        } else {
          surface = Align(
            alignment: Alignment.topLeft,
            child: CompositedTransformFollower(
              link: composer.link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topRight,
              followerAnchor: Alignment.bottomRight,
              offset: const Offset(-4, -8),
              child: card,
            ),
          );
        }
        return surface;
      },
    ),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class _ChatModelMenu extends StatefulWidget {
  const _ChatModelMenu({required this.vm});

  final LlmChatViewModel vm;

  @override
  State<_ChatModelMenu> createState() => _ChatModelMenuState();
}

class _ChatModelMenuState extends State<_ChatModelMenu> {
  LlmRoleBinding? _previewBinding;
  LlmThinkingLevel? _previewLevel;
  bool _showModels = false;

  Future<void> _chooseModel(LlmRoleBinding binding) async {
    if (widget.vm.isSending) return;
    setState(() => _showModels = false);
    await widget.vm.setRoleBinding(LlmProfileRole.main, binding);
  }

  Future<void> _saveLevel(
      LlmRoleBinding binding, LlmThinkingLevel level) async {
    if (widget.vm.isSending) return;
    await widget.vm.setModelThinkingLevel(binding, level);
    if (mounted && _previewBinding == binding && _previewLevel == level) {
      setState(() {
        _previewBinding = null;
        _previewLevel = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.vm,
        builder: (context, _) {
          final binding = widget.vm.mainBinding;
          final config = widget.vm.mainConfig;
          final levels =
              LlmThinking.levels(config.protocol, config.baseUrl, config.model);
          final chosen = (_previewBinding == binding ? _previewLevel : null) ??
              config.thinkingLevel;
          final index = levels.indexOf(chosen).clamp(0, levels.length - 1);
          final level = levels[index];
          final levelLabel = LlmThinking.label(config.model, level);
          final theme = Theme.of(context);
          final colors = theme.colorScheme;
          final glass = FrostedTheme.of(context);
          final dark = theme.brightness == Brightness.dark;
          final peak = index > 0 && index == levels.length - 1;
          final accent = peak
              ? (dark ? const Color(0xffc28aff) : const Color(0xff6c40b5))
              : (dark ? const Color(0xff71b4ff) : const Color(0xff305eac));
          final duration = MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150);
          final providerName = widget.vm.providers
              .where((p) => p.id == binding.providerId)
              .firstOrNull
              ?.name;

          final controls = _showModels
              ? ModelSelectionSheet(
                  key: const ValueKey('chat-model-inline-picker'),
                  providers: widget.vm.providers,
                  selected: binding,
                  title: '选择模型',
                  onBack: () => setState(() => _showModels = false),
                  onSelected: _chooseModel,
                )
              : SingleChildScrollView(
                  key: const ValueKey('chat-model-thinking-controls'),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      Expanded(
                        child: TextButton(
                          key: const ValueKey('chat-model-menu-choose'),
                          onPressed: widget.vm.isSending
                              ? null
                              : () => setState(() => _showModels = true),
                          style: TextButton.styleFrom(
                            foregroundColor: colors.onSurface,
                            alignment: AlignmentDirectional.centerStart,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (providerName?.isNotEmpty ?? false)
                                    Text(providerName!,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                                color:
                                                    colors.onSurfaceVariant)),
                                  Text(
                                      binding.model.isEmpty
                                          ? '选择主模型'
                                          : binding.model,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.unfold_more_rounded, size: 18),
                          ]),
                        ),
                      ),
                      if (levels.length > 1)
                        IconButton(
                          tooltip: '恢复自动思考',
                          onPressed: index == 0 || widget.vm.isSending
                              ? null
                              : () {
                                  setState(() {
                                    _previewBinding = binding;
                                    _previewLevel = LlmThinkingLevel.automatic;
                                  });
                                  _saveLevel(
                                      binding, LlmThinkingLevel.automatic);
                                },
                          icon: const Icon(Icons.restart_alt_rounded, size: 19),
                        ),
                    ]),
                    if (levels.length > 1) ...[
                      Divider(height: 16, color: glass.border),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(children: [
                          Expanded(
                              child: Text('思考等级',
                                  style: theme.textTheme.labelMedium)),
                          AnimatedSwitcher(
                            duration: duration,
                            child: Text(
                              levelLabel,
                              key: ValueKey(levelLabel),
                              style: theme.textTheme.titleMedium?.copyWith(
                                  color: accent, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ]),
                      ),
                      _ThinkingSlider(
                        key: ValueKey(binding),
                        index: index,
                        divisions: levels.length - 1,
                        colorDuration: duration,
                        labelAt: (index) =>
                            LlmThinking.label(config.model, levels[index]),
                        onChanged: widget.vm.isSending
                            ? null
                            : (index) {
                                setState(() {
                                  _previewBinding = binding;
                                  _previewLevel = levels[index];
                                });
                              },
                        onChangeEnd: (index) =>
                            _saveLevel(binding, levels[index]),
                      ),
                    ] else if (binding.model.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 5, 10, 4),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text('此模型使用默认思考设置',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant)),
                        ),
                      ),
                  ]),
                );
          final content = duration == Duration.zero
              ? controls
              : AnimatedSize(
                  alignment: Alignment.bottomCenter,
                  duration: const Duration(milliseconds: 210),
                  curve: Curves.easeOutCubic,
                  child: AnimatedSwitcher(
                    duration: duration,
                    layoutBuilder: (current, _) =>
                        current ?? const SizedBox.shrink(),
                    child: controls,
                  ),
                );
          return TextFieldTapRegion(
            child: FrostedSurface(
              key: const ValueKey('chat-model-thinking-menu'),
              radius: 22,
              blur: 0,
              color: theme.dialogTheme.backgroundColor ??
                  colors.surfaceContainerHigh,
              child: content,
            ),
          );
        },
      );
}

class _ThinkingSlider extends StatefulWidget {
  const _ThinkingSlider({
    super.key,
    required this.index,
    required this.divisions,
    required this.colorDuration,
    required this.labelAt,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final int index;
  final int divisions;
  final Duration colorDuration;
  final String Function(int) labelAt;
  final ValueChanged<int>? onChanged;
  final ValueChanged<int> onChangeEnd;

  bool get atPeak => index == divisions;

  @override
  State<_ThinkingSlider> createState() => _ThinkingSliderState();
}

class _ThinkingSliderState extends State<_ThinkingSlider>
    with SingleTickerProviderStateMixin {
  late final _stretch = AnimationController.unbounded(vsync: this);
  int? _pointer;
  Offset _downPosition = Offset.zero;
  bool _horizontalDrag = false;
  bool _pullLeft = false;

  bool get _canStretch =>
      widget.onChanged != null && widget.colorDuration != Duration.zero;

  @override
  void didUpdateWidget(covariant _ThinkingSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_canStretch) {
      _pointer = null;
      if (_stretch.value != 0 || _stretch.isAnimating) _stretch.value = 0;
    }
  }

  void _startPull(PointerDownEvent event) {
    if (!_canStretch || _pointer != null || event.buttons != kPrimaryButton) {
      return;
    }
    _pointer = event.pointer;
    _downPosition = event.localPosition;
    _horizontalDrag = false;
    if (_stretch.value != 0 || _stretch.isAnimating) _stretch.value = 0;
  }

  void _updatePull(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final movement = event.localPosition - _downPosition;
    if (!_horizontalDrag) {
      final slop =
          computeHitSlop(event.kind, MediaQuery.gestureSettingsOf(context));
      if (movement.dy.abs() > slop && movement.dy.abs() > movement.dx.abs()) {
        _pointer = null;
        return;
      }
      if (movement.dx.abs() <= slop || movement.dx.abs() <= movement.dy.abs()) {
        return;
      }
      _horizontalDrag = true;
    }

    // Use the resting discrete thumb centers, even while painting the stretch.
    const inset = _thinkingOverlayRadius + _thinkingTrackHeight / 2;
    final width = context.size!.width;
    if (width <= 2 * inset) return;
    final x = event.localPosition.dx;
    final distance = x - x.clamp(inset, width - inset);
    final strength = distance.abs() / (distance.abs() + 24);
    final left = distance < 0;
    if (_stretch.value != strength || _pullLeft != left) {
      _pullLeft = left;
      _stretch.value = strength;
    }
  }

  void _finishPull(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (_stretch.value == 0) return;
    _stretch.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 420, damping: 27),
      _stretch.value,
      0,
      0,
      snapToEnd: true,
    ));
  }

  @override
  void dispose() {
    _stretch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final track = theme.brightness == Brightness.dark
        ? const Color(0xff3a82ee)
        : const Color(0xff356ed6);
    return Listener(
      onPointerDown: _startPull,
      onPointerMove: _updatePull,
      onPointerUp: _finishPull,
      onPointerCancel: _finishPull,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: widget.atPeak ? 1 : 0),
        duration: widget.colorDuration,
        curve: Curves.easeOutCubic,
        builder: (context, blend, slider) => AnimatedBuilder(
          animation: _stretch,
          builder: (context, child) {
            final pullingMinimum =
                _pullLeft == (Directionality.of(context) == TextDirection.ltr);
            final atPulledEnd =
                pullingMinimum ? widget.index == 0 : widget.atPeak;
            final strength = atPulledEnd ? _stretch.value : 0.0;
            final pullDistance = strength * 16;
            final thumbOffset = (_pullLeft ? -1 : 1) * pullDistance * .72;
            return SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: _thinkingTrackHeight,
                activeTrackColor: track,
                inactiveTrackColor: colors.onSurface.withValues(alpha: .14),
                thumbColor: const Color(0xfffcfcff),
                overlayColor: Color.lerp(track, const Color(0xffa879f4), blend)!
                    .withValues(alpha: .16),
                activeTickMarkColor: Colors.white.withValues(alpha: .42),
                inactiveTickMarkColor:
                    colors.onSurfaceVariant.withValues(alpha: .58),
                trackShape: _ThinkingCapsuleTrack(
                  blend: blend,
                  pullLeft: _pullLeft,
                  pullDistance: pullDistance,
                  heightFactor: 1 - .24 * strength,
                  thumbOffset: thumbOffset,
                  atPeak: widget.atPeak,
                ),
                thumbShape: _ThinkingThumb(thumbOffset),
                overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: _thinkingOverlayRadius),
                tickMarkShape: widget.atPeak
                    ? SliderTickMarkShape.noTickMark
                    : const RoundSliderTickMarkShape(tickMarkRadius: 2.4),
                showValueIndicator: ShowValueIndicator.never,
              ),
              child: child!,
            );
          },
          child: slider,
        ),
        child: Slider(
          key: const ValueKey('chat-thinking-slider'),
          value: widget.index.toDouble(),
          max: widget.divisions.toDouble(),
          divisions: widget.divisions,
          semanticFormatterCallback: (index) =>
              '思考等级：${widget.labelAt(index.round())}',
          onChanged: widget.onChanged == null
              ? null
              : (index) => widget.onChanged!(index.round()),
          onChangeEnd: (index) => widget.onChangeEnd(index.round()),
        ),
      ),
    );
  }
}

class _ThinkingThumb extends SliderComponentShape {
  const _ThinkingThumb(this.horizontalOffset);

  static const _diameter = 34.0;
  final double horizontalOffset;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(_diameter);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final color = Color.lerp(sliderTheme.disabledThumbColor,
        sliderTheme.thumbColor, enableAnimation.value)!;
    context.canvas.drawCircle(
      center.translate(horizontalOffset, 0),
      _diameter / 2,
      Paint()..color = color,
    );
  }
}

class _ThinkingCapsuleTrack extends SliderTrackShape with BaseSliderTrackShape {
  const _ThinkingCapsuleTrack({
    required this.blend,
    required this.pullLeft,
    required this.pullDistance,
    required this.heightFactor,
    required this.thumbOffset,
    required this.atPeak,
  });

  final double blend;
  final bool pullLeft;
  final double pullDistance;
  final double heightFactor;
  final double thumbOffset;
  final bool atPeak;

  @override
  bool get isRounded => true;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final track = getPreferredRect(
        parentBox: parentBox,
        offset: offset,
        sliderTheme: sliderTheme,
        isEnabled: isEnabled,
        isDiscrete: isDiscrete);
    final height = track.height * heightFactor;
    final bounds = Rect.fromLTRB(
      track.left - (pullLeft ? pullDistance : 0),
      track.center.dy - height / 2,
      track.right + (pullLeft ? 0 : pullDistance),
      track.center.dy + height / 2,
    );
    final capsule =
        RRect.fromRectAndRadius(bounds, Radius.circular(height / 2));
    final active = sliderTheme.activeTrackColor!;
    final rest = sliderTheme.inactiveTrackColor!;
    final canvas = context.canvas;
    if (!isEnabled) {
      canvas.drawRRect(capsule, Paint()..color = rest);
      return;
    }
    final activePaint = Paint()..color = active;
    if (blend > 0) {
      activePaint.shader = LinearGradient(
        begin: AlignmentDirectional.centerStart,
        end: AlignmentDirectional.centerEnd,
        stops: const [0, .58, 1],
        colors: [
          Color.lerp(active, const Color(0xff6651d6), blend)!,
          Color.lerp(active, const Color(0xffaf83f3), blend)!,
          Color.lerp(active, const Color(0xff7543d2), blend)!,
        ],
      ).createShader(bounds, textDirection: textDirection);
    }
    if (atPeak) {
      canvas.drawRRect(capsule, activePaint);
      return;
    }
    final center =
        (thumbCenter.dx + thumbOffset).clamp(bounds.left, bounds.right);
    final filled = textDirection == TextDirection.rtl
        ? Rect.fromLTRB(center, bounds.top, bounds.right, bounds.bottom)
        : Rect.fromLTRB(bounds.left, bounds.top, center, bounds.bottom);
    canvas.drawRRect(capsule, Paint()..color = rest);
    canvas.save();
    canvas.clipRRect(capsule);
    canvas.drawRect(filled, activePaint);
    canvas.restore();
  }
}
