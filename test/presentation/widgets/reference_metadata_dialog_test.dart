import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/data/datasources/local/reference_image_importer.dart';
import 'package:nai_huishi/domain/entities/image_tag_result.dart';
import 'package:nai_huishi/presentation/widgets/reference_metadata_dialog.dart';

void main() {
  testWidgets('reference import allows omitting seed while keeping prompt',
      (tester) async {
    final folder = Directory.systemTemp.createTempSync('reference-dialog-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File('${folder.path}/source.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 16, height: 16)));
    Set<String>? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await showDialog<Set<String>>(
                          context: context,
                          builder: (_) => ReferenceMetadataDialog(
                              image: PreparedReferenceImage(
                                  file.path,
                                  16,
                                  16,
                                  const ImageTagResult(
                                      source: TagSource.naiMetadata,
                                      general: [TagEntry(tag: 'silver hair')],
                                      metadata: {'seed': 42}))),
                        );
                      },
                      child: const Text('导入')),
                ))));
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seed'));
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(result, {'prompt'});
    expect(tester.takeException(), isNull);
  });
}
