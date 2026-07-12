import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/domain/entities/llm_profile_role.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_role_binding.dart';
import 'package:nai_huishi/presentation/pages/llm_provider_manage_page.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart'
    show showFloatingToast;

Future<void> showChatSettingsSheet(
  BuildContext context,
  LlmChatViewModel vm,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ChatSettingsSheet(vm: vm),
  );
}

class _ChatSettingsSheet extends StatefulWidget {
  final LlmChatViewModel vm;
  const _ChatSettingsSheet({required this.vm});

  @override
  State<_ChatSettingsSheet> createState() => _ChatSettingsSheetState();
}

class _ChatSettingsSheetState extends State<_ChatSettingsSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final TextEditingController _systemPromptController;
  late final TextEditingController _contextLimitController;
  late final TextEditingController _nsfwBookPathController;
  late final TextEditingController _defaultStyleWordsController;

  bool _nsfwBookLoaded = false;
  String _nsfwBookStatus = '';
  bool _webSearchEnabled = false;

  @override
  void initState() {
    super.initState();
    final vm = widget.vm;
    _tabController = TabController(length: 2, vsync: this); // 模型配置 / 通用
    _systemPromptController = TextEditingController(text: vm.systemPrompt);
    _contextLimitController =
        TextEditingController(text: vm.contextLimit.toString());
    _nsfwBookPathController = TextEditingController(text: '');
    _defaultStyleWordsController =
        TextEditingController(text: vm.defaultStyleWords);
    _webSearchEnabled = vm.webSearchEnabled;

    _loadNsfwBookStatus();
  }

  Future<void> _loadNsfwBookStatus() async {
    final vm = widget.vm;
    _nsfwBookLoaded = vm.nsfwBook.isLoaded;
    _nsfwBookStatus =
        _nsfwBookLoaded ? '已加载（${vm.nsfwBook.entryCount} 条）' : '未加载';
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _systemPromptController.dispose();
    _contextLimitController.dispose();
    _nsfwBookPathController.dispose();
    _defaultStyleWordsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF14141A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // 顶部拖拽条
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    'LLM 配置',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(CupertinoIcons.xmark_circle_fill,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: const [
                Tab(text: '模型配置'),
                Tab(text: '通用'),
              ],
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              indicatorColor: theme.colorScheme.primary,
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildModelTab(),
                  _buildGeneralTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 模型配置 tab ──
  Widget _buildModelTab() {
    final theme = Theme.of(context);
    final vm = widget.vm;
    final providers = vm.providers;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 供应商管理入口
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => LlmProviderManagePage(vm: vm),
                ),
              );
              if (mounted) setState(() {});
            },
            icon: const Icon(CupertinoIcons.cube_box),
            label: const Text('供应商管理'),
          ),
          const SizedBox(height: 16),
          if (providers.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(CupertinoIcons.info_circle,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '尚未配置任何供应商。点击上方"供应商管理"新建一个，然后回到这里为各角色绑定模型。',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Text('供应商（${providers.length}）',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          const SizedBox(height: 12),
          _buildRoleSection(
            role: LlmProfileRole.main,
            label: '主模型',
            description: 'Agent 主循环使用，负责工具调用与最终回复',
          ),
          const SizedBox(height: 16),
          _buildRoleSection(
            role: LlmProfileRole.vision,
            label: '识图模型',
            description: '图片理解任务使用，需支持 vision 输入',
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildRoleSection({
    required LlmProfileRole role,
    required String label,
    required String description,
  }) {
    final theme = Theme.of(context);
    final vm = widget.vm;
    final providers = vm.providers;
    final binding = vm.getBinding(role);

    LlmProvider? selectedProvider;
    if (binding.providerId != null) {
      for (final p in providers) {
        if (p.id == binding.providerId) {
          selectedProvider = p;
          break;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  )),
              const SizedBox(width: 8),
              if (binding.isConfigured)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('已配置',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.greenAccent.shade700,
                      )),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('未配置',
                      style: TextStyle(fontSize: 10, color: Colors.orange)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(description,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 12),
          _Label('供应商'),
          DropdownButton<String?>(
            value: binding.providerId,
            isExpanded: true,
            hint: const Text('选择供应商'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('（未选择）', style: TextStyle(fontSize: 13)),
              ),
              ...providers.map((p) => DropdownMenuItem<String?>(
                    value: p.id,
                    child: Text(
                      '${p.name}  ·  ${p.baseUrl}',
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
            ],
            onChanged: providers.isEmpty
                ? null
                : (newId) async {
                    final newBinding = LlmRoleBinding(
                      providerId: newId,
                      model: '',
                    );
                    await vm.setRoleBinding(role, newBinding);
                    if (mounted) setState(() {});
                  },
          ),
          const SizedBox(height: 12),
          _Label('模型'),
          DropdownButton<String>(
            value: (selectedProvider != null &&
                    binding.model.isNotEmpty &&
                    selectedProvider.models.contains(binding.model))
                ? binding.model
                : null,
            isExpanded: true,
            hint: Text(
              selectedProvider == null
                  ? '请先选择供应商'
                  : (selectedProvider.models.isEmpty
                      ? '该供应商下没有模型，去供应商管理添加'
                      : '选择模型'),
              style: const TextStyle(fontSize: 13),
            ),
            items: (selectedProvider?.models ?? const <String>[])
                .map((m) => DropdownMenuItem<String>(
                      value: m,
                      child: Text(m, style: const TextStyle(fontSize: 13)),
                    ))
                .toList(),
            onChanged:
                (selectedProvider == null || selectedProvider.models.isEmpty)
                    ? null
                    : (newModel) async {
                        if (newModel == null) return;
                        final provider = selectedProvider;
                        if (provider == null) return;
                        final newBinding = LlmRoleBinding(
                          providerId: provider.id,
                          model: newModel,
                        );
                        await vm.setRoleBinding(role, newBinding);
                        if (mounted) setState(() {});
                      },
          ),
        ],
      ),
    );
  }

  // ── 通用 tab ──
  Widget _buildGeneralTab() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label('系统提示词'),
          TextField(
            controller: _systemPromptController,
            maxLines: 10,
            minLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  _systemPromptController.text =
                      AppConstants.defaultLlmSystemPrompt;
                },
                child: const Text('恢复默认'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  await widget.vm.setSystemPrompt(_systemPromptController.text);
                  if (mounted) showFloatingToast(context, '已保存');
                },
                child: const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _Label('上下文条数'),
          Row(
            children: [
              Expanded(
                child: Slider(
                  min: 1,
                  max: 50,
                  divisions: 49,
                  value: double.tryParse(_contextLimitController.text) ?? 20,
                  onChanged: (v) {
                    _contextLimitController.text = v.toInt().toString();
                    setState(() {});
                  },
                ),
              ),
              SizedBox(
                width: 50,
                child: Text(
                  _contextLimitController.text,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                onPressed: () async {
                  final v = int.tryParse(_contextLimitController.text) ?? 20;
                  await widget.vm.setContextLimit(v);
                  if (mounted) showFloatingToast(context, '已保存');
                },
                icon: Icon(CupertinoIcons.checkmark_circle_fill,
                    color: theme.colorScheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('联网搜索'),
            subtitle: const Text('让 Agent 能用 DuckDuckGo 联网查信息'),
            value: _webSearchEnabled,
            onChanged: (v) async {
              await widget.vm.setWebSearchEnabled(v);
              setState(() => _webSearchEnabled = v);
            },
          ),
          const SizedBox(height: 16),
          _Label('默认画风画师词'),
          TextField(
            controller: _defaultStyleWordsController,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              hintText: '如：masterpiece, best quality, artist:xxx',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '每次生图时自动拼到正向 prompt 最前面；空则不拼。',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  await widget.vm.setDefaultStyleWords(
                      _defaultStyleWordsController.text.trim());
                  if (mounted) showFloatingToast(context, '已保存');
                },
                child: const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Label('知识库'),
          Row(
            children: [
              Expanded(
                child: Text(
                  _nsfwBookStatus,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  await widget.vm.reloadNsfwBook();
                  await _loadNsfwBookStatus();
                },
                child: const Text('重新加载'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nsfwBookPathController,
            decoration: const InputDecoration(
              hintText: '外部知识库 JSON 路径（可选）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
