import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A normalized view of metadata stored in a PNG's text chunks and Comment JSON.
class PngMetadataDocument {
  final Map<String, String> text;
  final Map<String, dynamic> comment;

  PngMetadataDocument({
    required Map<String, String> text,
    required Map<String, dynamic> comment,
  })  : text = Map.unmodifiable(text),
        comment = Map.unmodifiable(comment);
}

/// Reads and rewrites PNG metadata while preserving ordinary PNG image data.
///
/// Metadata rewriting uses standard uncompressed iTXt chunks. Known NovelAI
/// and WebUI stealth payloads are read from alpha/RGB LSBs and removed before
/// the image data is rewritten. APNG is deliberately unsupported because a
/// frame-by-frame pixel rewrite would otherwise silently flatten animation.
class PngMetadataService {
  PngMetadataService._();

  static const List<int> _signature = [
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
  ];
  static const int _maxStealthPixels = 16 * 1024 * 1024;
  static const int _maxStealthPayloadBytes = 16 * 1024 * 1024;
  static const Set<String> _metadataChunkTypes = {
    'tEXt',
    'zTXt',
    'iTXt',
    'eXIf',
    'tIME',
  };
  static const Set<String> _formatDependentChunks = {
    'bKGD',
    'hIST',
    'sBIT',
    'sPLT',
  };
  static const Set<String> _renderingAncillaryChunks = {
    'bKGD',
    'cHRM',
    'cICP',
    'cLLi',
    'gAMA',
    'hIST',
    'iCCP',
    'mDCv',
    'pHYs',
    'sBIT',
    'sPLT',
    'sRGB',
    'tRNS',
  };
  static const List<_StealthSignature> _stealthSignatures = [
    _StealthSignature('stealth_pngcomp', _StealthMode.alpha, true),
    _StealthSignature('stealth_pnginfo', _StealthMode.alpha, false),
    _StealthSignature('stealth_rgbcomp', _StealthMode.rgb, true),
    _StealthSignature('stealth_rgbinfo', _StealthMode.rgb, false),
  ];
  static final List<int> _crcTable = List<int>.generate(256, (index) {
    var value = index;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 1) == 1 ? 0xedb88320 ^ (value >> 1) : value >> 1;
    }
    return value & 0xffffffff;
  }, growable: false);

  /// Read tEXt, zTXt, iTXt and known alpha/RGB stealth metadata.
  ///
  /// Text chunks take precedence. Missing text fields and missing Comment
  /// members are filled from a recognized stealth payload.
  /// The image is decoded to inspect stealth bits. Images above 16 Mi pixels
  /// are rejected to bound memory use on mobile devices.
  static PngMetadataDocument read(Uint8List bytes) {
    final png = _PngFile.parse(bytes);
    final text = _readTextChunks(png);
    final comment = _decodeComment(text['Comment']);

    final decoded = _decodeStealth(bytes, png);
    for (final carrier in decoded.carriers) {
      final payload = carrier.metadata;
      if (payload == null) continue;
      _mergeStealthText(text, payload);
      _mergeStealthComment(comment, payload['Comment']);
    }

    return PngMetadataDocument(text: text, comment: comment);
  }

  /// Replace all known old metadata with [text], where Comment is JSON text.
  /// New fields are stored as standard UTF-8 iTXt chunks.
  static Uint8List rewrite(Uint8List bytes, Map<String, String> text) {
    _validateText(text);
    return _rewrite(bytes, text);
  }

  /// Remove PNG text/EXIF/time chunks and recognized stealth payloads.
  static Uint8List strip(Uint8List bytes) => _rewrite(bytes, const {});

  static Uint8List _rewrite(Uint8List bytes, Map<String, String> text) {
    final png = _PngFile.parse(bytes);
    final stealth = _decodeStealth(bytes, png);
    final carriers = stealth.carriers;
    Uint8List? encodedPixels;
    _PngFile? encodedPng;
    if (carriers.isNotEmpty) {
      if (png.bitDepth != 8) {
        throw const FormatException(
          '图片包含隐写元数据，但当前仅支持安全重写 8 位 PNG',
        );
      }
      final image = stealth.image!;
      for (final carrier in carriers) {
        _clearCarrier(image, carrier);
      }
      encodedPixels = Uint8List.fromList(img.encodePng(image));
      encodedPng = _PngFile.parse(encodedPixels);
      if (encodedPng.width != png.width || encodedPng.height != png.height) {
        throw const FormatException('PNG 重编码改变了图片尺寸');
      }
    }

    final newTextChunks = text.entries
        .map((entry) => _buildITxtChunk(entry.key, entry.value))
        .toList(growable: false);
    final output = BytesBuilder(copy: false)..add(_signature);

    if (encodedPng == null) {
      var wroteText = false;
      for (final chunk in png.chunks) {
        if (!_shouldKeepChunk(chunk.type)) continue;
        if (chunk.type == 'IDAT' && !wroteText) {
          for (final newTextChunk in newTextChunks) {
            output.add(newTextChunk);
          }
          wroteText = true;
        }
        _appendChunk(output, bytes, chunk);
      }
      return output.takeBytes();
    }

    final generatedByType = <String, List<_PngChunk>>{};
    for (final chunk in encodedPng.chunks) {
      generatedByType.putIfAbsent(chunk.type, () => []).add(chunk);
    }
    final pixels = encodedPixels!;
    final generatedFile = encodedPng;
    final generatedIhdr = generatedByType['IHDR']!.single;
    final generatedIdats = generatedByType['IDAT']!;
    final originalHeader = png.ihdrData(bytes);
    final generatedHeader = generatedFile.ihdrData(pixels);
    final sampleFormatChanged = originalHeader[8] != generatedHeader[8] ||
        originalHeader[9] != generatedHeader[9];
    var wroteIdat = false;
    var wrotePalette = false;
    var wroteTransparency = false;

    for (final chunk in png.chunks) {
      if (!_shouldKeepChunk(chunk.type)) continue;
      switch (chunk.type) {
        case 'IHDR':
          _appendChunk(output, pixels, generatedIhdr);
          break;
        case 'PLTE':
          final paletteChunks = generatedByType['PLTE'];
          final replacement = paletteChunks == null || paletteChunks.isEmpty
              ? null
              : paletteChunks.first;
          if (replacement != null) {
            _appendChunk(output, pixels, replacement);
            wrotePalette = true;
          }
          break;
        case 'tRNS':
          final transparencyChunks = generatedByType['tRNS'];
          final replacement =
              transparencyChunks == null || transparencyChunks.isEmpty
                  ? null
                  : transparencyChunks.first;
          if (replacement != null) {
            _appendChunk(output, pixels, replacement);
            wroteTransparency = true;
          }
          break;
        case 'IDAT':
          if (!wroteIdat) {
            if (!wrotePalette && generatedByType['PLTE']?.isNotEmpty == true) {
              _appendChunk(output, pixels, generatedByType['PLTE']!.first);
              wrotePalette = true;
            }
            if (!wroteTransparency &&
                generatedByType['tRNS']?.isNotEmpty == true) {
              _appendChunk(output, pixels, generatedByType['tRNS']!.first);
              wroteTransparency = true;
            }
            for (final newTextChunk in newTextChunks) {
              output.add(newTextChunk);
            }
            for (final idat in generatedIdats) {
              _appendChunk(output, pixels, idat);
            }
            wroteIdat = true;
          }
          break;
        default:
          if (sampleFormatChanged &&
              _formatDependentChunks.contains(chunk.type)) {
            break;
          }
          _appendChunk(output, bytes, chunk);
      }
    }
    return output.takeBytes();
  }

  static Map<String, String> _readTextChunks(_PngFile png) {
    final values = <String, String>{};
    for (final chunk in png.chunks) {
      if (chunk.type != 'tEXt' &&
          chunk.type != 'zTXt' &&
          chunk.type != 'iTXt') {
        continue;
      }
      try {
        final data = chunk.data(png.bytes);
        switch (chunk.type) {
          case 'tEXt':
            final separator = data.indexOf(0);
            if (separator <= 0) continue;
            final keyword = latin1.decode(data.sublist(0, separator));
            final value = latin1.decode(data.sublist(separator + 1));
            values[keyword] = value;
            break;
          case 'zTXt':
            final separator = data.indexOf(0);
            if (separator <= 0 || separator + 2 > data.length) continue;
            if (data[separator + 1] != 0) continue;
            final keyword = latin1.decode(data.sublist(0, separator));
            final inflated = _inflate(
              data.sublist(separator + 2),
              gzipEncoded: false,
            );
            values[keyword] = latin1.decode(inflated);
            break;
          case 'iTXt':
            final parsed = _readITxt(data);
            if (parsed != null) values[parsed.$1] = parsed.$2;
            break;
        }
      } on FormatException {
        // An invalid optional text chunk does not invalidate image pixels.
      } on ArgumentError {
        // Ignore malformed text encoding and continue to later chunks.
      }
    }
    return values;
  }

  static (String, String)? _readITxt(Uint8List data) {
    final keywordEnd = data.indexOf(0);
    if (keywordEnd <= 0 || keywordEnd + 2 >= data.length) return null;
    final flag = data[keywordEnd + 1];
    final method = data[keywordEnd + 2];
    if ((flag != 0 && flag != 1) || method != 0) return null;
    final languageEnd = data.indexOf(0, keywordEnd + 3);
    if (languageEnd < 0) return null;
    final translatedEnd = data.indexOf(0, languageEnd + 1);
    if (translatedEnd < 0) return null;
    final encodedText = data.sublist(translatedEnd + 1);
    final decoded =
        flag == 1 ? _inflate(encodedText, gzipEncoded: false) : encodedText;
    return (
      latin1.decode(data.sublist(0, keywordEnd)),
      utf8.decode(decoded),
    );
  }

  static List<int> _inflate(
    List<int> bytes, {
    required bool gzipEncoded,
  }) {
    final sink = _CappedByteSink(_maxStealthPayloadBytes);
    final decoder = (gzipEncoded ? gzip.decoder : zlib.decoder)
        .startChunkedConversion(sink);
    decoder.add(bytes);
    decoder.close();
    return sink.takeBytes();
  }

  static Map<String, dynamic> _decodeComment(String? raw) {
    if (raw == null) return {};
    try {
      final value = jsonDecode(raw);
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      // Preserve raw text in the text map; only JSON objects become Comment.
    }
    return {};
  }

  static void _mergeStealthText(
    Map<String, String> text,
    Map<String, dynamic> payload,
  ) {
    for (final entry in payload.entries) {
      if (entry.key == 'Comment' || entry.value is! String) continue;
      text.putIfAbsent(entry.key, () => entry.value as String);
    }
  }

  static void _mergeStealthComment(
    Map<String, dynamic> comment,
    Object? rawComment,
  ) {
    Map<String, dynamic>? source;
    if (rawComment is Map<String, dynamic>) {
      source = rawComment;
    } else if (rawComment is String) {
      final parsed = _decodeComment(rawComment);
      if (parsed.isNotEmpty) source = parsed;
    }
    if (source == null) return;
    for (final entry in source.entries) {
      comment.putIfAbsent(entry.key, () => entry.value);
    }
  }

  static _StealthReadResult _decodeStealth(Uint8List bytes, _PngFile png) {
    if (png.pixelCount > _maxStealthPixels) {
      throw const FormatException(
        '图片超过 16 Mi 像素，无法安全检查隐写元数据',
      );
    }
    img.Image? image;
    try {
      image = img.PngDecoder().decode(bytes);
    } on Object {
      throw const FormatException('PNG 像素数据无法解码');
    }
    if (image == null) {
      throw const FormatException('PNG 像素数据无法解码');
    }

    final carriers = <_StealthCarrier>[];
    final colorType = png.colorType;
    if ((colorType == 4 || colorType == 6) && image.numChannels >= 2) {
      final carrier = _readCarrier(image, _StealthMode.alpha);
      if (carrier != null) carriers.add(carrier);
    }
    if ((colorType == 2 || colorType == 6) && image.numChannels >= 3) {
      final carrier = _readCarrier(image, _StealthMode.rgb);
      if (carrier != null) carriers.add(carrier);
    }
    return _StealthReadResult(carriers, image);
  }

  static _StealthCarrier? _readCarrier(img.Image image, _StealthMode mode) {
    final capacity =
        image.width * image.height * (mode == _StealthMode.rgb ? 3 : 1);
    if (capacity < 152) return null;
    final header = _readCarrierBytes(image, mode, 0, 19);
    final magic = latin1.decode(header.sublist(0, 15));
    final signature = _stealthSignatures.cast<_StealthSignature?>().firstWhere(
          (item) => item!.mode == mode && item.value == magic,
          orElse: () => null,
        );
    if (signature == null) return null;

    final payloadBitLength = _u32(header, 15);
    if (payloadBitLength == 0 ||
        payloadBitLength % 8 != 0 ||
        payloadBitLength > _maxStealthPayloadBytes * 8 ||
        payloadBitLength + 152 > capacity) {
      throw const FormatException('Stealth PNG payload 长度无效');
    }
    final payload = _readCarrierBytes(
      image,
      mode,
      152,
      payloadBitLength ~/ 8,
    );
    Map<String, dynamic>? metadata;
    try {
      final decoded =
          signature.compressed ? _inflate(payload, gzipEncoded: true) : payload;
      final value = jsonDecode(utf8.decode(decoded));
      if (value is Map<String, dynamic>) metadata = value;
      if (metadata?['Comment'] is String) {
        final parsed = _decodeComment(metadata!['Comment'] as String);
        if (parsed.isNotEmpty) metadata['Comment'] = parsed;
      }
    } on FormatException {
      // The carrier is still recognized and scrubbed if its JSON is invalid.
    } on ArgumentError {
      // Ignore invalid UTF-8 metadata while retaining the carrier bounds.
    }
    return _StealthCarrier(mode, 152 + payloadBitLength, metadata);
  }

  static Uint8List _readCarrierBytes(
    img.Image image,
    _StealthMode mode,
    int startBit,
    int byteCount,
  ) {
    final result = Uint8List(byteCount);
    final bitCount = byteCount * 8;
    for (var i = 0; i < bitCount; i++) {
      result[i >> 3] =
          (result[i >> 3] << 1) | _readCarrierBit(image, mode, startBit + i);
    }
    return result;
  }

  static int _readCarrierBit(img.Image image, _StealthMode mode, int bitIndex) {
    final samplesPerPixel = mode == _StealthMode.rgb ? 3 : 1;
    final pixelIndex = bitIndex ~/ samplesPerPixel;
    final x = pixelIndex ~/ image.height;
    final y = pixelIndex % image.height;
    final pixel = image.getPixel(x, y);
    if (mode == _StealthMode.alpha) return pixel.a.toInt() & 1;
    return switch (bitIndex % 3) {
      0 => pixel.r.toInt() & 1,
      1 => pixel.g.toInt() & 1,
      _ => pixel.b.toInt() & 1,
    };
  }

  static void _clearCarrier(img.Image image, _StealthCarrier carrier) {
    for (var bitIndex = 0; bitIndex < carrier.totalBits; bitIndex++) {
      final samplesPerPixel = carrier.mode == _StealthMode.rgb ? 3 : 1;
      final pixelIndex = bitIndex ~/ samplesPerPixel;
      final x = pixelIndex ~/ image.height;
      final y = pixelIndex % image.height;
      final pixel = image.getPixel(x, y);
      if (carrier.mode == _StealthMode.alpha) {
        pixel.a = pixel.a.toInt() & 0xfe;
      } else {
        switch (bitIndex % 3) {
          case 0:
            pixel.r = pixel.r.toInt() & 0xfe;
          case 1:
            pixel.g = pixel.g.toInt() & 0xfe;
          case 2:
            pixel.b = pixel.b.toInt() & 0xfe;
        }
      }
      image.setPixel(x, y, pixel);
    }
  }

  static Uint8List _buildITxtChunk(String keyword, String value) {
    final keyBytes = latin1.encode(keyword);
    final textBytes = utf8.encode(value);
    final data = <int>[...keyBytes, 0, 0, 0, 0, 0, ...textBytes];
    return _buildChunk('iTXt', data);
  }

  static bool _shouldKeepChunk(String type) {
    if (_metadataChunkTypes.contains(type)) return false;
    final ancillary = type.codeUnitAt(0) >= 0x61 && type.codeUnitAt(0) <= 0x7a;
    return !ancillary || _renderingAncillaryChunks.contains(type);
  }

  static void _validateText(Map<String, String> text) {
    for (final entry in text.entries) {
      final key = entry.key;
      final keyBytes = latin1.encode(key);
      if (keyBytes.isEmpty ||
          keyBytes.length > 79 ||
          keyBytes.any((byte) =>
              byte == 0 || (byte < 32) || (byte >= 127 && byte < 161)) ||
          keyBytes.first == 32 ||
          keyBytes.last == 32 ||
          List.generate(keyBytes.length - 1,
                  (i) => keyBytes[i] == 32 && keyBytes[i + 1] == 32)
              .contains(true)) {
        throw FormatException('PNG iTXt 关键字不合法：$key');
      }
      if (entry.value.contains('\u0000')) {
        throw FormatException('PNG iTXt 文本不能包含空字节：$key');
      }
    }
  }

  static Uint8List _buildChunk(String type, List<int> data) {
    if (data.length > 0x7fffffff) {
      throw const FormatException('PNG chunk 超过格式长度上限');
    }
    final typeBytes = ascii.encode(type);
    final bytes = Uint8List(data.length + 12);
    _putU32(bytes, 0, data.length);
    bytes.setRange(4, 8, typeBytes);
    bytes.setRange(8, 8 + data.length, data);
    _putU32(bytes, 8 + data.length, _crc32(bytes, 4, 8 + data.length));
    return bytes;
  }

  static void _appendChunk(
    BytesBuilder output,
    Uint8List source,
    _PngChunk chunk,
  ) {
    output.add(source.sublist(chunk.start, chunk.end));
  }

  static int _crc32(Uint8List bytes, int start, int end) {
    var crc = 0xffffffff;
    for (var i = start; i < end; i++) {
      crc = _crcTable[(crc ^ bytes[i]) & 0xff] ^ (crc >> 8);
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  static int _u32(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  static void _putU32(Uint8List bytes, int offset, int value) {
    bytes[offset] = (value >> 24) & 0xff;
    bytes[offset + 1] = (value >> 16) & 0xff;
    bytes[offset + 2] = (value >> 8) & 0xff;
    bytes[offset + 3] = value & 0xff;
  }
}

enum _StealthMode { alpha, rgb }

class _StealthSignature {
  final String value;
  final _StealthMode mode;
  final bool compressed;

  const _StealthSignature(this.value, this.mode, this.compressed);
}

class _StealthCarrier {
  final _StealthMode mode;
  final int totalBits;
  final Map<String, dynamic>? metadata;

  const _StealthCarrier(this.mode, this.totalBits, this.metadata);
}

class _StealthReadResult {
  final List<_StealthCarrier> carriers;
  final img.Image? image;

  const _StealthReadResult(this.carriers, [this.image]);
}

class _CappedByteSink implements Sink<List<int>> {
  final int maximumBytes;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  int _length = 0;

  _CappedByteSink(this.maximumBytes);

  @override
  void add(List<int> chunk) {
    _length += chunk.length;
    if (_length > maximumBytes) {
      throw const FormatException('压缩 PNG 元数据超过安全长度限制');
    }
    _builder.add(chunk);
  }

  @override
  void close() {}

  Uint8List takeBytes() => _builder.takeBytes();
}

class _PngFile {
  final Uint8List bytes;
  final List<_PngChunk> chunks;
  final int width;
  final int height;
  final int bitDepth;
  final int colorType;

  const _PngFile(
    this.bytes,
    this.chunks,
    this.width,
    this.height,
    this.bitDepth,
    this.colorType,
  );

  int get pixelCount => width * height;

  Uint8List ihdrData(Uint8List source) =>
      chunks.singleWhere((chunk) => chunk.type == 'IHDR').data(source);

  static _PngFile parse(Uint8List bytes) {
    if (bytes.length < 8 ||
        !_PngMetadataServiceBytes.equal(bytes, PngMetadataService._signature)) {
      throw const FormatException('不是有效的 PNG 文件');
    }
    final chunks = <_PngChunk>[];
    var position = 8;
    var sawHeader = false;
    var sawData = false;
    var endedData = false;
    var sawEnd = false;
    var width = 0;
    var height = 0;
    var bitDepth = 0;
    var colorType = 0;

    while (position < bytes.length) {
      if (bytes.length - position < 12) {
        throw const FormatException('PNG chunk 被截断');
      }
      final length = PngMetadataService._u32(bytes, position);
      if (length > 0x7fffffff) {
        throw const FormatException('PNG chunk 长度超出规范范围');
      }
      final dataStart = position + 8;
      final dataEnd = dataStart + length;
      final end = dataEnd + 4;
      if (end > bytes.length) {
        throw const FormatException('PNG chunk 数据不完整');
      }
      final type = ascii.decode(bytes.sublist(position + 4, position + 8));
      if (!RegExp(r'^[A-Za-z]{4}$').hasMatch(type)) {
        throw const FormatException('PNG chunk 类型无效');
      }
      final expectedCrc = PngMetadataService._u32(bytes, dataEnd);
      final actualCrc = PngMetadataService._crc32(bytes, position + 4, dataEnd);
      if (expectedCrc != actualCrc) {
        throw FormatException('PNG $type chunk CRC 校验失败');
      }
      if (type == 'acTL' || type == 'fcTL' || type == 'fdAT') {
        throw UnsupportedError('暂不支持 APNG 动画图片');
      }
      if (!sawHeader && type != 'IHDR') {
        throw const FormatException('PNG 首个 chunk 必须是 IHDR');
      }
      if (type == 'IHDR') {
        if (sawHeader || chunks.isNotEmpty || length != 13) {
          throw const FormatException('PNG IHDR chunk 无效');
        }
        sawHeader = true;
        width = PngMetadataService._u32(bytes, dataStart);
        height = PngMetadataService._u32(bytes, dataStart + 4);
        bitDepth = bytes[dataStart + 8];
        colorType = bytes[dataStart + 9];
        if (width <= 0 || height <= 0) {
          throw const FormatException('PNG 图片尺寸无效');
        }
      } else if (type == 'IDAT') {
        if (endedData) throw const FormatException('PNG IDAT chunk 不连续');
        sawData = true;
      } else if (sawData && type != 'IEND') {
        endedData = true;
      }
      if (type == 'IEND') {
        if (length != 0 || !sawData || end != bytes.length) {
          throw const FormatException('PNG IEND chunk 无效或存在尾随数据');
        }
        sawEnd = true;
      }
      chunks.add(_PngChunk(type, position, dataStart, dataEnd, end));
      position = end;
      if (sawEnd) break;
    }
    if (!sawHeader || !sawData || !sawEnd) {
      throw const FormatException('PNG 缺少必要 chunk');
    }
    return _PngFile(bytes, chunks, width, height, bitDepth, colorType);
  }
}

class _PngChunk {
  final String type;
  final int start;
  final int dataStart;
  final int dataEnd;
  final int end;

  const _PngChunk(
      this.type, this.start, this.dataStart, this.dataEnd, this.end);

  Uint8List data(Uint8List source) => source.sublist(dataStart, dataEnd);
}

class _PngMetadataServiceBytes {
  static bool equal(Uint8List bytes, List<int> value) {
    if (bytes.length < value.length) return false;
    for (var i = 0; i < value.length; i++) {
      if (bytes[i] != value[i]) return false;
    }
    return true;
  }
}
