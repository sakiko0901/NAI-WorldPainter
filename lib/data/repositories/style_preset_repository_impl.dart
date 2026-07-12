import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/data/models/style_preset_model.dart';
import 'package:nai_huishi/domain/entities/style_preset.dart';
import 'package:nai_huishi/domain/repositories/style_preset_repository.dart';

class StylePresetRepositoryImpl implements StylePresetRepository {
  final Database _db;
  static const String _table = 'style_presets';
  static const _uuid = Uuid();

  StylePresetRepositoryImpl(this._db);

  @override
  Future<List<StylePreset>> getAll() async {
    var rows = await _db.query(_table, orderBy: 'updated_at DESC');
    if (rows.isEmpty) {
      await _seedBuiltinPresets();
      rows = await _db.query(_table, orderBy: 'updated_at DESC');
    }
    return rows.map(StylePresetModel.fromDb).toList();
  }

  Future<void> _seedBuiltinPresets() async {
    final jsonStr =
        await rootBundle.loadString('assets/style_presets/style_presets.json');
    final List list = jsonDecode(jsonStr) as List;
    final dir = await getApplicationDocumentsDirectory();
    final targetDir =
        Directory(p.join(dir.path, AppConstants.stylePresetsDirName));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final assetImage = (map['assetImage'] as String?) ?? '';
      String savedPath = '';
      if (assetImage.isNotEmpty) {
        final data = await rootBundle.load(assetImage);
        final bytes = data.buffer.asUint8List();
        final targetPath = p.join(targetDir.path, '${_uuid.v4()}.jpg');
        await File(targetPath).writeAsBytes(bytes);
        savedPath = targetPath;
      }
      final now = DateTime.now();
      final preset = StylePreset(
        title: (map['title'] as String?) ?? '',
        prompt: (map['prompt'] as String?) ?? '',
        imagePath: savedPath,
        createdAt: now,
        updatedAt: now,
      );
      await _db.insert(_table, StylePresetModel.toDb(preset));
    }
  }

  @override
  Future<StylePreset> createFromImage({
    required String title,
    required String prompt,
    required String sourceImagePath,
  }) async {
    final savedPath = await _compressAndSave(sourceImagePath);
    final now = DateTime.now();
    final preset = StylePreset(
      title: title.trim(),
      prompt: prompt.trim(),
      imagePath: savedPath,
      createdAt: now,
      updatedAt: now,
    );
    final id = await _db.insert(_table, StylePresetModel.toDb(preset));
    return preset.copyWith(id: id);
  }

  @override
  Future<StylePreset> update(StylePreset preset) async {
    final updated = preset.copyWith(
      title: preset.title.trim(),
      prompt: preset.prompt.trim(),
      updatedAt: DateTime.now(),
    );
    await _db.update(
      _table,
      StylePresetModel.toDb(updated),
      where: 'id = ?',
      whereArgs: [updated.id],
    );
    return updated;
  }

  @override
  Future<void> delete(int id) async {
    final rows =
        await _db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty) {
      final imagePath = rows.first['image_path'] as String;
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  Future<String> _compressAndSave(String sourceImagePath) async {
    final bytes = await File(sourceImagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('图片格式无法读取');

    final resized =
        decoded.width > 1080 ? img.copyResize(decoded, width: 1080) : decoded;
    final jpg = img.encodeJpg(resized, quality: 82);

    final dir = await getApplicationDocumentsDirectory();
    final targetDir =
        Directory(p.join(dir.path, AppConstants.stylePresetsDirName));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final targetPath = p.join(targetDir.path, '${_uuid.v4()}.jpg');
    await File(targetPath).writeAsBytes(jpg);
    return targetPath;
  }
}
