import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/agents/tool_registry.dart';
import 'package:nai_huishi/domain/agents/tools/comic_panel_prompt_tools.dart';
import 'package:nai_huishi/domain/entities/comic_project.dart';
import 'package:nai_huishi/presentation/pages/comic_post_editor_page.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_drawer.dart';
import 'package:nai_huishi/presentation/viewmodels/comic_project_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

class ComicEditorPage extends StatefulWidget {
  final String projectId;

  const ComicEditorPage({super.key, required this.projectId});

  @override
  State<ComicEditorPage> createState() => _ComicEditorPageState();
}

class _ComicEditorPageState extends State<ComicEditorPage> {
  late final ComicProjectViewModel _vm;
  String? _selectedPanelId;

  @override
  void initState() {
    super.initState();
    _vm = sl<ComicProjectViewModel>();
    _vm.addListener(_changed);
    _vm.open(widget.projectId);
  }

  @override
  void dispose() {
    _vm.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  ComicPanel? get _selectedPanel {
    final current = _vm.project;
    if (current == null || current.panels.isEmpty) return null;
    for (final panel in current.panels) {
      if (panel.id == _selectedPanelId) return panel;
    }
    return current.panels.first;
  }

  Future<void> _import() async {
    final controller = TextEditingController();
    final source = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.82,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('导入分镜',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                const Text(
                    '支持逐行 Tag、CSV 或 JSON。每条台词会在首轮生成时追加为 TEXT: 指令，之后仍可本地修正。'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 6,
                  maxLines: 14,
                  autofocus: true,
                  decoration: const InputDecoration(
                    alignLabelWithHint: true,
                    labelText: '分镜内容',
                    hintText: '1girl, classroom\n1girl, close-up, smile',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, controller.text),
                    child: const Text('导入并替换当前分镜'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (source == null) {
      return;
    }
    try {
      await _vm.importStoryboard(source);
      if (mounted) {
        showFloatingToast(context, '分镜已导入', icon: CupertinoIcons.check_mark);
      }
    } catch (e) {
      if (mounted) {
        showFloatingToast(context, '$e',
            icon: CupertinoIcons.exclamationmark_triangle);
      }
    }
  }

  Future<void> _openSettings() async {
    final current = _vm.project;
    if (current == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ComicGlobalSettings(
        project: current,
        options: _vm.modelOptions,
        onSave: _vm.updateProject,
      ),
    );
  }

  void _openComicAgent(ComicProject project, ComicPanel panel) {
    final tools = ComicPanelPromptTools(
      panel: panel,
      save: _vm.updatePanel,
    );
    const comicSystemPrompt = '''
## 漫画分镜提示词模式
你正在协助编辑单个漫画分镜。请先理解本格的画面目的，再按镜头景别、构图重心、角色连续性、动作、表情、场景、光影和阅读节奏给出建议。输出可直接用于 NovelAI 的英文 Danbooru/NovelAI Tag。不要将对白文本混入画面 Tag；对白由漫画工程单独处理。需要读取或写入时，只能调用 read_comic_panel_prompt 和 write_comic_panel_prompt。写入前保留用户已有 Tag，除非用户明确要求替换。
''';
    final registry = sl<ToolRegistry>().subset(const [
      'get_memories',
      'save_memory',
      'ask_user',
      'search_danbooru',
    ])
      ..register(tools.read)
      ..register(tools.write);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭提示词辅助',
      barrierColor: Colors.transparent,
      pageBuilder: (_, __, ___) => ChatDrawer(
        title: '漫画 Agent · ${panel.title}',
        onClose: () => Navigator.of(context).pop(),
        onInitializeScope: (chat) => chat.openScopedSession(
          contextKey: 'comic:${project.id}:${panel.id}',
          title: '漫画 · ${project.title} · ${panel.title}',
          systemPrompt: comicSystemPrompt,
          registry: registry,
        ),
        onCloseScope: (chat) => chat.closeScopedSession(),
      ),
    );
  }

  Future<void> _deletePanel(ComicProject project, ComicPanel panel) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除分镜'),
        content: Text('“${panel.title}”及其候选图、后期图层会被删除，无法恢复。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final index = project.panels.indexWhere((item) => item.id == panel.id);
      await _vm.deletePanel(panel.id);
      if (!mounted) return;
      final remaining = _vm.project?.panels ?? const <ComicPanel>[];
      setState(() {
        _selectedPanelId = remaining.isEmpty
            ? null
            : remaining[index.clamp(0, remaining.length - 1)].id;
      });
      showFloatingToast(context, '分镜已删除', icon: CupertinoIcons.delete);
    } catch (e) {
      if (mounted) {
        showFloatingToast(context, '$e',
            icon: CupertinoIcons.exclamationmark_triangle);
      }
    }
  }

  Future<void> _export() async {
    try {
      final path = await _vm.exportProject();
      if (!mounted) return;
      showFloatingToast(context, '已导出整页和分镜 PNG',
          icon: CupertinoIcons.square_arrow_down);
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('漫画已导出'),
          content: Text(path),
          actions: [
            CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭')),
            CupertinoDialogAction(
              onPressed: () async {
                final saved = await _vm.saveExportToGallery();
                if (context.mounted) {
                  Navigator.pop(context);
                  showFloatingToast(context, saved ? '整页已保存到相册' : '保存到相册失败',
                      icon: CupertinoIcons.photo);
                }
              },
              child: const Text('保存整页到相册'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        showFloatingToast(context, '导出失败：$e',
            icon: CupertinoIcons.exclamationmark_triangle);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = _vm.project;
    if (_vm.isLoading) {
      return const Scaffold(body: Center(child: CupertinoActivityIndicator()));
    }
    if (project == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(_vm.error ?? '漫画工程不可用')),
      );
    }
    final panel = _selectedPanel;
    return Theme(
      data: _comicTheme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: _EditorAppBarTitle(project: project, panel: panel),
          actions: [
            if (panel != null)
              IconButton(
                tooltip: '打开漫画提示词 Agent',
                onPressed: () => _openComicAgent(project, panel),
                icon: const Icon(CupertinoIcons.wand_stars),
              ),
            IconButton(
              tooltip: '统一生成设置',
              onPressed: _openSettings,
              icon: const Icon(CupertinoIcons.slider_horizontal_3),
            ),
            IconButton(
              tooltip: '导出整页 PNG',
              onPressed: _export,
              icon: const Icon(CupertinoIcons.square_arrow_down),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 860;
              return Column(
                children: [
                  if (_vm.error != null) _ErrorBanner(error: _vm.error!),
                  Expanded(
                    child: project.panels.isEmpty
                        ? _ComicEmptyState(
                            onImport: _import,
                            onAdd: _vm.addPanel,
                          )
                        : wide
                            ? _WideEditorLayout(
                                project: project,
                                panel: panel,
                                isGenerating: _vm.isGenerating,
                                onImport: _import,
                                onAdd: _vm.addPanel,
                                onSelect: (id) =>
                                    setState(() => _selectedPanelId = id),
                                onDelete: _vm.isGenerating
                                    ? null
                                    : (value) => _deletePanel(project, value),
                                onUpdate: _vm.updatePanel,
                                onGenerate: () => _vm.generatePanel(panel!.id),
                                onSelectCandidate: (candidateId) =>
                                    _vm.selectCandidate(panel!.id, candidateId),
                                onOpenAgent: panel == null
                                    ? null
                                    : () => _openComicAgent(project, panel),
                                onEditPost: panel == null
                                    ? null
                                    : () => _openPostEditor(panel),
                              )
                            : _CompactEditorLayout(
                                project: project,
                                panel: panel,
                                isGenerating: _vm.isGenerating,
                                onImport: _import,
                                onAdd: _vm.addPanel,
                                onSelect: (id) =>
                                    setState(() => _selectedPanelId = id),
                                onDelete: _vm.isGenerating
                                    ? null
                                    : (value) => _deletePanel(project, value),
                                onUpdate: _vm.updatePanel,
                                onGenerate: () => _vm.generatePanel(panel!.id),
                                onSelectCandidate: (candidateId) =>
                                    _vm.selectCandidate(panel!.id, candidateId),
                                onOpenAgent: panel == null
                                    ? null
                                    : () => _openComicAgent(project, panel),
                                onEditPost: panel == null
                                    ? null
                                    : () => _openPostEditor(panel),
                              ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openPostEditor(ComicPanel panel) async {
    if (panel.selectedCandidate == null) {
      showFloatingToast(context, '请先选择一张主图', icon: CupertinoIcons.info);
      return;
    }
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => ComicPostEditorPage(
          panel: panel,
          onSave: _vm.updatePanel,
        ),
      ),
    );
  }
}

ThemeData _comicTheme(ThemeData base) {
  const goldDark = Color(0xFF9A7222);
  const mint = Color(0xFF2F9E8F);
  final dark = base.brightness == Brightness.dark;
  final scheme = base.colorScheme.copyWith(
    primary: dark ? const Color(0xFFD4A84C) : goldDark,
    onPrimary: Colors.white,
    primaryContainer: dark ? const Color(0xFF4A391B) : const Color(0xFFF1DFB5),
    onPrimaryContainer:
        dark ? const Color(0xFFFFEAC0) : const Color(0xFF2D2107),
    secondary: mint,
    onSecondary: Colors.white,
    secondaryContainer:
        dark ? const Color(0xFF163D38) : const Color(0xFFD4EEE8),
    onSecondaryContainer:
        dark ? const Color(0xFFB8F0E5) : const Color(0xFF103B35),
    tertiary: mint,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor:
        dark ? const Color(0xFF0F1011) : const Color(0xFFF3F2EE),
    cardTheme: base.cardTheme.copyWith(
      color: dark ? const Color(0xFF191B1D) : Colors.white,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: dark ? const Color(0xFF111314) : const Color(0xFFF8F8F5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: dark ? Colors.white12 : Colors.black12,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            BorderSide(color: dark ? const Color(0xFFD4A84C) : goldDark),
      ),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      surfaceTintColor: Colors.transparent,
      backgroundColor: dark ? const Color(0xFF111213) : const Color(0xFFF3F2EE),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    ),
  );
}

class _EditorAppBarTitle extends StatelessWidget {
  final ComicProject project;
  final ComicPanel? panel;

  const _EditorAppBarTitle({required this.project, required this.panel});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          project.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        Text(
          panel == null
              ? '${project.panels.length} 个分镜'
              : '编辑第 ${panel?.index} 格 · ${project.panels.length} 个分镜',
          style: TextStyle(fontSize: 11, color: muted),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String error;

  const _ErrorBanner({required this.error});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.exclamationmark_triangle,
              size: 18, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child:
                Text(error, style: TextStyle(color: colors.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

class _ComicEmptyState extends StatelessWidget {
  final VoidCallback onImport;
  final VoidCallback onAdd;

  const _ComicEmptyState({required this.onImport, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: _EditorSurface(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(CupertinoIcons.rectangle_3_offgrid,
                      size: 32, color: colors.onPrimaryContainer),
                ),
                const SizedBox(height: 18),
                const Text('开始编排你的漫画',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  '先导入已有分镜，或从空白分镜开始。之后可以生成候选图、挑选主图，再完成本地对白排版。',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.5, color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stack = constraints.maxWidth < 310;
                    final importButton = FilledButton.icon(
                      onPressed: onImport,
                      icon: const Icon(CupertinoIcons.square_arrow_down),
                      label: const Text('导入分镜'),
                    );
                    final addButton = OutlinedButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(CupertinoIcons.add),
                      label: const Text('新增一格'),
                    );
                    if (stack) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          importButton,
                          const SizedBox(height: 9),
                          addButton,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: importButton),
                        const SizedBox(width: 10),
                        Expanded(child: addButton),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WideEditorLayout extends StatelessWidget {
  final ComicProject project;
  final ComicPanel? panel;
  final bool isGenerating;
  final VoidCallback onImport;
  final VoidCallback onAdd;
  final ValueChanged<String> onSelect;
  final ValueChanged<ComicPanel>? onDelete;
  final ValueChanged<ComicPanel> onUpdate;
  final VoidCallback onGenerate;
  final ValueChanged<String> onSelectCandidate;
  final VoidCallback? onOpenAgent;
  final VoidCallback? onEditPost;

  const _WideEditorLayout({
    required this.project,
    required this.panel,
    required this.isGenerating,
    required this.onImport,
    required this.onAdd,
    required this.onSelect,
    required this.onDelete,
    required this.onUpdate,
    required this.onGenerate,
    required this.onSelectCandidate,
    required this.onOpenAgent,
    required this.onEditPost,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 286,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProjectSummary(
                    project: project, onImport: onImport, onAdd: onAdd),
                const SizedBox(height: 12),
                Expanded(
                  child: _EditorSurface(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                    child: _StoryboardStrip(
                      project: project,
                      selectedPanelId: panel?.id,
                      wide: true,
                      onSelect: onSelect,
                      onDelete: onDelete,
                      onAdd: onAdd,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _EditorScrollArea(
            child: panel == null
                ? _ComicEmptyState(onImport: onImport, onAdd: onAdd)
                : _ComicPanelSection(
                    panel: panel!,
                    isGenerating: isGenerating,
                    onUpdate: onUpdate,
                    onGenerate: onGenerate,
                    onSelectCandidate: onSelectCandidate,
                    onOpenAgent: onOpenAgent,
                    onEditPost: onEditPost!,
                  ),
          ),
        ),
      ],
    );
  }
}

class _CompactEditorLayout extends StatelessWidget {
  final ComicProject project;
  final ComicPanel? panel;
  final bool isGenerating;
  final VoidCallback onImport;
  final VoidCallback onAdd;
  final ValueChanged<String> onSelect;
  final ValueChanged<ComicPanel>? onDelete;
  final ValueChanged<ComicPanel> onUpdate;
  final VoidCallback onGenerate;
  final ValueChanged<String> onSelectCandidate;
  final VoidCallback? onOpenAgent;
  final VoidCallback? onEditPost;

  const _CompactEditorLayout({
    required this.project,
    required this.panel,
    required this.isGenerating,
    required this.onImport,
    required this.onAdd,
    required this.onSelect,
    required this.onDelete,
    required this.onUpdate,
    required this.onGenerate,
    required this.onSelectCandidate,
    required this.onOpenAgent,
    required this.onEditPost,
  });

  @override
  Widget build(BuildContext context) {
    return _EditorScrollArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProjectSummary(project: project, onImport: onImport, onAdd: onAdd),
          const SizedBox(height: 12),
          _StoryboardStrip(
            project: project,
            selectedPanelId: panel?.id,
            onSelect: onSelect,
            onDelete: onDelete,
            onAdd: onAdd,
          ),
          if (panel != null) ...[
            const SizedBox(height: 14),
            _ComicPanelSection(
              panel: panel!,
              isGenerating: isGenerating,
              onUpdate: onUpdate,
              onGenerate: onGenerate,
              onSelectCandidate: onSelectCandidate,
              onOpenAgent: onOpenAgent,
              onEditPost: onEditPost!,
            ),
          ],
        ],
      ),
    );
  }
}

class _EditorScrollArea extends StatelessWidget {
  final Widget child;

  const _EditorScrollArea({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: child,
      ),
    );
  }
}

class _EditorSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _EditorSurface({required this.child, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: dark ? Colors.white10 : Colors.black.withValues(alpha: 0.07),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _ProjectSummary extends StatelessWidget {
  final ComicProject project;
  final VoidCallback onImport;
  final VoidCallback onAdd;

  const _ProjectSummary({
    required this.project,
    required this.onImport,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _EditorSurface(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('创作概览',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: 0.2)),
              ),
              _StatusPill(
                label: project.status == ComicProjectStatus.exported
                    ? '已导出'
                    : project.status == ComicProjectStatus.generating
                        ? '生成中'
                        : '编辑中',
                color: project.status == ComicProjectStatus.exported
                    ? colors.secondary
                    : colors.primary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _SummaryMetric(value: '${project.panels.length}', label: '分镜'),
              _SummaryMetric(value: project.resolution, label: '画布'),
              _SummaryMetric(value: '${project.candidateCount}', label: '每格候选'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onImport,
                  icon: const Icon(CupertinoIcons.square_arrow_down, size: 17),
                  label: const Text('导入分镜'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(CupertinoIcons.add, size: 17),
                  label: const Text('新增一格'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String value;
  final String label;

  const _SummaryMetric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary)),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _StoryboardStrip extends StatelessWidget {
  final ComicProject project;
  final String? selectedPanelId;
  final ValueChanged<String> onSelect;
  final ValueChanged<ComicPanel>? onDelete;
  final VoidCallback? onAdd;
  final bool wide;

  const _StoryboardStrip({
    required this.project,
    required this.selectedPanelId,
    required this.onSelect,
    this.onDelete,
    this.onAdd,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final panel in project.panels)
        _StoryboardCard(
          panel: panel,
          selected: panel.id == selectedPanelId,
          onSelect: () => onSelect(panel.id),
          onDelete: onDelete == null ? null : () => onDelete!(panel),
          wide: wide,
        ),
      if (onAdd != null) _AddPanelCard(onTap: onAdd!, wide: wide),
    ];
    if (wide) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(height: 9),
        itemBuilder: (_, index) => children[index],
      );
    }
    return SizedBox(
      height: 142,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) => children[index],
      ),
    );
  }
}

class _StoryboardCard extends StatelessWidget {
  final ComicPanel panel;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onDelete;
  final bool wide;

  const _StoryboardCard({
    required this.panel,
    required this.selected,
    required this.onSelect,
    required this.onDelete,
    required this.wide,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final candidate = panel.selectedCandidate;
    final statusColor = switch (panel.status) {
      ComicPanelStatus.done => colors.secondary,
      ComicPanelStatus.failed => colors.error,
      ComicPanelStatus.generating || ComicPanelStatus.queued => colors.primary,
      ComicPanelStatus.ready => colors.onSurfaceVariant,
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '第 ${panel.index} 格，${panel.title}，${_panelStatus(panel)}',
      child: SizedBox(
        width: wide ? double.infinity : 124,
        height: wide ? 82 : 142,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: selected
                ? colors.primaryContainer.withValues(alpha: 0.72)
                : colors.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.8 : 0.8,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: onSelect,
              child: wide
                  ? Row(children: [
                      _StoryboardThumbnail(
                          panel: panel, candidate: candidate, wide: wide),
                      Expanded(
                          child: _StoryboardCardDetails(
                        panel: panel,
                        statusColor: statusColor,
                        onDelete: onDelete,
                      )),
                    ])
                  : Column(children: [
                      Expanded(
                          child: _StoryboardThumbnail(
                              panel: panel, candidate: candidate, wide: wide)),
                      _StoryboardCardDetails(
                          panel: panel,
                          statusColor: statusColor,
                          onDelete: onDelete),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

String _panelStatus(ComicPanel panel) => switch (panel.status) {
      ComicPanelStatus.ready => '待生成',
      ComicPanelStatus.queued => '排队中',
      ComicPanelStatus.generating => '生成中',
      ComicPanelStatus.done => '已完成',
      ComicPanelStatus.failed => '失败',
    };

class _StoryboardThumbnail extends StatelessWidget {
  final ComicPanel panel;
  final ComicCandidate? candidate;
  final bool wide;

  const _StoryboardThumbnail({
    required this.panel,
    required this.candidate,
    required this.wide,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasImage = candidate != null &&
        candidate!.imagePath.isNotEmpty &&
        File(candidate!.imagePath).existsSync();
    return ClipRRect(
      borderRadius: wide
          ? const BorderRadius.horizontal(left: Radius.circular(15))
          : const BorderRadius.vertical(top: Radius.circular(15)),
      child: SizedBox(
        width: wide ? 70 : double.infinity,
        child: hasImage
            ? Image.file(File(candidate!.imagePath), fit: BoxFit.cover)
            : ColoredBox(
                color: colors.surfaceContainerHighest,
                child: Center(
                  child: Icon(CupertinoIcons.photo,
                      size: wide ? 20 : 25,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.7)),
                ),
              ),
      ),
    );
  }
}

class _StoryboardCardDetails extends StatelessWidget {
  final ComicPanel panel;
  final Color statusColor;
  final VoidCallback? onDelete;

  const _StoryboardCardDetails({
    required this.panel,
    required this.statusColor,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 7, 7, 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${panel.index}. ${panel.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(CupertinoIcons.circle_fill, size: 6, color: statusColor),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      '${_panelStatus(panel)} · ${panel.candidates.length} 张',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: statusColor),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: '删除分镜',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: onDelete,
              icon: const Icon(CupertinoIcons.ellipsis, size: 17),
            ),
        ],
      ),
    );
  }
}

class _AddPanelCard extends StatelessWidget {
  final VoidCallback onTap;
  final bool wide;

  const _AddPanelCard({required this.onTap, required this.wide});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: wide ? double.infinity : 124,
      height: wide ? 70 : 142,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colors.outlineVariant),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.add_circled, color: colors.primary),
            const SizedBox(height: 5),
            const Text('新增分镜', style: TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _ComicPanelSection extends StatefulWidget {
  final ComicPanel panel;
  final bool isGenerating;
  final ValueChanged<ComicPanel> onUpdate;
  final VoidCallback onGenerate;
  final ValueChanged<String> onSelectCandidate;
  final VoidCallback onEditPost;
  final VoidCallback? onOpenAgent;

  const _ComicPanelSection({
    required this.panel,
    required this.isGenerating,
    required this.onUpdate,
    required this.onGenerate,
    required this.onSelectCandidate,
    required this.onEditPost,
    required this.onOpenAgent,
  });

  @override
  State<_ComicPanelSection> createState() => _ComicPanelSectionState();
}

class _ComicPanelSectionState extends State<_ComicPanelSection> {
  static const _uuid = Uuid();
  late final TextEditingController _title;
  late final TextEditingController _prompt;
  late final TextEditingController _dialogue;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.panel.title);
    _prompt = TextEditingController(text: widget.panel.prompt);
    _dialogue = TextEditingController(
        text: widget.panel.dialogues.map((item) => item.text).join('\n'));
  }

  @override
  void didUpdateWidget(covariant _ComicPanelSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panel.id != widget.panel.id) {
      _title.text = widget.panel.title;
      _prompt.text = widget.panel.prompt;
      _dialogue.text =
          widget.panel.dialogues.map((item) => item.text).join('\n');
      return;
    }
    if (oldWidget.panel.title != widget.panel.title &&
        _title.text == oldWidget.panel.title) {
      _title.text = widget.panel.title;
    }
    if (oldWidget.panel.prompt != widget.panel.prompt &&
        _prompt.text == oldWidget.panel.prompt) {
      _prompt.text = widget.panel.prompt;
    }
    final oldDialogue =
        oldWidget.panel.dialogues.map((item) => item.text).join('\n');
    final nextDialogue =
        widget.panel.dialogues.map((item) => item.text).join('\n');
    if (oldDialogue != nextDialogue && _dialogue.text == oldDialogue) {
      _dialogue.text = nextDialogue;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    _dialogue.dispose();
    super.dispose();
  }

  void _saveFields() {
    final existing = widget.panel.dialogues;
    final dialogues = _dialogue.text
        .split(RegExp(r'\r?\n'))
        .map((text) => text.trim())
        .where((text) => text.isNotEmpty)
        .toList()
        .asMap()
        .entries
        .map((entry) => ComicDialogue(
              id: entry.key < existing.length
                  ? existing[entry.key].id
                  : _uuid.v4(),
              speaker: entry.key < existing.length
                  ? existing[entry.key].speaker
                  : '',
              text: entry.value,
              generateText: entry.key < existing.length
                  ? existing[entry.key].generateText
                  : true,
            ))
        .toList();
    widget.onUpdate(widget.panel.copyWith(
        title: _title.text, prompt: _prompt.text, dialogues: dialogues));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dialogueCount = widget.panel.dialogues.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EditorSurface(
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('第 ${widget.panel.index} 格',
                            style: TextStyle(
                                color: colors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text('画面描述',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  _StatusPill(
                    label: _panelStatus(widget.panel),
                    color: widget.panel.status == ComicPanelStatus.done
                        ? colors.secondary
                        : colors.primary,
                  ),
                ],
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _title,
                enabled: !widget.isGenerating,
                onChanged: (_) => _saveFields(),
                onEditingComplete: _saveFields,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '分镜标题',
                  prefixIcon: Icon(CupertinoIcons.textformat),
                ),
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  const Expanded(
                    child: Text('NovelAI / Danbooru Tags',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (widget.onOpenAgent != null)
                    TextButton.icon(
                      onPressed:
                          widget.isGenerating ? null : widget.onOpenAgent,
                      icon: const Icon(CupertinoIcons.wand_stars, size: 16),
                      label: const Text('优化 Tags'),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text('描述镜头、构图、动作和光影；对白由漫画工程单独处理。',
                  style:
                      TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
              const SizedBox(height: 7),
              TextField(
                controller: _prompt,
                enabled: !widget.isGenerating,
                minLines: 4,
                maxLines: 9,
                onChanged: (_) => _saveFields(),
                decoration: const InputDecoration(
                  hintText: '例如：close-up, dynamic angle, ...',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _EditorSurface(
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('对白脚本',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  Text('$dialogueCount 条',
                      style: TextStyle(color: colors.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 5),
              Text('每行一条台词；首次生成会尝试使用 TEXT: 指令绘字。',
                  style:
                      TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
              const SizedBox(height: 8),
              TextField(
                controller: _dialogue,
                enabled: !widget.isGenerating,
                minLines: 3,
                maxLines: 7,
                onChanged: (_) => _saveFields(),
                decoration: const InputDecoration(
                  hintText: '角色：你好，欢迎来到这里。',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 13),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  FilledButton.icon(
                    onPressed: widget.isGenerating
                        ? null
                        : () {
                            _saveFields();
                            widget.onGenerate();
                          },
                    icon: widget.isGenerating
                        ? const CupertinoActivityIndicator()
                        : const Icon(CupertinoIcons.sparkles),
                    label: Text(widget.isGenerating ? '正在生成' : '生成候选图'),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onEditPost,
                    icon: const Icon(CupertinoIcons.text_bubble),
                    label: const Text('对白后期'),
                  ),
                ],
              ),
              if (widget.isGenerating) ...[
                const SizedBox(height: 11),
                Row(
                  children: [
                    SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: colors.primary)),
                    const SizedBox(width: 8),
                    Text('正在为当前分镜生成候选图，请稍候。',
                        style: TextStyle(color: colors.onSurfaceVariant)),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (widget.panel.candidates.isNotEmpty) ...[
          const SizedBox(height: 12),
          _CandidateGallery(
            panel: widget.panel,
            enabled: !widget.isGenerating,
            onSelect: widget.onSelectCandidate,
          ),
        ],
      ],
    );
  }
}

class _CandidateGallery extends StatelessWidget {
  final ComicPanel panel;
  final bool enabled;
  final ValueChanged<String> onSelect;

  const _CandidateGallery({
    required this.panel,
    required this.enabled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completed = panel.candidates
        .where((candidate) => candidate.status == ComicPanelStatus.done)
        .length;
    return _EditorSurface(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child:
                    Text('候选结果', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              Text('$completed/${panel.candidates.length} 已完成',
                  style: TextStyle(color: colors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 4),
          Text('点击已完成的图片，将它设为当前分镜主图。',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          const SizedBox(height: 13),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720
                  ? 4
                  : constraints.maxWidth >= 470
                      ? 3
                      : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 12,
                children: [
                  for (final candidate in panel.candidates)
                    _CandidateCard(
                      candidate: candidate,
                      selected: candidate.id == panel.selectedCandidateId,
                      enabled: enabled,
                      width: width,
                      onSelect: () => onSelect(candidate.id),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final ComicCandidate candidate;
  final bool selected;
  final bool enabled;
  final double width;
  final VoidCallback onSelect;

  const _CandidateCard({
    required this.candidate,
    required this.selected,
    required this.enabled,
    required this.width,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final done = candidate.status == ComicPanelStatus.done;
    final failed = candidate.status == ComicPanelStatus.failed;
    final hasImage = done &&
        candidate.imagePath.isNotEmpty &&
        File(candidate.imagePath).existsSync();
    return Semantics(
      button: done && enabled,
      label: '候选图，${_candidateStatus(candidate)}${selected ? '，当前主图' : ''}',
      child: SizedBox(
        width: width,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: done && enabled ? onSelect : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: width * 1.18,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? colors.primary : colors.outlineVariant,
                    width: selected ? 2.2 : 0.8,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasImage
                    ? Image.file(
                        File(candidate.imagePath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const _CandidatePlaceholder(failed: true),
                      )
                    : _CandidatePlaceholder(failed: failed),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      done && selected ? '主图' : _candidateStatus(candidate),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: failed ? colors.error : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(CupertinoIcons.check_mark_circled_solid,
                        size: 16, color: colors.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _candidateStatus(ComicCandidate candidate) => switch (candidate.status) {
      ComicPanelStatus.ready => '等待中',
      ComicPanelStatus.queued => '排队中',
      ComicPanelStatus.generating => '生成中',
      ComicPanelStatus.done => '设为主图',
      ComicPanelStatus.failed => '生成失败',
    };

class _CandidatePlaceholder extends StatelessWidget {
  final bool failed;

  const _CandidatePlaceholder({required this.failed});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            failed
                ? CupertinoIcons.exclamationmark_triangle
                : CupertinoIcons.hourglass,
            color: failed ? colors.error : colors.onSurfaceVariant,
          ),
          const SizedBox(height: 7),
          Text(failed ? '图片不可用' : '准备中',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SettingsSectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _ComicGlobalSettings extends StatefulWidget {
  final ComicProject project;
  final List<ImageModelOption> options;
  final ValueChanged<ComicProject> onSave;

  const _ComicGlobalSettings(
      {required this.project, required this.options, required this.onSave});

  @override
  State<_ComicGlobalSettings> createState() => _ComicGlobalSettingsState();
}

class _ComicGlobalSettingsState extends State<_ComicGlobalSettings> {
  late final TextEditingController _prompt;
  late final TextEditingController _negative;
  String _modelId = '';
  late String _resolution;
  late int _count;

  @override
  void initState() {
    super.initState();
    _prompt = TextEditingController(text: widget.project.globalPrompt);
    _negative = TextEditingController(text: widget.project.negativePrompt);
    for (final option in widget.options) {
      if (option.actualModel == widget.project.model &&
          option.endpointId == widget.project.endpointId) {
        _modelId = option.modelId;
        break;
      }
    }
    if (_modelId.isEmpty) {
      for (final option in widget.options) {
        if (option.actualModel == widget.project.model) {
          _modelId = option.modelId;
          break;
        }
      }
    }
    _resolution = widget.project.resolution;
    _count = widget.project.candidateCount;
  }

  @override
  void dispose() {
    _prompt.dispose();
    _negative.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    final validModelId = options.any((option) => option.modelId == _modelId)
        ? _modelId
        : (options.isEmpty ? '' : options.first.modelId);
    ImageModelOption? selectedOption;
    for (final option in options) {
      if (option.modelId == validModelId) {
        selectedOption = option;
        break;
      }
    }
    final dropdownItems = options
        .map((option) => DropdownMenuItem<String>(
              value: option.modelId,
              child: Text(
                option.displayName,
                overflow: TextOverflow.ellipsis,
              ),
            ))
        .toList();
    const standardResolutions = [
      '832x1216',
      '1216x832',
      '1024x1024',
      '1024x1536',
      '1536x1024',
    ];
    final resolutions = [
      if (!standardResolutions.contains(_resolution)) _resolution,
      ...standardResolutions,
    ];
    final colors = Theme.of(context).colorScheme;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Material(
              color: Theme.of(context).cardTheme.color,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.onSurfaceVariant.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text('统一生成设置',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('这些参数会应用到项目内的每一个分镜。',
                        style: TextStyle(color: colors.onSurfaceVariant)),
                    const SizedBox(height: 18),
                    const _SettingsSectionLabel(
                        icon: CupertinoIcons.cube_box, label: '生成模型'),
                    const SizedBox(height: 9),
                    if (options.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: colors.errorContainer,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Text('尚未配置可用的 NovelAI 模型，请先到 API 配置中完成设置。',
                            style: TextStyle(color: colors.onErrorContainer)),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue:
                            validModelId.isEmpty ? null : validModelId,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'NovelAI 模型'),
                        items: dropdownItems,
                        onChanged: (value) =>
                            setState(() => _modelId = value ?? ''),
                      ),
                    const SizedBox(height: 18),
                    const _SettingsSectionLabel(
                        icon: CupertinoIcons.paintbrush, label: '风格与约束'),
                    const SizedBox(height: 9),
                    TextField(
                      controller: _prompt,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: '全局风格词 / 提示词',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _negative,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: '全局负面词',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _SettingsSectionLabel(
                        icon: CupertinoIcons.rectangle_expand_vertical,
                        label: '输出'),
                    const SizedBox(height: 9),
                    DropdownButtonFormField<String>(
                      initialValue: _resolution,
                      decoration: const InputDecoration(labelText: '分镜尺寸'),
                      items: resolutions
                          .map((value) => DropdownMenuItem(
                              value: value, child: Text(value)))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _resolution = value ?? _resolution),
                    ),
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('每格候选数',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        _StatusPill(label: '$_count 张', color: colors.primary),
                      ],
                    ),
                    Slider(
                      value: _count.toDouble(),
                      min: comicCandidateCountMin.toDouble(),
                      max: comicCandidateCountMax.toDouble(),
                      divisions:
                          comicCandidateCountMax - comicCandidateCountMin,
                      label: '$_count',
                      onChanged: (value) =>
                          setState(() => _count = value.round()),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: options.isEmpty
                          ? null
                          : () {
                              widget.onSave(widget.project.copyWith(
                                globalPrompt: _prompt.text,
                                negativePrompt: _negative.text,
                                model: selectedOption?.actualModel ?? '',
                                endpointId: selectedOption?.endpointId,
                                protocol: selectedOption?.protocol ?? '',
                                resolution: _resolution,
                                candidateCount: _count,
                              ));
                              Navigator.pop(context);
                            },
                      icon: const Icon(CupertinoIcons.check_mark),
                      label: const Text('保存统一设置'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
