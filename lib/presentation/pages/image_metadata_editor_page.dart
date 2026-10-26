import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nai_huishi/core/di/injection.dart' show sl;
import 'package:nai_huishi/data/datasources/local/png_metadata_service.dart';
import 'package:nai_huishi/data/datasources/local/png_metadata_edit.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

/// 编辑当前图片的数据，另存 PNG 副本；从不覆盖源文件。
class ImageMetadataEditorPage extends StatefulWidget {
  const ImageMetadataEditorPage({
    super.key,
    this.initialImagePath,
    this.initialStripMetadata = false,
  });

  final String? initialImagePath;
  final bool initialStripMetadata;

  @override
  State<ImageMetadataEditorPage> createState() =>
      _ImageMetadataEditorPageState();
}

class _ImageMetadataEditorPageState extends State<ImageMetadataEditorPage> {
  final _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _extraController = TextEditingController();
  String? _imagePath;
  Uint8List? _sourceBytes;
  PngMetadataDocument? _document;
  bool _loading = false;
  bool _exporting = false;
  late bool _stripMetadata = widget.initialStripMetadata;
  String? _error;

  bool get _busy => _loading || _exporting;

  @override
  void initState() {
    super.initState();
    for (final key in PngMetadataEdit.labels.keys) {
      _controllers[key] = TextEditingController();
    }
    if (widget.initialImagePath != null) {
      _loadImage(widget.initialImagePath!);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _extraController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_busy) return;
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      await _loadImage(picked.path);
    } catch (e) {
      if (mounted) setState(() => _error = '选择图片失败：$e');
    }
  }

  Future<void> _loadImage(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _imagePath = path;
      _sourceBytes = null;
      _document = null;
    });
    try {
      final bytes = await File(path).readAsBytes();
      final document = await compute(PngMetadataService.read, bytes);
      if (!mounted) return;
      final values = PngMetadataEdit.values(document);
      for (final entry in _controllers.entries) {
        entry.value.text = values[entry.key] ?? '';
      }
      _extraController.text = const JsonEncoder.withIndent('  ')
          .convert(PngMetadataEdit.extraComment(document));
      setState(() {
        _sourceBytes = bytes;
        _document = document;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '读取失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export() async {
    final bytes = _sourceBytes;
    final document = _document;
    if (_busy || bytes == null || document == null) return;
    if (!_stripMetadata && !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      // Capture the draft before the first await; switching modes cannot change
      // the bytes or the success message of an in-flight export.
      final strip = _stripMetadata;
      final Uint8List output;
      if (strip) {
        output = await compute(PngMetadataService.strip, bytes);
      } else {
        final text = PngMetadataEdit.build(
          document,
          _controllers.map((key, controller) => MapEntry(key, controller.text)),
          extraJson: _extraController.text,
        );
        output = await compute(_rewriteMetadata, (bytes, text));
      }
      if (!mounted) return;
      final ok = await sl<SaveImageUseCase>().savePngBytesToGallery(output);
      if (!mounted) return;
      if (!ok) throw StateError('保存到相册失败，请检查相册权限后重试');
      showFloatingToast(
        context,
        strip ? '已将清除数据的 PNG 副本保存到相册' : '已将修改数据的 PNG 副本保存到相册',
        icon: CupertinoIcons.checkmark_circle,
      );
    } catch (e) {
      if (mounted) setState(() => _error = '导出失败：$e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('原图数据')),
      bottomNavigationBar: _document == null
          ? null
          : SafeArea(
              minimum: EdgeInsets.fromLTRB(
                  16, 8, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
              child: FilledButton.icon(
                key: const ValueKey('metadata-export'),
                onPressed: _busy ? null : _export,
                icon: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.square_arrow_down),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(_exporting
                      ? '正在保存…'
                      : _stripMetadata
                          ? '清除数据并另存 PNG'
                          : '保存修改后的 PNG'),
                ),
              ),
            ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _buildPreview(),
              const SizedBox(height: 12),
              const Text(
                '支持静态 PNG。修改提示词等文件数据，不会重新生成画面。'
                '保存时另存到相册，原文件保留。',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_error!,
                      key: const ValueKey('metadata-error'),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              if (_document != null) ...[
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  key: const ValueKey('metadata-strip'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('抹去原图数据'),
                  subtitle: const Text('清除提示词、参数、文本及已识别的隐藏元数据'),
                  value: _stripMetadata,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _stripMetadata = value),
                ),
                if (_stripMetadata)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('导出图片不写入替代提示词。需要编辑数据时，关闭上方开关即可。'),
                  )
                else ...[
                  if (_document!.text.isEmpty && _document!.comment.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: Text('未发现可编辑的生成数据，可以填写新数据或直接清除后另存。'),
                    ),
                  for (final entry in PngMetadataEdit.labels.entries)
                    _buildField(entry.key, entry.value),
                  ExpansionTile(
                    key: const ValueKey('metadata-extra'),
                    tilePadding: EdgeInsets.zero,
                    title: const Text('角色与其他参数（JSON）'),
                    subtitle: const Text('保留未修改字段；可编辑或删除角色提示词等数据'),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text('基础正负提示词会与上方同步。清空为 {} 可删除这些额外参数。'),
                      ),
                      TextFormField(
                        key: const ValueKey('metadata-extra-json'),
                        controller: _extraController,
                        enabled: !_busy,
                        minLines: 6,
                        maxLines: 16,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: '额外生成参数 JSON',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                        validator: PngMetadataEdit.validateExtraJson,
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final bytes = _sourceBytes;
    return Column(
      children: [
        if (_loading)
          const SizedBox(
            height: 180,
            child: Center(child: CupertinoActivityIndicator(radius: 14)),
          )
        else if (bytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(bytes,
                height: 220, cacheWidth: 720, fit: BoxFit.contain),
          )
        else
          const Padding(
            padding: EdgeInsets.all(32),
            child: Icon(CupertinoIcons.photo_on_rectangle, size: 56),
          ),
        TextButton.icon(
          key: const ValueKey('metadata-pick'),
          onPressed: _busy ? null : _pickImage,
          icon: const Icon(CupertinoIcons.photo),
          label: Text(_imagePath == null ? '选择 PNG 图片' : '更换图片'),
        ),
      ],
    );
  }

  Widget _buildField(String key, String label) {
    final numeric = PngMetadataEdit.numericKeys.contains(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        key: ValueKey('metadata-$key'),
        controller: _controllers[key],
        enabled: !_busy,
        minLines: 1,
        maxLines: key == 'prompt' || key == 'uc' ? 6 : 1,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.multiline,
        decoration: InputDecoration(
          labelText: label,
          helperText: numeric ? '留空可移除该参数' : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          alignLabelWithHint: true,
        ),
        validator: (value) => PngMetadataEdit.validateValue(key, value ?? ''),
      ),
    );
  }
}

Uint8List _rewriteMetadata((Uint8List, Map<String, String>) request) =>
    PngMetadataService.rewrite(request.$1, request.$2);
