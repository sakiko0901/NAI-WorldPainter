import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/data/datasources/local/png_metadata_service.dart';

const _pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

void main() {
  test('reads tEXt, compressed zTXt, UTF-8 iTXt and Comment JSON', () {
    final png = _insertBeforeIdat(_makeImage(), [
      _chunk('tEXt', [...latin1.encode('Title'), 0, ...latin1.encode('plain')]),
      _chunk('zTXt', [
        ...latin1.encode('Software'),
        0,
        0,
        ...zlib.encode(latin1.encode('NovelAI')),
      ]),
      _chunk('iTXt', [
        ...latin1.encode('Comment'),
        0,
        0,
        0,
        0,
        0,
        ...utf8.encode(jsonEncode({'prompt': '星空, 青い髪', 'seed': 19})),
      ]),
    ]);

    final document = PngMetadataService.read(png);
    expect(document.text['Title'], 'plain');
    expect(document.text['Software'], 'NovelAI');
    expect(document.comment['prompt'], '星空, 青い髪');
    expect(document.comment['seed'], 19);
  });

  test('reads NovelAI alpha stealth with the payload offset after length', () {
    final png = _withStealth(
      _makeImage(width: 64, height: 64),
      {
        'Description': 'alpha description',
        'Software': 'NovelAI',
        'Comment': {'prompt': 'alpha secret', 'seed': 42},
      },
    );

    final document = PngMetadataService.read(png);
    expect(document.text['Description'], 'alpha description');
    expect(document.text['Software'], 'NovelAI');
    expect(document.comment['prompt'], 'alpha secret');
    expect(document.comment['seed'], 42);
  });

  test('reads uncompressed PNG and RGB stealth payloads', () {
    for (final mode in _StealthFixtureMode.values) {
      final png = _withStealth(
        _makeImage(width: 64, height: 64),
        {
          'Comment': {'prompt': 'raw ${mode.name} payload'}
        },
        mode: mode,
        compressed: false,
      );
      expect(
        PngMetadataService.read(png).comment['prompt'],
        'raw ${mode.name} payload',
      );
    }
  });

  test('reads RGB stealth and gives text chunks priority over conflicting keys',
      () {
    final png = _insertBeforeIdat(
      _withStealth(
        _makeImage(width: 64, height: 64),
        {
          'Description': 'from stealth',
          'Comment': {'prompt': 'stealth prompt', 'seed': 7},
        },
        mode: _StealthFixtureMode.rgb,
      ),
      [
        _chunk('tEXt', [
          ...latin1.encode('Description'),
          0,
          ...latin1.encode('from text'),
        ]),
        _chunk('tEXt', [
          ...latin1.encode('Comment'),
          0,
          ...latin1.encode(jsonEncode({'prompt': 'text prompt'})),
        ]),
      ],
    );

    final document = PngMetadataService.read(png);
    expect(document.text['Description'], 'from text');
    expect(document.comment['prompt'], 'text prompt');
    expect(document.comment['seed'], 7);
  });

  test('rewrite replaces old metadata with UTF-8 iTXt even for tiny PNGs', () {
    final source = _insertBeforeIdat(_makeImage(width: 1, height: 1), [
      _chunk('tEXt', [
        ...latin1.encode('Description'),
        0,
        ...latin1.encode('old prompt secret'),
      ]),
      _chunk('eXIf', [1, 2, 3, 4]),
      _chunk('tIME', [0, 0, 0, 0, 0, 0, 0]),
      _chunk('vpAg', [9, 8, 7]),
      _chunk('sRGB', [0]),
    ]);
    final rewritten = PngMetadataService.rewrite(source, {
      'Title': '新标题',
      'Description': '新的提示词: 星河',
      'Comment': jsonEncode({'prompt': '新提示词', 'seed': 99}),
    });

    final document = PngMetadataService.read(rewritten);
    expect(document.text['Title'], '新标题');
    expect(document.text['Description'], '新的提示词: 星河');
    expect(document.comment['prompt'], '新提示词');
    expect(document.comment['seed'], 99);
    expect(utf8.decode(rewritten, allowMalformed: true),
        isNot(contains('old prompt secret')));
    final types = _chunkTypes(rewritten);
    expect(types, isNot(contains('tEXt')));
    expect(types, isNot(contains('zTXt')));
    expect(types, isNot(contains('eXIf')));
    expect(types, isNot(contains('tIME')));
    expect(types, isNot(contains('vpAg')));
    expect(types, contains('sRGB'));
  });

  test('strip removes text, EXIF and the full alpha stealth payload', () {
    final original = _withStealth(
      _makeImage(width: 64, height: 64),
      {
        'Description': 'secret description',
        'Comment': {'prompt': 'secret prompt', 'uc': 'secret negative'},
      },
    );
    final before = img.decodePng(original)!;
    final rewritten = PngMetadataService.strip(original);
    final after = img.decodePng(rewritten)!;

    expect(PngMetadataService.read(rewritten).text, isEmpty);
    expect(PngMetadataService.read(rewritten).comment, isEmpty);
    expect(_chunkTypes(rewritten), isNot(contains('iTXt')));
    expect(_chunkTypes(rewritten), isNot(contains('eXIf')));
    _expectOnlyStealthAlphaBitsCleared(before, after);
  });

  test('strip preserves PNG data chunks and transparent pixels without stealth',
      () {
    final source = img.decodePng(_makeImage(width: 4, height: 3))!;
    source.textData = {
      'Comment': jsonEncode({'prompt': 'remove me'})
    };
    final original = Uint8List.fromList(img.encodePng(source));
    final cleaned = PngMetadataService.strip(original);
    final originalIdat = _chunkBytes(original, 'IDAT');
    final cleanedIdat = _chunkBytes(cleaned, 'IDAT');

    expect(cleanedIdat, originalIdat);
    expect(PngMetadataService.read(cleaned).text, isEmpty);
    expect(PngMetadataService.read(cleaned).comment, isEmpty);
    final decoded = img.decodePng(cleaned)!;
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        expect(decoded.getPixel(x, y).a, source.getPixel(x, y).a);
      }
    }
  });

  test(
      'rewrite clears RGB carrier bits while keeping non-carrier alpha unchanged',
      () {
    final original = _withStealth(
      _makeImage(width: 64, height: 64),
      {
        'Comment': {'prompt': 'rgb secret'}
      },
      mode: _StealthFixtureMode.rgb,
    );
    final before = img.decodePng(original)!;
    final rewritten = PngMetadataService.rewrite(original, {
      'Comment': jsonEncode({'prompt': 'replacement'}),
    });
    final document = PngMetadataService.read(rewritten);
    final after = img.decodePng(rewritten)!;

    expect(document.comment['prompt'], 'replacement');
    for (var y = 0; y < before.height; y++) {
      for (var x = 0; x < before.width; x++) {
        expect(after.getPixel(x, y).a, before.getPixel(x, y).a);
      }
    }
    expect(_hasStealthMagic(after, _StealthFixtureMode.rgb), isFalse);
  });

  test('rejects non-PNG, APNG and damaged chunk CRCs', () {
    final valid = _makeImage(width: 2, height: 2);
    expect(() => PngMetadataService.read(Uint8List.fromList([1, 2, 3])),
        throwsFormatException);

    final apng = _insertBeforeIdat(valid, [
      _chunk('acTL', [0, 0, 0, 1, 0, 0, 0, 0])
    ]);
    expect(() => PngMetadataService.strip(apng), throwsUnsupportedError);

    final damaged = Uint8List.fromList(valid)..[valid.length - 1] ^= 1;
    expect(() => PngMetadataService.read(damaged), throwsFormatException);
  });

  test('rejects an oversized PNG before decoding its pixel data', () {
    final oversized =
        _withDimensions(_makeImage(width: 1, height: 1), 4097, 4097);
    expect(() => PngMetadataService.read(oversized), throwsFormatException);
    expect(() => PngMetadataService.strip(oversized), throwsFormatException);
  });

  test(
      'does not treat a recognized stealth header with invalid length as empty',
      () {
    final malformed =
        _withInvalidStealthLength(_makeImage(width: 64, height: 64));
    expect(() => PngMetadataService.read(malformed), throwsFormatException);
    expect(() => PngMetadataService.strip(malformed), throwsFormatException);
  });
}

