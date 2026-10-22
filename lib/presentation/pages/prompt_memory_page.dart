import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:nai_huishi/domain/services/prompt_memory_context.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_memories.dart';
import 'package:nai_huishi/presentation/viewmodels/prompt_memory_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

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
    final triggerParts = memory == null
        ? const <String>[]
        : PromptMemoryTriggers.parse(memory.trigger);
    final triggerController = TextEditingController(
        text: triggerParts.isEmpty ? '' : triggerParts.first);
    final aliasesController = TextEditingController(
        text: triggerParts.length < 2 ? '' : triggerParts.skip(1).join(' | '));
    final contentController =
        TextEditingController(text: memory?.content ?? '');
    var type = memory?.type ?? PromptMemoryType.other;
    final legacyOversizedTrigger = memory != null &&
        PromptMemoryTriggers.encode(
              PromptMemoryTriggers.parse(memory.trigger),
            ).runes.length >
            512;
    final legacyOversizedContent =
        memory != null && memory.content.runes.length > 6000;

    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => CupertinoAlertDialog(
          title: Text(memory == null ? '新增记忆' : '编辑记忆'),
          content: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (MediaQuery.sizeOf(ctx).height -
                        MediaQuery.viewInsetsOf(ctx).bottom -
                        180)
                    .clamp(160, 560)
                    .toDouble(),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: 12),
                    TextField(
                      controller: triggerController,
                      maxLength: legacyOversizedTrigger ? null : 512,
                      decoration: const InputDecoration(labelText: '角色名/主要触发词'),
                    ),
                    TextField(
                      controller: aliasesController,
                      maxLength: legacyOversizedTrigger ? null : 512,
                      decoration: const InputDecoration(
                        labelText: '别名（多个用 | 分隔）',
                        hintText: '例如：纳西妲 | Nahida',
                        helperText: '触发词与全部别名合计最多 512 个字符',
                      ),
                    ),
                    TextField(
                      controller: contentController,
                      maxLength: legacyOversizedContent ? null : 6000,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: type == PromptMemoryType.characterOutfit
                            ? '标准穿搭描述'
                            : '正确内容',
                        hintText: type == PromptMemoryType.characterOutfit
                            ? '可用自然语言，也可填写参考图识别出的服装描述'
                            : null,
                      ),
                    ),
                    if (type == PromptMemoryType.characterOutfit)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          '仅在用户明确要求记住或更新标准穿搭时保存。临时换装不覆盖标准穿搭；参考图中看不清的细节请标为不确定。',
                          style: TextStyle(fontSize: 12),
                        ),
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
                            value: PromptMemoryType.characterOutfit,
                            child: Text('角色标准穿搭')),
                        DropdownMenuItem(
                            value: PromptMemoryType.style, child: Text('画风')),
                        DropdownMenuItem(
                            value: PromptMemoryType.fact,
                            child: Text('事实(agent)')),
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
                final combinedTrigger = PromptMemoryTriggers.encode([
                  trigger,
                  ...PromptMemoryTriggers.parse(aliasesController.text),
                ]);
                try {
                  final conflicts = await _vm.saveOrFindConflicts(
                    id: memory?.id,
                    trigger: combinedTrigger,
                    content: content,
                    type: type,
                    supersededBy: memory?.supersededBy,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (conflicts.isNotEmpty && mounted) {
                    _showConflictDialog(
                      conflicts.first,
                      PromptMemory(
                        trigger: combinedTrigger,
                        content: content,
                        type: type,
                        source: PromptMemorySource.manual,
                        supersededBy: memory?.supersededBy,
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      ),
                    );
                  }
                } catch (error) {
                  if (!ctx.mounted) return;
                  final message =
                      error is ArgumentError ? error.message?.toString() : null;
                  showFloatingToast(
                    ctx,
                    message == null || message.isEmpty
                        ? '保存失败，请检查输入后重试。'
                        : '保存失败：$message',
                    icon: CupertinoIcons.exclamationmark_circle,
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
    aliasesController.dispose();
    contentController.dispose();
  }

  String _typeLabel(PromptMemoryType type) {
    switch (type) {
      case PromptMemoryType.characterName:
        return '人名';
      case PromptMemoryType.characterFeature:
        return '人物特征';
      case PromptMemoryType.characterOutfit:
        return '角色标准穿搭';
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
    final triggerParts = PromptMemoryTriggers.parse(memory.trigger);
    final triggerController = TextEditingController(
        text: triggerParts.isEmpty ? '' : triggerParts.first);
    final aliasesController = TextEditingController(
        text: triggerParts.length < 2 ? '' : triggerParts.skip(1).join(' | '));
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
                  decoration: const InputDecoration(labelText: '角色名/主要触发词'),
                ),
                TextField(
                  controller: aliasesController,
                  decoration: const InputDecoration(
                    labelText: '别名（多个用 | 分隔）',
                    hintText: '例如：纳西妲 | Nahida',
                  ),
                ),
                TextField(
                  controller: contentController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: type == PromptMemoryType.characterOutfit
                        ? '标准穿搭描述'
                        : '正确内容',
                    hintText: type == PromptMemoryType.characterOutfit
                        ? '自然语言或参考图识别到的服装描述'
                        : null,
                  ),
                ),
                if (type == PromptMemoryType.characterOutfit)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      '确认后会替换同一角色的旧标准穿搭；临时换装不应作为标准穿搭保存。',
                      style: TextStyle(fontSize: 12),
                    ),
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
                        value: PromptMemoryType.characterOutfit,
                        child: Text('角色标准穿搭')),
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
                final ok = await _vm.promotePending(
                  memory.id!,
                  newTrigger: PromptMemoryTriggers.encode([
                    triggerController.text,
                    ...PromptMemoryTriggers.parse(aliasesController.text),
                  ]),
                  newContent: contentController.text,
                  newType: type,
                );
                if (!ctx.mounted) return;
                if (ok) {
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  showFloatingToast(
                    context,
                    '候选记忆已确认',
                    icon: CupertinoIcons.checkmark_circle_fill,
                  );
                } else {
                  showFloatingToast(
                    ctx,
                    _vm.errorMessage ?? '确认失败',
                    icon: CupertinoIcons.exclamationmark_circle,
                  );
                }
              },
              child: Text('确认晋升'),
            ),
          ],
        ),
      ),
    );
    triggerController.dispose();
    aliasesController.dispose();
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
          Text(
            '候选确认前不会参与检索。确认标准穿搭会替换同一角色的旧标准穿搭，其他类型记忆会保留。',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
                    onPressed: () async {
                      final ok = await _vm.promotePending(m.id!);
                      if (!mounted) return;
                      showFloatingToast(
                        context,
                        ok ? '候选记忆已确认' : (_vm.errorMessage ?? '确认失败'),
                        icon: ok
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.exclamationmark_circle,
                      );
                    },
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
