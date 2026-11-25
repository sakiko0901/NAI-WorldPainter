import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/navigation/app_destination.dart';
import 'package:nai_huishi/presentation/widgets/studio_animated_icon.dart';

/// A continuous glass surface, without a boxed outline around the bottom bar.
class StudioBottomSurface extends StatelessWidget {
  final Widget child;
  final bool navigation;
  final Color? backgroundColor;
  const StudioBottomSurface(
      {super.key,
      required this.child,
      this.backgroundColor,
      this.navigation = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = FrostedTheme.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final surface = backgroundColor ?? theme.colorScheme.surface;
    if (navigation) {
      final tint = backgroundColor ?? theme.scaffoldBackgroundColor;
      return ClipRect(
          child: Stack(children: [
        if (glass.blurEnabled && !highContrast)
          for (final pass in const [
            (sigma: 3.0, start: 0.0),
            (sigma: 9.0, start: .24)
          ])
            Positioned.fill(
                child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: pass.sigma, sigmaY: pass.sigma),
              child: DecoratedBox(
                  decoration: BoxDecoration(
                backgroundBlendMode: BlendMode.dstIn,
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: const [
                      Colors.transparent,
                      Color(0x32ffffff),
                      Color(0xc8ffffff),
                      Colors.white
                    ],
                    stops: [
                      pass.start,
                      pass.start + .22,
                      .8,
                      1
                    ]),
              )),
            )),
        DecoratedBox(
            decoration: BoxDecoration(
                gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                tint.withValues(alpha: highContrast ? 1 : 0),
                tint.withValues(alpha: highContrast ? 1 : .48),
                tint.withValues(alpha: highContrast ? 1 : .94)
              ],
              stops: const [0, .55, 1],
            )),
            child: child),
      ]));
    }
    return ClipRect(
      child: BackdropFilter(
        enabled: glass.blurEnabled && !highContrast,
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, .45, 1],
              colors: [
                surface.withValues(alpha: highContrast ? 1 : 0),
                surface.withValues(alpha: highContrast ? 1 : .8),
                surface.withValues(alpha: highContrast ? 1 : .96),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class StudioNavigationBar extends StatefulWidget {
  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;
  final Color? backgroundColor;

  const StudioNavigationBar(
      {super.key,
      required this.selected,
      required this.onSelected,
      this.backgroundColor});

  static double contentHeightOf(BuildContext context) =>
      56 + (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(0.0, 32.0);

  @override
  State<StudioNavigationBar> createState() => _StudioNavigationBarState();
}

class _StudioNavigationBarState extends State<StudioNavigationBar> {
  Timer? _idle;
  bool _showSelection = true;

  void _restartIdle() {
    _idle?.cancel();
    if (!_showSelection) setState(() => _showSelection = true);
    _idle = Timer(const Duration(milliseconds: 1400),
        () => setState(() => _showSelection = false));
  }

  @override
  void initState() {
    super.initState();
    _restartIdle();
  }

  @override
  void didUpdateWidget(StudioNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) _restartIdle();
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final theme = Theme.of(context);
    final glass = FrostedTheme.of(context);
    final selectedForeground =
        glass.appearanceMode == AppearanceMode.coffeePaper
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface;
    final highContrast = MediaQuery.highContrastOf(context);
    return StudioBottomSurface(
      navigation: true,
      backgroundColor: widget.backgroundColor,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: StudioNavigationBar.contentHeightOf(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 3),
            child: Stack(
              children: [
                Positioned.fill(
                    child: AnimatedOpacity(
                  opacity: _showSelection ? 1 : 0,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 420),
                  curve: Curves.easeInOut,
                  child: _NavigationSelection(
                    index: selected.index,
                    child: DecoratedBox(
                      key: const ValueKey('navigation-selection'),
                      decoration: BoxDecoration(
                        color: glass.selection.withValues(
                            alpha: highContrast
                                ? 1
                                : theme.brightness == Brightness.dark
                                    ? .12
                                    : glass.appearanceMode ==
                                            AppearanceMode.coffeePaper
                                        ? .85
                                        : .45),
                        borderRadius: BorderRadius.circular(26),
                        border: highContrast
                            ? Border.all(color: glass.border)
                            : null,
                      ),
                    ),
                  ),
                )),
                Row(
                  children: [
                    for (final destination in AppDestination.values)
                      Expanded(
                        child: Semantics(
                          selected: destination == selected,
                          button: true,
                          label: destination.label,
                          child: Tooltip(
                            message: destination.label,
                            excludeFromSemantics: true,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                key: ValueKey('navigation-${destination.name}'),
                                borderRadius: BorderRadius.circular(16),
                                splashFactory: NoSplash.splashFactory,
                                highlightColor: Colors.transparent,
                                onTap: () {
                                  _restartIdle();
                                  if (destination == selected) return;
                                  HapticFeedback.selectionClick();
                                  widget.onSelected(destination);
                                },
                                child: ExcludeSemantics(
                                  child: Builder(
                                    builder: (context) {
                                      final color = destination == selected
                                          ? (highContrast
                                              ? (_showSelection
                                                  ? glass.onSelection
                                                  : theme.colorScheme.onSurface)
                                              : selectedForeground)
                                          : theme.colorScheme.onSurfaceVariant;
                                      return Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          StudioAnimatedIcon(
                                              switch (destination) {
                                                AppDestination.create =>
                                                  CupertinoIcons.pen,
                                                AppDestination.assistant =>
                                                  CupertinoIcons.sparkles,
                                                AppDestination.tools =>
                                                  CupertinoIcons
                                                      .square_grid_2x2,
                                              },
                                              selected: destination == selected,
                                              size: 24,
                                              color: color),
                                          const SizedBox(height: 3),
                                          Text(destination.label,
                                              maxLines: 1,
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  height: 1.25,
                                                  fontWeight: FontWeight.w600,
                                                  color: color)),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Only the glass highlight animates; labels and the backdrop stay still.
/// Edges travel at different speeds to stretch toward the selected tab, then
/// gather into a capsule. Retarget from the painted shape during rapid taps.
class _NavigationSelection extends StatefulWidget {
  final int index;
  final Widget child;

  const _NavigationSelection({required this.index, required this.child});

  @override
  State<_NavigationSelection> createState() => _NavigationSelectionState();
}

class _NavigationSelectionState extends State<_NavigationSelection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1,
  );
  late Rect _from = _target;
  Rect get _target => Rect.fromLTWH(widget.index.toDouble(), 0, 1, 1);
  bool _reduceMotion = false;

  Rect _shapeFor(Rect target) {
    final t = _controller.value;
    final forward = target.center.dx >= _from.center.dx;
    // A very small overshoot gives the leading edge a soft landing.
    final leading = const Cubic(.2, .9, .3, 1.025).transform(t);
    final trailing = Curves.easeInOutCubic.transform(t);
    final squeeze = math.sin(math.pi * t) *
        (target.center.dx - _from.center.dx).abs().clamp(0.0, 1.0) *
        .035;
    return Rect.fromLTRB(
      lerpDouble(_from.left, target.left, forward ? trailing : leading)!,
      lerpDouble(_from.top, 0, trailing)! + squeeze,
      lerpDouble(_from.right, target.right, forward ? leading : trailing)!,
      lerpDouble(_from.bottom, 1, trailing)! - squeeze,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant _NavigationSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    _from = _shapeFor(Rect.fromLTWH(oldWidget.index.toDouble(), 0, 1, 1));
    if (_reduceMotion) {
      _from = _target;
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: LayoutBuilder(builder: (context, constraints) {
            final slot = constraints.maxWidth / AppDestination.values.length;
            return AnimatedBuilder(
              animation: _controller,
              child: widget.child,
              builder: (context, child) {
                final shape = _shapeFor(_target);
                return Stack(children: [
                  PositionedDirectional(
                    start: shape.left * slot + 5,
                    width: shape.width * slot - 10,
                    top: shape.top * constraints.maxHeight,
                    height: shape.height * constraints.maxHeight,
                    child: child!,
                  ),
                ]);
              },
            );
          }),
        ),
      );
}
