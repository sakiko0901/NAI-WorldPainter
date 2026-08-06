import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:image/image.dart';
import 'package:nai_huishi/domain/entities/image_tag_result.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';

/// 从 NAI 生成的 PNG 图片中提取元数据。
///
/// 支持两种存储方式（按优先级）：
/// 1. PNG tEXt / iTXt chunks（NAI 默认方式）：keyword 包括 Title / Description /
///    Software=NovelAI / Source / Comment（嵌套 JSON，含 prompt/uc/seed/...）
/// 2. Stealth alpha LSB（可选）：alpha 通道最低位编码 magic("stealth_pngcomp")
///    + 4字节长度（位）+ gzip 压缩的 JSON
class NaiMetadataParser {
  static const String _stealthMagic = 'stealth_pngcomp';

  /// 解析 PNG 文件，提取 NAI 元数据。
  /// 返回 null 表示该图片不是 NAI 生成的或元数据已丢失。
  static Future<ImageTagResult?> parse(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();

    // 先尝试 PNG text chunks（最常见）
    try {
      final textData = _readPngTextChunks(bytes);
      if (textData.isNotEmpty) {
        final merged = _normalizeTextChunks(textData);
        if (merged.isNotEmpty) {
          return _jsonToResult(merged);
        }
      }
    } catch (_) {}

    // 后备：stealth alpha LSB
    try {
      final img = decodeImage(bytes);
      if (img != null) {
        return _extractStealthFromImage(img);
      }
    } catch (_) {}

    return null;
  }

  /// 读取 PNG 文件的 tEXt / iTXt chunks，返回 keyword → value 映射。
  static Map<String, String> _readPngTextChunks(Uint8List bytes) {
    final result = <String, String>{};
    // PNG 签名
    if (bytes.length < 8 ||
        bytes[0] != 0x89 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x4E ||
        bytes[3] != 0x47 ||
        bytes[4] != 0x0D ||
        bytes[5] != 0x0A ||
        bytes[6] != 0x1A ||
        bytes[7] != 0x0A) {
      return result;
    }

    int pos = 8;
    while (pos + 8 <= bytes.length) {
      final length = (bytes[pos] << 24) |
          (bytes[pos + 1] << 16) |
          (bytes[pos + 2] << 8) |
          bytes[pos + 3];
      final type =
          utf8.decode(bytes.sublist(pos + 4, pos + 8), allowMalformed: true);
      final dataStart = pos + 8;
      final dataEnd = dataStart + length;
      if (dataEnd + 4 > bytes.length) break;

      if (type == 'tEXt') {
        // keyword\0value（Latin-1）
        final data = bytes.sublist(dataStart, dataEnd);
        final nullIdx = data.indexOf(0);
        if (nullIdx > 0 && nullIdx < data.length - 1) {
          final keyword = String.fromCharCodes(data.sublist(0, nullIdx));
          final value = String.fromCharCodes(data.sublist(nullIdx + 1));
          result[keyword] = value;
        }
      } else if (type == 'iTXt') {
        // keyword\0compressionFlag\0compressionMethod\0languageTag\0
        // translatedKeyword\0text(UTF-8, 可能压缩)
        final data = bytes.sublist(dataStart, dataEnd);
        try {
          int p = 0;
          int findNull(int from) {
            for (int i = from; i < data.length; i++) {
              if (data[i] == 0) return i;
            }
            return -1;
          }

          final n1 = findNull(p);
          if (n1 < 0) {
            pos = dataEnd + 4;
            continue;
          }
          final keyword = String.fromCharCodes(data.sublist(p, n1));
          p = n1 + 1;
          if (p + 2 > data.length) {
            pos = dataEnd + 4;
            continue;
          }
          final compressed = data[p] != 0;
          // final method = data[p + 1];
          p += 2;
          final n2 = findNull(p); // language tag
          if (n2 < 0) {
            pos = dataEnd + 4;
            continue;
          }
          p = n2 + 1;
          final n3 = findNull(p); // translated keyword
          if (n3 < 0) {
            pos = dataEnd + 4;
            continue;
          }
          p = n3 + 1;
          final textBytes = data.sublist(p);
          List<int> finalBytes;
          if (compressed) {
            finalBytes = zlib.decode(textBytes);
          } else {
            finalBytes = textBytes;
          }
          final value = utf8.decode(finalBytes, allowMalformed: true);
          result[keyword] = value;
        } catch (_) {}
      } else if (type == 'IEND') {
        break;
      }

      pos = dataEnd + 4; // 跳过 CRC
    }
    return result;
  }

