import 'dart:io';

import 'package:flutter/material.dart';

/// Both images keep identical bounds; dragging only changes the reveal clip.
class InpaintComparison extends StatefulWidget {
  final String beforePath;
  final String afterPath;
  final ValueChanged<bool> onGestureActive;

  const InpaintComparison({
    super.key,
    required this.beforePath,
    required this.afterPath,
    required this.onGestureActive,
  });

  @override
  State<InpaintComparison> createState() => _InpaintComparisonState();
}

class _InpaintComparisonState extends State<InpaintComparison> {
  double _position = 0.5;

  void _move(Offset point, double width) {
    if (width <= 0) return;
    setState(() => _position = (point.dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => Semantics(
          label: '重绘前后滑动对比',
          value: '重绘后显示 ${(_position * 100).round()}%',
          increasedValue:
              '重绘后显示 ${((_position + 0.1).clamp(0.0, 1.0) * 100).round()}%',
          decreasedValue:
              '重绘后显示 ${((_position - 0.1).clamp(0.0, 1.0) * 100).round()}%',
          onIncrease: () => setState(
            () => _position = (_position + 0.1).clamp(0.0, 1.0),
          ),
          onDecrease: () => setState(
            () => _position = (_position - 0.1).clamp(0.0, 1.0),
          ),
          child: Listener(
            onPointerDown: (_) => widget.onGestureActive(true),
            onPointerUp: (_) => widget.onGestureActive(false),
            onPointerCancel: (_) => widget.onGestureActive(false),
            child: GestureDetector(
              key: const ValueKey('inpaint-comparison-drag'),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (event) =>
                  _move(event.localPosition, constraints.maxWidth),
              onHorizontalDragUpdate: (event) =>
                  _move(event.localPosition, constraints.maxWidth),
              onHorizontalDragEnd: (_) => widget.onGestureActive(false),
              onHorizontalDragCancel: () => widget.onGestureActive(false),
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(widget.beforePath), fit: BoxFit.fill),
                    ClipRect(
                      key: const ValueKey('inpaint-comparison-reveal'),
                      clipper: InpaintRevealClipper(_position),
                      child:
                          Image.file(File(widget.afterPath), fit: BoxFit.fill),
                    ),
                    const Positioned(left: 8, top: 8, child: _Label('重绘后')),
                    const Positioned(right: 8, top: 8, child: _Label('重绘前')),
                    Positioned(
                      left: constraints.maxWidth * _position - 1,
                      top: 0,
                      bottom: 0,
                      width: 2,
                      child: const ColoredBox(color: Colors.white),
                    ),
                    Positioned(
                      left: constraints.maxWidth * _position - 18,
                      top: constraints.maxHeight / 2 - 18,
                      width: 36,
                      height: 36,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xE6222630),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 8),
                          ],
                        ),
                        child: const Icon(
                          Icons.swap_horiz,
                          color: Colors.white,
                          size: 21,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class InpaintRevealClipper extends CustomClipper<Rect> {
  final double fraction;
  const InpaintRevealClipper(this.fraction);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction.clamp(0.0, 1.0), size.height);

  @override
  bool shouldReclip(InpaintRevealClipper oldClipper) =>
      oldClipper.fraction != fraction;
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xB31A1C22),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Text(text,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ),
      );
}
