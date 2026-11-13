import 'package:flutter/material.dart';

class PromptChangePreview extends StatelessWidget {
  final Map<String, dynamic> change;
  const PromptChangePreview({super.key, required this.change});
  @override
  Widget build(BuildContext context) {
    final target = change['target']?.toString() ?? '';
    final targetLabel = switch (target) {
      'positive' => '主正向提示词',
      'negative' => '主负面提示词',
      'inpaint_positive' => '局部重绘正向提示词',
      'inpaint_negative' => '局部重绘负面提示词',
      _ =>
        target.replaceFirst('character_', '角色 ').replaceFirst('_uc', ' 负面提示词'),
    };
    final before = change['before']?.toString() ?? '';
    final after = change['after']?.toString() ?? '';
    final previous = before
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet();
    final next = after
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet();
    final theme = Theme.of(context);
    return SizedBox(
        width: 500,
        child: SingleChildScrollView(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '目标：$targetLabel · ${change['mode']?.toString().trim() == 'replace' ? "替换" : "追加"}',
              style: theme.textTheme.labelLarge),
          if (change['position'] != null) Text('角色位置：${change['position']}'),
          const SizedBox(height: 12),
          Wrap(spacing: 5, runSpacing: 5, children: [
            for (final tag in previous.difference(next))
              Chip(
                  label: Text('− $tag'),
                  backgroundColor: theme.colorScheme.errorContainer),
            for (final tag in next.difference(previous))
              Chip(
                  label: Text('+ $tag'),
                  backgroundColor: theme.colorScheme.primaryContainer),
          ]),
          const SizedBox(height: 12),
          const Text('修改前'),
          SelectableText(before.isEmpty ? '（空）' : before,
              style: theme.textTheme.bodySmall),
          const Divider(height: 24),
          const Text('修改后'),
          SelectableText(after.isEmpty ? '（空）' : after),
          const SizedBox(height: 8),
          Text('应用后可在聊天栏撤销最近一次写入。', style: theme.textTheme.bodySmall),
        ])));
  }
}
