import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/presentation/app_theme.dart';

Future<T?> showStudioAlertDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) =>
    showCupertinoDialog<T>(
      context: context,
      builder: builder,
      barrierColor: DialogTheme.of(context).barrierColor,
    );

/// Cupertino's alert surface has a fixed palette. Use the app's dialog surface
/// for Coffee Paper while retaining the same actions and route behavior.
class StudioAlertDialog extends StatelessWidget {
  const StudioAlertDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  final Widget title;
  final Widget content;
  final List<CupertinoDialogAction> actions;

  @override
  Widget build(BuildContext context) {
    if (FrostedTheme.of(context).appearanceMode != AppearanceMode.coffeePaper) {
      return CupertinoAlertDialog(
        title: title,
        content: content,
        actions: actions,
      );
    }
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 480),
      title: title,
      content: content,
      scrollable: true,
      actions: [
        for (final action in actions)
          if (action.isDefaultAction && !action.isDestructiveAction)
            FilledButton(onPressed: action.onPressed, child: action.child)
          else
            TextButton(
              onPressed: action.onPressed,
              style: action.isDestructiveAction
                  ? TextButton.styleFrom(foregroundColor: colors.error)
                  : null,
              child: action.child,
            ),
      ],
    );
  }
}
