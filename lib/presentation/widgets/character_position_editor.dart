import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/presentation/app_theme.dart';

class CharacterPositionEditor extends StatefulWidget {
  final double aspectRatio;
  final bool continuous;
  final int roleNumber;
  final double? x, y;
  final ValueChanged<Offset> onChanged;
  final VoidCallback onAuto;
  final ValueChanged<bool>? onGestureActive;

  const CharacterPositionEditor(
      {super.key,
      required this.aspectRatio,
      required this.continuous,
      required this.roleNumber,
      this.x,
      this.y,
      required this.onChanged,
      required this.onAuto,
      this.onGestureActive});

  @override
  State<CharacterPositionEditor> createState() =>
      _CharacterPositionEditorState();
}

class _CharacterPositionEditorState extends State<CharacterPositionEditor> {
  final _xController = TextEditingController();
  final _yController = TextEditingController();
  final _xFocus = FocusNode();
  final _yFocus = FocusNode();
  int? _pointer;

  bool get _manual => widget.x != null && widget.y != null;
  Offset get _point => Offset(widget.x ?? .5, widget.y ?? .5);

  @override
  void initState() {
    super.initState();
    _xFocus.addListener(_syncFields);
    _yFocus.addListener(_syncFields);
    _syncFields();
  }

  void _syncFields() {
    if (!_xFocus.hasFocus) _xController.text = _point.dx.toStringAsFixed(3);
    if (!_yFocus.hasFocus) _yController.text = _point.dy.toStringAsFixed(3);
  }

  @override
  void didUpdateWidget(covariant CharacterPositionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFields();
  }

