import 'package:flutter/material.dart';
import 'studio_entrance.dart';

/// Retains workspaces while the selected body settles beneath its header.
class StudioDestinationView extends StatefulWidget {
  const StudioDestinationView(
      {super.key, required this.index, required this.children})
      : assert(index >= 0 && index < children.length);
  final int index;
  final List<Widget> children;
  static const duration = Duration(milliseconds: 420);
  @override
  State<StudioDestinationView> createState() => _StudioDestinationViewState();
}

class _StudioDestinationViewState extends State<StudioDestinationView>
    with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(
      vsync: this, duration: StudioDestinationView.duration, value: 1);
  bool _forward = true;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _clock.value = 1;
  }

  @override
  void didUpdateWidget(covariant StudioDestinationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      if (_reduceMotion) {
        _clock.value = 1;
      } else {
        _forward = widget.index > oldWidget.index;
        _clock.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        for (var i = 0; i < widget.children.length; i++)
          Positioned.fill(
              key: ValueKey(i),
              child: Offstage(
                  offstage: i != widget.index,
                  child: IgnorePointer(
                    ignoring: i != widget.index,
                    child: ExcludeFocus(
                      excluding: i != widget.index,
                      child: ExcludeSemantics(
                        excluding: i != widget.index,
                        child: TickerMode(
                          enabled: i == widget.index,
                          child: HeroMode(
                            enabled: i == widget.index,
                            child: StudioEntranceScope(
                              animation: i == widget.index && !_reduceMotion
                                  ? _clock
                                  : const AlwaysStoppedAnimation(1),
                              direction: _forward ? 1 : -1,
                              child: RepaintBoundary(
                                  child: ColoredBox(
                                color:
                                    Theme.of(context).scaffoldBackgroundColor,
                                child: widget.children[i],
                              )),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ))),
      ]);
}
