import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_memories.dart';
import 'package:nai_huishi/presentation/viewmodels/prompt_memory_viewmodel.dart';

class PromptMemoryPage extends StatefulWidget {
  const PromptMemoryPage({super.key});

  @override
  State<PromptMemoryPage> createState() => _PromptMemoryPageState();
}

class _PromptMemoryPageState extends State<PromptMemoryPage> {
  late final PromptMemoryViewModel _vm;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _vm = sl<PromptMemoryViewModel>();
    _searchController = TextEditingController();
    _vm.addListener(_onChanged);
    _vm.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showEditor([PromptMemory? memory]) async {
    final triggerController =
        TextEditingController(text: memory?.trigger ?? '');
    final contentController =
        TextEditingController(text: memory?.content ?? '');
    var type = memory?.type ?? PromptMemoryType.other;

    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => CupertinoAlertDialog(
          title: Text(memory == null ? '新增记忆' : '编辑记忆'),
          content: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                SizedBox(height: 12),
                TextField(
                  controller: triggerController,
                  decoration: const InputDecoration(labelText: '触发词'),
                ),
                TextField(
                  controller: contentController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '正确内容'),
                ),
                SizedBox(height: 8),
                DropdownButton<PromptMemoryType>(
                  value: type,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                        value: PromptMemoryType.characterName,
                        child: Text('人名')),
                    DropdownMenuItem(
                        value: PromptMemoryType.characterFeature,
                        child: Text('人物特征')),
                    DropdownMenuItem(
                        value: PromptMemoryType.style, child: Text('画风')),
                    DropdownMenuItem(
                        value: PromptMemoryType.fact, child: Text('事实(agent)')),
                    DropdownMenuItem(
                        value: PromptMemoryType.preference,
                        child: Text('偏好(agent)')),
                    DropdownMenuItem(
                        value: PromptMemoryType.observation,
                        child: Text('观察(agent)')),
                    DropdownMenuItem(
                        value: PromptMemoryType.decision,
                        child: Text('决策(agent)')),
                    DropdownMenuItem(
                        value: PromptMemoryType.other, child: Text('其他')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => type = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: Text('取消'),
            ),
            CupertinoDialogAction(
              onPressed: () async {
                final trigger = triggerController.text.trim();
                final content = contentController.text.trim();
                if (trigger.isEmpty || content.isEmpty) return;
                final conflicts = await _vm.saveOrFindConflicts(
                  id: memory?.id,
                  trigger: trigger,
                  content: content,
                  type: type,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (conflicts.isNotEmpty && mounted) {
                  _showConflictDialog(
                    conflicts.first,
                    PromptMemory(
                      trigger: trigger,
                      content: content,
                      type: type,
                      source: PromptMemorySource.manual,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    ),
                  );
                }
              },
              child: Text('保存'),
            ),
          ],
        ),
      ),
    );

    triggerController.dispose();
    contentController.dispose();
  }

  String _typeLabel(PromptMemoryType type) {
    switch (type) {
      case PromptMemoryType.characterName:
        return '人名';
      case PromptMemoryType.characterFeature:
        return '人物特征';
      case PromptMemoryType.style:
        return '画风';
      case PromptMemoryType.fact:
        return '事实';
      case PromptMemoryType.preference:
        return '偏好';
      case PromptMemoryType.observation:
        return '观察';
      case PromptMemoryType.decision:
        return '决策';
      case PromptMemoryType.other:
        return '其他';
    }
  }

  /// 冲突处理弹窗
  Future<void> _showConflictDialog(
    PromptMemory existing,
    PromptMemory newMemory,
  ) async {
    final strategy = await showCupertinoDialog<MemoryConflictStrategy>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('发现冲突'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('触发词「${newMemory.trigger}」已存在记忆：',
                  style: TextStyle(fontSize: 13)),
              SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(existing.content,
                    style: TextStyle(fontSize: 12, fontFamily: 'monospace')),
              ),
              SizedBox(height: 8),
              Text('新内容：', style: TextStyle(fontSize: 13)),
              SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(newMemory.content,
                    style: TextStyle(fontSize: 12, fontFamily: 'monospace')),
              ),
              SizedBox(height: 8),
              Text('如何处理？', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, MemoryConflictStrategy.replace),
            child: Text('替换（旧记忆归档）'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, MemoryConflictStrategy.merge),
            child: Text('合并（旧内容追加）'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, MemoryConflictStrategy.coexist),
            child: Text('并存'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消'),
          ),
        ],
      ),
    );
    if (strategy == null) return;
    await _vm.resolveConflict(
      strategy: strategy,
      existing: existing,
      newMemory: newMemory,
    );
  }

  /// 候选编辑后晋升
  Future<void> _editAndPromotePending(PromptMemory memory) async {
    final triggerController = TextEditingController(text: memory.trigger);
    final contentController = TextEditingController(text: memory.content);
    var type = memory.type;

    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => CupertinoAlertDialog(
          title: Text('编辑后确认'),
          content: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                SizedBox(height: 12),
                TextField(
                  controller: triggerController,
                  decoration: const InputDecoration(labelText: '触发词'),
                ),
                TextField(
                  controller: contentController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '正确内容'),
                ),
                SizedBox(height: 8),
                DropdownButton<PromptMemoryType>(
                  value: type,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                        value: PromptMemoryType.characterName,
                        child: Text('人名')),
                    DropdownMenuItem(
                        value: PromptMemoryType.characterFeature,
                        child: Text('人物特征')),
                    DropdownMenuItem(
                        value: PromptMemoryType.style, child: Text('画风')),
                    DropdownMenuItem(
                        value: PromptMemoryType.other, child: Text('其他')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => type = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: Text('取消'),
            ),
            CupertinoDialogAction(
              onPressed: () async {
                await _vm.promotePending(
                  memory.id!,
                  newTrigger: triggerController.text,
                  newContent: contentController.text,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text('确认晋升'),
            ),
          ],
        ),
      ),
    );
    triggerController.dispose();
    contentController.dispose();
  }

  /// 清理向导
  Future<void> _openStaleWizard() async {
    final stale = await _vm.listStale();
    if (!mounted) return;
    if (stale.isEmpty) {
      showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text('无可清理记忆'),
          content: Text('没有超过 90 天未命中的记忆。'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: Text('好'),
            ),
          ],
        ),
      );
      return;
    }

    final selected = <int>{};
    for (final m in stale) {
      if (m.id != null) selected.add(m.id!);
    }

    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => CupertinoAlertDialog(
          title: Text('清理向导（${stale.length} 条候选）'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: stale.length,
                itemBuilder: (_, i) {
                  final m = stale[i];
                  final checked = selected.contains(m.id);
                  return CheckboxListTile(
                    value: checked,
                    title: Text(m.trigger, style: TextStyle(fontSize: 13)),
                    subtitle: Text(
                      '${_typeLabel(m.type)} · ${m.content.length > 30 ? '${m.content.substring(0, 30)}…' : m.content}',
                      style: TextStyle(fontSize: 11),
                    ),
                    onChanged: (v) {
                      setDialogState(() {
                        if (v == true && m.id != null) {
                          selected.add(m.id!);
                        } else if (m.id != null) {
                          selected.remove(m.id!);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: Text('取消'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () async {
                await _vm.batchDelete(selected.toList());
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text('删除选中 ${selected.length} 条'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('学习记忆'),
        actions: [
          IconButton(
            onPressed: _openStaleWizard,
            tooltip: '清理向导',
            icon: Icon(CupertinoIcons.trash),
          ),
          IconButton(
            onPressed: () => _showEditor(),
            icon: Icon(CupertinoIcons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_vm.pendingCount > 0) _buildPendingSection(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: _vm.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(CupertinoIcons.search),
                hintText: '搜索触发词或内容',
              ),
            ),
          ),
          Expanded(
            child: _vm.isLoading
                ? Center(child: CupertinoActivityIndicator())
                : _vm.memories.isEmpty
                    ? Center(
                        child: Text('暂无记忆',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _vm.memories.length,
                        itemBuilder: (context, index) {
                          final memory = _vm.memories[index];
                          final isSuperseded = memory.supersededBy != null;
                          return Card(
                            color: isSuperseded
                                ? Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.04)
                                : null,
                            child: ListTile(
                              title: Text(
                                memory.trigger,
                                style: TextStyle(
                                  decoration: isSuperseded
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: isSuperseded
                                      ? Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                      : null,
                                ),
                              ),
                              subtitle: Text(
                                '${_typeLabel(memory.type)}'
                                '${memory.hitCount > 0 ? ' · 命中 ${memory.hitCount} 次' : ''}'
                                '${isSuperseded ? ' · 已归档' : ''}'
                                ' · ${memory.content}',
                                style: TextStyle(fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _showEditor(memory),
                              trailing: IconButton(
                                icon: Icon(CupertinoIcons.delete,
                                    color: Colors.redAccent),
                                onPressed: memory.id == null
                                    ? null
                                    : () => _vm.delete(memory.id!),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingSection() {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.clock,
                  size: 16, color: theme.colorScheme.primary),
              SizedBox(width: 6),
              Text(
                '待确认候选（${_vm.pendingCount}）',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          ..._vm.pendingMemories.map((m) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.trigger,
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500)),
                        Text(m.content,
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(CupertinoIcons.checkmark_alt_circle,
                        size: 18, color: Colors.green),
                    onPressed: () => _vm.promotePending(m.id!),
                    tooltip: '确认晋升',
                  ),
                  IconButton(
                    icon: Icon(CupertinoIcons.pencil, size: 16),
                    onPressed: () => _editAndPromotePending(m),
                    tooltip: '编辑后确认',
                  ),
                  IconButton(
                    icon: Icon(CupertinoIcons.xmark_circle,
                        size: 18, color: Colors.redAccent),
                    onPressed: () => _vm.rejectPending(m.id!),
                    tooltip: '拒绝',
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
