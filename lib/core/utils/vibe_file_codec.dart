import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:nai_huishi/domain/entities/vibe_encoding.dart';

/// NovelAI's portable encoding envelope. Never includes the source image.
class VibeFileCodec {
  static const models = {
    'v4curated': 'nai-diffusion-4-curated-preview',
    'v4full': 'nai-diffusion-4-full',
    'v4-5curated': 'nai-diffusion-4-5-curated',
    'v4-5full': 'nai-diffusion-4-5-full',
  };

  static Future<Uint8List> encode(VibeEncoding value) async {
    final key = models.entries
        .where((e) => e.value == value.encodedModel)
        .firstOrNull
        ?.key;
    if (key == null) throw const FormatException('该编码缺少受支持的模型信息，无法导出');
    if (value.encodedVibe.isEmpty) throw const FormatException('编码内容为空');
    base64Decode(value.encodedVibe);
    final info = value.informationExtracted;
    final hash = sha256
        .convert(utf8.encode(
            'information_extracted:${info == info.roundToDouble() ? info.toInt() : info}'))
        .toString();
    final thumbnail = File(value.thumbnailPath);
    final data = <String, dynamic>{
      'identifier': 'novelai-vibe-transfer',
      'version': 1,
      'type': 'encoding',
      'id': sha256.convert(utf8.encode(value.encodedVibe)).toString(),
      'name': value.title,
      'createdAt': value.createdAt.millisecondsSinceEpoch,
      'encodings': {
        key: {
          hash: {
            'encoding': value.encodedVibe,
            'params': {'information_extracted': info}
          }
        }
      },
      'importInfo': {
        'model': value.encodedModel,
        'information_extracted': info,
        'strength': .3
      },
      if (await thumbnail.exists())
        'thumbnail':
            'data:image/jpeg;base64,${base64Encode(await thumbnail.readAsBytes())}',
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(data)));
  }

  static List<
      ({
        String title,
        String model,
        String encoding,
        double information,
        Uint8List? thumbnail
      })> decode(Uint8List bytes) {
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (data['identifier'] != 'novelai-vibe-transfer' || data['version'] != 1) {
      throw const FormatException('不是支持的 .naiv4vibe 文件');
    }
    final result = <({
      String title,
      String model,
      String encoding,
      double information,
      Uint8List? thumbnail
    })>[];
    final encodings = data['encodings'] as Map<String, dynamic>;
    Uint8List? thumbnail;
    final preview = data['thumbnail'];
    if (preview is String && preview.contains(';base64,')) {
      thumbnail = base64Decode(preview.split(';base64,').last);
    }
    for (final group in encodings.entries) {
      final model = models[group.key];
      if (model == null) continue;
      for (final raw in (group.value as Map).values) {
        final value = raw as Map;
        final encoded = value['encoding'] as String;
        if (base64Decode(encoded).isEmpty) {
          throw const FormatException('编码内容为空');
        }
        final info =
            (value['params']['information_extracted'] as num).toDouble();
        if (!info.isFinite || info < 0 || info > 1) {
          throw const FormatException('信息提取度无效');
        }
        result.add((
          title: data['name'] as String? ?? '导入氛围',
          model: model,
          encoding: encoded,
          information: info,
          thumbnail: thumbnail
        ));
      }
    }
    if (result.isEmpty) throw const FormatException('文件中没有受支持的 V4 / V4.5 编码');
    return result;
  }
}
