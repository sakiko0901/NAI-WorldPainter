import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:nai_huishi/core/di/injection.dart' show sl;
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

/// 修改图片标签：查看/编辑 PNG 图片中的 NAI 元数据并导出。
///
/// 参考 Semi-Auto-NovelAI-to-Pixiv 的 pnginfo_modify / naimeta 实现：
/// - PNG tEXt/iTXt chunks（Title/Description/Software/Source/Comment）
/// - stealth alpha LSB 隐写层（magic "stealth_pngcomp" + gzip JSON），
///   NAI 官方与多数工具从这里读取元数据，导出时必须同步重写
/// - Comment JSON 逐字段编辑（prompt / uc / steps / sampler / scale / seed 等）
/// - 支持一键清除全部元数据（写入通用伪装信息）
///
/// 所有像素级读写都在后台 isolate 完成，避免大图 ANR。
class ImageMetadataEditorPage extends StatefulWidget {
  const ImageMetadataEditorPage({super.key});

  @override
  State<ImageMetadataEditorPage> createState() =>
      _ImageMetadataEditorPageState();
}

/// Comment JSON 中开放编辑的字段（顺序即展示顺序）。
const _commentEditableKeys = <String, String>{
  'prompt': '正向提示词',
  'uc': '负向提示词',
  'steps': '迭代步数',
  'sampler': '采样器',
  'scale': '引导比例',
  'cfg_rescale': '引导重缩放',
  'noise_schedule': '噪声调度',
  'seed': '随机种子',
  'width': '图像宽度',
  'height': '图像高度',
};

const _topLevelKeys = <String, String>{
  'Title': '标题',
  'Software': '生成软件',
  'Source': '来源',
};

class _ImageMetadataEditorPageState extends State<ImageMetadataEditorPage> {
  String? _imagePath;

  /// 原始 Comment JSON（含未开放编辑的字段），导出时合并修改。
  Map<String, dynamic> _originalComment = {};

  final Map<String, TextEditingController> _topControllers = {};
  final Map<String, TextEditingController> _commentControllers = {};
  final TextEditingController _descriptionController = TextEditingController();

