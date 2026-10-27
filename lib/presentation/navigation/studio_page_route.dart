import 'package:flutter/material.dart';

/// Shared, directional transitions for the pages beside the creation workspace.
Route<T> studioPageRoute<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required String name,
  bool fromLeft = false,
}) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return PageRouteBuilder<T>(
    settings: RouteSettings(name: name),
    transitionDuration:
        reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
    reverseTransitionDuration:
        reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
    pageBuilder: (context, _, __) => builder(context),
    transitionsBuilder: (_, animation, __, child) {
      final progress =
          animation.drive(CurveTween(curve: Curves.easeInOutCubic));
      return FadeTransition(
        opacity: progress,
        child: SlideTransition(
          position: progress.drive(Tween<Offset>(
            begin: Offset(fromLeft ? -0.12 : 0.12, 0),
            end: Offset.zero,
          )),
          child: child,
        ),
      );
    },
  );
}
