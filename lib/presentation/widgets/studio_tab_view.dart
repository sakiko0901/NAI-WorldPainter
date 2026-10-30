import 'package:flutter/material.dart';

/// Keeps each workspace mounted while cross-fading between destinations.
/// In a scroll view, only the selected child determines the target height.
class StudioTabView extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final bool expand;

  const StudioTabView({
    super.key,
    required this.index,
    required this.children,
    this.expand = true,
  }) : assert(index >= 0 && index < children.length);

  static const duration = Duration(milliseconds: 320);
  static const curve = Curves.easeInOutCubic;

  @override
  State<StudioTabView> createState() => _StudioTabViewState();
}

class _StudioTabViewState extends State<StudioTabView> {
  final _contentKey = GlobalKey();
  late final Set<int> _visible = {widget.index};
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _visible
        ..clear()
        ..add(widget.index);
    }
  }

  @override
  void didUpdateWidget(covariant StudioTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_reduceMotion) _visible.clear();
    _visible.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    final duration = _reduceMotion ? Duration.zero : StudioTabView.duration;
    final direction = Directionality.of(context) == TextDirection.ltr ? 1 : -1;
    final stack = Stack(
      key: _contentKey,
      fit: widget.expand ? StackFit.expand : StackFit.loose,
      alignment: Alignment.topCenter,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          Positioned(
            // Keep the wrapper types stable so switching never remounts a page.
            top: widget.expand || i != widget.index ? 0 : null,
            left: widget.expand || i != widget.index ? 0 : null,
            right: widget.expand || i != widget.index ? 0 : null,
            bottom: widget.expand ? 0 : null,
            child: Offstage(
              offstage: !_visible.contains(i),
              child: IgnorePointer(
                ignoring: i != widget.index,
                child: ExcludeFocus(
                  excluding: i != widget.index,
                  child: ExcludeSemantics(
                    excluding: i != widget.index,
                    child: AnimatedOpacity(
                      opacity: i == widget.index ? 1 : 0,
                      duration: duration,
                      curve: StudioTabView.curve,
                      onEnd: () {
                        if (mounted &&
                            i != widget.index &&
                            _visible.contains(i)) {
                          setState(() => _visible.remove(i));
                        }
                      },
                      child: AnimatedSlide(
                        offset: _reduceMotion || i == widget.index
                            ? Offset.zero
                            : Offset(
                                i < widget.index
                                    ? -.045 * direction
                                    : .045 * direction,
                                0),
                        duration: duration,
                        curve: StudioTabView.curve,
                        child: TickerMode(
                          enabled: i == widget.index,
                          child: RepaintBoundary(child: widget.children[i]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return ClipRect(
      child: widget.expand || _reduceMotion
          ? stack
          : AnimatedSize(
              duration: duration,
              curve: StudioTabView.curve,
              alignment: Alignment.topCenter,
              child: stack,
            ),
    );
  }
}
