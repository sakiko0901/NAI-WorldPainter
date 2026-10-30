import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/navigation/app_destination.dart';
import 'package:nai_huishi/presentation/widgets/fountain_pen_icon.dart';

/// A continuous glass surface, without a boxed outline around the bottom bar.
class StudioBottomSurface extends StatelessWidget {
  final Widget child;
  const StudioBottomSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = FrostedTheme.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    return ClipRect(
      child: BackdropFilter(
        enabled: glass.blurEnabled && !highContrast,
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, .45, 1],
              colors: [
                theme.colorScheme.surface
                    .withValues(alpha: highContrast ? 1 : 0),
                theme.colorScheme.surface
                    .withValues(alpha: highContrast ? 1 : .8),
                theme.colorScheme.surface
                    .withValues(alpha: highContrast ? 1 : .96),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class StudioNavigationBar extends StatelessWidget {
  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;

  const StudioNavigationBar(
      {super.key, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = FrostedTheme.of(context);
    final extraHeight =
        (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(0.0, 32.0);
    final highContrast = MediaQuery.highContrastOf(context);
    return StudioBottomSurface(
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64 + extraHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 12, 7),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: AlignmentDirectional(selected.index - 1.0, 0),
                    child: FractionallySizedBox(
                      widthFactor: 1 / AppDestination.values.length,
                      heightFactor: 1,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: DecoratedBox(
                          key: const ValueKey('navigation-selection'),
                          decoration: BoxDecoration(
                            color: glass.selection.withValues(
                                alpha: highContrast
                                    ? 1
                                    : theme.brightness == Brightness.dark
                                        ? .14
                                        : .65),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: glass.border),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final destination in AppDestination.values)
                      Expanded(
                        child: Semantics(
                          selected: destination == selected,
                          button: true,
                          label: destination.label,
                          child: Tooltip(
                            message: destination.label,
                            excludeFromSemantics: true,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                key: ValueKey('navigation-${destination.name}'),
                                borderRadius: BorderRadius.circular(16),
                                splashFactory: NoSplash.splashFactory,
                                highlightColor: Colors.transparent,
                                onTap: () {
                                  if (destination == selected) return;
                                  HapticFeedback.selectionClick();
                                  onSelected(destination);
                                },
                                child: ExcludeSemantics(
                                  child: Builder(
                                    builder: (context) {
                                      final color = destination == selected
                                          ? (highContrast
                                              ? glass.onSelection
                                              : theme.colorScheme.onSurface)
                                          : theme.colorScheme.onSurfaceVariant;
                                      return Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          switch (destination) {
                                            AppDestination.create =>
                                              FountainPenIcon(
                                                  color: color, size: 22),
                                            AppDestination.assistant => Icon(
                                                CupertinoIcons.sparkles,
                                                size: 22,
                                                color: color),
                                            AppDestination.tools => Icon(
                                                CupertinoIcons.square_grid_2x2,
                                                size: 22,
                                                color: color),
                                          },
                                          const SizedBox(height: 3),
                                          Text(destination.label,
                                              maxLines: 1,
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  height: 1.25,
                                                  fontWeight: FontWeight.w600,
                                                  color: color)),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
