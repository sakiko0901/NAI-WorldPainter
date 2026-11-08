import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/utils/vibe_file_codec.dart';
import 'package:nai_huishi/domain/entities/vibe_encoding.dart';

void main() {
  test('portable file retains exact model, encoding and extraction', () async {
    final bytes = await VibeFileCodec.encode(VibeEncoding(
        title: '柔光',
        thumbnailPath: '',
        encodedVibe: 'AQID',
        encodedModel: 'nai-diffusion-4-5-full',
        informationExtracted: .7,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026)));
    final json = jsonDecode(utf8.decode(bytes)) as Map;
    expect(json['identifier'], 'novelai-vibe-transfer');
    expect(json['encodings'], contains('v4-5full'));
    expect(json.containsKey('image'), false);
    final restored = VibeFileCodec.decode(bytes).single;
    expect(restored.encoding, 'AQID');
    expect(restored.information, .7);
    expect(restored.model, 'nai-diffusion-4-5-full');
    expect(restored.title, '柔光');
  });
  test('invalid envelope is rejected before import', () {
    expect(
        () => VibeFileCodec.decode(
            Uint8List.fromList(utf8.encode('{"version":1}'))),
        throwsFormatException);
  });
  test('unknown model is never exported under a guessed model', () {
    expect(
        VibeFileCodec.encode(VibeEncoding(
            title: '旧编码',
            thumbnailPath: '',
            encodedVibe: 'AQID',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026))),
        throwsFormatException);
  });
}
