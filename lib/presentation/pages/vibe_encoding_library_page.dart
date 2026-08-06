import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/vibe_encoding.dart';
import 'package:nai_huishi/presentation/viewmodels/vibe_encoding_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

class VibeEncodingLibraryPage extends StatefulWidget {
  const VibeEncodingLibraryPage({super.key});

  @override
  State<VibeEncodingLibraryPage> createState() =>
      _VibeEncodingLibraryPageState();
}

class _VibeEncodingLibraryPageState extends State<VibeEncodingLibraryPage> {
  late final VibeEncodingViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = sl<VibeEncodingViewModel>();
    _vm.addListener(_onChanged);
    _vm.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _rename(VibeEncoding encoding) async {
    final controller = TextEditingController(text: encoding.title);
    final title = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('重命名氛围编码'),
        content: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(controller: controller, autofocus: true),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty || encoding.id == null) return;
    await _vm.updateTitle(encoding, title);
  }

  Future<void> _delete(VibeEncoding encoding) async {
    if (encoding.id == null) return;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除氛围编码？'),
        content: const Text('只会删除本地保存的编码和缩略图，不会删除相册原图。'),
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
    await _vm.delete(encoding.id!);
    if (!mounted) return;
    showFloatingToast(context, '已删除氛围编码', icon: CupertinoIcons.delete);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vibe 编码库')),
      body: _vm.isLoading
          ? const Center(child: CupertinoActivityIndicator())
          : _vm.encodings.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '暂无已保存的氛围编码\n首次使用本地氛围参考图完成编码后，会自动出现在这里。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: _vm.encodings.length,
                  itemBuilder: (context, index) {
                    final encoding = _vm.encodings[index];
                    return _VibeEncodingCard(
                      encoding: encoding,
                      onRename: () => _rename(encoding),
                      onDelete: () => _delete(encoding),
                    );
                  },
                ),
    );
  }
}

class _VibeEncodingCard extends StatelessWidget {
  final VibeEncoding encoding;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _VibeEncodingCard({
    required this.encoding,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Image.file(
              File(encoding.thumbnailPath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                CupertinoIcons.photo,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  encoding.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onRename,
                        child: const Text('重命名'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      onPressed: onDelete,
                      icon: const Icon(CupertinoIcons.delete, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
