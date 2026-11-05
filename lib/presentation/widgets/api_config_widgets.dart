import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';

/// A single glass surface, with a scrolling form and always reachable actions.
class ApiConfigDialog extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget content;
  final List<Widget> actions;
  final String? errorText;

  const ApiConfigDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.content,
    required this.actions,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      // Dialogs have their own group so they never share a filter with the page
      // underneath them while the route transition is running.
      child: BackdropGroup(
        child: FrostedSurface(
          radius: 24,
          blur: 24,
          child: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleLarge),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    child: content,
                  ),
                ),
                Divider(height: 1, color: FrostedTheme.of(context).border),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (errorText != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(errorText!,
                              style: TextStyle(color: theme.colorScheme.error)),
                        ),
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: 8,
                        overflowSpacing: 8,
                        children: actions,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ApiEndpointHeader extends StatelessWidget {
  final String title;
  final String url;
  final bool active;
  final bool expanded;
  final VoidCallback onTap;

  const ApiEndpointHeader({
    super.key,
    required this.title,
    required this.url,
    required this.active,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onTap: onTap,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: active
              ? FrostedTheme.of(context).selection
              : FrostedTheme.of(context).field,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SizedBox.square(
          dimension: 38,
          child: Icon(
            active ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.link,
            size: 19,
            color: active
                ? FrostedTheme.of(context).onSelection
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ),
      trailing: Icon(
        expanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
        size: 16,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class ApiModelList extends StatelessWidget {
  final List<String> models;
  final String? activeModel;
  final ValueChanged<String> onSelected;
  final Widget? action;

  const ApiModelList({
    super.key,
    required this.models,
    required this.activeModel,
    required this.onSelected,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = FrostedTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text('可用模型 · ${models.length}',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              if (action != null) action!,
            ],
          ),
        ),
        if (models.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('尚未添加模型，点击编辑填写模型名称。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        for (final model in models)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color:
                  activeModel == model ? glass.selection : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: ValueKey('api-model-$model'),
                selected: activeModel == model,
                selectedColor: glass.onSelection,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                minLeadingWidth: 20,
                horizontalTitleGap: 10,
                leading: Icon(
                  activeModel == model
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.circle,
                  size: 19,
                ),
                title: Text(model, style: const TextStyle(fontSize: 13)),
                onTap: () => onSelected(model),
              ),
            ),
          ),
      ],
    );
  }
}
