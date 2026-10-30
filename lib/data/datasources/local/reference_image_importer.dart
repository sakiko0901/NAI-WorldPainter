import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/data/datasources/local/nai_metadata_parser.dart';
import 'package:nai_huishi/domain/entities/image_tag_result.dart';

class PreparedReferenceImage {
  final String path;
  final int width;
  final int height;
  final ImageTagResult? metadata;
  const PreparedReferenceImage(
      this.path, this.width, this.height, this.metadata);
}

/// Called with compute; metadata must be read before resizing/re-encoding.
Future<PreparedReferenceImage> prepareReferenceImage(
    ({String source, String target, bool preserveSize}) input) async {
  final bytes = await File(input.source).readAsBytes();
  final metadata = NaiMetadataParser.parseBytes(bytes);
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('无法读取图片');
  var image = img.bakeOrientation(decoded);
  if (!input.preserveSize && (image.width > 2048 || image.height > 2048)) {
    image = img.copyResize(image,
        width: image.width >= image.height ? 2048 : null,
        height: image.height > image.width ? 2048 : null,
        interpolation: img.Interpolation.average);
  }
  await File(input.target).writeAsBytes(img.encodePng(image, level: 6));
  return PreparedReferenceImage(
      input.target, image.width, image.height, metadata);
}
