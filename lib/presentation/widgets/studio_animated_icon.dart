import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'studio_entrance.dart';

enum StudioIconKind {
  nib,
  stars,
  grid,
  box,
  video,
  tag,
  text,
  gallery,
  search,
  people,
  waveform,
  upscale,
  layers,
  brush,
  panels,
  download,
  menu,
  edit,
  settings,
  wand,
  dreamMoon,
  forward,
  sliders,
}

/// Original 24-unit vectors, with motion applied to individual components.
class StudioAnimatedIcon extends StatefulWidget {
  const StudioAnimatedIcon(this.icon,
      {super.key, this.size, this.color, this.selected, this.trigger});
  final bool? selected;
  final int? trigger;
  final IconData icon;
  final double? size;
  final Color? color;

  static StudioIconKind? resolve(IconData icon) => {
        CupertinoIcons.moon_stars: StudioIconKind.dreamMoon,
        CupertinoIcons.pen: StudioIconKind.nib,
        CupertinoIcons.sparkles: StudioIconKind.stars,
        CupertinoIcons.square_grid_2x2: StudioIconKind.grid,
        CupertinoIcons.cube_box: StudioIconKind.box,
        CupertinoIcons.video_camera_solid: StudioIconKind.video,
        CupertinoIcons.tag: StudioIconKind.tag,
        CupertinoIcons.text_cursor: StudioIconKind.text,
        CupertinoIcons.photo_on_rectangle: StudioIconKind.gallery,
        Icons.photo_library_outlined: StudioIconKind.gallery,
        CupertinoIcons.search: StudioIconKind.search,
        CupertinoIcons.person_2_square_stack: StudioIconKind.people,
        CupertinoIcons.waveform: StudioIconKind.waveform,
        CupertinoIcons.arrow_up_right_square: StudioIconKind.upscale,
        CupertinoIcons.square_stack_3d_up: StudioIconKind.layers,
        CupertinoIcons.paintbrush_fill: StudioIconKind.brush,
        CupertinoIcons.rectangle_3_offgrid: StudioIconKind.panels,
        CupertinoIcons.arrow_down_circle: StudioIconKind.download,
        CupertinoIcons.list_bullet: StudioIconKind.menu,
        CupertinoIcons.square_pencil: StudioIconKind.edit,
        CupertinoIcons.gear_alt: StudioIconKind.settings,
        CupertinoIcons.wand_stars: StudioIconKind.wand,
        CupertinoIcons.chevron_right: StudioIconKind.forward,
        Icons.tune: StudioIconKind.sliders,
      }[icon];

  @override
  State<StudioAnimatedIcon> createState() => _StudioAnimatedIconState();
}

class _StudioAnimatedIconState extends State<StudioAnimatedIcon>
    with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 880), value: 1);
  Animation<double>? _page;
  bool _enabled = false;
  int _ticket = 0;
  double _delay = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final page = StudioEntranceScope.of(context);
    final enabled = TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    final changed = page != _page || enabled != _enabled;
    if (page != _page) {
      _page?.removeStatusListener(_status);
      _page = page;
      page.addStatusListener(_status);
    }
    _enabled = enabled;
    if (!enabled || page is AlwaysStoppedAnimation<double>) {
      _ticket++;
      _clock.value = 1;
    } else if (changed &&
        page.status == AnimationStatus.forward &&
        page.value < .1) {
      _queue();
    }
  }

  @override
  void didUpdateWidget(StudioAnimatedIcon old) {
    super.didUpdateWidget(old);
    if (widget.selected != old.selected) {
      if (widget.selected == true && _enabled) {
        _delay = 0;
        _clock.forward(from: 0);
      } else {
        _clock.value = 1;
      }
    }
    if (widget.trigger != null && widget.trigger != old.trigger) {
      if (_enabled) {
        _delay = 0;
        _clock.forward(from: 0);
      } else {
        _clock.value = 1;
      }
    }
  }

  void _status(AnimationStatus status) {
    if (_enabled && status == AnimationStatus.forward) _queue();
  }

  void _queue() {
    if (StudioAnimatedIcon.resolve(widget.icon) == null) return;
    final ticket = ++_ticket;
    _clock.value = 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_enabled || ticket != _ticket) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final view = View.of(context);
      var rect = MatrixUtils.transformRect(
              box.getTransformTo(null), Offset.zero & box.size)
          .intersect(Offset.zero & (view.physicalSize / view.devicePixelRatio));
      RenderObject node = box;
      while (!rect.isEmpty && node.parent != null) {
        final parent = node.parent!;
        if (parent is RenderOffstage && parent.offstage) return;
        final clip = parent.describeApproximatePaintClip(node);
        if (clip != null) {
          rect = rect.intersect(
              MatrixUtils.transformRect(parent.getTransformTo(null), clip));
        }
        node = parent;
      }
      if (rect.isEmpty || !rect.isFinite) return;
      _IconBatch.add(_page!, this, ticket, rect.center.dy);
    });
  }

  void _play(int ticket, double delay) {
    if (!mounted || !_enabled || ticket != _ticket) return;
    setState(() => _delay = delay);
    _clock.forward(from: 0);
  }

  @override
  void dispose() {
    _ticket++;
    _page?.removeStatusListener(_status);
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = StudioAnimatedIcon.resolve(widget.icon);
    if (kind == null) {
      return Icon(widget.icon, size: widget.size, color: widget.color);
    }
    final theme = IconTheme.of(context);
    final size = widget.size ?? theme.size ?? 24;
    final inkColor =
        widget.color ?? theme.color ?? Theme.of(context).colorScheme.onSurface;
    return ExcludeSemantics(
        child: SizedBox.square(
      dimension: size,
      child: RepaintBoundary(
          child: CustomPaint(
              painter: StudioIconPainter(
        kind: kind,
        clock: _clock,
        delay: _delay,
        color: inkColor.withValues(alpha: inkColor.a * (theme.opacity ?? 1)),
      ))),
    ));
  }
}

