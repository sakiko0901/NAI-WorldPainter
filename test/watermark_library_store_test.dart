import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/data/datasources/local/watermark_library_store.dart';

void main() {
  late Directory root;
  late Directory sources;

  setUp(() {
    root = Directory.systemTemp.createTempSync('watermark-library-test-');
    sources = Directory.systemTemp.createTempSync('watermark-sources-test-');
  });
  tearDown(() {
    root.deleteSync(recursive: true);
    sources.deleteSync(recursive: true);
  });

  File writeSource(String name) => File('${sources.path}/$name.png')
    ..writeAsBytesSync(
        img.encodePng(img.Image(width: 32, height: 16, numChannels: 4)));

  test('persists independent image copies across store instances', () async {
    final source = writeSource('signature');
    final original = source.readAsBytesSync();
    final store = WatermarkLibraryStore(directory: root);
    final first = await store.importFile(source.path);
    final second = await store.importFile(source.path);
    expect(first.id, isNot(second.id));
    source.deleteSync();
    final reopened = await WatermarkLibraryStore(directory: root).load();
    expect(reopened, hasLength(2));
    expect(reopened.map((asset) => asset.name), everyElement('signature'));
    for (final asset in reopened) {
      expect(File(asset.path).readAsBytesSync(), original);
      expect(asset.width, 32);
      expect(asset.height, 16);
    }
  });

  test('deleting one library image preserves its source and other images',
      () async {
    final source = writeSource('logo');
    final store = WatermarkLibraryStore(directory: root);
    final first = await store.importFile(source.path);
    final second = await store.importFile(source.path);
    await store.remove(first);
    expect(File(first.path).existsSync(), isFalse);
    expect(source.existsSync(), isTrue);
    expect((await store.load()).single.id, second.id);
  });

  test('corrupt imports and incomplete folders do not affect saved watermarks',
      () async {
    final store = WatermarkLibraryStore(directory: root);
    await store.importFile(writeSource('good').path);
    final bad = File('${sources.path}/bad.png')
      ..writeAsStringSync('not an image');
    await expectLater(store.importFile(bad.path), throwsFormatException);
    Directory('${root.path}/interrupted').createSync();
    expect(await store.load(), hasLength(1));
  });
}
