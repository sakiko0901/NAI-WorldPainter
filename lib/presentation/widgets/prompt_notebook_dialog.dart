import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/domain/entities/prompt_template.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_templates.dart';

Future<void> showPromptNotebook({
  required BuildContext context,
  required ManagePromptTemplatesUseCase templates,
  required Future<void> Function(String content) onImport,
}) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭提示词笔记本',
      barrierColor: Colors.black54,
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 260),
      transitionBuilder: (context, animation, _, child) {
        final curve = animation.drive(CurveTween(curve: Curves.easeOutCubic));
        return FadeTransition(
            opacity: curve,
            child: ScaleTransition(
                scale: Tween(begin: 0.96, end: 1.0).animate(curve),
                child: SlideTransition(
                    position:
                        Tween(begin: const Offset(0, 0.035), end: Offset.zero)
                            .animate(curve),
                    child: child)));
      },
      pageBuilder: (context, _, __) =>
          PromptNotebookDialog(templates: templates, onImport: onImport),
    );

class PromptNotebookDialog extends StatefulWidget {
  const PromptNotebookDialog(
      {super.key, required this.templates, required this.onImport});
  final ManagePromptTemplatesUseCase templates;
  final Future<void> Function(String content) onImport;

  @override
  State<PromptNotebookDialog> createState() => _PromptNotebookDialogState();
}

