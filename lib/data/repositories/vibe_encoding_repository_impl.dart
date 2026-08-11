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
  static const _encodingChunkSize = 128 * 1024;
  static const _metadataColumns = <String>[
    'id',
    'title',
    'thumbnail_path',
    'source_image_path',
    'encoded_vibe_path',
    'encoded_model',
    'created_at',
    'updated_at',
  ];

  final Database _db;
  Future<void>? _migration;

  VibeEncodingRepositoryImpl(this._db);

  @override
  Future<List<VibeEncoding>> getAll() async {
    await _migrateLegacyEncodings();
    final rows = await _db.query(
      _table,
      columns: _metadataColumns,
      orderBy: 'updated_at DESC',
    );
    return rows.map(VibeEncodingModel.fromDb).toList();
  }

  @override
  Future<VibeEncoding?> getById(int id) async {
    await _migrateLegacyEncodings();
    final rows = await _db.query(
      _table,
      columns: _metadataColumns,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : _withEncodedVibe(VibeEncodingModel.fromDb(rows.first));
  }

  @override
  Future<VibeEncoding?> findBySourceImagePath(String path) async {
    await _migrateLegacyEncodings();
    final rows = await _db.query(
      _table,
      columns: _metadataColumns,
      where: 'source_image_path = ?',
      whereArgs: [path],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : _withEncodedVibe(VibeEncodingModel.fromDb(rows.first));
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
    String? encodedVibePath;
    try {
      encodedVibePath = await _writeEncodedVibe(encodedVibe);
      final now = DateTime.now();
      final value = VibeEncoding(
        title: title.trim().isEmpty ? '未命名氛围' : title.trim(),
        thumbnailPath: thumbnailPath,
        sourceImagePath: sourceImagePath,
        encodedVibePath: encodedVibePath,
        encodedModel: encodedModel,
        createdAt: now,
        updatedAt: now,
      );
      final id = await _db.insert(_table, VibeEncodingModel.toDb(value));
      return value.copyWith(id: id, encodedVibe: encodedVibe);
    } catch (_) {
      await _deleteFileIfExists(thumbnailPath);
      if (encodedVibePath != null) {
        await _deleteFileIfExists(encodedVibePath);
      }
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
    await _migrateLegacyEncodings();
    final rows = await _db.query(
      _table,
      columns: ['thumbnail_path', 'encoded_vibe_path'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      await _deleteFileIfExists(rows.first['thumbnail_path'] as String);
      final encodedPath = rows.first['encoded_vibe_path'] as String?;
      if (encodedPath != null) await _deleteFileIfExists(encodedPath);
    }
  }

  Future<VibeEncoding> _withEncodedVibe(VibeEncoding value) async {
    final path = value.encodedVibePath;
    if (path == null || path.isEmpty || !await File(path).exists()) {
      throw StateError('已保存的氛围编码文件不可用，请重新选择原图编码');
    }
    return value.copyWith(encodedVibe: await File(path).readAsString());
  }

  Future<void> _migrateLegacyEncodings() async {
    final migration = _migration ??= _migrateLegacyEncodingsInner();
    try {
      await migration;
    } catch (_) {
      if (identical(_migration, migration)) _migration = null;
      rethrow;
    }
  }

  Future<void> _migrateLegacyEncodingsInner() async {
    final rows = await _db.query(
      _table,
      columns: ['id'],
      where: "encoded_vibe_path IS NULL OR encoded_vibe_path = ''",
    );
    for (final row in rows) {
      final id = row['id'] as int;
      final lengthRow = await _db.rawQuery(
        'SELECT length(encoded_vibe) AS value FROM $_table WHERE id = ?',
        [id],
      );
      final length = lengthRow.single['value'] as int? ?? 0;
      if (length == 0) continue;

      final buffer = StringBuffer();
      for (var offset = 1; offset <= length; offset += _encodingChunkSize) {
        final chunk = await _db.rawQuery(
          'SELECT substr(encoded_vibe, ?, ?) AS value FROM $_table WHERE id = ?',
          [offset, _encodingChunkSize, id],
        );
        buffer.write(chunk.single['value'] as String? ?? '');
      }
      final encodedVibe = buffer.toString();
      if (encodedVibe.length != length) {
        throw StateError('迁移氛围编码失败：编码长度不一致');
      }
      final path = await _writeEncodedVibe(encodedVibe);
      await _db.update(
        _table,
        {'encoded_vibe': '', 'encoded_vibe_path': path},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<String> _writeEncodedVibe(String encodedVibe) async {
    final directory = await _vibeDirectory();
    final path = p.join(directory.path, '${_uuid.v4()}.vibe');
    await File(path).writeAsString(encodedVibe, flush: true);
    return path;
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
    final directory = await _vibeDirectory();
    final path = p.join(directory.path, '${_uuid.v4()}.jpg');
    await File(path).writeAsBytes(jpg);
    return path;
  }

  Future<Directory> _vibeDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final targetDirectory =
        Directory(p.join(directory.path, AppConstants.vibeEncodingsDirName));
    await targetDirectory.create(recursive: true);
    return targetDirectory;
  }

  Future<void> _deleteFileIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
