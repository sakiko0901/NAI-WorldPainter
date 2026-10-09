import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/presentation/pages/comic_editor_page.dart';
import 'package:nai_huishi/presentation/viewmodels/comic_project_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

class ComicProjectsPage extends StatefulWidget {
  const ComicProjectsPage({super.key});

  @override
  State<ComicProjectsPage> createState() => _ComicProjectsPageState();
}

class _ComicProjectsPageState extends State<ComicProjectsPage> {
  late final ComicProjectViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = sl<ComicProjectViewModel>();
    _vm.addListener(_changed);
    _vm.loadProjects();
  }

  @override
  void dispose() {
    _vm.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _create() async {
    final controller = TextEditingController();
    final title = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('新建漫画项目'),
        content: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '项目名称'),
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null) return;
    final project = await _vm.create(title);
    if (!mounted) return;
    await Navigator.of(context).push(
      CupertinoPageRoute(
          builder: (_) => ComicEditorPage(projectId: project.id)),
    );
    await _vm.loadProjects();
  }

  Future<void> _open(String id) async {
    await Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => ComicEditorPage(projectId: id)),
    );
    await _vm.loadProjects();
  }

  Future<void> _delete(String id, String title) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除漫画项目？'),
        content: Text('将删除“$title”的分镜、候选图与可编辑对话工程。'),
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
    await _vm.delete(id);
    if (mounted) {
      showFloatingToast(context, '已删除漫画项目', icon: CupertinoIcons.delete);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('漫画生成'),
        actions: [
          IconButton(
            tooltip: '新建项目',
            onPressed: _create,
            icon: const Icon(CupertinoIcons.add),
          ),
        ],
      ),
      body: _vm.isLoading
          ? const Center(child: CupertinoActivityIndicator())
          : _vm.error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_vm.error!, textAlign: TextAlign.center),
                ))
              : _vm.projects.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.rectangle_stack_badge_plus,
                                size: 48,
                                color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(height: 14),
                            const Text('还没有漫画项目'),
                            const SizedBox(height: 8),
                            Text(
                              '新建项目后可导入逐行 Tag、CSV 或 JSON 分镜，再生成候选图并完成本地对白排版。',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  height: 1.45,
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: _create,
                              icon: const Icon(CupertinoIcons.add),
                              label: const Text('新建漫画项目'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _vm.projects.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final project = _vm.projects[index];
                        final cover = project.coverPath;
                        return Material(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.36),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _open(project.id),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 76,
                                    height: 76,
                                    child: cover != null &&
                                            File(cover).existsSync()
                                        ? Image.file(File(cover),
                                            fit: BoxFit.cover)
                                        : ColoredBox(
                                            color: theme
                                                .colorScheme.primaryContainer,
                                            child: Icon(
                                                CupertinoIcons
                                                    .rectangle_3_offgrid,
                                                color: theme.colorScheme
                                                    .onPrimaryContainer),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(project.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 6),
                                    Text(
                                        '${project.panels.length} 个分镜 · ${project.canvasWidth}×${project.canvasHeight}',
                                        style: TextStyle(
                                            color: theme
                                                .colorScheme.onSurfaceVariant)),
                                    const SizedBox(height: 4),
                                    Text(
                                        '最近编辑 ${project.updatedAt.toLocal().toString().substring(0, 16)}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: theme
                                                .colorScheme.onSurfaceVariant)),
                                  ],
                                )),
                                IconButton(
                                  tooltip: '删除项目',
                                  onPressed: () =>
                                      _delete(project.id, project.title),
                                  icon: const Icon(CupertinoIcons.delete,
                                      size: 20),
                                ),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