class _IconBatch {
  static final _pending = <Animation<double>,
      List<({_StudioAnimatedIconState state, int ticket, double y})>>{};
  static void add(Animation<double> page, _StudioAnimatedIconState state,
      int ticket, double y) {
    final first = _pending.isEmpty;
    (_pending[page] ??= []).add((state: state, ticket: ticket, y: y));
    if (!first) return;
    scheduleMicrotask(() {
      final batches = _pending.values.toList();
      _pending.clear();
      for (final batch in batches) {
        batch.removeWhere(
            (e) => !e.state.mounted || e.ticket != e.state._ticket);
        batch.sort((a, b) => a.y.compareTo(b.y));
        final rows =
            <List<({_StudioAnimatedIconState state, int ticket, double y})>>[];
        for (final entry in batch) {
          if (rows.isEmpty || entry.y - rows.last.first.y > 16) rows.add([]);
          rows.last.add(entry);
        }
        for (var i = 0; i < rows.length; i++) {
          final delay = rows.length <= 1 ? 0.0 : 360 * i / (rows.length - 1);
          for (final entry in rows[i]) {
            entry.state._play(entry.ticket, delay);
          }
        }
      }
    });
  }
}

/// Repaints only the small glyph; its label, hit target and surface stay still.
class StudioIconPainter extends CustomPainter {
  StudioIconPainter(
      {required this.kind,
      required this.clock,
      required this.color,
      this.delay = 0})
      : super(repaint: clock);
  final StudioIconKind kind;
  final Animation<double> clock;
  final Color color;
  final double delay;

