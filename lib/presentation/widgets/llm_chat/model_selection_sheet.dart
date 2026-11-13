import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_role_binding.dart';

/// Provider filtering and model selection share one sheet, with no nested menus.
class ModelSelectionSheet extends StatefulWidget {
  const ModelSelectionSheet(
      {super.key,
      required this.providers,
      required this.selected,
      required this.title});
  final List<LlmProvider> providers;
  final LlmRoleBinding selected;
  final String title;

  @override
  State<ModelSelectionSheet> createState() => _ModelSelectionSheetState();
}

class _ModelSelectionSheetState extends State<ModelSelectionSheet> {
  String _query = '';
  String? _providerId;

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
                    onPressed: () =>
                        Navigator.pop(context, const LlmRoleBinding()),
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

  Widget _filter(String label, String? id) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
            label: Text(label),
            selected: _providerId == id,
            showCheckmark: false,
            onSelected: (_) => setState(() => _providerId = id)),
      );

  Widget _model(LlmProvider provider, String model) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = widget.selected.providerId == provider.id &&
        widget.selected.model == model;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
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
          onTap: () => Navigator.pop(
              context, LlmRoleBinding(providerId: provider.id, model: model)),
        ),
      ),
    );
  }
}
