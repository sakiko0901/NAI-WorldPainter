import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nai_huishi/data/datasources/local/tag_completion_catalog.dart';

class CatalogBundle extends CachingAssetBundle {
  CatalogBundle(this.data, this.manifest);
  final List<int> data;
  final Map<String, dynamic> manifest;
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(
          key.endsWith('.json') ? utf8.encode(jsonEncode(manifest)) : data));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'installs verified bundle, repairs truncation, falls back on bad upgrade',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('tag_install_');
    final source =
        await databaseFactoryFfi.openDatabase('${temp.path}/source.db');
    await source.execute('PRAGMA user_version=1');
    await source.execute('CREATE TABLE tags(name TEXT,translation TEXT)');
    await source.execute('CREATE TABLE terms(term TEXT)');
    await source.execute('CREATE TABLE zh_grams(gram TEXT)');
    await source.close();
    final data = await File('${temp.path}/source.db').readAsBytes();
    final compressed = gzip.encode(data);
    final manifest = <String, dynamic>{
      'version': 'test1',
      'size': data.length,
      'sha256': sha256.convert(data).toString(),
      'compressedSha256': sha256.convert(compressed).toString()
    };
    TagCompletionCatalog catalog = TagCompletionCatalog(
        bundle: CatalogBundle(compressed, manifest),
        supportDirectory: () async => temp);
    try {
      final db = await catalog.open();
      expect(await db.getVersion(), 1);
      expect(await catalog.open(), same(db));
      await catalog.close();
      await File('${temp.path}/tag_completion/catalog-test1.db')
          .writeAsString('broken');
      expect(await (await catalog.open()).getVersion(), 1);
      await catalog.close();
      catalog = TagCompletionCatalog(
          bundle: CatalogBundle(compressed,
              {...manifest, 'version': 'test2', 'sha256': 'invalid'}),
          supportDirectory: () async => temp);
      expect(await (await catalog.open()).getVersion(), 1);
      expect(catalog.metadata!['version'], 'test1');
      expect(
          await File('${temp.path}/tag_completion/catalog-test2.db').exists(),
          false);
    } finally {
      await catalog.close();
      await temp.delete(recursive: true);
    }
  });
}
