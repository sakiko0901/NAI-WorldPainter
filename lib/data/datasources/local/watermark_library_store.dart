import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:nai_huishi/domain/entities/watermark.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Each import owns a directory, so an interrupted import cannot corrupt the
/// other saved watermarks. Source files are never modified or deleted.
class WatermarkLibraryStore {
  final Directory? directory;

  WatermarkLibraryStore({this.directory});

  Future<Directory> _root() async {
    final root = directory ??
        Directory(p.join((await getApplicationDocumentsDirectory()).path,
            'watermark_library'));
    await root.create(recursive: true);
    return root;
  }

  Future<List<WatermarkAsset>> load() async {
    final root = await _root();
    final assets = <WatermarkAsset>[];
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory) continue;
      try {
        final data = jsonDecode(
                await File(p.join(entry.path, 'asset.json')).readAsString())
            as Map<String, dynamic>;
        final filename = data['file'] as String;
        if (p.basename(filename) != filename ||
            filename == '.' ||
            filename == '..') {
          continue;
        }
        final path = p.join(entry.path, filename);
        if (!await File(path).exists()) continue;
        final width = data['width'] as int;
        final height = data['height'] as int;
        if (width <= 0 || height <= 0) continue;
        assets.add(WatermarkAsset(
          id: p.basename(entry.path),
          name: data['name'] as String,
          path: path,
          width: width,
          height: height,
          createdAt: DateTime.parse(data['createdAt'] as String),
        ));
      } on FileSystemException {
        // An incomplete or missing import does not hide the rest of the library.
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    assets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return assets;
  }

  Future<WatermarkAsset> importFile(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) {
      throw const FormatException('无法读取这张水印图片');
    }
    final root = await _root();
    final id = const Uuid().v4();
    final folder = Directory(p.join(root.path, id));
    final extension = p.extension(sourcePath).toLowerCase();
    final filename =
        'image${RegExp(r'^\.[a-z0-9]+$').hasMatch(extension) ? extension : '.img'}';
    final createdAt = DateTime.now().toUtc();
    final asset = WatermarkAsset(
      id: id,
      name: p.basenameWithoutExtension(sourcePath),
      path: p.join(folder.path, filename),
      width: info.width,
      height: info.height,
      createdAt: createdAt,
    );
    try {
      await folder.create();
      await File(asset.path).writeAsBytes(bytes, flush: true);
      await File(p.join(folder.path, 'asset.json')).writeAsString(
          jsonEncode({
            'name': asset.name,
            'file': filename,
            'width': asset.width,
            'height': asset.height,
            'createdAt': createdAt.toIso8601String(),
          }),
          flush: true);
      return asset;
    } catch (_) {
      if (await folder.exists()) await folder.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> remove(WatermarkAsset asset) async {
    final root = p.normalize(p.absolute((await _root()).path));
    final folder = p.normalize(p.absolute(p.join(root, asset.id)));
    if (p.basename(asset.id) != asset.id || !p.isWithin(root, folder)) {
      throw ArgumentError('Invalid watermark id');
    }
    final directory = Directory(folder);
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
