import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/data/models/vibe_encoding_model.dart';
import 'package:nai_huishi/domain/entities/vibe_encoding.dart';
import 'package:nai_huishi/domain/repositories/vibe_encoding_repository.dart';

class VibeEncodingRepositoryImpl implements VibeEncodingRepository {
  static const _table = 'vibe_encodings';
  static const _uuid = Uuid();

  final Database _db;

  VibeEncodingRepositoryImpl(this._db);

  @override
  Future<List<VibeEncoding>> getAll() async {
    final rows = await _db.query(_table, orderBy: 'updated_at DESC');
    return rows.map(VibeEncodingModel.fromDb).toList();
  }

  @override
  Future<VibeEncoding?> getById(int id) async {
    final rows = await _db.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : VibeEncodingModel.fromDb(rows.first);
  }

  @override
  Future<VibeEncoding?> findBySourceImagePath(String path) async {
    final rows = await _db.query(
      _table,
      where: 'source_image_path = ?',
      whereArgs: [path],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : VibeEncodingModel.fromDb(rows.first);
  }

  @override
  Future<VibeEncoding> createFromEncoding({
    required String title,
    required String encodedVibe,
    required String sourceImagePath,
    String? encodedModel,
  }) async {
    if (encodedVibe.isEmpty) {
      throw ArgumentError('Vibe 编码不能为空');
    }
    final thumbnailPath = await _createThumbnail(sourceImagePath);
    final now = DateTime.now();
    final value = VibeEncoding(
      title: title.trim().isEmpty ? '未命名氛围' : title.trim(),
      thumbnailPath: thumbnailPath,
      sourceImagePath: sourceImagePath,
      encodedVibe: encodedVibe,
      encodedModel: encodedModel,
      createdAt: now,
      updatedAt: now,
    );
    try {
      final id = await _db.insert(_table, VibeEncodingModel.toDb(value));
      return value.copyWith(id: id);
    } catch (_) {
      await _deleteFileIfExists(thumbnailPath);
      rethrow;
    }
  }

  @override
  Future<List<VibeEncoding>> createManyFromEncodings({
    required String titlePrefix,
    required String sourceImagePath,
    required List<String> encodedVibes,
    String? encodedModel,
  }) async {
    final result = <VibeEncoding>[];
    for (var index = 0; index < encodedVibes.length; index++) {
      result.add(await createFromEncoding(
        title: '$titlePrefix · 氛围编码 ${index + 1}',
        encodedVibe: encodedVibes[index],
        sourceImagePath: sourceImagePath,
        encodedModel: encodedModel,
      ));
    }
    return result;
  }

  @override
  Future<VibeEncoding> updateTitle(VibeEncoding encoding, String title) async {
    final updated = encoding.copyWith(
      title: title.trim().isEmpty ? encoding.title : title.trim(),
      updatedAt: DateTime.now(),
    );
    await _db.update(
      _table,
      VibeEncodingModel.toDb(updated),
      where: 'id = ?',
      whereArgs: [encoding.id],
    );
    return updated;
  }

  @override
  Future<void> delete(int id) async {
    final rows = await _db.query(
      _table,
      columns: ['thumbnail_path'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      await _deleteFileIfExists(rows.first['thumbnail_path'] as String);
    }
  }

  Future<String> _createThumbnail(String sourceImagePath) async {
    final bytes = await File(sourceImagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('图片格式无法读取');
    final resized = decoded.width > 512 || decoded.height > 512
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 512 : null,
            height: decoded.height > decoded.width ? 512 : null,
          )
        : decoded;
    final jpg = img.encodeJpg(resized, quality: 82);
    final directory = await getApplicationDocumentsDirectory();
    final targetDirectory =
        Directory(p.join(directory.path, AppConstants.vibeEncodingsDirName));
    await targetDirectory.create(recursive: true);
    final path = p.join(targetDirectory.path, '${_uuid.v4()}.jpg');
    await File(path).writeAsBytes(jpg);
    return path;
  }

  Future<void> _deleteFileIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
