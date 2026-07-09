import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// LSB 隐写工具：用 alpha 通道最低位写入：
///   magic("stealth_pngcomp") + 32bit length(bits, big-endian) + gzip(JSON)
/// 同时移除 PNG tEXt/iTXt chunks (Title/Comment/Software/Source 等)。
///
/// 移植自 SANP utils/naimeta.py 的 inject_data。
class PixivImageCloaker {
  /// 处理图片，输出到临时目录的新文件。返回新文件路径。
  /// 大图会放进 compute() Isolate 处理。
  Future<String> cloak(
    String inputPath, {
    String junkText = '',
  }) async {
    final bytes = await File(inputPath).readAsBytes();

    final Uint8List outBytes = await compute<_CloakInput, Uint8List>(
      _cloakIsolate,
      _CloakInput(
        pngBytes: bytes,
        junkText: junkText,
      ),
    );

    final dir = await getTemporaryDirectory();
    final outDir = Directory(p.join(dir.path, 'pixiv_cloak'));
    if (!await outDir.exists()) await outDir.create(recursive: true);
    final outPath = p.join(
      outDir.path,
      '${const Uuid().v4()}_${p.basename(inputPath)}',
    );
    final outFile = File(outPath);
    await outFile.writeAsBytes(outBytes);
    return outPath;
  }
}

class _CloakInput {
  final Uint8List pngBytes;
  final String junkText;
  _CloakInput({required this.pngBytes, required this.junkText});
}

Uint8List _cloakIsolate(_CloakInput input) {
  // 1. 解码
  final decoded = img.decodeImage(input.pngBytes);
  if (decoded == null) {
    throw StateError('PNG 解码失败');
  }
  // 2. 确保 RGBA
  final rgba = decoded.numChannels == 4
      ? decoded
      : decoded.convert(numChannels: 4);

  // 3. 准备隐写 payload：
  //    serialize_metadata({}, [...]) → gzip(json.dumps({}))，
  //    在 SANP 中元数据被全清后 data 为空 dict，再 gzip 压。
  //    我们这里直接写 {"None": junkText} 或 {}（看 junkText 是否非空）。
  final jsonStr = input.junkText.isEmpty
      ? '{}'
      : jsonEncode({'None': input.junkText});
  final gz = gzip.encode(utf8.encode(jsonStr));
  final payload = Uint8List.fromList(gz);

  // 4. LSB 写入到 alpha 通道
  const magic = 'stealth_pngcomp';
  final magicBytes = utf8.encode(magic);
  final lenBits = payload.length * 8;
  final lenBytes = Uint8List(4);
  ByteData.view(lenBytes.buffer).setUint32(0, lenBits, Endian.big);

  // 总比特：magic + 32bit + payload bits
  final totalBits = (magicBytes.length + 4 + payload.length) * 8;
  final totalPixels = rgba.width * rgba.height;
  if (totalBits > totalPixels) {
    throw StateError('图片像素不足以承载隐写数据');
  }

  // 与 SANP 一致的遍历顺序：先按 row 再按 col（即逐列向下）
  // injector 内部：row 自增到 rows 后 col++、row 归零
  int row = 0, col = 0;
  void putBit(int bit) {
    final pixel = rgba.getPixel(col, row);
    // alpha = pixel.a
    final a = pixel.a.toInt();
    final newA = (a & 0xFE) | (bit & 1);
    pixel.a = newA;
    rgba.setPixel(col, row, pixel);
    row++;
    if (row == rgba.height) {
      row = 0;
      col++;
    }
  }

  void putByte(int byte) {
    for (int i = 0; i < 8; i++) {
      final bit = (byte >> (7 - i)) & 1;
      putBit(bit);
    }
  }

  for (final b in magicBytes) {
    putByte(b);
  }
  for (final b in lenBytes) {
    putByte(b);
  }
  for (final b in payload) {
    putByte(b);
  }

  // 5. 重编码 PNG（不会保留任何 tEXt/iTXt chunk）
  final outBytes = img.encodePng(rgba, level: 6);
  return Uint8List.fromList(outBytes);
}