  @override
  void dispose() {
    if (_pointer != null) {
      final callback = widget.onGestureActive;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => callback?.call(false));
    }
    _xFocus.removeListener(_syncFields);
    _yFocus.removeListener(_syncFields);
    _xController.dispose();
    _yController.dispose();
    _xFocus.dispose();
    _yFocus.dispose();
    super.dispose();
  }

  double _coordinate(double value) => widget.continuous
      ? value.clamp(0.0, 1.0)
      : (.1 + ((value - .1) / .2).round().clamp(0, 4) * .2);

  void _update(double x, double y) =>
      widget.onChanged(Offset(_coordinate(x), _coordinate(y)));

  void _release(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    widget.onGestureActive?.call(false);
  }

  Widget _coordinateField(bool horizontal) {
    final controller = horizontal ? _xController : _yController;
    final focus = horizontal ? _xFocus : _yFocus;
    return Expanded(
        child: TextField(
      key: ValueKey(
          horizontal ? 'character-coordinate-x' : 'character-coordinate-y'),
      controller: controller,
      focusNode: focus,
      enabled: _manual,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        TextInputFormatter.withFunction((oldValue, newValue) =>
            RegExp(r'^-?\d*\.?\d*$').hasMatch(newValue.text)
                ? newValue
                : oldValue)
      ],
      style: const TextStyle(
          fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
      textAlign: TextAlign.end,
      decoration: InputDecoration(
          labelText: horizontal ? 'X' : 'Y',
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
      onChanged: (value) {
        final number = double.tryParse(value);
        if (number == null || !number.isFinite) return;
        _update(
            horizontal ? number : _point.dx, horizontal ? _point.dy : number);
      },
      onEditingComplete: () {
        focus.unfocus();
        _syncFields();
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final glass = FrostedTheme.of(context);
    final ratio = widget.aspectRatio.isFinite && widget.aspectRatio > 0
        ? widget.aspectRatio
        : 1.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
            child: Text('角色位置',
                style:
                    TextStyle(fontSize: 12, color: colors.onSurfaceVariant))),
        CupertinoSlidingSegmentedControl<bool>(
          groupValue: _manual,
          backgroundColor: glass.field,
          thumbColor: glass.selection,
          children: {
            for (final manual in [false, true])
              manual: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Text(manual ? '手动' : '自动',
                      style: TextStyle(
                          fontSize: 11,
                          color: _manual == manual
                              ? glass.onSelection
                              : colors.onSurfaceVariant)))
          },
          onValueChanged: (manual) {
            if (manual == false) {
              widget.onAuto();
            } else if (manual == true) {
              _update(_point.dx, _point.dy);
            }
          },
        ),
      ]),
      Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(builder: (context, constraints) {
            final width = math.min(constraints.maxWidth, 340 * ratio);
            final height = width / ratio;
            void at(Offset point) =>
                _update(point.dx / width, point.dy / height);
            final board = SizedBox(
              key: ValueKey(widget.continuous
                  ? 'free-character-position'
                  : 'legacy-character-position'),
              width: width,
              height: height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: glass.stage,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.outlineVariant)),
                child: widget.continuous
                    ? Stack(clipBehavior: Clip.none, children: [
                        for (final fraction in [.2, .4, .6, .8]) ...[
                          Positioned(
                              left: width * fraction,
                              top: 0,
                              bottom: 0,
                              child: ColoredBox(
                                  color: glass.border,
                                  child: const SizedBox(width: 1))),
                          Positioned(
                              top: height * fraction,
                              left: 0,
                              right: 0,
                              child: ColoredBox(
                                  color: glass.border,
                                  child: const SizedBox(height: 1))),
                        ],
                        if (_manual)
                          Positioned(
                            left: widget.x! * width - 13,
                            top: widget.y! * height - 13,
                            child: Container(
                                key:
                                    const ValueKey('character-position-marker'),
                                width: 26,
                                height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: glass.selection,
                                    border: Border.all(
                                        color: colors.onSurface
                                            .withValues(alpha: .6)),
                                    boxShadow: [
                                      BoxShadow(
                                          color: colors.onSurface
                                              .withValues(alpha: .1),
                                          blurRadius: 6)
                                    ]),
                                child: Text('${widget.roleNumber}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: glass.onSelection))),
                          ),
                      ])
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: GridView.count(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 5,
                          childAspectRatio: ratio,
                          children: [
                            for (var row = 0; row < 5; row++)
                              for (var col = 0; col < 5; col++)
                                Semantics(
                                    button: true,
                                    selected: _manual &&
                                        (widget.x! - (.1 + col * .2)).abs() <
                                            .01 &&
                                        (widget.y! - (.1 + row * .2)).abs() <
                                            .01,
                                    label:
                                        '位置 ${String.fromCharCode(65 + col)}${row + 1}',
                                    child: InkWell(
                                        onTap: () => _update(
                                            .1 + col * .2, .1 + row * .2),
                                        child: DecoratedBox(
                                            decoration: BoxDecoration(
                                                border: Border.all(
                                                    color: glass.border,
                                                    width: .5),
                                                color: _manual &&
                                                        (widget.x! - (.1 + col * .2))
                                                                .abs() <
                                                            .01 &&
                                                        (widget.y! -
                                                                    (.1 +
                                                                        row *
                                                                            .2))
                                                                .abs() <
                                                            .01
                                                    ? glass.selection
                                                    : Colors.transparent),
                                            child: const SizedBox.expand()))),
                          ],
                        )),
              ),
            );
            return Center(
                child: Semantics(
              label: '角色位置，点击或拖动设置',
              child: widget.continuous
                  ? Focus(
                      onKeyEvent: (_, event) {
                        if (event is! KeyDownEvent)
                          return KeyEventResult.ignored;
                        final step =
                            HardwareKeyboard.instance.isShiftPressed ? .1 : .01;
                        final key = event.logicalKey;
                        if (![
                          LogicalKeyboardKey.arrowLeft,
                          LogicalKeyboardKey.arrowRight,
                          LogicalKeyboardKey.arrowUp,
                          LogicalKeyboardKey.arrowDown
                        ].contains(key)) return KeyEventResult.ignored;
                        _update(
                            _point.dx +
                                (key == LogicalKeyboardKey.arrowRight
                                    ? step
                                    : key == LogicalKeyboardKey.arrowLeft
                                        ? -step
                                        : 0),
                            _point.dy +
                                (key == LogicalKeyboardKey.arrowDown
                                    ? step
                                    : key == LogicalKeyboardKey.arrowUp
                                        ? -step
                                        : 0));
                        return KeyEventResult.handled;
                      },
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) {
                          if (_pointer != null) return;
                          _xFocus.unfocus();
                          _yFocus.unfocus();
                          _pointer = event.pointer;
                          widget.onGestureActive?.call(true);
                          at(event.localPosition);
                        },
                        onPointerMove: (event) {
                          if (_pointer == event.pointer)
                            at(event.localPosition);
                        },
                        onPointerUp: _release,
                        onPointerCancel: _release,
                        child: board,
                      ),
                    )
                  : board,
            ));
          })),
      Row(children: [
        _coordinateField(true),
        const SizedBox(width: 8),
        _coordinateField(false)
      ]),
      const SizedBox(height: 7),
      Text(widget.continuous ? '连续坐标 · 0 – 1' : '5 × 5 定位',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
    ]);
  }
}
