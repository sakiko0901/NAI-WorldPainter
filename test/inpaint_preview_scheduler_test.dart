import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/controllers/inpaint_preview_scheduler.dart';

void main() {
  test('suspended preview can be drained before full-size image work', () {
    fakeAsync((async) {
      final scheduler = InpaintPreviewScheduler();
      final active = Completer<Uint8List>();
      var published = false;
      var drained = false;
      scheduler.schedule('active', () => active.future, (_, __) {
        published = true;
      });
      async.elapse(const Duration(milliseconds: 250));
      scheduler.suspend();
      unawaited(scheduler.settled.then((_) => drained = true));
      async.flushMicrotasks();
      expect(drained, isFalse);
      expect(scheduler.activeCount, 1);
      active.complete(_bytes(1));
      async.flushMicrotasks();
      expect(drained, isTrue);
      expect(published, isFalse);
      expect(scheduler.activeCount, 0);
      scheduler.dispose();
    });
  });

  test('debounces and runs only the latest pending request after active work',
      () {
    fakeAsync((async) {
      final scheduler = InpaintPreviewScheduler();
      final active = Completer<Uint8List>();
      final latest = Completer<Uint8List>();
      final starts = <String>[];
      final results = <String>[];

      scheduler.schedule('active', () {
        starts.add('active');
        return active.future;
      }, (signature, _) => results.add(signature));
      async.elapse(const Duration(milliseconds: 250));

      expect(starts, ['active']);
      expect(scheduler.activeCount, 1);

      scheduler.schedule('replaced', () {
        starts.add('replaced');
        return Future.value(_bytes(2));
      }, (signature, _) => results.add(signature));
      async.elapse(const Duration(milliseconds: 100));
      scheduler.schedule('latest', () {
        starts.add('latest');
        return latest.future;
      }, (signature, _) => results.add(signature));
      async.elapse(const Duration(milliseconds: 250));

      expect(starts, ['active']);
      expect(scheduler.activeCount, 1);
      expect(scheduler.pendingCount, 1);

      active.complete(_bytes(1));
      async.flushMicrotasks();
      expect(starts, ['active', 'latest']);
      expect(results, isEmpty);
      expect(scheduler.activeCount, 1);
      expect(scheduler.pendingCount, 0);

      latest.complete(_bytes(3));
      async.flushMicrotasks();
      expect(results, ['latest']);
      expect(scheduler.activeCount, 0);
      expect(scheduler.pendingCount, 0);
      scheduler.dispose();
    });
  });

  test('invalidation drops old results and new work waits for active Future',
      () {
    fakeAsync((async) {
      final scheduler = InpaintPreviewScheduler();
      final oldWork = Completer<Uint8List>();
      final newWork = Completer<Uint8List>();
      final starts = <String>[];
      final results = <String>[];

      scheduler.schedule('old-source', () {
        starts.add('old-source');
        return oldWork.future;
      }, (signature, _) => results.add(signature));
      async.elapse(const Duration(milliseconds: 250));
      scheduler.invalidate();

      scheduler.schedule('new-source', () {
        starts.add('new-source');
        return newWork.future;
      }, (signature, _) => results.add(signature));
      async.elapse(const Duration(milliseconds: 250));
      expect(starts, ['old-source']);
      expect(scheduler.pendingCount, 1);

      oldWork.complete(_bytes(1));
      async.flushMicrotasks();
      expect(results, isEmpty);
      expect(starts, ['old-source', 'new-source']);

      newWork.complete(_bytes(2));
      async.flushMicrotasks();
      expect(results, ['new-source']);
      expect(scheduler.activeCount, 0);
      scheduler.dispose();
    });
  });

  test('suspend cancels debounce and ignores scheduling until resumed', () {
    fakeAsync((async) {
      final scheduler = InpaintPreviewScheduler();
      final starts = <String>[];
      final results = <String>[];
      Future<Uint8List> work(String signature) async {
        starts.add(signature);
        return _bytes(1);
      }

      scheduler.schedule('before-gesture', () => work('before-gesture'),
          (signature, _) => results.add(signature));
      async.elapse(const Duration(milliseconds: 200));
      scheduler.suspend();
      for (var frame = 0; frame < 20; frame++) {
        scheduler.schedule(
          'gesture-$frame',
          () => work('gesture-$frame'),
          (signature, _) => results.add(signature),
        );
        async.elapse(const Duration(milliseconds: 100));
      }

      expect(scheduler.isSuspended, isTrue);
      expect(starts, isEmpty);
      expect(scheduler.pendingCount, 0);
      expect(results, isEmpty);

      scheduler.resume();
      scheduler.schedule('after-gesture', () => work('after-gesture'),
          (signature, _) => results.add(signature));
      async.elapse(const Duration(milliseconds: 250));
      async.flushMicrotasks();

      expect(starts, ['after-gesture']);
      expect(results, ['after-gesture']);
      scheduler.dispose();
    });
  });

  test('dispose prevents pending work from starting or active work publishing',
      () {
    fakeAsync((async) {
      final scheduler = InpaintPreviewScheduler();
      final active = Completer<Uint8List>();
      final starts = <String>[];
      final results = <String>[];

      scheduler.schedule('active', () {
        starts.add('active');
        return active.future;
      }, (signature, _) => results.add(signature));
      async.elapse(const Duration(milliseconds: 250));
      scheduler.schedule('pending', () {
        starts.add('pending');
        return Future.value(_bytes(2));
      }, (signature, _) => results.add(signature));
      scheduler.dispose();
      async.elapse(const Duration(seconds: 1));

      expect(starts, ['active']);
      expect(scheduler.pendingCount, 0);

      active.complete(_bytes(1));
      async.flushMicrotasks();
      expect(results, isEmpty);
      expect(starts, ['active']);
      expect(scheduler.activeCount, 0);
    });
  });

  test('deduplicates pending, active, and delivered keys; failures can retry',
      () {
    fakeAsync((async) {
      var errorCount = 0;
      final starts = <String>[];
      final results = <String>[];
      final retry = Completer<Uint8List>();
      final scheduler = InpaintPreviewScheduler(
        onError: (_, __, ___) => errorCount++,
      );

      scheduler.schedule('same', () {
        starts.add('same');
        return Future<Uint8List>.error(StateError('preview failed'));
      }, (signature, _) => results.add(signature));
      async.elapse(const Duration(milliseconds: 100));
      scheduler.schedule('same', () {
        starts.add('duplicate-pending');
        return Future.value(_bytes(0));
      }, (signature, _) => results.add(signature));
      async.elapse(const Duration(milliseconds: 150));
      async.flushMicrotasks();

      expect(starts, ['same']);
      expect(errorCount, 1);
      expect(scheduler.activeCount, 0);

      scheduler.schedule('same', () {
        starts.add('retry');
        return retry.future;
      }, (signature, _) => results.add(signature));
      async.elapse(const Duration(milliseconds: 250));
      scheduler.schedule('same', () {
        starts.add('duplicate-active');
        return Future.value(_bytes(9));
      }, (signature, _) => results.add(signature));
      expect(starts, ['same', 'retry']);

      retry.complete(_bytes(2));
      async.flushMicrotasks();
      scheduler.schedule('same', () {
        starts.add('duplicate-delivered');
        return Future.value(_bytes(3));
      }, (signature, _) => results.add(signature));
      async.elapse(const Duration(seconds: 1));

      expect(starts, ['same', 'retry']);
      expect(results, ['same']);
      expect(scheduler.activeCount, 0);
      scheduler.dispose();
    });
  });
}

Uint8List _bytes(int value) => Uint8List.fromList([value]);
