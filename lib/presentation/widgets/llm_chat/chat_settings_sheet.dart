import 'package:nai_huishi/presentation/widgets/llm_chat/model_selection_sheet.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/model_connection_button.dart';

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
    showDragHandle: false,
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
  late final TextEditingController _negativeV5Controller;
  late final TextEditingController _negativeV45Controller;
  late final TextEditingController _defaultStyleWordsV5Controller;
  late final TextEditingController _defaultStyleWordsV45Controller;

  @override
  void initState() {
    super.initState();
    final vm = widget.vm;
    _tabController = TabController(length: 2, vsync: this); // 模型配置 / 通用
    _systemPromptController = TextEditingController(text: vm.systemPrompt);
    _negativeV5Controller =
        TextEditingController(text: vm.defaultNegativeWordsV5);
    _negativeV45Controller =
        TextEditingController(text: vm.defaultNegativeWordsV45);
    _defaultStyleWordsV5Controller =
        TextEditingController(text: vm.defaultStyleWordsV5);
    _defaultStyleWordsV45Controller =
        TextEditingController(text: vm.defaultStyleWordsV45);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _systemPromptController.dispose();
    _negativeV5Controller.dispose();
    _negativeV45Controller.dispose();
    _defaultStyleWordsV5Controller.dispose();
    _defaultStyleWordsV45Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: FractionallySizedBox(
          heightFactor: 0.9,
          child: Container(
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
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
                        '助手设置',
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
                Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(16)),
                        child: TabBar(
                          controller: _tabController,
                          dividerColor: Colors.transparent,
                          indicatorSize: TabBarIndicatorSize.tab,
                          indicatorPadding: const EdgeInsets.all(4),
                          indicator: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12)),
                          tabs: const [
                            Tab(text: '模型'),
                            Tab(text: '通用'),
                          ],
                          labelColor: theme.colorScheme.primary,
                          unselectedLabelColor:
                              theme.colorScheme.onSurfaceVariant,
                        ))),
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
        ),
      ),
    );
  }

  Future<void> _manageProviders() async {
    await Navigator.push(
        context,
        CupertinoPageRoute(
            builder: (_) => LlmProviderManagePage(vm: widget.vm)));
    if (mounted) setState(() {});
  }

  Widget _buildModelTab() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text('选择对话与识图模型', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        _buildRoleSection(
            role: LlmProfileRole.main,
            label: '主模型',
            description: '编排提示词，调用工具，与你交流'),
        const SizedBox(height: 16),
        _buildRoleSection(
            role: LlmProfileRole.vision,
            label: '识图模型',
            description:
                widget.vm.multimodal ? '多模态已开启，当前由主模型看图' : '理解参考图的角色、画风与构图'),
        const SizedBox(height: 24),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: const Icon(CupertinoIcons.cube_box),
          title: const Text('供应商管理'),
          subtitle: Text(widget.vm.providers.isEmpty
              ? '添加供应商，开始配置模型'
              : '${widget.vm.providers.length} 个供应商'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _manageProviders,
        ),
      ],
    );
  }

  Widget _buildRoleSection(
      {required LlmProfileRole role,
      required String label,
      required String description}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final vm = widget.vm;
    final binding = vm.getBinding(role);
    LlmProvider? provider;
    for (final item in vm.providers) {
      if (item.id == binding.providerId) provider = item;
    }
    final configured = provider != null && binding.model.isNotEmpty;
    final selectedProvider = provider;
    return FrostedSurface(
      blur: 0,
      radius: 24,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(children: [
              Icon(
                  role == LlmProfileRole.main
                      ? CupertinoIcons.sparkles
                      : CupertinoIcons.photo,
                  size: 19,
                  color: colors.primary),
              const SizedBox(width: 8),
              Text(label,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: colors.onSurfaceVariant)),
            ])),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _selectModel(role),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 18),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(configured ? binding.model : '选择模型',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontSize: 21, height: 1.25)),
                      const SizedBox(height: 6),
                      Text(provider?.name ?? '点击选择供应商与模型',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colors.primary)),
                    ])),
                const SizedBox(width: 12),
                Icon(Icons.unfold_more_rounded, color: colors.onSurfaceVariant),
              ]),
            ),
          ),
        ),
        if (role == LlmProfileRole.vision && vm.multimodal)
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(description,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant))),
        if (configured) ...[
          Divider(
              height: 1,
              indent: 20,
              endIndent: 20,
              color: colors.onSurface.withValues(alpha: 0.07)),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: const Text('流式输出'),
            subtitle: Text(role == LlmProfileRole.vision
                ? (vm.streamingFor(role) ? '分段接收识图结果' : '完整接收识图结果')
                : (vm.streamingFor(role) ? '边生成边显示' : '生成完成后显示')),
            value: vm.streamingFor(role),
            onChanged: (value) async {
              await vm.setModelStreaming(role, value);
              if (mounted) setState(() {});
            },
          ),
          Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: ValueKey(
                    '${role.name}-${binding.providerId}-${binding.model}'),
                tilePadding: const EdgeInsets.symmetric(horizontal: 20),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                title: Text('连接与能力检测', style: theme.textTheme.bodySmall),
                children: [
                  ModelConnectionButton(
                      streaming: vm.streamingFor(role),
                      apiKey: selectedProvider!.apiKey,
                      baseUrl: selectedProvider.baseUrl,
                      model: binding.model)
                ],
              )),
        ],
      ]),
    );
  }

  Future<void> _selectModel(LlmProfileRole role) async {
    if (widget.vm.providers.isEmpty) {
      await _manageProviders();
      return;
    }
    final selected = await showModalBottomSheet<LlmRoleBinding>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => ModelSelectionSheet(
          providers: widget.vm.providers,
          selected: widget.vm.getBinding(role),
          title: role == LlmProfileRole.main ? '选择主模型' : '选择识图模型'),
    );
    if (selected != null) await widget.vm.setRoleBinding(role, selected);
    if (mounted) setState(() {});
  }

  Widget _buildPromptDefaultsSection({
    required String version,
    required TextEditingController styleController,
    required TextEditingController negativeController,
  }) {
    final isV5 = version == 'V5';
    final savedStyle =
        isV5 ? widget.vm.defaultStyleWordsV5 : widget.vm.defaultStyleWordsV45;
    final savedNegative = isV5
        ? widget.vm.defaultNegativeWordsV5
        : widget.vm.defaultNegativeWordsV45;
    return _PromptCard(
      title: '$version 默认提示词',
      badge: version,
      summary:
          '画风${savedStyle.trim().isEmpty ? "未设置" : "已设置"} · 负面词${savedNegative.trim().isEmpty ? "未设置" : "已设置"}',
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _PromptEditor(
            label: '画风与画师',
            controller: styleController,
            hint: '如：masterpiece, best quality, artist:xxx',
          ),
          const SizedBox(height: 16),
          _PromptEditor(
            label: '负面提示词',
            controller: negativeController,
            hint: '输入希望排除的内容',
          ),
          const SizedBox(height: 12),
          Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () async {
                  if (isV5) {
                    await widget.vm
                        .setDefaultStyleWordsV5(styleController.text.trim());
                    await widget.vm.setDefaultNegativeWordsV5(
                        negativeController.text.trim());
                  } else {
                    await widget.vm
                        .setDefaultStyleWordsV45(styleController.text.trim());
                    await widget.vm.setDefaultNegativeWordsV45(
                        negativeController.text.trim());
                  }
                  if (mounted) {
                    setState(() {});
                    showFloatingToast(context, '$version 默认提示词已保存');
                  }
                },
                child: Text('保存 $version'),
              )),
        ]),
      ],
    );
  }

  // ── 通用 tab ──
  Widget _buildGeneralTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PromptCard(
            title: '系统提示词',
            summary:
                widget.vm.systemPrompt.replaceAll(RegExp(r'\s+'), ' ').trim(),
            children: [
              _PromptEditor(
                label: '助手的角色与行为',
                controller: _systemPromptController,
                hint: '描述助手如何理解和回应你的需求',
                maxLines: 8,
              ),
              const SizedBox(height: 12),
              Row(children: [
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
                    await widget.vm
                        .setSystemPrompt(_systemPromptController.text);
                    if (!mounted) return;
                    setState(() {});
                    showFloatingToast(context, '系统提示词已保存');
                  },
                  child: const Text('保存'),
                ),
              ]),
            ],
          ),
          const SizedBox(height: 12),
          _buildPromptDefaultsSection(
            version: 'V5',
            styleController: _defaultStyleWordsV5Controller,
            negativeController: _negativeV5Controller,
          ),
          const SizedBox(height: 12),
          _buildPromptDefaultsSection(
            version: 'V4.5',
            styleController: _defaultStyleWordsV45Controller,
            negativeController: _negativeV45Controller,
          ),
          const SizedBox(height: 24),
          FrostedSurface(
              blur: 0,
              padding: const EdgeInsets.all(4),
              child: Column(children: [
                SwitchListTile.adaptive(
                  title: const Text('多模态'),
                  subtitle: const Text('直接让主模型理解图片；主模型需支持图片输入和工具调用。'),
                  value: widget.vm.multimodal,
                  onChanged: (value) async {
                    await widget.vm.setMultimodal(value);
                    if (mounted) setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.cached),
                  title: const Text('WD-Tagger 缓存'),
                  subtitle: const Text(
                      '仅保存 WD-Tagger 标签；相同图片和标签配置可复用。最多保留 256 条，LLM 识图每次重新请求。'),
                  trailing: TextButton(
                    onPressed: () async {
                      try {
                        await widget.vm.clearImageAnalysisCache();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('WD-Tagger 缓存已清除')));
                      } catch (_) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('清除失败，请重试')));
                      }
                    },
                    child: const Text('清除'),
                  ),
                ),
                const ListTile(
                    leading: Icon(Icons.all_inclusive),
                    title: Text('无限条数 · 自动压缩'),
                    subtitle: Text('完整保留聊天记录，较长对话自动生成历史摘要，保留最近的交流。')),
              ])),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  final String title;
  final String summary;
  final String? badge;
  final List<Widget> children;

  const _PromptCard({
    required this.title,
    required this.summary,
    required this.children,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return FrostedSurface(
      blur: 0,
      radius: 24,
      child: ExpansionTile(
        maintainState: true,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        onExpansionChanged: (expanded) {
          if (!expanded) FocusScope.of(context).unfocus();
        },
        leading: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(13),
          ),
          child: badge == null
              ? Icon(CupertinoIcons.text_alignleft,
                  size: 20, color: colors.primary)
              : Text(badge!,
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.primary, fontWeight: FontWeight.w700)),
        ),
        title: Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant, height: 1.5)),
        ),
        children: children,
      ),
    );
  }
}

class _PromptEditor extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final int maxLines;

  const _PromptEditor({
    required this.label,
    required this.hint,
    required this.controller,
    this.maxLines = 5,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 9),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: colors.onSurfaceVariant))),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) => Text('${value.text.runes.length} 字',
                style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.65))),
          ),
        ]),
      ),
      TextField(
        controller: controller,
        minLines: 3,
        maxLines: maxLines,
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.65),
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: colors.onSurface.withValues(alpha: 0.035),
          contentPadding: const EdgeInsets.all(16),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
              borderSide:
                  BorderSide(color: colors.primary.withValues(alpha: 0.5))),
        ),
      ),
    ]);
  }
}
