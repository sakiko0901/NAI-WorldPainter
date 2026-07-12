import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nai_huishi/data/models/artist_prompt_model.dart';
import 'package:nai_huishi/domain/entities/artist_prompt.dart';
import 'package:nai_huishi/domain/repositories/artist_prompt_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class ArtistPromptRepositoryImpl implements ArtistPromptRepository {
  final Database _db;
  static const String _artistsTable = 'artist_prompts';
  static const String _categoriesTable = 'artist_prompt_categories';
  static const String _assetJson = 'assets/artist_prompts/artist_prompts.json';

  ArtistPromptRepositoryImpl(this._db);

  @override
  Future<List<ArtistPrompt>> getAll() async {
    var rows = await _db.query(_artistsTable, orderBy: 'updated_at DESC');
    if (rows.isEmpty) {
      await _seedBuiltinArtists();
      rows = await _db.query(_artistsTable, orderBy: 'updated_at DESC');
    }
    return rows.map(ArtistPromptModel.fromDb).toList();
  }

  @override
  Future<List<String>> getCategories() async {
    final rows =
        await _db.query(_categoriesTable, orderBy: 'name COLLATE NOCASE ASC');
    final categories = rows.map((row) => row['name'] as String).toList();
    return categories.isEmpty
        ? ['二次元', '厚涂', '写实', '水墨', '黑白', 'R18']
        : categories;
  }

  @override
  Future<ArtistPrompt> create({
    required String name,
    required String tag,
    required String imagePath,
    required List<String> categories,
    required int danbooruCount,
  }) async {
    final now = DateTime.now();
    final normalizedCategories = _normalizeCategories(categories);
    final artist = ArtistPrompt(
      name: name.trim().isEmpty ? tag.trim() : name.trim(),
      tag: tag.trim(),
      imagePath: imagePath.trim(),
      categories: normalizedCategories,
      danbooruCount: danbooruCount,
      createdAt: now,
      updatedAt: now,
    );
    final id = await _db.insert(_artistsTable, ArtistPromptModel.toDb(artist));
    await _ensureCategories(normalizedCategories);
    return artist.copyWith(id: id);
  }

  @override
  Future<ArtistPrompt> update(ArtistPrompt artist) async {
    final normalizedCategories = _normalizeCategories(artist.categories);
    final updated = artist.copyWith(
      name: artist.name.trim().isEmpty ? artist.tag.trim() : artist.name.trim(),
      tag: artist.tag.trim(),
      imagePath: artist.imagePath.trim(),
      categories: normalizedCategories,
      updatedAt: DateTime.now(),
    );
    await _db.update(
      _artistsTable,
      ArtistPromptModel.toDb(updated),
      where: 'id = ?',
      whereArgs: [updated.id],
    );
    await _ensureCategories(normalizedCategories);
    return updated;
  }

  @override
  Future<void> delete(int id) =>
      _db.delete(_artistsTable, where: 'id = ?', whereArgs: [id]);

  @override
  Future<void> addCategory(String category) async {
    final name = category.trim();
    if (name.isEmpty || name == '全部' || name == '未分类') return;
    await _db.insert(
      _categoriesTable,
      {'name': name, 'created_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> deleteCategory(String category) async {
    final name = category.trim();
    if (name.isEmpty || name == '未分类') return;
    await _db.delete(_categoriesTable, where: 'name = ?', whereArgs: [name]);
    final artists = await getAll();
    for (final artist in artists) {
      if (!artist.categories.contains(name)) continue;
      final nextCategories = artist.categories.where((c) => c != name).toList();
      await update(artist.copyWith(
          categories: nextCategories.isEmpty ? ['未分类'] : nextCategories));
    }
  }

  @override
  Future<Map<String, dynamic>> exportData() async {
    final artists = await getAll();
    final categories = await getCategories();
    return {
      'version': 12,
      'artists': artists
          .map((artist) => {
                'id': artist.id,
                'name': artist.name,
                'tag': artist.tag,
                'imageUrl': artist.imagePath,
                'categories': artist.categories,
                'danbooruCount': artist.danbooruCount,
                'createdAt': artist.createdAt.millisecondsSinceEpoch,
              })
          .toList(),
      'categories': categories,
      'presets': const [],
    };
  }

  @override
  Future<int> importData(Map<String, dynamic> data) async {
    final rawArtists = data['artists'];
    final list = rawArtists is List ? rawArtists : const [];
    final existing = await getAll();
    final existingTags =
        existing.map((artist) => artist.tag.toLowerCase()).toSet();
    var added = 0;

    final rawCategories = data['categories'];
    if (rawCategories is List) {
      for (final category in rawCategories) {
        await addCategory(category.toString());
      }
    }

    for (final item in list) {
      if (item is! Map) continue;
      final tag = (item['tag'] ?? item['prompt'] ?? item['name'] ?? '')
          .toString()
          .trim();
      if (tag.isEmpty || existingTags.contains(tag.toLowerCase())) continue;
      final name = (item['name'] ?? tag).toString().trim();
      final imagePath =
          (item['imagePath'] ?? item['imageUrl'] ?? item['image'] ?? '')
              .toString();
      final categories = _readCategories(item);
      final count =
          int.tryParse((item['danbooruCount'] ?? '0').toString()) ?? 0;
      await create(
        name: name,
        tag: tag,
        imagePath: imagePath,
        categories: categories,
        danbooruCount: count,
      );
      existingTags.add(tag.toLowerCase());
      added++;
    }
    return added;
  }

  Future<void> _seedBuiltinArtists() async {
    final raw = await rootBundle.loadString(_assetJson);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final artists = data['artists'];
    if (artists is! List || artists.isEmpty) return;

    final dir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(p.join(dir.path, 'artist_prompts'));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    for (final item in artists) {
      if (item is! Map) continue;
      final tag = (item['tag'] ?? item['name'] ?? '').toString().trim();
      if (tag.isEmpty) continue;

      var imagePath = '';
      final assetImage = (item['assetImage'] ?? '').toString();
      if (assetImage.isNotEmpty) {
        final data = await rootBundle.load(assetImage);
        final fileName = p.basename(assetImage);
        final targetPath = p.join(targetDir.path, fileName);
        final targetFile = File(targetPath);
        if (!await targetFile.exists()) {
          await targetFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
        }
        imagePath = targetPath;
      }

      final createdAtMs = int.tryParse((item['createdAt'] ?? '').toString());
      final createdAt = createdAtMs == null || createdAtMs <= 0
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(createdAtMs);
      final categories = _readCategories(item);
      await _ensureCategories(categories);
      await _db.insert(
        _artistsTable,
        ArtistPromptModel.toDb(ArtistPrompt(
          name: (item['name'] ?? tag).toString().trim(),
          tag: tag,
          imagePath: imagePath,
          categories: categories,
          danbooruCount:
              int.tryParse((item['danbooruCount'] ?? '0').toString()) ?? 0,
          createdAt: createdAt,
          updatedAt: createdAt,
        )),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  List<String> _readCategories(Map item) {
    final rawCategories = item['categories'];
    if (rawCategories is List) {
      return _normalizeCategories(
          rawCategories.map((e) => e.toString()).toList());
    }
    final category = item['category']?.toString();
    return _normalizeCategories(
        category == null || category.isEmpty ? const [] : [category]);
  }

  List<String> _normalizeCategories(List<String> categories) {
    final result = categories
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != '全部')
        .toSet()
        .toList();
    return result.isEmpty ? ['未分类'] : result;
  }

  Future<void> _ensureCategories(List<String> categories) async {
    for (final category in categories) {
      await addCategory(category);
    }
  }
}