  /// 把 PNG text chunks 合并为统一的元数据 dict（含展开的 Comment）。
  static Map<String, dynamic> _normalizeTextChunks(Map<String, String> chunks) {
    final out = <String, dynamic>{};
    for (final e in chunks.entries) {
      out[e.key] = e.value;
    }
    final comment = chunks['Comment'];
    if (comment != null) {
      try {
        final parsed = jsonDecode(comment);
        if (parsed is Map<String, dynamic>) {
          out['Comment'] = parsed;
        }
      } catch (_) {}
    }
    return out;
  }

  /// 从图片 alpha 通道按列优先提取 LSB 隐写元数据。
  static ImageTagResult? _extractStealthFromImage(Image img) {
    final width = img.width;
    final height = img.height;
    // alpha.T.reshape((-1,)): 先列后行
    final alphaLsb = Uint8List(width * height);
    int idx = 0;
    for (int x = 0; x < width; x++) {
      for (int y = 0; y < height; y++) {
        final pixel = img.getPixel(x, y);
        alphaLsb[idx++] = pixel.a.toInt() & 1;
      }
    }

    final packed = _packBits(alphaLsb);
    if (packed.length < 20) return null;

    final magicBytes = packed.sublist(0, 16);
    final magicStr = utf8.decode(magicBytes, allowMalformed: true);
    if (magicStr != _stealthMagic) return null;

    final lenBytes = packed.sublist(16, 20);
    final jsonBitLen = (lenBytes[0] << 24) |
        (lenBytes[1] << 16) |
        (lenBytes[2] << 8) |
        lenBytes[3];
    final jsonByteLen = jsonBitLen ~/ 8;
    if (jsonByteLen <= 0 || 20 + jsonByteLen > packed.length) return null;

    final gzipped = packed.sublist(20, 20 + jsonByteLen);
    Uint8List? decompressed;
    try {
      decompressed = Uint8List.fromList(gzip.decode(gzipped));
    } catch (_) {
      return null;
    }

    final jsonStr = utf8.decode(decompressed, allowMalformed: true);
    dynamic jsonData;
    try {
      jsonData = jsonDecode(jsonStr);
    } catch (_) {
      return null;
    }
    if (jsonData is! Map<String, dynamic>) return null;
    if (jsonData['Comment'] is String) {
      try {
        jsonData['Comment'] = jsonDecode(jsonData['Comment'] as String);
      } catch (_) {}
    }
    return _jsonToResult(jsonData);
  }

  static Uint8List _packBits(Uint8List bits) {
    final byteCount = bits.length ~/ 8;
    final result = Uint8List(byteCount);
    for (int i = 0; i < byteCount; i++) {
      int byte = 0;
      for (int j = 0; j < 8; j++) {
        byte = (byte << 1) | (bits[i * 8 + j] & 1);
      }
      result[i] = byte;
    }
    return result;
  }

