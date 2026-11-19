import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/data/datasources/remote/official_novelai_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scale in [2, 4]) {
    final operation =
        scale == 2 ? 'two separate 2x operations' : 'one 4x operation';
    test('$operation resubmits the full result and saves the returned size',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('official_upscale');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
      addTearDown(() async {
        messenger.setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      });

      final original = _png(832, 1216);
      final firstResult = _png(1664, 2432);
      final secondResult = _png(2912, 4288);
      final source =
          await File('${directory.path}/source.png').writeAsBytes(original);
      final responses = [firstResult, secondResult].iterator;
      final uploads = <String>[];
      final paths = <String>[];
      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        paths.add(request.path);
        uploads.add((request.data as Map<String, dynamic>)['image'] as String);
        responses.moveNext();
        handler.resolve(Response<List<int>>(
          requestOptions: request,
          data: responses.current,
          statusCode: 200,
        ));
      }));

      final service = OfficialNovelAiApiService(dio);
      final statuses = <String>[];
      var resultPath = await service.upscaleImage(
        imagePath: source.path,
        token: 'test',
        scale: scale,
        onStatus: statuses.add,
      );
      if (scale == 2) {
        resultPath = await service.upscaleImage(
          imagePath: resultPath,
          token: 'test',
          onStatus: statuses.add,
        );
      }

      expect(
          paths, [ApiConstants.officialUpscale, ApiConstants.officialUpscale]);
      expect(uploads, [base64Encode(original), base64Encode(firstResult)]);
      expect(File(resultPath).readAsBytesSync(), secondResult);
      expect(statuses.last, '超分完成：2912×4288');
    });
  }
}

List<int> _png(int width, int height) =>
    img.encodePng(img.Image(width: width, height: height, numChannels: 1));
