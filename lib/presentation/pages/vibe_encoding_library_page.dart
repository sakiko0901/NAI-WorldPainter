import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/utils/vibe_file_codec.dart';
import 'package:nai_huishi/domain/usecases/manage_vibe_encodings.dart';
import 'dart:io';

import 'package:nai_huishi/presentation/widgets/studio_scaffold.dart';
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

  bool _busy = false;

  Future<void> _transfer(VibeEncoding encoding, {required bool share}) async {
    if (_busy || encoding.id == null) return;
    setState(() => _busy = true);
    try {
      final full = await sl<ManageVibeEncodingsUseCase>().getById(encoding.id!);
      if (full == null) throw StateError('编码已不存在');
      final bytes = await VibeFileCodec.encode(full);
      final name =
          '${encoding.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')}.naiv4vibe';
      if (share) {
        final folder =
            await (await getTemporaryDirectory()).createTemp('vibe_share_');
        final file = File('${folder.path}/$name');
        await file.writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        await Share.shareXFiles(
            [XFile(file.path, mimeType: 'application/octet-stream')],
            sharePositionOrigin:
                box == null ? null : box.localToGlobal(Offset.zero) & box.size);
      } else {
        final path = await FilePicker.platform
            .saveFile(fileName: name, bytes: bytes, type: FileType.any);
        if (path != null) {
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
            await File(path).writeAsBytes(bytes, flush: true);
          }
          if (mounted) showFloatingToast(context, '已保存 Vibe 文件');
        }
      }
    } catch (error) {
      if (mounted) showFloatingToast(context, '导出失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    Directory? temporary;
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.any);
      if (picked == null) return;
      final file = picked.files.single;
      if (file.size > 100 * 1024 * 1024) {
        throw const FormatException('文件过大，最多 100 MB');
      }
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final entries = VibeFileCodec.decode(bytes);
      temporary =
          await (await getTemporaryDirectory()).createTemp('vibe_import_');
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final preview = File('${temporary.path}/$i.png');
        await preview.writeAsBytes(entry.thumbnail ??
            Uint8List.fromList(
                img.encodePng(img.Image(width: 32, height: 32))));
        await sl<ManageVibeEncodingsUseCase>().createFromEncoding(
            title: entry.title,
            encodedVibe: entry.encoding,
            sourceImagePath: preview.path,
            encodedModel: entry.model,
            informationExtracted: entry.information);
      }
      await _vm.load();
      if (mounted) {
        showFloatingToast(context, '已导入 ${entries.length} 条编码，无需重新编码');
      }
    } catch (error) {
      if (mounted) showFloatingToast(context, '导入失败：$error');
    } finally {
      if (temporary != null) await temporary.delete(recursive: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StudioScaffold(
      appBar: AppBar(title: const Text('Vibe 编码库'), actions: [
        IconButton(
            onPressed: _busy ? null : _import,
            tooltip: '导入 .naiv4vibe',
            icon: const Icon(Icons.file_upload_outlined))
      ]),
      body: _vm.isLoading
          ? const Center(child: CupertinoActivityIndicator())
          : _vm.error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _vm.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.5,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                )
              : _vm.encodings.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '暂无已保存的氛围编码\n首次使用本地氛围参考图完成编码后，会自动出现在这里。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            height: 1.5,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        mainAxisExtent: 310,
                      ),
                      itemCount: _vm.encodings.length,
                      itemBuilder: (context, index) {
                        final encoding = _vm.encodings[index];
                        return _VibeEncodingCard(
                          encoding: encoding,
                          onRename: () => _rename(encoding),
                          onDelete: () => _delete(encoding),
                          onDownload: _busy
                              ? null
                              : () => _transfer(encoding, share: false),
                          onShare: _busy
                              ? null
                              : () => _transfer(encoding, share: true),
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
  final VoidCallback? onDownload;
  final VoidCallback? onShare;

  const _VibeEncodingCard({
    required this.encoding,
    required this.onRename,
    required this.onDelete,
    this.onDownload,
    this.onShare,
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
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  IconButton(
                      tooltip: '下载 .naiv4vibe',
                      onPressed: onDownload,
                      icon: const Icon(Icons.download_rounded)),
                  IconButton(
                      tooltip: '分享到其它应用',
                      onPressed: onShare,
                      icon: const Icon(Icons.share_outlined)),
                ]),
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