enum _StealthFixtureMode { alpha, rgb }

Uint8List _makeImage({int width = 8, int height = 8}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final alpha = (x + y) % 4 == 0 ? 0 : 253 - ((x + y) % 3);
      image.setPixelRgba(x, y, 20 + x, 30 + y, 40 + x + y, alpha);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _withStealth(
  Uint8List png,
  Map<String, dynamic> metadata, {
  _StealthFixtureMode mode = _StealthFixtureMode.alpha,
  bool compressed = true,
}) {
  final image = img.decodePng(png)!;
  final jsonBytes = utf8.encode(jsonEncode(metadata));
  final payloadData = Uint8List.fromList(
    compressed ? gzip.encode(jsonBytes) : jsonBytes,
  );
  final length = ByteData(4)..setUint32(0, payloadData.length * 8);
  final signature = utf8.encode(
    'stealth_${mode == _StealthFixtureMode.alpha ? 'png' : 'rgb'}${compressed ? 'comp' : 'info'}',
  );
  final payload = <int>[
    ...signature,
    ...length.buffer.asUint8List(),
    ...payloadData,
  ];
  var bitIndex = 0;
  for (final byte in payload) {
    for (var bit = 7; bit >= 0; bit--) {
      final value = (byte >> bit) & 1;
      final pixelIndex = bitIndex ~/ (mode == _StealthFixtureMode.rgb ? 3 : 1);
      final x = pixelIndex ~/ image.height;
      final y = pixelIndex % image.height;
      final pixel = image.getPixel(x, y);
      if (mode == _StealthFixtureMode.alpha) {
        pixel.a = (pixel.a.toInt() & 0xfe) | value;
      } else {
        switch (bitIndex % 3) {
          case 0:
            pixel.r = (pixel.r.toInt() & 0xfe) | value;
          case 1:
            pixel.g = (pixel.g.toInt() & 0xfe) | value;
          case 2:
            pixel.b = (pixel.b.toInt() & 0xfe) | value;
        }
      }
      image.setPixel(x, y, pixel);
      bitIndex++;
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _withInvalidStealthLength(Uint8List png) {
  final image = img.decodePng(png)!;
  final payload = <int>[
    ...utf8.encode('stealth_pngcomp'),
    ...((ByteData(4)..setUint32(0, 0xffffffff)).buffer.asUint8List()),
  ];
  var bitIndex = 0;
  for (final byte in payload) {
    for (var bit = 7; bit >= 0; bit--) {
      final x = bitIndex ~/ image.height;
      final y = bitIndex % image.height;
      final pixel = image.getPixel(x, y);
      pixel.a = (pixel.a.toInt() & 0xfe) | ((byte >> bit) & 1);
      image.setPixel(x, y, pixel);
      bitIndex++;
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _withDimensions(Uint8List png, int width, int height) {
  final result = Uint8List.fromList(png);
  _writeU32(result, 16, width);
  _writeU32(result, 20, height);
  _writeU32(result, 8 + 8 + 13, _crc32(result, 12, 8 + 8 + 13));
  return result;
}

void _expectOnlyStealthAlphaBitsCleared(img.Image before, img.Image after) {
  final text = jsonEncode({
    'Description': 'secret description',
    'Comment': {'prompt': 'secret prompt', 'uc': 'secret negative'},
  });
  final compressedLength = gzip.encode(utf8.encode(text)).length;
  final usedBits = (15 + 4 + compressedLength) * 8;
  var index = 0;
  for (var x = 0; x < before.width; x++) {
    for (var y = 0; y < before.height; y++) {
      final oldAlpha = before.getPixel(x, y).a.toInt();
      final newAlpha = after.getPixel(x, y).a.toInt();
      if (index < usedBits) {
        expect(newAlpha & 1, 0);
        expect(newAlpha & 0xfe, oldAlpha & 0xfe);
      } else {
        expect(newAlpha, oldAlpha);
      }
      index++;
    }
  }
}

bool _hasStealthMagic(img.Image image, _StealthFixtureMode mode) {
  final bits = <int>[];
  final magicLength = utf8
      .encode(
        mode == _StealthFixtureMode.alpha
            ? 'stealth_pngcomp'
            : 'stealth_rgbcomp',
      )
      .length;
  for (var i = 0; i < magicLength * 8; i++) {
    final pixelIndex = i ~/ (mode == _StealthFixtureMode.rgb ? 3 : 1);
    final x = pixelIndex ~/ image.height;
    final y = pixelIndex % image.height;
    final pixel = image.getPixel(x, y);
    final value = mode == _StealthFixtureMode.alpha
        ? pixel.a.toInt() & 1
        : switch (i % 3) {
            0 => pixel.r.toInt() & 1,
            1 => pixel.g.toInt() & 1,
            _ => pixel.b.toInt() & 1,
          };
    bits.add(value);
  }
  final magic = <int>[];
  for (var i = 0; i < bits.length; i += 8) {
    var value = 0;
    for (var j = 0; j < 8; j++) {
      value = (value << 1) | bits[i + j];
    }
    magic.add(value);
  }
  return latin1.decode(magic) ==
      (mode == _StealthFixtureMode.alpha
          ? 'stealth_pngcomp'
          : 'stealth_rgbcomp');
}

Uint8List _insertBeforeIdat(Uint8List png, List<Uint8List> insertions) {
  final output = BytesBuilder(copy: false)..add(_pngSignature);
  var offset = _pngSignature.length;
  var inserted = false;
  while (offset < png.length) {
    final length = _readU32(png, offset);
    final type = ascii.decode(png.sublist(offset + 4, offset + 8));
    if (!inserted && type == 'IDAT') {
      for (final insertion in insertions) {
        output.add(insertion);
      }
      inserted = true;
    }
    final end = offset + 12 + length;
    output.add(png.sublist(offset, end));
    offset = end;
  }
  return output.takeBytes();
}

Uint8List _chunk(String type, List<int> data) {
  final typeBytes = ascii.encode(type);
  final result = Uint8List(data.length + 12);
  _writeU32(result, 0, data.length);
  result.setRange(4, 8, typeBytes);
  result.setRange(8, 8 + data.length, data);
  _writeU32(result, 8 + data.length, _crc32(result, 4, 8 + data.length));
  return result;
}

List<String> _chunkTypes(Uint8List png) {
  final result = <String>[];
  var offset = _pngSignature.length;
  while (offset < png.length) {
    final length = _readU32(png, offset);
    result.add(ascii.decode(png.sublist(offset + 4, offset + 8)));
    offset += 12 + length;
  }
  return result;
}

Uint8List _chunkBytes(Uint8List png, String target) {
  final output = BytesBuilder(copy: false);
  var offset = _pngSignature.length;
  while (offset < png.length) {
    final length = _readU32(png, offset);
    final type = ascii.decode(png.sublist(offset + 4, offset + 8));
    if (type == target) output.add(png.sublist(offset, offset + 12 + length));
    offset += 12 + length;
  }
  return output.takeBytes();
}

int _readU32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

void _writeU32(Uint8List bytes, int offset, int value) {
  bytes[offset] = (value >> 24) & 0xff;
  bytes[offset + 1] = (value >> 16) & 0xff;
  bytes[offset + 2] = (value >> 8) & 0xff;
  bytes[offset + 3] = value & 0xff;
}

int _crc32(Uint8List bytes, int start, int end) {
  var crc = 0xffffffff;
  for (var i = start; i < end; i++) {
    crc ^= bytes[i];
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
