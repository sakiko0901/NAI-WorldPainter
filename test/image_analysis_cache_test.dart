import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/services/image_analysis_cache.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('analysis-cache-test');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  ImageAnalysisCache cache() =>
      ImageAnalysisCache(directory: () async => directory);
  final key =
      ImageAnalysisCache.key('AQIDBA==', ['vision', 'model', 'purpose']);

  test('persists successful analysis across instances and clears disk',
      () async {
    var calls = 0;
    Future<String> analyze() async {
      calls++;
      return 'description';
    }

    expect(await cache().resolve(key, analyze), 'description');
    expect(await cache().resolve(key, analyze), 'description');
    expect(calls, 1);
    await cache().clear();
    await cache().resolve(key, analyze);
    expect(calls, 2);
  });

  test('image, model, purpose and credentials each invalidate the key', () {
    final original =
        ImageAnalysisCache.key('AQIDBA==', ['model', 'purpose', 'secret']);
    for (final changed in [
      ImageAnalysisCache.key('BQIDBA==', ['model', 'purpose', 'secret']),
      ImageAnalysisCache.key('AQIDBA==', ['other', 'purpose', 'secret']),
      ImageAnalysisCache.key('AQIDBA==', ['model', 'other', 'secret']),
      ImageAnalysisCache.key('AQIDBA==', ['model', 'purpose', 'other']),
    ]) {
      expect(changed, isNot(original));
    }
    expect(original, isNot(contains('secret')));
  });

  test('empty results and failures are retried; corrupt storage recovers',
      () async {
    final file = File('${directory.path}/assistant_wd_tagger_v1.json');
    await file.writeAsString('{broken');
    final subject = cache();
    expect(await subject.resolve(key, () async => ''), '');
    await expectLater(
        subject.resolve(key, () async => throw StateError('offline')),
        throwsStateError);
    expect(await subject.resolve(key, () async => 'recovered'), 'recovered');
    expect(await cache().resolve(key, () async => 'wrong'), 'recovered');
  });

  test('clearing during analysis prevents late result from repopulating cache',
      () async {
    final subject = cache();
    final started = Completer<void>();
    final pending = Completer<String>();
    final result = subject.resolve(key, () {
      started.complete();
      return pending.future;
    });
    await started.future;
    await subject.clear();
    pending.complete('old');
    expect(await result, 'old');
    expect(await subject.resolve(key, () async => 'new'), 'new');
  });

  test('initialization removes legacy LLM cache and temporary file', () async {
    final legacy = File('${directory.path}/assistant_image_analysis_v1.json');
    final temporary = File('${legacy.path}.tmp');
    await legacy.writeAsString('{"old":"LLM description"}');
    await temporary.writeAsString('LLM description');
    await cache().initialize();
    expect(await legacy.exists(), isFalse);
    expect(await temporary.exists(), isFalse);
  });

  test('bounded cache evicts oldest entries', () async {
    final subject = ImageAnalysisCache.memory();
    for (var i = 0; i <= ImageAnalysisCache.maxEntries; i++) {
      await subject.resolve('$i', () async => 'value$i');
    }
    expect(await subject.resolve('0', () async => 'refreshed'), 'refreshed');
  });
}
