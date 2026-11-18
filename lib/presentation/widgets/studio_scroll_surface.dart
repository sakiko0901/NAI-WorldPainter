import 'dart:ui';
import 'studio_entrance.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:nai_huishi/presentation/app_theme.dart';

/// Keeps scrolling content behind fixed controls, with padding at its ends.
/// The history panel shares the header blur without needing a chat footer.
class StudioScrollSurface extends StatefulWidget {
  final Widget header;
  final double initialHeaderHeight;
  final Widget? footer;
  final Widget Function(EdgeInsets insets) bodyBuilder;
  final VoidCallback? onInsetsChanged;
  final double footerBottomInset;
  final Widget? background;

  const StudioScrollSurface({
    super.key,
    required this.header,
    this.initialHeaderHeight = 62,
    this.footer,
    required this.bodyBuilder,
    this.onInsetsChanged,
    this.footerBottomInset = 0,
    this.background,
  });

  @override
  State<StudioScrollSurface> createState() => _StudioScrollSurfaceState();
}

class _StudioScrollSurfaceState extends State<StudioScrollSurface> {
  late double _headerHeight = widget.initialHeaderHeight;
  double _footerHeight = 84;

  void _updateHeight(double height, {required bool header}) {
    if (!mounted || height == (header ? _headerHeight : _footerHeight)) return;
    setState(() {
      if (header) {
        _headerHeight = height;
      } else {
        _footerHeight = height;
      }
    });
    // Scroll extents are updated in the following layout, after the end
    // padding has caught up with an expanding composer or keyboard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onInsetsChanged?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final motion =
        context.dependOnInheritedWidgetOfExactType<StudioEntranceScope>();
    final body = widget.bodyBuilder(EdgeInsets.only(
      top: _headerHeight + 16,
      bottom: widget.footer == null ? 20 : _footerHeight + 20,
    ));
    return LayoutBuilder(
        builder: (context, constraints) => ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.background != null)
                    Positioned.fill(child: widget.background!),
                  if (motion == null)
                    body
                  else
                    AnimatedBuilder(
                      animation: motion.animation,
                      child: body,
                      builder: (context, child) {
                        final remaining = 1 -
                            const Cubic(.32, .05, .18, 1)
                                .transform(motion.animation.value);
                        return Transform.translate(
                            offset: Offset(-6 * motion.direction * remaining,
                                2 * remaining),
                            child: child);
                      },
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: _headerHeight + 48,
                    child: const _EdgeBlur(),
                  ),
                  if (widget.footer != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: _footerHeight + 32,
                      child: _FooterVeil(
                        bottomInset: widget.footerBottomInset,
                        pageHeight: constraints.maxHeight,
                        background: widget.background,
                      ),
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _MeasureHeight(
                      onHeight: (height) => _updateHeight(height, header: true),
                      child: widget.header,
                    ),
                  ),
                  if (widget.footer != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _MeasureHeight(
                        onHeight: (height) =>
                            _updateHeight(height, header: false),
                        child: widget.footer!,
                      ),
                    ),
                ],
              ),
            ));
  }
}

class _EdgeBlur extends StatelessWidget {
  const _EdgeBlur();

  // Each pass softens the previous result over a wide, overlapping ramp.
  // Unlike blending a single strong blur with the sharp image, this does not
  // leave readable letter outlines underneath a blurred halo. No hard strips.
  static final _passes = [
    (fadeEnd: 1.0, filter: ImageFilter.blur(sigmaX: 1.25, sigmaY: 1.25)),
    (fadeEnd: .85, filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5)),
    (fadeEnd: .68, filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5)),
    (fadeEnd: .48, filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10)),
  ];

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).colorScheme.surface;
    final highContrast = MediaQuery.highContrastOf(context);
    final blur = FrostedTheme.of(context).blurEnabled && !highContrast;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: ClipRect(
          child: Stack(fit: StackFit.expand, children: [
            if (blur)
              for (final pass in _passes)
                // Use the same clip for every pass: clipping at each fade end
                // introduces subpixel seams when the backdrop is sampled.
                // Keep masks inside the backdrop layers and do not group them;
                // each pass must sample the previously softened output.
                BackdropFilter(
                  filter: pass.filter,
                  child: CustomPaint(painter: _BlurMask(end: pass.fadeEnd)),
                ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, .3, .65, 1],
                  colors: [
                    background.withValues(alpha: highContrast ? 1 : .12),
                    background.withValues(alpha: highContrast ? 1 : .06),
                    background.withValues(alpha: highContrast ? .7 : .015),
                    background.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _BlurMask extends CustomPainter {
  final double end;
  const _BlurMask({required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, .25 * end, .4 * end, .55 * end, .7 * end, .85 * end, end],
          colors: const [
            Colors.white,
            Colors.white,
            Color(0xF0FFFFFF),
            Color(0xAEFFFFFF),
            Color(0x51FFFFFF),
            Color(0x0FFFFFFF),
            Color(0x00FFFFFF),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_BlurMask oldDelegate) => oldDelegate.end != end;
}

/// The composer provides its own clipped glass. Below it, restore the ambient
/// page background without blurring the same messages across the whole footer.
class _FooterVeil extends StatelessWidget {
  final double bottomInset;
  final double pageHeight;
  final Widget? background;
  const _FooterVeil(
      {required this.bottomInset, required this.pageHeight, this.background});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).scaffoldBackgroundColor;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(builder: (context, constraints) {
          final height = constraints.maxHeight;
          final fadeEnd = ((height - bottomInset) / height).clamp(0.01, 1.0);
          final fadeStart = (fadeEnd - 28 / height).clamp(0.0, fadeEnd);
          // Reveal the exact same full-page background beneath the composer.
          // A solid black scrim here changes the page's grey glass palette.
          // Only this small footer is masked; the scrolling list stays intact.
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, fadeStart, fadeEnd, 1],
              colors: const [
                Colors.transparent,
                Colors.transparent,
                Colors.white,
                Colors.white,
              ],
            ).createShader(rect),
            child: ClipRect(
              child: Stack(fit: StackFit.expand, children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: pageHeight,
                  child: ColoredBox(color: base, child: background),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }
}

class _MeasureHeight extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onHeight;
  const _MeasureHeight({required this.onHeight, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _HeightReporter(onHeight);

  @override
  void updateRenderObject(BuildContext context, _HeightReporter renderObject) {
    renderObject.onHeight = onHeight;
  }
}

class _HeightReporter extends RenderProxyBox {
  ValueChanged<double> onHeight;
  double? _lastHeight;
  _HeightReporter(this.onHeight);

  @override
  void performLayout() {
    super.performLayout();
    if (_lastHeight == size.height) return;
    _lastHeight = size.height;
    final height = size.height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached && _lastHeight == height) onHeight(height);
    });
  }
}
