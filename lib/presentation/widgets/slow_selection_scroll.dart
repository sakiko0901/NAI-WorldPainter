import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A single observer above the navigator also sees selection handles living in
/// overlays. It never claims a gesture, so native selection/copy menus survive.
class SlowSelectionScroll extends StatefulWidget {
  const SlowSelectionScroll({super.key, required this.child});
  final Widget child;
  @override
  State<SlowSelectionScroll> createState() => _SlowSelectionScrollState();
}

class _SlowSelectionScrollState extends State<SlowSelectionScroll> {
  Timer? _timer;
  int? _pointer;
  Offset? _point;
  Offset? _start;
  EditableTextState? _editor;
  TextSelection? _initial;
  int? _anchor;
  bool _selecting = false;
  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
    _stop();
    super.dispose();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _pointer = null;
    _point = null;
    _editor = null;
    _anchor = null;
    _initial = null;
    _selecting = false;
  }

  Rect _visible(RenderEditable render) {
    var rect = render.localToGlobal(Offset.zero) & render.size;
    final media = MediaQuery.of(context);
    rect = rect.intersect(Rect.fromLTRB(0, media.padding.top, media.size.width,
        media.size.height - media.viewInsets.bottom - media.padding.bottom));
    RenderObject? parent = render.parent;
    while (parent != null) {
      if (parent is RenderAbstractViewport && parent is RenderBox) {
        rect = rect.intersect((parent as RenderBox).localToGlobal(Offset.zero) &
            (parent as RenderBox).size);
      }
      parent = parent.parent;
    }
    return rect;
  }

  EditableTextState? _find(Offset point) {
    EditableTextState? best;
    double distance = double.infinity;
    void visit(Element element) {
      if (element.widget is IgnorePointer &&
          (element.widget as IgnorePointer).ignoring) {
        return;
      }
      if (element.widget is Offstage && (element.widget as Offstage).offstage) {
        return;
      }
      if (element is StatefulElement && element.state is EditableTextState) {
        final state = element.state as EditableTextState;
        if (!state.widget.enableInteractiveSelection ||
            state.widget.obscureText) {
          return;
        }
        final render = state.renderEditable;
        if (!render.attached || !render.hasSize) return;
        final rect = _visible(render);
        if (rect.isEmpty || !rect.inflate(44).contains(point)) return;
        // Prefer the active editor when a sheet overlaps the page underneath.
        final d = (rect.center - point).distance -
            (state.widget.focusNode.hasFocus ? 100000 : 0);
        if (d < distance) {
          distance = d;
          best = state;
        }
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return best;
  }

  void _route(PointerEvent event) {
    if (event is PointerDownEvent) {
      if (_pointer != null) {
        _stop();
        return;
      }
      _pointer = event.pointer;
      _point = event.position;
      _start = event.position;
      _editor = _find(event.position);
      _initial = _editor?.widget.controller.selection;
      if (_editor != null) {
        _timer =
            Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
      }
    } else if (event.pointer == _pointer) {
      if (event is PointerUpEvent || event is PointerCancelEvent) {
        _stop();
      } else if (event is PointerMoveEvent) {
        _point = event.position;
      }
    }
  }

  void _tick() {
    final editor = _editor;
    final point = _point;
    if (editor == null || !editor.mounted || point == null) return;
    final value = editor.widget.controller.value;
    if (!value.selection.isValid || value.selection.isCollapsed) return;
    if (!_selecting) {
      final render = editor.renderEditable;
      final base = render.localToGlobal(
          render.getLocalRectForCaret(value.selection.base).center);
      final extent = render.localToGlobal(
          render.getLocalRectForCaret(value.selection.extent).center);
      final moved = (point - _start!).distance > 5;
      final nearHandle =
          (base - _start!).distance < 44 || (extent - _start!).distance < 44;
      if (!moved || (value.selection == _initial && !nearHandle)) return;
      _selecting = true;
      _anchor = _initial?.isCollapsed != false
          ? value.selection.baseOffset
          : (base - _start!).distance < (extent - _start!).distance
              ? value.selection.extentOffset
              : value.selection.baseOffset;
    }
    final render = editor.renderEditable;
    final rect = _visible(render);
    if (rect.isEmpty || rect.height < 20) return;
    const edge = 32.0;
    double direction = 0;
    if (point.dy > rect.bottom - edge) {
      direction =
          ((point.dy - rect.bottom + edge) / edge).clamp(.25, 1.0).toDouble();
    } else if (point.dy < rect.top + edge) {
      direction =
          -((rect.top + edge - point.dy) / edge).clamp(.25, 1.0).toDouble();
    }
    if (direction == 0) return;
    // 30–120 logical pixels/second, independent of gesture update frequency.
    final delta = direction * 120 * .016;
    bool scroll(ScrollPosition position) {
      if (!position.hasContentDimensions ||
          axisDirectionToAxis(position.axisDirection) != Axis.vertical) {
        return false;
      }
      final sign = position.axisDirection == AxisDirection.up ? -1 : 1;
      final target = (position.pixels + delta * sign)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((target - position.pixels).abs() < .01) return false;
      position.jumpTo(target);
      return true;
    }

    final changed = render.offset is ScrollPosition &&
        scroll(render.offset as ScrollPosition);
    if (!changed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_selecting || !editor.mounted || _pointer == null) {
        return;
      }
      final visible = _visible(render);
      if (visible.width < 2 || visible.height < 2) return;
      final target = Offset(point.dx.clamp(visible.left + 1, visible.right - 1),
          point.dy.clamp(visible.top + 1, visible.bottom - 1));
      final extent = render
          .getPositionForPoint(target)
          .offset
          .clamp(0, editor.widget.controller.text.length);
      final anchor = _anchor!.clamp(0, editor.widget.controller.text.length);
      // Updating the controller preserves native handles without invoking
      // EditableText's drag bringIntoView, which jumps by whole text lines.
      editor.widget.controller.selection =
          TextSelection(baseOffset: anchor, extentOffset: extent);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
