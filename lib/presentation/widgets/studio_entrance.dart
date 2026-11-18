import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// One finite clock for a destination. Data updates and scrolling never restart it.
class StudioEntranceScope extends InheritedWidget {
  const StudioEntranceScope({
    super.key,
    this.direction = 1,
    required this.animation,
    required super.child,
  });

  final double direction;
  final Animation<double> animation;

  static Animation<double> of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<StudioEntranceScope>()
          ?.animation ??
      const AlwaysStoppedAnimation(1);

  @override
  bool updateShouldNotify(StudioEntranceScope oldWidget) =>
      animation != oldWidget.animation || direction != oldWidget.direction;
}

/// Timing is local to a group, capped so long lists do not accumulate delays.
class StudioEntranceGroup extends InheritedWidget {
  const StudioEntranceGroup(
      {super.key, required this.order, required super.child});
  final int order;

  static double delayOf(BuildContext context) =>
      (context
                  .dependOnInheritedWidgetOfExactType<StudioEntranceGroup>()
                  ?.order ??
              0)
          .clamp(0, 3) *
      .025;

  @override
  bool updateShouldNotify(StudioEntranceGroup oldWidget) =>
      order != oldWidget.order;
}

enum StudioEntranceRole {
  rule(.02, .48),
  heading(.0, .52),
  icon(.10, .80),
  content(.16, .76),
  detail(.24, .90),
  action(.30, .92);

  const StudioEntranceRole(this.start, this.end);
  final double start;
  final double end;
}

/// Reveal only foreground ink; keep glass, geometry and text layout stationary.
class StudioEntrance extends StatelessWidget {
  const StudioEntrance({super.key, required this.role, required this.child});
  final StudioEntranceRole role;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = MediaQuery.disableAnimationsOf(context)
        ? const AlwaysStoppedAnimation<double>(1)
        : StudioEntranceScope.of(context);
    // Interactive surfaces and ordinary content remain complete from frame one.
    if (role != StudioEntranceRole.heading && role != StudioEntranceRole.rule) {
      return child;
    }
    return _EntrancePaint(
      animation: animation,
      role: role,
      delay: StudioEntranceGroup.delayOf(context),
      rtl: Directionality.of(context) == TextDirection.rtl,
      child: child,
    );
  }
}

class _EntrancePaint extends SingleChildRenderObjectWidget {
  const _EntrancePaint(
      {required this.animation,
      required this.role,
      required this.delay,
      required this.rtl,
      required super.child});
  final Animation<double> animation;
  final StudioEntranceRole role;
  final double delay;
  final bool rtl;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEntrance(animation, role, delay, rtl);

  @override
  void updateRenderObject(
          BuildContext context, covariant _RenderEntrance renderObject) =>
      renderObject.update(animation, role, delay, rtl);
}

class _RenderEntrance extends RenderProxyBox {
  _RenderEntrance(this._animation, this._role, this._delay, this._rtl);
  Animation<double> _animation;
  StudioEntranceRole _role;
  double _delay;
  bool _rtl;
  final _clipLayer = LayerHandle<ClipRectLayer>();

  void update(Animation<double> animation, StudioEntranceRole role,
      double delay, bool rtl) {
    if (animation != _animation) {
      if (attached) _animation.removeListener(markNeedsPaint);
      _animation = animation;
      if (attached) _animation.addListener(markNeedsPaint);
    }
    _role = role;
    _delay = delay;
    _rtl = rtl;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _animation.removeListener(markNeedsPaint);
    super.detach();
  }

  double get progress =>
      ((_animation.value - _role.start - _delay) / (_role.end - _role.start))
          .clamp(0.0, 1.0);

  Rect get reveal {
    final p = Curves.easeOutCubic.transform(progress);
    if (_role == StudioEntranceRole.icon) return Offset.zero & size;
    if (_role == StudioEntranceRole.action) {
      return Rect.fromLTWH(0, 0, size.width, size.height * p);
    }
    return Rect.fromLTWH(
        _rtl ? size.width * (1 - p) : 0, 0, size.width * p, size.height);
  }

  Offset get displacement {
    if (_role == StudioEntranceRole.rule) return Offset.zero;
    if (_role == StudioEntranceRole.icon) {
      return Offset(0, 5 * (1 - Curves.easeOutBack.transform(progress)));
    }
    return Offset.zero;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (progress == 0) return;
    if (progress == 1) {
      _clipLayer.layer = null;
      super.paint(context, offset);
      return;
    }
    _clipLayer.layer = context.pushClipRect(needsCompositing, offset, reveal,
        (context, offset) => super.paint(context, offset + displacement),
        clipBehavior: Clip.hardEdge, oldLayer: _clipLayer.layer);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform
      .multiply(Matrix4.translationValues(displacement.dx, displacement.dy, 0));

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (progress == 0 || !reveal.contains(position)) return false;
    return result.addWithPaintOffset(
        offset: displacement,
        position: position,
        hitTest: (result, position) =>
            super.hitTest(result, position: position));
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    super.dispose();
  }
}