  bool _loading = false;
  bool _exporting = false;
  bool _stripMetadata = false;
  String? _error;

  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _disposeControllers();
    _descriptionController.dispose();
    super.dispose();
  }

  void _disposeControllers() {
    for (final c in _topControllers.values) {
      c.dispose();
    }
    _topControllers.clear();
    for (final c in _commentControllers.values) {
      c.dispose();
    }
    _commentControllers.clear();
  }

  Future<void> _pickImage() async {
    if (_loading || _exporting) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    await _loadImage(picked.path);
  }

  Future<void> _loadImage(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _imagePath = path;
      _stripMetadata = false;
    });
    try {
      final bytes = await File(path).readAsBytes();
      final data = await Isolate.run(() => _loadAllMetadata(bytes));
      _disposeControllers();
      for (final e in _topLevelKeys.entries) {
        _topControllers[e.key] =
            TextEditingController(text: data.textChunks[e.key] ?? '');
      }
      _descriptionController.text = data.textChunks['Description'] ?? '';
      for (final e in _commentEditableKeys.entries) {
        final v = data.comment[e.key];
        _commentControllers[e.key] = TextEditingController(
          text: v == null ? '' : (v is String ? v : jsonEncode(v)),
        );
      }
      if (mounted) {
        setState(() {
          _originalComment = data.comment;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '读取失败：$e';
          _loading = false;
        });
      }
    }
  }

  /// 读取 tEXt/iTXt + stealth LSB 隐写层，合并出 Comment JSON。
  static _LoadedMeta _loadAllMetadata(Uint8List bytes) {
    final textChunks = _readTextChunks(bytes);
    Map<String, dynamic> comment = {};
    if (textChunks['Comment'] != null) {
      try {
        final parsed = jsonDecode(textChunks['Comment']!);
        if (parsed is Map<String, dynamic>) comment = parsed;
      } catch (_) {}
    }
    // stealth 隐写层优先（NAI 官方实际读取来源），缺失字段用它补全
    try {
      final stealth = _extractStealth(bytes);
      if (stealth != null) {
        final stealthComment = stealth['Comment'];
        if (stealthComment is Map<String, dynamic>) {
          for (final e in stealthComment.entries) {
            comment.putIfAbsent(e.key, () => e.value);
          }
        }
        for (final key in ['Description', 'Software', 'Source', 'Title']) {
          if (textChunks[key] == null && stealth[key] is String) {
            textChunks[key] = stealth[key] as String;
          }
        }
      }
    } catch (_) {}
    return _LoadedMeta(textChunks: textChunks, comment: comment);
  }

  // ── PNG text chunks 读取 ──

  static Map<String, String> _readTextChunks(Uint8List bytes) {
    final result = <String, String>{};
    if (bytes.length < 8 || !_isPng(bytes)) return result;
    int pos = 8;
    while (pos + 8 <= bytes.length) {
      final length = _be32(bytes, pos);
      final type =
          utf8.decode(bytes.sublist(pos + 4, pos + 8), allowMalformed: true);
      final dataStart = pos + 8;
      final dataEnd = dataStart + length;
      if (dataEnd + 4 > bytes.length) break;
      if (type == 'tEXt') {
        final data = bytes.sublist(dataStart, dataEnd);
        final nullIdx = data.indexOf(0);
        if (nullIdx > 0 && nullIdx < data.length - 1) {
          final keyword = String.fromCharCodes(data.sublist(0, nullIdx));
          final value = String.fromCharCodes(data.sublist(nullIdx + 1));
          result[keyword] = value;
        }
      } else if (type == 'iTXt') {
        try {
          final value = _readITxtValue(bytes.sublist(dataStart, dataEnd));
          if (value != null) result[value.$1] = value.$2;
        } catch (_) {}
      } else if (type == 'IEND') {
        break;
      }
      pos = dataEnd + 4;
    }
    return result;
  }

  static (String, String)? _readITxtValue(Uint8List data) {
    int findNull(int from) {
      for (int i = from; i < data.length; i++) {
        if (data[i] == 0) return i;
      }
      return -1;
    }

    final n1 = findNull(0);
    if (n1 <= 0) return null;
    final keyword = String.fromCharCodes(data.sublist(0, n1));
    if (n1 + 2 >= data.length) return null;
    final compressed = data[n1 + 1] != 0;
    int p = n1 + 3;
    final n2 = findNull(p); // language tag
    if (n2 < 0) return null;
    p = n2 + 1;
    final n3 = findNull(p); // translated keyword
    if (n3 < 0) return null;
    p = n3 + 1;
    final textBytes = data.sublist(p);
    final value = compressed
        ? utf8.decode(zlib.decode(textBytes), allowMalformed: true)
        : utf8.decode(textBytes, allowMalformed: true);
    return (keyword, value);
  }

  static bool _isPng(Uint8List b) =>
      b.length > 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47 &&
      b[4] == 0x0D &&
      b[5] == 0x0A &&
      b[6] == 0x1A &&
      b[7] == 0x0A;

  // ── stealth LSB 提取（列优先、字节 MSB 先行）──

  static const String _stealthMagic = 'stealth_pngcomp';

  static Map<String, dynamic>? _extractStealth(Uint8List bytes) {
    final image = img.decodePng(bytes);
    if (image == null) return null;
    if (image.numChannels < 4) {
      // 不透明 PNG（无 alpha 通道）无法携带隐写层
      return null;
    }
    final magic = _readStealthBytes(image, _stealthMagic.length);
    if (magic == null) return null;
    final magicStr = utf8.decode(magic, allowMalformed: true);
    if (magicStr != _stealthMagic) return null;
    final lenBytes = _readStealthBytes(image, 4);
    if (lenBytes == null) return null;
    final bitLen = _be32(lenBytes, 0);
    final byteLen = bitLen ~/ 8;
    if (byteLen <= 0) return null;
    final gz = _readStealthBytes(image, byteLen);
    if (gz == null) return null;
    final jsonStr =
        utf8.decode(gzip.decode(gz), allowMalformed: true);
    final parsed = jsonDecode(jsonStr);
    if (parsed is! Map<String, dynamic>) return null;
    if (parsed['Comment'] is String) {
      try {
        parsed['Comment'] = jsonDecode(parsed['Comment'] as String);
      } catch (_) {}
    }
    return parsed;
  }

  /// 从图片 alpha 通道按列优先读取 [count] 字节。
  static Uint8List? _readStealthBytes(img.Image image, int count) {
    final width = image.width;
    final height = image.height;
    final capacity = width * height ~/ 8;
    if (count > capacity) return null;
    final out = Uint8List(count);
    int bitIdx = 0;
    for (int x = 0; x < width && bitIdx < count * 8; x++) {
      for (int y = 0; y < height && bitIdx < count * 8; y++) {
        final bit = image.getPixel(x, y).a.toInt() & 1;
        out[bitIdx >> 3] = (out[bitIdx >> 3] << 1) | bit;
        bitIdx++;
      }
    }
    return out;
  }

  // ── 导出 ──

  Map<String, String> _collectUpdates() {
    final updates = <String, String>{
      'Description': _descriptionController.text,
    };
    for (final e in _topControllers.entries) {
      updates[e.key] = e.value.text;
    }
    // 合并 Comment：保留未开放编辑的字段，覆盖已编辑字段
    final merged = <String, dynamic>{..._originalComment};
    for (final e in _commentControllers.entries) {
      final text = e.value.text;
      final original = _originalComment[e.key];
      if (text.isEmpty && original == null) continue;
      if (original is num) {
        final parsed = num.tryParse(text);
        merged[e.key] = parsed ?? original;
      } else if (original is bool) {
        merged[e.key] = original;
      } else {
        merged[e.key] = text;
      }
    }
    updates['Comment'] = jsonEncode(merged);
    return updates;
  }

  Future<void> _export() async {
    if (_imagePath == null || _exporting || _loading) return;
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final bytes = await File(_imagePath!).readAsBytes();
      final Uint8List output;
      if (_stripMetadata) {
        // 清除元数据：写入通用伪装信息（参考 pnginfo_modify 的 data_cloaking）
        output = await Isolate.run(() => _stripAndWrite(bytes));
      } else {
        final updates = _collectUpdates();
        output = await Isolate.run(() => _rewriteAll(bytes, updates));
      }
      final ok = await sl<SaveImageUseCase>().saveBytesToGallery(output);
      if (!mounted) return;
      if (!ok) throw Exception('保存到相册失败');
      showFloatingToast(context, '已导出到相册',
          icon: CupertinoIcons.checkmark_circle);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '导出失败：$e');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 一键清除：重置 text chunks 为通用伪装样例，隐写层写同样内容。
  static Uint8List _stripAndWrite(Uint8List bytes) {
    final image = img.decodePng(bytes);
    final w = image?.width ?? 832;
    final h = image?.height ?? 1216;
    final cloaking = <String, String>{
      'Title': 'AI generated image',
      'Description': '1girl, cute',
      'Software': 'NovelAI',
      'Source': 'Stable Diffusion XL C1E1DE52',
      'Comment': jsonEncode({
        'prompt': '1girl, cute',
        'steps': 28,
        'height': h,
        'width': w,
        'scale': 5.0,
        'seed': 1234567890,
        'sampler': 'k_euler',
        'uc': 'lowres, bad quality',
      }),
    };
    return _rewriteAll(bytes, cloaking);
  }

  /// 重写元数据：解码 PNG → RGBA → 注入 stealth 隐写层 → 重新编码。
  /// image 包编码出的 PNG 不含任何 tEXt/iTXt（文本块即被清除），
  /// 隐写层写入新数据，与官方读取工具（novelai-image-metadata 等）兼容。
  static Uint8List _rewriteAll(
    Uint8List bytes,
    Map<String, String> updates,
  ) {
    final image = img.decodePng(bytes);
    if (image == null) {
      throw Exception('无法解码 PNG 图片');
    }
    final rgba = image.convert(numChannels: 4);
    _injectStealth(rgba, updates);
    final encoded = img.encodePng(rgba);
    return Uint8List.fromList(encoded);
  }

  /// stealth LSB 注入：magic(15字节) + 32位 bit 长度 + gzip JSON，
  /// 按列优先、MSB-first 写入 alpha 最低位（与官方 LSBInjector 一致）。
  static void _injectStealth(img.Image rgba, Map<String, String> data) {
    final jsonStr = jsonEncode(data);
    final compressed = Uint8List.fromList(gzip.encode(utf8.encode(jsonStr)));
    final payload = BytesBuilder()
      ..add(utf8.encode(_stealthMagic))
      ..add(_be32Bytes(compressed.length * 8))
      ..add(compressed);
    final bytes = payload.toBytes();
    final width = rgba.width;
    final height = rgba.height;
    if (bytes.length * 8 > width * height) {
      throw Exception('图片太小，无法写入隐写元数据');
    }
    int bitIdx = 0;
    for (int x = 0; x < width && bitIdx < bytes.length * 8; x++) {
      for (int y = 0; y < height && bitIdx < bytes.length * 8; y++) {
        final bit = (bytes[bitIdx >> 3] >> (7 - (bitIdx & 7))) & 1;
        final p = rgba.getPixel(x, y);
        final a = (p.a.toInt() & 0xFE) | bit;
        rgba.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), a);
        bitIdx++;
      }
    }
  }

  static int _be32(Uint8List b, int offset) =>
      (b[offset] << 24) |
      (b[offset + 1] << 16) |
      (b[offset + 2] << 8) |
      b[offset + 3];

  static Uint8List _be32Bytes(int value) => Uint8List.fromList([
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ]);

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('修改图片标签')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildPreview(isDark),
            const SizedBox(height: 18),
            if (_error != null) ...[
              _buildError(),
              const SizedBox(height: 14),
            ],
            if (_commentControllers.isNotEmpty) ...[
              _buildStripToggle(isDark),
              if (!_stripMetadata) ...[
                const SizedBox(height: 18),
                _buildEditor(isDark),
              ],
              const SizedBox(height: 22),
              _buildExportButton(),
            ] else if (!_loading)
              _buildHint(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(bool isDark) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final imagePath = _imagePath;
    Widget child;
    if (imagePath == null || !File(imagePath).existsSync()) {
      child = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.photo_on_rectangle,
              size: 48, color: isDark ? Colors.white54 : Colors.black38),
          const SizedBox(height: 12),
          Text('点击选择 PNG 图片',
              style:
                  TextStyle(color: isDark ? Colors.white54 : Colors.black38)),
        ],
      );
    } else {
      child = Image.file(File(imagePath), fit: BoxFit.contain);
    }
    final preview = GestureDetector(
      onTap: _loading ? null : _pickImage,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          color: cardColor,
          child: _loading
              ? const Center(child: CupertinoActivityIndicator(radius: 14))
              : child,
        ),
      ),
    );
    if (imagePath == null || !File(imagePath).existsSync()) {
      return AspectRatio(aspectRatio: 1, child: preview);
    }
    return SizedBox(height: 260, child: preview);
  }

  Widget _buildHint(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '读取并编辑 NovelAI 图片内的提示词与参数（正向/负向提示词、采样器、种子等），'
        '同时重写 PNG 文本块与 stealth 隐写层，保证其他工具也能读到新元数据。'
        '支持一键清除元数据。仅支持 PNG 图片。',
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: isDark ? Colors.white60 : Colors.black54,
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(_error ?? '',
          style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
    );
  }

  Widget _buildStripToggle(bool isDark) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('清除元数据',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        subtitle: Text(
          '写入通用伪装信息，抹去原始提示词与参数',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
        value: _stripMetadata,
        onChanged: (v) => setState(() => _stripMetadata = v),
      ),
    );
  }

  Widget _buildEditor(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          label: '正向提示词（Description）',
          controller: _descriptionController,
          maxLines: 4,
        ),
        for (final e in _topLevelKeys.entries)
          _field(label: e.value, controller: _topControllers[e.key]!),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '生成参数',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        for (final e in _commentEditableKeys.entries)
          _field(
            label: e.value,
            controller: _commentControllers[e.key]!,
            maxLines:
                e.key == 'prompt' || e.key == 'uc' ? 4 : 1,
          ),
      ],
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(label,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          TextField(
            controller: controller,
            maxLines: maxLines,
            minLines: 1,
            style: const TextStyle(fontSize: 13, height: 1.35),
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        onPressed: _exporting ? null : _export,
        icon: _exporting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(CupertinoIcons.share, size: 20),
        label: Text(
          _exporting ? '导出中...' : '导出修改后的图片',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _LoadedMeta {
  final Map<String, String> textChunks;
  final Map<String, dynamic> comment;

  const _LoadedMeta({required this.textChunks, required this.comment});
}
