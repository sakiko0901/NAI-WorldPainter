import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_role_binding.dart';
import 'package:nai_huishi/presentation/pages/llm_provider_edit_page.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart' show showFloatingToast;

class LlmProviderManagePage extends StatefulWidget {
  final LlmChatViewModel vm;
  const LlmProviderManagePage({super.key, required this.vm});

  @override
  State<LlmProviderManagePage> createState() => _LlmProviderManagePageState();
}

class _LlmProviderManagePageState extends State<LlmProviderManagePage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = widget.vm;
    final providers = vm.providers;

    // 哪些供应商正被角色 binding 引用
    Set<String> referencedProviderIds() {
      return {
        vm.mainBinding.providerId,
        vm.visionBinding.providerId,
      }.whereType<String>().toSet();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('LLM 供应商管理'),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.add_circled),
            onPressed: () async {
              final newProvider = LlmProvider.create(name: '新供应商');
              final list = List<LlmProvider>.from(vm.providers);
              list.add(newProvider);
              await vm.setProviders(list);
              if (!mounted) return;
              await Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => LlmProviderEditPage(
                    vm: vm,
                    providerId: newProvider.id,
                  ),
                ),
              );
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: providers.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.cube_box,
                        size: 64,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.4)),
                    const SizedBox(height: 16),
                    Text(
                      '还没有任何 LLM 供应商',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '点击右上角 + 新建一个',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: providers.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = providers[i];
                final isReferenced = referencedProviderIds().contains(p.id);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.15),
                    child: Text(
                      p.name.isNotEmpty ? p.name.substring(0, 1).toUpperCase() : '?',
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  ),
                  title: Text(p.name.isEmpty ? '(未命名)' : p.name),
                  subtitle: Text(
                    '${p.baseUrl.isEmpty ? "(未设置 base URL)" : p.baseUrl}\n模型 ${p.models.length} 个'
                    '${isReferenced ? "  ·  被角色绑定引用" : ""}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(CupertinoIcons.delete),
                    onPressed: () => _confirmDelete(p, isReferenced),
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => LlmProviderEditPage(
                          vm: vm,
                          providerId: p.id,
                        ),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                );
              },
            ),
    );
  }

  Future<void> _confirmDelete(LlmProvider provider, bool isReferenced) async {
    if (isReferenced) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('无法删除'),
          content: Text(
              '该供应商（${provider.name}）正被某个角色绑定引用。请先在"模型配置"页解除绑定（把对应角色供应商下拉框设为"未选择"），再回来删除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除供应商'),
        content: Text('确定删除 "${provider.name}" 吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final list = List<LlmProvider>.from(widget.vm.providers)
      ..removeWhere((p) => p.id == provider.id);
    await widget.vm.setProviders(list);
    if (mounted) {
      showFloatingToast(context, '已删除');
      setState(() {});
    }
  }
}
