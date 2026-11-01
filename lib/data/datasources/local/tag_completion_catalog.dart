import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:nai_huishi/domain/entities/tag_completion.dart';

/// Read-only, versioned catalog. Existing versions survive failed upgrades.
class TagCompletionCatalog {
  TagCompletionCatalog(
      {Database? database,
      AssetBundle? bundle,
      Future<Directory> Function()? supportDirectory})
      : _db = database,
        _bundle = bundle ?? rootBundle,
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;
  final AssetBundle _bundle;
  final Future<Directory> Function() _supportDirectory;
  Database? _db;
  Future<Database>? _opening;
  Map<String, dynamic>? metadata;

  Future<Database> open() async {
    if (_db != null) return _db!;
    return _opening ??=
        _install().then((db) => _db = db).whenComplete(() => _opening = null);
  }

  Future<void> repair() async {
    await close();
    _db = await _install(force: true);
  }

  Future<Database> _install({bool force = false}) async {
    final manifest = jsonDecode(
            await _bundle.loadString('assets/tag_completion/manifest.json'))
        as Map<String, dynamic>;
    metadata = manifest;
    final dir =
        Directory(p.join((await _supportDirectory()).path, 'tag_completion'));
    await dir.create(recursive: true);
    final target = p.join(dir.path, 'catalog-${manifest['version']}.db');
    try {
      if (force ||
          !await File(target).exists() ||
          await File(target).length() != manifest['size']) {
        final bytes = await _bundle.load('assets/tag_completion/catalog.db.gz');
        await compute(_unpackCatalog, <String, Object>{
          'bytes': bytes.buffer
              .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          'target': target,
          'hash': manifest['sha256'] as String,
          'compressedHash': manifest['compressedSha256'] as String,
        });
      }
      final db =
          await openDatabase(target, readOnly: true, singleInstance: false);
      try {
        final version = await db.getVersion();
        if (version != 1) {
          throw const FormatException('Unsupported tag catalog');
        }
        await db.rawQuery('SELECT name,translation FROM tags LIMIT 1');
        await db.rawQuery('SELECT term FROM terms LIMIT 1');
        await db.rawQuery('SELECT gram FROM zh_grams LIMIT 1');
        await File('$target.json')
            .writeAsString(jsonEncode(manifest), flush: true);
        await File(p.join(dir.path, 'active.txt'))
            .writeAsString(p.basename(target), flush: true);
        return db;
      } catch (_) {
        await db.close();
        rethrow;
      }
    } catch (_) {
      final active = File(p.join(dir.path, 'active.txt'));
      if (await active.exists()) {
        final name = (await active.readAsString()).trim();
        if (RegExp(r'^catalog-[\w.-]+\.db$').hasMatch(name) &&
            name != p.basename(target)) {
          final oldMetadata = File(p.join(dir.path, '$name.json'));
          metadata = await oldMetadata.exists()
              ? jsonDecode(await oldMetadata.readAsString())
                  as Map<String, dynamic>
              : null;
          return openDatabase(p.join(dir.path, name),
              readOnly: true, singleInstance: false);
        }
      }
      rethrow;
    }
  }

  Future<List<TagCompletion>> search(String query,
      {int limit = 48, bool artistOnly = false}) async {
    final db = await open();
    final q = normalizeCompletionTag(query);
    if (q.isEmpty) return const [];
    final chinese = RegExp(r'[\u3400-\u9fff]').hasMatch(q);
    final category = artistOnly ? 'AND t.category IN (1,8)' : '';
    final List<Map<String, Object?>> rows;
    if (chinese) {
      final gram = q.length > 1 ? q.substring(0, 2) : q;
      rows = await db.rawQuery('''
        SELECT t.*, NULL AS alias, CASE WHEN t.translation=? THEN 0 ELSE 3 END AS rank
        FROM zh_grams g JOIN tags t ON t.id=g.tag_id
        WHERE g.gram=? AND instr(t.translation,?)>0 $category
        ORDER BY rank,t.post_count DESC,t.name LIMIT ?
      ''', [q, gram, q, limit]);
    } else {
      rows = await db.rawQuery('''
        SELECT t.*, CASE WHEN s.kind=1 THEN s.term END AS alias,
          MIN(CASE WHEN s.term=? THEN s.kind ELSE s.kind+3 END) AS rank
        FROM terms s JOIN tags t ON t.id=s.tag_id
        WHERE s.term>=? AND s.term<? $category
        GROUP BY t.id ORDER BY rank,t.post_count DESC,t.name LIMIT ?
      ''', [q, q, '$q\uffff', limit]);
    }
    return rows
        .map((r) => TagCompletion(
            tag: r['name'] as String,
            category: r['category'] as int,
            count: r['post_count'] as int,
            translation: r['translation'] as String,
            alias: r['alias'] as String?,
            match: r['rank'] as int))
        .toList(growable: false);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

// Both decompression and hashing stay off the Flutter UI isolate.
Future<void> _unpackCatalog(Map<String, Object> args) async {
  final compressed = args['bytes'] as Uint8List;
  if (sha256.convert(compressed).toString() != args['compressedHash']) {
    throw const FormatException('Tag archive checksum mismatch');
  }
  final target = args['target'] as String;
  final temp = File('$target.installing');
  final backup = File('$target.previous');
  try {
    await gzip.decoder
        .bind(Stream<List<int>>.value(compressed))
        .pipe(temp.openWrite());
    if ((await sha256.bind(temp.openRead()).first).toString() != args['hash']) {
      throw const FormatException('Tag catalog checksum mismatch');
    }
    if (await backup.exists()) await backup.delete();
    if (await File(target).exists()) await File(target).rename(backup.path);
    try {
      await temp.rename(target);
    } catch (_) {
      if (await backup.exists()) await backup.rename(target);
      rethrow;
    }
    if (await backup.exists()) await backup.delete();
  } finally {
    if (temp.existsSync()) temp.deleteSync();
  }
}
