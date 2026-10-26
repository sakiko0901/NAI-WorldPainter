import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:path/path.dart' as p;

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _galleryChannel = MethodChannel('image_gallery_saver_plus');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryRoot;
  late File sourceFile;
  late SaveImageUseCase saveImage;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    temporaryRoot =
        await Directory.systemTemp.createTemp('save_image_bytes_test_');
    sourceFile = File(p.join(temporaryRoot.path, 'source.png'));
    saveImage = SaveImageUseCase(_UnusedHistoryRepository());
    messenger.setMockMethodCallHandler(_pathProviderChannel, (call) async {
      expect(call.method, 'getTemporaryDirectory');
      return temporaryRoot.path;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(_galleryChannel, null);
    messenger.setMockMethodCallHandler(_pathProviderChannel, null);
    await temporaryRoot.delete(recursive: true);
  });

  test('copies PNG bytes unchanged to uniquely named PNG files and cleans up',
      () async {
    final image = img.Image(width: 1, height: 1)
      ..addTextData({'Comment': 'embedded metadata must survive'});
    final pngBytes = img.encodePng(image);
    await sourceFile.writeAsBytes(pngBytes, flush: true);

    final savedNames = <String>[];
    final savedBytes = <List<int>>[];
    messenger.setMockMethodCallHandler(_galleryChannel, (call) async {
      expect(call.method, 'saveFileToGallery');
      final arguments = call.arguments as Map<dynamic, dynamic>;
      final exportPath = arguments['file'] as String;
      final galleryName = arguments['name'] as String;
      final exportFile = File(exportPath);

      expect(exportPath, endsWith('.png'));
      expect(galleryName, p.basenameWithoutExtension(exportPath));
      expect(await exportFile.exists(), isTrue);
      expect(p.dirname(p.dirname(exportPath)), temporaryRoot.path);
      savedNames.add(galleryName);
      savedBytes.add(await exportFile.readAsBytes());
      return <String, Object?>{'isSuccess': true};
    });

    final firstResult = await saveImage.savePngBytesToGallery(pngBytes);
    final secondResult = await saveImage.savePngBytesToGallery(pngBytes);

    expect(firstResult, isTrue);
    expect(secondResult, isTrue);
    expect(savedNames, hasLength(2));
    expect(savedNames.toSet(), hasLength(2));
    expect(savedNames.every((name) => !name.endsWith('.png')), isTrue);
    for (final bytes in savedBytes) {
      expect(bytes, orderedEquals(pngBytes));
    }
    await _expectOnlySourceRemains(temporaryRoot, sourceFile, pngBytes);
  });

  test('cleans its temporary PNG when gallery reports failure', () async {
    final pngBytes = _metadataPng();
    await sourceFile.writeAsBytes(pngBytes, flush: true);
    String? exportPath;

    messenger.setMockMethodCallHandler(_galleryChannel, (call) async {
      expect(call.method, 'saveFileToGallery');
      final arguments = call.arguments as Map<dynamic, dynamic>;
      exportPath = arguments['file'] as String;
      expect(await File(exportPath!).readAsBytes(), orderedEquals(pngBytes));
      return <String, Object?>{'isSuccess': false};
    });

    final result = await saveImage.savePngBytesToGallery(pngBytes);

    expect(result, isFalse);
    expect(exportPath, endsWith('.png'));
    await _expectOnlySourceRemains(temporaryRoot, sourceFile, pngBytes);
  });

  test('cleans its temporary PNG when gallery channel throws', () async {
    final pngBytes = _metadataPng();
    await sourceFile.writeAsBytes(pngBytes, flush: true);
    String? exportPath;

    messenger.setMockMethodCallHandler(_galleryChannel, (call) async {
      final arguments = call.arguments as Map<dynamic, dynamic>;
      exportPath = arguments['file'] as String;
      expect(await File(exportPath!).readAsBytes(), orderedEquals(pngBytes));
      throw PlatformException(code: 'mock_gallery_failure');
    });

    await expectLater(
      saveImage.savePngBytesToGallery(pngBytes),
      throwsA(isA<PlatformException>()),
    );

    expect(exportPath, endsWith('.png'));
    await _expectOnlySourceRemains(temporaryRoot, sourceFile, pngBytes);
  });
}

Future<void> _expectOnlySourceRemains(
  Directory temporaryRoot,
  File sourceFile,
  List<int> sourceBytes,
) async {
  expect(await sourceFile.exists(), isTrue);
  expect(await sourceFile.readAsBytes(), orderedEquals(sourceBytes));
  final remaining = await temporaryRoot.list().toList();
  expect(remaining.map((entity) => p.basename(entity.path)), ['source.png']);
}

List<int> _metadataPng() {
  final image = img.Image(width: 1, height: 1)
    ..addTextData({'Comment': 'embedded metadata must survive'});
  return img.encodePng(image);
}

class _UnusedHistoryRepository implements HistoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