  static double pulse(double t) {
    if (t <= 0 || t >= 1) return 0;
    return 1.28 * math.sin(t * math.pi * 2) * math.sin(t * math.pi) * (1 - t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = ((clock.value * 880 - delay) / 520).clamp(0.0, 1.0);
    final a = pulse(t), b = pulse((t - .06) / .94), c = pulse((t - .12) / .88);
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    void line(double x, double y, double xx, double yy) =>
        canvas.drawLine(Offset(x, y), Offset(xx, yy), ink);
    void circle(double x, double y, double r) =>
        canvas.drawCircle(Offset(x, y), r, ink);
    void rect(double x, double y, double w, double h) => canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, h), const Radius.circular(1.5)),
        ink);
    void path(List<Offset> points, {bool close = false}) {
      final p = Path()..addPolygon(points, close);
      canvas.drawPath(p, ink);
    }

    switch (kind) {
      case StudioIconKind.nib:
        path([
          const Offset(3, 21),
          Offset(7 - 3 * a, 8 - 2 * a),
          const Offset(15, 3),
          const Offset(21, 9),
          Offset(16 + 2 * b, 17 + 3 * b)
        ], close: true);
        line(4, 20, 12 + 3 * b, 12 - 3 * b);
        circle(13 + 3 * b, 11 - 3 * b, 1.5);
      case StudioIconKind.grid:
        rect(2 + 2 * a, 2 + 2 * a, 8 - 2 * a, 8 - 2 * a);
        rect(14 - 3 * b, 2 + 2 * b, 8, 8 - 2 * b);
        rect(2 + 2 * b, 14 - 3 * b, 8 - 2 * b, 8);
        rect(14 - 3 * c, 14 - 3 * c, 8 + c, 8 + c);
      case StudioIconKind.stars:
        void star(double x, double y, double r) {
          path([
            Offset(x, y - r),
            Offset(x + r * .3, y - r * .3),
            Offset(x + r, y),
            Offset(x + r * .3, y + r * .3),
            Offset(x, y + r),
            Offset(x - r * .3, y + r * .3),
            Offset(x - r, y),
            Offset(x - r * .3, y - r * .3)
          ], close: true);
        }
        star(9, 14, 6 + 4 * a);
        star(18 + b, 6 - b, 3.5 - 3 * b);
      case StudioIconKind.box:
        path([
          const Offset(3, 9),
          const Offset(3, 18),
          const Offset(12, 22),
          const Offset(21, 18),
          const Offset(21, 9)
        ]);
        path([
          Offset(3, 7 - 3 * a),
          Offset(12, 3 - 3 * a),
          Offset(21, 7 - 3 * a),
          Offset(12, 11 - 3 * a)
        ], close: true);
        line(12, 12, 12, 22);
      case StudioIconKind.video:
        rect(2, 6, 13, 12);
        path([
          const Offset(15, 10),
          const Offset(22, 6),
          const Offset(22, 18),
          const Offset(15, 14)
        ], close: true);
        circle(8.5, 12, 2.2 + 1.2 * a);
        line(5, 4 - 1.2 * b, 11, 4 - 1.2 * b);
      case StudioIconKind.tag:
        final p = Path()
          ..moveTo(3, 3)
          ..lineTo(12, 3)
          ..quadraticBezierTo(18 + 2 * a, 7, 22, 13)
          ..lineTo(13, 22)
          ..lineTo(3, 12)
          ..close();
        canvas.drawPath(p, ink);
        circle(7 + 1.2 * b, 7, 1.3);
      case StudioIconKind.text:
        line(3, 5, 15, 5);
        line(9, 5, 9, 20);
        line(6, 20, 12, 20);
        final x = 19 + 2 * a;
        line(x, 3, x, 21);
        line(x - 2, 3, x + 2, 3);
        line(x - 2, 21, x + 2, 21);
      case StudioIconKind.gallery:
        rect(2, 2 - 1.2 * a, 16, 15);
        rect(6, 7, 16, 15);
        circle(17, 11 - 1.4 * b, 1.3);
        path([
          const Offset(7, 19),
          Offset(11, 14 - 1.3 * c),
          const Offset(15, 18),
          const Offset(18, 15),
          const Offset(21, 18)
        ]);
      case StudioIconKind.search:
        circle(10, 10, 6.5);
        line(15, 15, 21 + 1.4 * a, 21 - 1.4 * a);
        canvas.drawArc(Rect.fromCircle(center: const Offset(10, 10), radius: 4),
            -2.8 + a, 1.0, false, ink);
      case StudioIconKind.people:
        rect(2, 5, 20, 17);
        circle(9, 10 - 1.5 * a, 2.3);
        circle(17, 10 - 1.5 * b, 1.8);
        canvas.drawPath(
            Path()
              ..moveTo(4, 19)
              ..quadraticBezierTo(9, 12 - 2 * a, 14, 19),
            ink);
        canvas.drawPath(
            Path()
              ..moveTo(14, 16)
              ..quadraticBezierTo(18, 13 - 2 * b, 20, 18),
            ink);
      case StudioIconKind.waveform:
        for (var i = 0; i < 5; i++) {
          final h = [4.0, 10.0, 17.0, 10.0, 4.0][i] + [a, b, c, b, a][i] * 5;
          line(3 + i * 4, 12 - h / 2, 3 + i * 4, 12 + h / 2);
        }
      case StudioIconKind.upscale:
        path([
          const Offset(10, 3),
          const Offset(3, 3),
          const Offset(3, 21),
          const Offset(21, 21),
          const Offset(21, 14)
        ]);
        final d = 2 * a;
        line(9, 15, 20 + d, 4 - d);
        path([Offset(13, 4 - d), Offset(20 + d, 4 - d), Offset(20 + d, 11)]);
      case StudioIconKind.layers:
        for (var i = 2; i >= 0; i--) {
          final y = 6 + i * 5 - [a, b, c][i] * 3;
          path([
            Offset(3, y),
            Offset(12, y - 4),
            Offset(21, y),
            Offset(12, y + 4)
          ], close: true);
        }
      case StudioIconKind.brush:
        path([
          const Offset(9, 15),
          Offset(18 + 2 * a, 3),
          Offset(21 + 2 * a, 6),
          const Offset(12, 17)
        ], close: true);
        canvas.drawPath(
            Path()
              ..moveTo(10, 15)
              ..quadraticBezierTo(4, 12, 4, 19)
              ..quadraticBezierTo(3, 21, 2, 21)
              ..quadraticBezierTo(13 + 2 * b, 23, 12, 17),
            ink);
      case StudioIconKind.panels:
        rect(2, 3, 8, 18);
        rect(13, 3 - 1.5 * a, 9, 7);
        rect(13, 13 - 1.5 * b, 9, 8);
        line(5, 8, 7, 8);
        line(16, 17, 19, 17);
      case StudioIconKind.download:
        canvas.drawArc(
            const Rect.fromLTWH(2, 2, 20, 20), .1, math.pi - .2, false, ink);
        final y = 2.5 * a;
        line(12, 3 + y, 12, 16 + y);
        path([Offset(7, 11 + y), Offset(12, 16 + y), Offset(17, 11 + y)]);
        line(6, 21, 18, 21);
      case StudioIconKind.menu:
        for (var i = 0; i < 3; i++) {
          final d = [a, b, c][i] * 2;
          circle(3, 5 + i * 7, .5);
          line(7 + d, 5 + i * 7, 21, 5 + i * 7);
        }
      case StudioIconKind.edit:
        path([
          const Offset(10, 3),
          const Offset(3, 3),
          const Offset(3, 21),
          const Offset(21, 21),
          const Offset(21, 14)
        ]);
        final d = 1.8 * a;
        path([
          Offset(9 + d, 15 - d),
          Offset(18 + d, 6 - d),
          Offset(21 + d, 9 - d),
          Offset(12 + d, 18 - d),
          Offset(8 + d, 19 - d)
        ], close: true);
      case StudioIconKind.settings:
        final points = <Offset>[];
        for (var i = 0; i < 32; i++) {
          final angle = i * math.pi / 16 + a * .7;
          final r = i % 4 < 2 ? 9.0 : 7.4;
          points
              .add(Offset(12 + math.cos(angle) * r, 12 + math.sin(angle) * r));
        }
        path(points, close: true);
        circle(12, 12, 3.2);
      case StudioIconKind.dreamMoon:
        final fill = Paint()..color = color;
        final moon = Path()
          ..moveTo(12.8, 2.6)
          ..cubicTo(6.3, 2.2, 2.6, 6.6, 2.6, 12)
          ..cubicTo(2.6, 17.6, 7.1, 21.6, 12.6, 21.2)
          ..cubicTo(16.8, 20.9, 19.5, 18.2, 20.6, 14.9)
          ..cubicTo(17.4, 17.2, 12.7, 16.5, 10.3, 13.4)
          ..cubicTo(7.9, 10.2, 8.5, 5.8, 12.8, 2.6)
          ..close();
        canvas.drawPath(moon, fill);
        canvas.save();
        canvas.translate(17.7, 6.7 - .45 * b);
        canvas.scale(1 + .18 * a);
        final glint = Path()
          ..moveTo(0, -3.8)
          ..quadraticBezierTo(.45, -.55, 3.15, 0)
          ..quadraticBezierTo(.45, .55, 0, 3.8)
          ..quadraticBezierTo(-.45, .55, -3.15, 0)
          ..quadraticBezierTo(-.45, -.55, 0, -3.8)
          ..close();
        canvas.drawPath(glint, fill);
        canvas.restore();
      case StudioIconKind.wand:
        line(3, 21, 15, 9);
        line(5, 22, 17, 10);
        line(3, 21, 5, 22);
        for (var i = 0; i < 3; i++) {
          final x = [6.0, 18.0, 19.0][i],
              y = [5.0, 4.0, 17.0][i],
              r = 2 + [a, b, c][i] * 1.5;
          path([
            Offset(x - r, y),
            Offset(x, y - r),
            Offset(x + r, y),
            Offset(x, y + r)
          ], close: true);
        }
      case StudioIconKind.forward:
        path([
          Offset(9, 5 - 1.3 * b),
          Offset(16 + 2 * a, 12),
          Offset(9, 19 + 1.3 * c)
        ]);
      case StudioIconKind.sliders:
        for (var i = 0; i < 3; i++) {
          final x = 5 + i * 7.0, y = [8.0, 16.0, 10.0][i] + [a, b, c][i] * 4;
          line(x, 3, x, y - 2);
          line(x, y + 2, x, 21);
          rect(x - 2, y - 2, 4, 4);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(StudioIconPainter oldDelegate) =>
      kind != oldDelegate.kind ||
      color != oldDelegate.color ||
      clock != oldDelegate.clock ||
      delay != oldDelegate.delay;
}
