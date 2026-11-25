import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// The draft and generation history must keep the image after library removal.
Future<String> copyCatalogReferenceToWorkspace(String sourcePath) async {
  final source = File(sourcePath);
  final sourceExtension = p.extension(sourcePath).toLowerCase();
  final extension = sourceExtension == '.jpeg' ? '.jpg' : sourceExtension;
  if (!const {'.png', '.jpg', '.webp'}.contains(extension)) {
    throw const FormatException('参考图格式不受支持。');
  }

  const uuid = Uuid();
  final checksum = await sha256.bind(source.openRead()).first;
  final id = uuid.v5(Namespace.url.value, 'nai-huishi:reference:$checksum');
  final directory = await ImageUtils.getImageDirectory();
  final target = File(p.join(directory.path, '$id$extension'));
  if (await target.exists()) return target.path;

  final staging = File(p.join(directory.path, '${uuid.v4()}.part'));
  try {
    await source.copy(staging.path);
    try {
      await staging.rename(target.path);
    } on FileSystemException {
      if (!await target.exists()) rethrow;
    }
  } finally {
    if (await staging.exists()) await staging.delete();
  }
  return target.path;
}
