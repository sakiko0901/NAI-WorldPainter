import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:nai_huishi/presentation/app_theme.dart';

/// Keeps the conversation behind the controls, with padding only at its ends.
class ChatScrollSurface extends StatefulWidget {
  final Widget header;
  final Widget footer;
  final Widget Function(EdgeInsets insets) bodyBuilder;
  final VoidCallback? onInsetsChanged;

  const ChatScrollSurface({
    super.key,
    required this.header,
    required this.footer,
    required this.bodyBuilder,
    this.onInsetsChanged,
  });

  @override
  State<ChatScrollSurface> createState() => _ChatScrollSurfaceState();
}

class _ChatScrollSurfaceState extends State<ChatScrollSurface> {
  double _headerHeight = 62;
  double _footerHeight = 84;

  void _updateHeight(double height, {required bool header}) {
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
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.bodyBuilder(EdgeInsets.only(
            top: _headerHeight + 16,
            bottom: _footerHeight + 20,
          )),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: _headerHeight + 24,
            child: const _EdgeBlur(),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: _footerHeight + 24,
            child: const _EdgeBlur(bottom: true),
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
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _MeasureHeight(
              onHeight: (height) => _updateHeight(height, header: false),
              child: widget.footer,
            ),
          ),
        ],
      ),
    );
  }
}

class _EdgeBlur extends StatelessWidget {
  final bool bottom;
  const _EdgeBlur({this.bottom = false});

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    final highContrast = MediaQuery.highContrastOf(context);
    final blur = FrostedTheme.of(context).blurEnabled && !highContrast;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(builder: (context, constraints) {
          // Disjoint clips sample the same backdrop (shared key) without
          // repeatedly blurring each other. Only the narrow edges are filtered.
          const steps = 12;
          final bandHeight = constraints.maxHeight / steps;
          return BackdropGroup(
            child: Stack(fit: StackFit.expand, children: [
              if (blur)
                for (var i = 0; i < steps; i++)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: i * bandHeight,
                    height: bandHeight,
                    child: ClipRect(
                      child: BackdropFilter.grouped(
                        filter: ImageFilter.blur(
                          sigmaX: _sigma(i, steps),
                          sigmaY: _sigma(i, steps),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin:
                        bottom ? Alignment.topCenter : Alignment.bottomCenter,
                    end: bottom ? Alignment.bottomCenter : Alignment.topCenter,
                    stops: const [0, 0.32, 0.72, 1],
                    colors: [
                      background.withValues(alpha: 0),
                      background.withValues(alpha: highContrast ? 0.65 : 0.12),
                      background.withValues(alpha: highContrast ? 1 : 0.55),
                      background.withValues(alpha: highContrast ? 1 : 0.92),
                    ],
                  ),
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }

  double _sigma(int index, int steps) {
    final t = (index + 0.5) / steps;
    final strength = bottom ? t : 1 - t;
    return (bottom ? 5 : 9) * strength * strength;
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
