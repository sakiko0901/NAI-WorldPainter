import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/constants/prompt_capsule_data.dart';
import 'package:nai_huishi/core/constants/prompt_capsule_library.dart';

class PromptCapsuleSheet extends StatefulWidget {
  final String title;
  final ValueChanged<PromptCapsuleTag> onSelect;

  const PromptCapsuleSheet({
    super.key,
    required this.title,
    required this.onSelect,
  });

  @override
  State<PromptCapsuleSheet> createState() => _PromptCapsuleSheetState();
}

class _PromptCapsuleSheetState extends State<PromptCapsuleSheet> {
  final TextEditingController _searchController = TextEditingController();
  int _categoryIndex = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PromptCapsuleCategory> get _categories =>
      filterPromptCapsuleCategories(_searchController.text,
          source: mergedPromptCapsules);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = _categories;
    final hasCategories = categories.isNotEmpty;
    if (hasCategories && _categoryIndex >= categories.length) {
      _categoryIndex = 0;
    }
    final selectedCategory = hasCategories ? categories[_categoryIndex] : null;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '搜索中文或英文 tag，点一下直接插入',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(CupertinoIcons.xmark),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() => _categoryIndex = 0),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(CupertinoIcons.search),
                    hintText: '例如：蓝发 / blue_hair / 星空 / 过膝袜',
                  ),
                ),
              ),
              if (!hasCategories)
                Expanded(
                  child: Center(
                    child: Text(
                      '没有匹配的标签',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else ...[
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final selected = index == _categoryIndex;
                      return ChoiceChip(
                        label: Text(categories[index].name),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _categoryIndex = index),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    children: [
                      for (final subgroup in selectedCategory!.subgroups) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 10),
                          child: Text(
                            subgroup.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in subgroup.tags)
                              ActionChip(
                                label: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(tag.zh),
                                    const SizedBox(height: 2),
                                    Text(
                                      tag.promptText,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                                avatar:
                                    const Icon(CupertinoIcons.add, size: 14),
                                onPressed: () => widget.onSelect(tag),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
