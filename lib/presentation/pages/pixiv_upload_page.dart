import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/presentation/pages/pixiv_settings_page.dart';
import 'package:nai_huishi/presentation/viewmodels/pixiv_upload_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

class PixivUploadPage extends StatefulWidget {
  const PixivUploadPage({super.key});

  @override
  State<PixivUploadPage> createState() => _PixivUploadPageState();
}

class _PixivUploadPageState extends State<PixivUploadPage> {
  late final PixivUploadViewModel _vm;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _newTagCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _vm = sl<PixivUploadViewModel>();
    _vm.addListener(_onChange);
    _vm.init();
    // 监听文本变化以更新按钮可用态
    _vm.titleCtrl.addListener(_onChange);
  }

  @override
  void dispose() {
    _vm.removeListener(_onChange);
    _vm.titleCtrl.removeListener(_onChange);
    _newTagCtrl.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _pickImages() async {
    if (_vm.imagePaths.length >= 4) {
      showFloatingToast(context, '最多 4 张图片', icon: CupertinoIcons.exclamationmark_circle);
      return;
    }
    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty) return;
    await _vm.addImages(picked.map((e) => e.path).toList());
  }

  Future<void> _doUpload() async {
    final id = await _vm.uploadNow();
    if (!mounted) return;
    if (id != null) {
      showFloatingToast(context, '上传成功 PID: $id', icon: CupertinoIcons.checkmark_circle);
    } else if (_vm.error != null) {
      showFloatingToast(context, _vm.error!, icon: CupertinoIcons.exclamationmark_circle);
    }
  }

  void _doEnqueue() {
    _vm.enqueue();
    showFloatingToast(context, '已加入队列', icon: CupertinoIcons.tray_arrow_down);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = _vm.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('上传到 Pixiv'),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.gear_alt),
            onPressed: () => Navigator.of(context).push(
              CupertinoPageRoute(builder: (_) => const PixivSettingsPage()),
            ),
          ),
        ],
      ),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
              children: [
                if (!settings.hasCredentials)
                  _WarningCard(
                    isDark: isDark,
                    text: '请先在 Pixiv 设置中配置 Cookie 与 CSRF Token',
                    actionLabel: '前往设置',
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(builder: (_) => const PixivSettingsPage()),
                    ),
                  ),
                if (!settings.hasCredentials) const SizedBox(height: 14),
                _Section(
                  isDark: isDark,
                  title: '图片',
                  trailing: _vm.imagePaths.isEmpty
                      ? null
                      : Text('${_vm.imagePaths.length}/4',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 12)),
                  child: _ImagesRow(
                    paths: _vm.imagePaths,
                    onAdd: _pickImages,
                    onRemove: _vm.removeImage,
                  ),
                ),
                if (_vm.hasNaiMetadata) ...[
                  const SizedBox(height: 10),
                  _NaiBadge(
                    isDark: isDark,
                    onAutoFill: () {
                      _vm.autoFillTitle();
                      _vm.autoFillCaption();
                      _vm.fetchSuggestedTags();
                      showFloatingToast(context, '已自动填充', icon: CupertinoIcons.sparkles);
                    },
                  ),
                ],
                const SizedBox(height: 18),
                _Section(
                  isDark: isDark,
                  title: '标题',
                  trailing: _IconBtn(
                    icon: CupertinoIcons.wand_stars,
                    label: '自动',
                    onTap: _vm.detectedPrompt == null ? null : _vm.autoFillTitle,
                  ),
                  child: TextField(
                    controller: _vm.titleCtrl,
                    decoration: const InputDecoration(
                      hintText: '请输入作品标题',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _Section(
                  isDark: isDark,
                  title: '描述',
                  trailing: _IconBtn(
                    icon: CupertinoIcons.text_alignleft,
                    label: '自动',
                    onTap: _vm.autoFillCaption,
                  ),
                  child: TextField(
                    controller: _vm.captionCtrl,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText: '作品描述',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _Section(
                  isDark: isDark,
                  title: '标签 (${_vm.tags.length}/10)',
                  trailing: _IconBtn(
                    icon: CupertinoIcons.tag_solid,
                    label: 'Pixiv 推荐',
                    onTap: _vm.imagePaths.isEmpty ? null : _vm.fetchSuggestedTags,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in _vm.tags)
                            _TagChip(
                              label: t,
                              onDeleted: () => _vm.removeTag(t),
                              isDark: isDark,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newTagCtrl,
                              decoration: const InputDecoration(
                                hintText: '输入新标签后回车',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (v) {
                                if (_vm.tags.length >= 10) {
                                  showFloatingToast(context, '标签最多 10 个',
                                      icon: CupertinoIcons.exclamationmark_circle);
                                  return;
                                }
                                _vm.addTag(v);
                                _newTagCtrl.clear();
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _Section(
                  isDark: isDark,
                  title: '选项',
                  child: Column(
                    children: [
                      _SwitchRow(
                        title: 'R18',
                        subtitle: '成人内容',
                        value: _vm.isR18,
                        onChanged: _vm.setR18,
                      ),
                      _SwitchRow(
                        title: '允许他人编辑标签',
                        subtitle: '其他用户可补充 Pixiv 标签',
                        value: _vm.allowTagEdit,
                        onChanged: _vm.setAllowTagEdit,
                      ),
                      _SwitchRow(
                        title: '上传前擦除元数据 (LSB 隐写)',
                        subtitle: '彻底去除 NovelAI 生成信息（不可逆）',
                        value: _vm.stripMetadata,
                        onChanged: _vm.setStripMetadata,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_vm.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_vm.error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _vm.imagePaths.isEmpty || _vm.titleCtrl.text.trim().isEmpty
                            ? null
                            : _doEnqueue,
                        icon: const Icon(CupertinoIcons.tray_arrow_down),
                        label: const Text('加入队列'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _vm.canUpload && !_vm.isUploading ? _doUpload : null,
                        icon: _vm.isUploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(CupertinoIcons.cloud_upload),
                        label: Text(_vm.isUploading ? '上传中...' : '立即上传'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  final bool isDark;
  final String title;
  final Widget child;
  final Widget? trailing;
  const _Section({
    required this.isDark,
    required this.title,
    required this.child,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8, right: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C21) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: isDark ? 0.06 : 0.08),
            ),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _WarningCard extends StatelessWidget {
  final bool isDark;
  final String text;
  final String actionLabel;
  final VoidCallback onTap;
  const _WarningCard({
    required this.isDark,
    required this.text,
    required this.actionLabel,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB020).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB020).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.exclamationmark_triangle, color: Color(0xFFFFB020)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          TextButton(onPressed: onTap, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _NaiBadge extends StatelessWidget {
  final bool isDark;
  final VoidCallback onAutoFill;
  const _NaiBadge({required this.isDark, required this.onAutoFill});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.sparkles, color: primary, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('已检测到 NovelAI 元数据',
                style: TextStyle(fontSize: 13)),
          ),
          TextButton(onPressed: onAutoFill, child: const Text('一键自动填充')),
        ],
      ),
    );
  }
}

class _ImagesRow extends StatelessWidget {
  final List<String> paths;
  final VoidCallback onAdd;
  final void Function(int) onRemove;
  const _ImagesRow({
    required this.paths,
    required this.onAdd,
    required this.onRemove,
  });
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (int i = 0; i < paths.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(File(paths[i]),
                        width: 96, height: 96, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () => onRemove(i),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(CupertinoIcons.xmark,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (paths.length < 4)
            GestureDetector(
              onTap: onAdd,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    style: BorderStyle.solid,
                  ),
                ),
                child: const Center(
                  child: Icon(CupertinoIcons.add, size: 28),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _IconBtn({required this.icon, required this.label, this.onTap});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final disabled = onTap == null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: disabled ? Colors.grey : primary),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: disabled ? Colors.grey : primary,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final VoidCallback onDeleted;
  final bool isDark;
  const _TagChip({
    required this.label,
    required this.onDeleted,
    required this.isDark,
  });
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDeleted,
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(CupertinoIcons.xmark, size: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
