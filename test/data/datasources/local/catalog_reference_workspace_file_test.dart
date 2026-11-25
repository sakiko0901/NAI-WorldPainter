import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/data/datasources/local/catalog_reference_workspace_file.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the draft keeps one exact JPG after removing the library file',
      () async {
    final root = await Directory.systemTemp.createTemp('reference-workspace-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getApplicationDocumentsDirectory');
      return root.path;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      await root.delete(recursive: true);
    });

    final bytes = image.encodeJpg(image.Image(width: 2, height: 2));
    final source =
        await File(p.join(root.path, 'saved.jpeg')).writeAsBytes(bytes);
    final paths = await Future.wait([
      copyCatalogReferenceToWorkspace(source.path),
      copyCatalogReferenceToWorkspace(source.path),
    ]);

    expect(paths[0], paths[1]);
    expect(paths[0], endsWith('.jpg'));
    final imageDirectory = await ImageUtils.getImageDirectory();
    expect(p.dirname(paths[0]), imageDirectory.path);
    expect(await imageDirectory.list().map((entry) => entry.path).toList(),
        [paths[0]]);

    await source.delete();
    expect(await File(paths[0]).readAsBytes(), bytes);
  });
}
