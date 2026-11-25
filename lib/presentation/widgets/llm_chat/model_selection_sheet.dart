import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_role_binding.dart';
import 'package:nai_huishi/presentation/app_theme.dart';

Future<LlmRoleBinding?> showModelSelectionSheet(
  BuildContext context, {
  required List<LlmProvider> providers,
  required LlmRoleBinding selected,
  required String title,
}) =>
    showModalBottomSheet<LlmRoleBinding>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Duration(milliseconds: 235),
              reverseDuration: Duration(milliseconds: 180)),
      backgroundColor: Theme.of(context).dialogTheme.backgroundColor ??
          Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => ModelSelectionSheet(
          providers: providers, selected: selected, title: title),
    );

/// Provider filtering and model selection share one sheet, with no nested menus.
class ModelSelectionSheet extends StatefulWidget {
  const ModelSelectionSheet(
      {super.key,
      required this.providers,
      required this.selected,
      required this.title,
      this.onBack,
      this.onSelected});
  final List<LlmProvider> providers;
  final LlmRoleBinding selected;
  final String title;
  final VoidCallback? onBack;
  final ValueChanged<LlmRoleBinding>? onSelected;

  @override
  State<ModelSelectionSheet> createState() => _ModelSelectionSheetState();
}

class _ModelSelectionSheetState extends State<ModelSelectionSheet> {
  String _query = '';
  String? _providerId;
  bool _searching = false;
  final _inlineScroll = ScrollController();

  @override
  void dispose() {
    _inlineScroll.dispose();
    super.dispose();
  }

  void _select(LlmRoleBinding binding) {
    final onSelected = widget.onSelected;
    if (onSelected != null) {
      onSelected(binding);
    } else {
      Navigator.pop(context, binding);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final groups = <LlmProvider, List<String>>{};
    for (final provider in widget.providers) {
      if (_providerId != null && provider.id != _providerId) continue;
      final models = provider.models
          .where((model) =>
              '${provider.name} $model'.toLowerCase().contains(_query))
          .toList();
      if (models.isNotEmpty) groups[provider] = models;
    }
    if (widget.onBack != null) return _buildInline(groups);
    return SafeArea(
      top: false,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 16),
              child: Row(children: [
                Expanded(
                    child:
                        Text(widget.title, style: theme.textTheme.titleLarge)),
                TextButton(
                    onPressed: () => _select(const LlmRoleBinding()),
                    child: const Text('暂不选择')),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: '搜索模型或供应商',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: colors.onSurface.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Row(children: [
                _filter('全部', null),
                for (final provider in widget.providers)
                  _filter(provider.name, provider.id),
              ]),
            ),
            Expanded(
                child: groups.isEmpty
                    ? Center(
                        child:
                            Text('没有匹配的模型', style: theme.textTheme.bodyMedium))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          final provider = groups.keys.elementAt(index);
                          final models = groups[provider]!;
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        12, 20, 12, 8),
                                    child: Text(provider.name,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                                color:
                                                    colors.onSurfaceVariant))),
                                for (final model in models)
                                  _model(provider, model),
                              ]);
                        },
                      )),
          ]),
        ),
      ),
    );
  }

  Widget _buildInline(Map<LlmProvider, List<String>> groups) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            IconButton(
              tooltip: '返回思考等级',
              onPressed: widget.onBack,
              icon: const Icon(Icons.chevron_left_rounded, size: 23),
            ),
            Expanded(
                child: Text(widget.title, style: theme.textTheme.titleSmall)),
            IconButton(
              tooltip: _searching ? '关闭搜索' : '搜索模型',
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) _query = '';
              }),
              icon: Icon(
                  _searching ? Icons.close_rounded : Icons.search_rounded,
                  size: 20),
            ),
          ]),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: TextField(
                autofocus: true,
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: '搜索模型或供应商',
                  isDense: true,
                  filled: true,
                  fillColor: colors.onSurface.withValues(alpha: .06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          Flexible(
            child: Scrollbar(
              controller: _inlineScroll,
              child: ListView(
                controller: _inlineScroll,
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                children: [
                  if (groups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text('没有匹配的模型', style: theme.textTheme.bodyMedium),
                    ),
                  for (final MapEntry(:key, :value) in groups.entries) ...[
                    if (groups.length > 1)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                        child: Text(key.name,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: colors.onSurfaceVariant)),
                      ),
                    for (final model in value) _model(key, model, inline: true),
                  ],
                  if (!_searching && widget.selected.model.isNotEmpty)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: () => _select(const LlmRoleBinding()),
                        child: const Text('暂不选择'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filter(String label, String? id) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
            label: Text(label),
            selected: _providerId == id,
            showCheckmark: false,
            onSelected: (_) => setState(() => _providerId = id)),
      );

  Widget _model(LlmProvider provider, String model, {bool inline = false}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final glass = FrostedTheme.of(context);
    final isCoffeePaper = glass.appearanceMode == AppearanceMode.coffeePaper;
    final selectedFill = isCoffeePaper
        ? glass.selection
        : colors.primary.withValues(alpha: inline ? .13 : 0.12);
    final selected = widget.selected.providerId == provider.id &&
        widget.selected.model == model;
    if (inline) {
      return Semantics(
        selected: selected,
        child: Material(
          borderRadius: BorderRadius.circular(13),
          color: selected ? selectedFill : Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: () =>
                _select(LlmRoleBinding(providerId: provider.id, model: model)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(children: [
                  Expanded(
                      child: Text(model,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: selected
                                  ? (isCoffeePaper
                                      ? FontWeight.w600
                                      : FontWeight.w700)
                                  : FontWeight.w500))),
                  if (selected)
                    Icon(Icons.check_rounded, size: 19, color: colors.primary),
                ]),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? selectedFill : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          title: Text(model,
              style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          trailing: Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 22,
              color: selected
                  ? colors.primary
                  : colors.outline.withValues(alpha: 0.5)),
          onTap: () =>
              _select(LlmRoleBinding(providerId: provider.id, model: model)),
        ),
      ),
    );
  }
}