  /// 把 NAI JSON 转成 ImageTagResult。
  ///
  /// 数据可能在多处：
  /// - prompt: Comment.prompt | Description | 顶层 prompt
  /// - uc: Comment.uc | Comment.negative_prompt
  /// - 多角色 v4: Comment.v4_prompt.caption.char_captions
  /// - 多角色 v3: Comment.messages（系统消息 "Characters: [...]"）
  static ImageTagResult _jsonToResult(Map<String, dynamic> json) {
    Map<String, dynamic> comment = {};
    if (json['Comment'] is Map<String, dynamic>) {
      comment = json['Comment'] as Map<String, dynamic>;
    }

    final prompt = (comment['prompt'] as String?) ??
        (json['Description'] as String?) ??
        (json['prompt'] as String?) ??
        '';
    final generalTags = prompt
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .map((t) => TagEntry(tag: t, confidence: 1.0, selected: true))
        .toList();

    final negativePrompt = (comment['uc'] as String?) ??
        (comment['negative_prompt'] as String?) ??
        (json['negative_prompt'] as String?) ??
        (json['uc'] as String?) ??
        '';
    final negativeTags = negativePrompt
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .map((t) => TagEntry(tag: t, confidence: 1.0, selected: true))
        .toList();

    final characters = <CharacterSpec>[];

    // v4 格式
    final v4Prompt = comment['v4_prompt'];
    if (v4Prompt is Map<String, dynamic>) {
      final caption = v4Prompt['caption'];
      if (caption is Map<String, dynamic>) {
        final charCaptions = caption['char_captions'];
        if (charCaptions is List) {
          List<dynamic>? charNegList;
          final v4Neg = comment['v4_negative_prompt'];
          if (v4Neg is Map<String, dynamic>) {
            final negCap = v4Neg['caption'];
            if (negCap is Map<String, dynamic>) {
              charNegList = negCap['char_captions'] as List?;
            }
          }
          for (int i = 0; i < charCaptions.length; i++) {
            final c = charCaptions[i];
            if (c is! Map<String, dynamic>) continue;
            final cp = c['char_caption'] as String? ?? '';
            String? cuc;
            double? cx, cy;
            final centers = c['centers'];
            if (centers is List && centers.isNotEmpty && centers[0] is Map) {
              cx = (centers[0]['x'] as num?)?.toDouble();
              cy = (centers[0]['y'] as num?)?.toDouble();
            }
            if (charNegList != null && i < charNegList.length) {
              final nc = charNegList[i];
              if (nc is Map<String, dynamic>) {
                cuc = nc['char_caption'] as String?;
              }
            }
            characters.add(CharacterSpec(
              prompt: cp,
              uc: cuc,
              centerX: cx,
              centerY: cy,
            ));
          }
        }
      }
    }

    // v3 messages 格式
    if (characters.isEmpty) {
      final messages = (comment['messages'] ?? json['messages']) as List?;
      if (messages != null) {
        for (final msg in messages) {
          if (msg is! Map<String, dynamic>) continue;
          final role = msg['role'] as String?;
          final content = msg['content'] as String?;
          if (content == null) continue;
          if (role == 'system' && content.startsWith('Characters:')) {
            try {
              final charsJson = content.substring('Characters:'.length).trim();
              final charsList = jsonDecode(charsJson) as List<dynamic>;
              for (final c in charsList) {
                if (c is! Map<String, dynamic>) continue;
                characters.add(CharacterSpec(
                  prompt: c['prompt'] as String? ?? '',
                  uc: c['uc'] as String?,
                  centerX: c['center'] != null
                      ? (c['center']['x'] as num?)?.toDouble()
                      : null,
                  centerY: c['center'] != null
                      ? (c['center']['y'] as num?)?.toDouble()
                      : null,
                ));
              }
            } catch (_) {}
          }
        }
      }
    }

    final rawVibeEncodings =
        comment['reference_image_multiple'] ?? json['reference_image_multiple'];
    final vibeEncodings = rawVibeEncodings is List
        ? rawVibeEncodings
            .whereType<String>()
            .where((encoding) => encoding.trim().isNotEmpty)
            .toList()
        : const <String>[];

    final metadata = <String, dynamic>{};
    for (final key in [
      'seed',
      'steps',
      'sampler',
      'scale',
      'cfg_rescale',
      'noise_schedule',
      'width',
      'height',
    ]) {
      final v = comment[key] ?? json[key];
      if (v != null) metadata[key] = v;
    }
    final src = json['Source'] as String?;
    if (src != null) metadata['Source'] = src;
    final sw = json['Software'] as String?;
    if (sw != null) metadata['Software'] = sw;

    return ImageTagResult(
      source: TagSource.naiMetadata,
      general: generalTags,
      negativePrompt: negativePrompt.isNotEmpty ? negativePrompt : null,
      negativeEntries: negativeTags,
      characters: characters.isNotEmpty ? characters : null,
      vibeEncodings: vibeEncodings,
      metadata: metadata.isNotEmpty ? metadata : null,
    );
  }
}
