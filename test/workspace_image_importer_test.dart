import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/data/datasources/local/workspace_image_importer.dart';

void main() {
  late Directory folder;
  setUp(
      () => folder = Directory.systemTemp.createTempSync('workspace-import-'));
  tearDown(() => folder.deleteSync(recursive: true));

  test('plain imported image records actual size without inventing seed',
      () async {
    final file = File('${folder.path}/image.png');
    await file.writeAsBytes(img.encodePng(img.Image(width: 31, height: 17)));
    final image = await WorkspaceImageImporter.read(file.path);
    expect(image.width, 31);
    expect(image.height, 17);
    expect(image.seed, isNull);
    expect(image.prompt, isEmpty);
    expect(image.status, 'success');
    expect(image.imagePath, file.path);
  });

  test('PNG metadata belongs to imported image, not current draft', () async {
    final image = img.Image(width: 17, height: 31);
    image.textData = {
      'Software': 'NovelAI',
      'Description': 'silver hair',
      'Comment': jsonEncode(
          {'prompt': 'silver hair', 'seed': 42, 'width': 832, 'height': 1216}),
    };
    final file = File('${folder.path}/metadata.png');
    await file.writeAsBytes(img.encodePng(image));
    final task = await WorkspaceImageImporter.read(file.path);
    expect(task.width, 17);
    expect(task.height, 31);
    expect(task.seed, 42);
    expect(task.prompt, 'silver hair');
  });

  test('invalid file is rejected', () async {
    final file = File('${folder.path}/invalid.png');
    await file.writeAsBytes([1, 2, 3]);
    await expectLater(
        WorkspaceImageImporter.read(file.path), throwsFormatException);
  });

  test('large PNG retains full dimensions and text metadata', () async {
    final image = img.Image(width: 4096, height: 1025);
    image.textData = {
      'Software': 'NovelAI',
      'Comment': jsonEncode({'seed': 73})
    };
    final file = File('${folder.path}/large.png');
    await file.writeAsBytes(img.encodePng(image));
    final task = await WorkspaceImageImporter.read(file.path);
    expect(task.width, 4096);
    expect(task.height, 1025);
    expect(task.seed, 73);
  });

  test('rotated JPEG reports the displayed orientation', () async {
    final image = img.Image(width: 17, height: 31);
    image.exif.imageIfd.orientation = 6;
    final file = File('${folder.path}/rotated.jpg');
    await file.writeAsBytes(img.encodeJpg(image));
    final task = await WorkspaceImageImporter.read(file.path);
    expect(task.width, 31);
    expect(task.height, 17);
    expect(task.seed, isNull);
  });
}
