import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:nai_huishi/core/constants/app_constants.dart';

/// Reclaims expired private image copies before the app opens its workspaces.
class GeneratedImageCleanup {
  GeneratedImageCleanup(
    this._db,
    this._preferences, {
    Future<Directory> Function()? documentsDirectory,
    DateTime Function()? now,
  })  : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory,
        _now = now ?? DateTime.now;

  static const _interval = Duration(days: 1);
  static const _lastCleanupKey = 'generated_image_cleanup_at';
  static const _imageNamePattern =
      r'(?:nai_\d+|inpaint_[a-z0-9_-]+|enhance_\d+|upscale_\d+_x\d+|'
      r'[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12})\.(?:png|jpe?g|webp)';
  static final _managedImage = RegExp(
    '^$_imageNamePattern\$',
    caseSensitive: false,
  );
  static final _imageReference = RegExp(
    r'(?:^|[/\\])' +
        RegExp.escape(AppConstants.imagesDirName) +
        r'[/\\]+(' +
        _imageNamePattern +
        r')(?=$|[^a-z0-9_.-])',
    caseSensitive: false,
  );

  static const _referenceColumns = {
    'generation_history': [
      'image_path',
      'source_image_path',
      'mask_image_path',
      'img2img_source_image_path',
      'characters',
      'vibe_references',
      'precise_references',
    ],
    'presets': ['characters'],
    'llm_messages': ['image_path', 'content', 'tool_calls', 'interaction_json'],
    'comic_projects': ['cover_path', 'last_export_path'],
    'comic_candidates': ['image_path'],
    'artist_prompts': ['image_path'],
    'style_presets': ['image_path'],
    'vibe_encodings': ['thumbnail_path', 'source_image_path'],
  };

  final Database _db;
  final SharedPreferences _preferences;
  final Future<Directory> Function() _documentsDirectory;
  final DateTime Function() _now;

  Future<void> runIfDue() async {
    final now = _now();
    final lastCleanup = _preferences.getInt(_lastCleanupKey);
    if (lastCleanup != null) {
      final elapsed = now.difference(
        DateTime.fromMillisecondsSinceEpoch(lastCleanup),
      );
      if (!elapsed.isNegative && elapsed < _interval) return;
    }

    final documents = await _documentsDirectory();
    final images =
        Directory(p.join(documents.path, AppConstants.imagesDirName));
    if (await _isDirectory(images)) {
      final cutoff = now.subtract(_interval);
      final expired = <File>[];
      await for (final entry in images.list(followLinks: false)) {
        if (entry is! File || !_managedImage.hasMatch(p.basename(entry.path))) {
          continue;
        }
        final stat = await entry.stat();
        if (stat.type == FileSystemEntityType.file &&
            stat.modified.isBefore(cutoff)) {
          expired.add(entry);
        }
      }

      if (expired.isNotEmpty) {
        final protected = await _loadReferencedNames(documents);
        for (final image in expired) {
          if (!protected.contains(p.basename(image.path).toLowerCase())) {
            await image.delete();
          }
        }
      }
    }
    await _preferences.setInt(_lastCleanupKey, now.millisecondsSinceEpoch);
  }

  Future<Set<String>> _loadReferencedNames(Directory documents) async {
    final names = <String>{};
    for (final table in _referenceColumns.entries) {
      for (final column in table.value) {
        // Return only a short window around each path so even legacy chat
        // payloads larger than Android's CursorWindow can be checked.
        final cursor = await _db.rawQueryCursor(
          '''
          WITH RECURSIVE refs(value, position) AS (
            SELECT "$column", instr("$column", ?1)
            FROM "${table.key}" WHERE instr("$column", ?1) > 0
            UNION ALL
            SELECT substr(value, position + length(?1)),
                   instr(substr(value, position + length(?1)), ?1)
            FROM refs WHERE position > 0
          )
          SELECT substr(value, max(1, position - 1), 512) AS path
          FROM refs WHERE position > 0
          ''',
          [AppConstants.imagesDirName],
        );
        try {
          while (await cursor.moveNext()) {
            _addNames(names, cursor.current['path'] as String);
          }
        } finally {
          await cursor.close();
        }
      }
    }

    for (final key in _preferences.getKeys()) {
      final value = _preferences.get(key);
      if (value is String) _addNames(names, value);
      if (value is List<String>) {
        for (final item in value) {
          _addNames(names, item);
        }
      }
    }

    final comics = Directory(
      p.join(documents.path, AppConstants.comicProjectsDirName),
    );
    if (await _isDirectory(comics)) {
      await for (final entry in comics.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is File && p.extension(entry.path) == '.json') {
          _addNames(names, await entry.readAsString());
        }
      }
    }
    return names;
  }

  static void _addNames(Set<String> names, String value) {
    for (final match in _imageReference.allMatches(value)) {
      names.add(match.group(1)!.toLowerCase());
    }
  }

  static Future<bool> _isDirectory(Directory directory) async =>
      await FileSystemEntity.type(directory.path, followLinks: false) ==
      FileSystemEntityType.directory;
}
