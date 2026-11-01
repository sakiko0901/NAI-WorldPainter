import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nai_huishi/data/datasources/local/tag_completion_catalog.dart';

void main() {
  late Directory temp;
  late TagCompletionCatalog catalog;
  late Database db;
  late Map<String, dynamic> manifest;
  setUpAll(() async {
    sqfliteFfiInit();
    temp = await Directory.systemTemp.createTemp('completion_test_');
    final data = gzip.decode(
        await File('assets/tag_completion/catalog.db.gz').readAsBytes());
    manifest = jsonDecode(
            await File('assets/tag_completion/manifest.json').readAsString())
        as Map<String, dynamic>;
    expect(sha256.convert(data).toString(), manifest['sha256']);
    final file = await File('${temp.path}/catalog.db').writeAsBytes(data);
    db = await databaseFactoryFfi.openDatabase(file.path,
        options: OpenDatabaseOptions(readOnly: true));
    catalog = TagCompletionCatalog(database: db);
  });
  tearDownAll(() async {
    await catalog.close();
    await temp.delete(recursive: true);
  });

  test('complete bundled catalog has all records and working indexes',
      () async {
    expect((await db.rawQuery('SELECT COUNT(*) n FROM tags')).single['n'],
        manifest['tags']);
    expect(
        (await db.rawQuery('SELECT COUNT(*) n FROM terms WHERE kind=1'))
            .single['n'],
        manifest['aliases']);
    expect(
        (await db.rawQuery("SELECT COUNT(*) n FROM tags WHERE translation<>''"))
            .single['n'],
        manifest['translations']);
    expect((await db.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok');
    expect(
        (await db.rawQuery(
                "EXPLAIN QUERY PLAN SELECT * FROM terms WHERE term>='blue' AND term<'bluez'"))
            .any((r) => r['detail'].toString().contains('SEARCH')),
        true);
  });
  test('English, Chinese, aliases, punctuation and artist filter', () async {
    expect((await catalog.search('blue hair')).first.tag, 'blue_hair');
    expect((await catalog.search('蓝发')).any((t) => t.tag == 'blue_hair'), true);
    final alias = (await db.rawQuery(
            'SELECT s.term,t.name FROM terms s JOIN tags t ON t.id=s.tag_id WHERE s.kind=1 ORDER BY t.post_count DESC LIMIT 1'))
        .single;
    expect(
        (await catalog.search(alias['term'] as String))
            .any((t) => t.tag == alias['name']),
        true);
    expect((await catalog.search(':3')).any((t) => t.tag == ':3'), true);
    final artists = await catalog.search('a', artistOnly: true);
    expect(artists, isNotEmpty);
    expect(artists.every((t) => t.category == 1 || t.category == 8), true);
    expect(await catalog.search("' OR 1=1 --"), isEmpty);
  });
  test('queries stay bounded and can find low popularity records', () async {
    final rare = (await db
            .rawQuery('SELECT name FROM tags ORDER BY post_count,name LIMIT 1'))
        .single['name'] as String;
    expect((await catalog.search(rare)).first.tag, rare);
    final watch = Stopwatch()..start();
    for (final query in [
      'bl',
      'hair',
      '蓝',
      '长发',
      'hatsune miku',
      'white shirt'
    ]) {
      expect((await catalog.search(query)).length, lessThanOrEqualTo(48));
    }
    // A generous ceiling catches accidental full catalog loading/quadratic scans.
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}
