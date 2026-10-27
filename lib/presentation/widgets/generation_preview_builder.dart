import 'package:flutter/material.dart';

/// Rebuilds the preview region at display-frame cadence while it is visible.
/// Encoded frames remain in the view model while this region is inactive, so
/// returning to the creation page renders the latest frame without a backlog.
class GenerationPreviewBuilder extends StatefulWidget {
  final Listenable updates;
  final WidgetBuilder builder;

  const GenerationPreviewBuilder({
    super.key,
    required this.updates,
    required this.builder,
  });

  @override
  State<GenerationPreviewBuilder> createState() =>
      _GenerationPreviewBuilderState();
}

class _GenerationPreviewBuilderState extends State<GenerationPreviewBuilder>
    with WidgetsBindingObserver {
  bool _listening = false;
  bool _tickersEnabled = true;
  AppLifecycleState? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickersEnabled = TickerMode.valuesOf(context).enabled;
    _syncSubscription();
  }

  @override
  void didUpdateWidget(GenerationPreviewBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updates != widget.updates) {
      if (_listening) oldWidget.updates.removeListener(_onPreview);
      _listening = false;
      _syncSubscription();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _syncSubscription();
    if (_listening) setState(() {});
  }

  void _syncSubscription() {
    final shouldListen = _tickersEnabled &&
        (_lifecycle == null || _lifecycle == AppLifecycleState.resumed);
    if (shouldListen == _listening) return;
    if (shouldListen) {
      widget.updates.addListener(_onPreview);
    } else {
      widget.updates.removeListener(_onPreview);
    }
    _listening = shouldListen;
  }

  void _onPreview() {
    // Multiple notifications before the next frame share one widget rebuild.
    setState(() {});
  }

  @override
  void dispose() {
    if (_listening) widget.updates.removeListener(_onPreview);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