class _PromptNotebookDialogState extends State<PromptNotebookDialog> {
  final _search = TextEditingController();
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _form = GlobalKey<FormState>();
  List<PromptTemplate> _entries = [];
  PromptTemplate? _editingEntry;
  bool _editing = false;
  bool _loading = true;
  bool _saving = false;
  int? _importingId;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final entries = await widget.templates.getAll();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '笔记加载失败，请重试';
        });
      }
    }
  }

  void _edit([PromptTemplate? entry]) {
    _title.text = entry?.name ?? '';
    _content.text = entry?.content ?? '';
    setState(() {
      _editingEntry = entry;
      _editing = true;
      _error = null;
      _message = null;
    });
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final now = DateTime.now();
    final entry = _editingEntry?.copyWith(
          name: _title.text.trim(),
          content: _content.text.trim(),
          updatedAt: now,
        ) ??
        PromptTemplate(
            name: _title.text.trim(),
            category: '笔记本',
            content: _content.text.trim(),
            createdAt: now,
            updatedAt: now);
    try {
      final saved = entry.id == null
          ? await widget.templates.create(entry)
          : await widget.templates.update(entry);
      if (!mounted) return;
      setState(() {
        _entries = [saved, ..._entries.where((item) => item.id != saved.id)];
        _editing = false;
        _message = '已保存「${saved.name}」';
      });
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，内容已保留，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _import(PromptTemplate entry) async {
    if (_importingId != null) return;
    setState(() {
      _importingId = entry.id;
      _error = null;
    });
    try {
      await widget.onImport(entry.content);
      if (mounted) setState(() => _message = '已导入「${entry.name}」');
      if (entry.id != null) {
        try {
          await widget.templates.incrementUseCount(entry.id!);
          if (mounted) {
            setState(() {
              _entries = _entries
                  .map((item) => item.id == entry.id
                      ? item.copyWith(useCount: item.useCount + 1)
                      : item)
                  .toList();
            });
          }
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) setState(() => _error = '导入失败，请重试');
    } finally {
      if (mounted) setState(() => _importingId = null);
    }
  }

  Future<void> _copy(PromptTemplate entry) async {
    try {
      await Clipboard.setData(ClipboardData(text: entry.content));
      if (mounted) {
        setState(() {
          _message = '已复制「${entry.name}」';
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '复制失败，请重试');
    }
  }

  Future<void> _delete(PromptTemplate entry) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('删除笔记'),
              content: Text('删除「${entry.name}」？'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除'))
              ],
            ));
    if (confirmed != true || !mounted || entry.id == null) return;
    try {
      await widget.templates.delete(entry.id!);
      if (mounted) {
        setState(() {
          _entries.removeWhere((item) => item.id == entry.id);
          _message = '已删除笔记';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '删除失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Dialog(
      key: const ValueKey('prompt-notebook-dialog'),
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (_editing)
                IconButton(
                    tooltip: '返回笔记本',
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                              _editing = false;
                              _error = null;
                            }),
                    icon: const Icon(CupertinoIcons.chevron_left, size: 18)),
              Expanded(
                  child: Text(
                      _editing
                          ? (_editingEntry == null ? '添加笔记' : '编辑笔记')
                          : '提示词笔记本',
                      style: theme.textTheme.titleMedium)),
              IconButton(
                  tooltip: '关闭笔记本',
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(CupertinoIcons.xmark, size: 18)),
            ]),
            const SizedBox(height: 12),
            Expanded(child: _editing ? _editor() : _library(colors)),
            if (_error != null || _message != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error ?? _message!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: _error != null
                            ? colors.error
                            : colors.onSurfaceVariant)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _editor() => LayoutBuilder(builder: (context, constraints) {
        final minimumHeight = 260 + MediaQuery.textScalerOf(context).scale(64);
        return SingleChildScrollView(
          child: SizedBox(
            height: constraints.maxHeight.clamp(minimumHeight, double.infinity),
            child: _editorForm(),
          ),
        );
      });

  Widget _editorForm() => Form(
        key: _form,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
              key: const ValueKey('notebook-title'),
              controller: _title,
              enabled: !_saving,
              textInputAction: TextInputAction.next,
              decoration:
                  const InputDecoration(labelText: '标题', hintText: '例如：柔和逆光'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请填写标题' : null),
          const SizedBox(height: 14),
          Expanded(
              child: TextFormField(
                  key: const ValueKey('notebook-content'),
                  controller: _content,
                  enabled: !_saving,
                  minLines: null,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                      labelText: '提示词内容',
                      hintText: '输入单个 tag 或一组提示词',
                      alignLabelWithHint: true),
                  validator: (value) => value == null ||
                          value.replaceAll(RegExp(r'[\s,，]'), '').isEmpty
                      ? '请填写提示词内容'
                      : null)),
          const SizedBox(height: 14),
          FilledButton.icon(
              key: const ValueKey('notebook-save'),
              onPressed: _saving ? null : _save,
              icon: const Icon(CupertinoIcons.check_mark, size: 17),
              label: Text(_saving ? '保存中…' : '保存笔记')),
        ]),
      );

  Widget _library(ColorScheme colors) {
    final words = _search.text.trim().toLowerCase().split(RegExp(r'\s+'));
    final entries = _entries.where((entry) {
      final text = '${entry.name}\n${entry.content}\n${entry.tags.join(' ')}'
          .toLowerCase();
      return words.every(text.contains);
    }).toList();
    return Column(children: [
      Row(children: [
        Expanded(
            child: TextField(
                key: const ValueKey('notebook-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    hintText: '搜索标题或提示词',
                    prefixIcon: const Icon(CupertinoIcons.search, size: 18),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空搜索',
                            onPressed: () => setState(_search.clear),
                            icon: const Icon(Icons.close, size: 16))))),
        const SizedBox(width: 8),
        IconButton.filledTonal(
            key: const ValueKey('notebook-add'),
            tooltip: '添加笔记',
            onPressed: _loading ? null : () => _edit(),
            icon: const Icon(CupertinoIcons.add)),
      ]),
      const SizedBox(height: 14),
      Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _entries.isEmpty
                  ? Center(
                      child: TextButton(
                          onPressed: () {
                            setState(() => _loading = true);
                            _load();
                          },
                          child: const Text('重新加载')))
                  : entries.isEmpty
                      ? Center(
                          child: Text(
                              _search.text.trim().isNotEmpty
                                  ? '没有找到匹配的笔记'
                                  : '点击 +，保存常用提示词',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.onSurfaceVariant)))
                      : ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) =>
                              _entryCard(entries[index], colors),
                        )),
    ]);
  }

  Widget _entryCard(PromptTemplate entry, ColorScheme colors) => Material(
        key: ValueKey('notebook-entry-${entry.id}'),
        color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: () => _edit(entry),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 8, 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(entry.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall)),
                      PopupMenuButton<String>(
                          tooltip: '管理笔记',
                          onSelected: (action) {
                            if (action == 'edit') {
                              _edit(entry);
                            } else {
                              _delete(entry);
                            }
                          },
                          itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('编辑')),
                                PopupMenuItem(
                                    value: 'delete', child: Text('删除'))
                              ],
                          icon: const Icon(CupertinoIcons.ellipsis, size: 18)),
                    ]),
                    Text(entry.content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: colors.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          TextButton.icon(
                              key: ValueKey('notebook-copy-${entry.id}'),
                              onPressed: () => _copy(entry),
                              icon: const Icon(CupertinoIcons.doc_on_doc,
                                  size: 15),
                              label: const Text('复制')),
                          FilledButton.tonalIcon(
                              key: ValueKey('notebook-import-${entry.id}'),
                              onPressed: _importingId != null
                                  ? null
                                  : () => _import(entry),
                              icon: const Icon(CupertinoIcons.arrow_down_doc,
                                  size: 15),
                              label: Text(
                                  _importingId == entry.id ? '导入中…' : '导入')),
                        ]),
                  ]),
            )),
      );
}
