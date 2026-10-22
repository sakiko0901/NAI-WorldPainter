import 'dart:async';
import 'dart:typed_data';

typedef InpaintPreviewWork = Future<Uint8List> Function();
typedef InpaintPreviewResultCallback = void Function(
  String signature,
  Uint8List bytes,
);
typedef InpaintPreviewErrorCallback = void Function(
  String signature,
  Object error,
  StackTrace stackTrace,
);

/// Debounces preview requests and allows at most one worker to run at a time.
///
/// A running Future cannot be cancelled. Invalidating a request therefore
/// suppresses its result while keeping the worker slot occupied until it ends.
class InpaintPreviewScheduler {
  InpaintPreviewScheduler({
    this.debounce = const Duration(milliseconds: 250),
    this.onError,
  });

  final Duration debounce;
  final InpaintPreviewErrorCallback? onError;

  Timer? _timer;
  _PreviewRequest? _pending;
  _PreviewRequest? _active;
  bool _pendingReady = false;
  bool _suspended = false;
  bool _disposed = false;
  int _epoch = 0;
  String? _desiredSignature;
  String? _lastDeliveredSignature;
  Future<void> _inFlight = Future<void>.value();

  /// Read-only diagnostics intended for tests and lightweight instrumentation.
  int get activeCount => _active == null ? 0 : 1;
  int get pendingCount => _pending == null ? 0 : 1;
  bool get isSuspended => _suspended;
  bool get isDisposed => _disposed;

  /// Suspend first to prevent new work, then await this before a full-size
  /// generation/source decode that must not overlap a preview worker.
  Future<void> get settled => _inFlight;

  /// Schedules the latest preview request after [debounce].
  ///
  /// [lazyWork] is called only when the debounce has elapsed and no other
  /// worker is active. Requests with an identical pending, active, or
  /// successfully delivered signature are deduplicated.
  void schedule(
    String signature,
    InpaintPreviewWork lazyWork,
    InpaintPreviewResultCallback onResult,
  ) {
    if (_disposed || _suspended) return;

    if (_lastDeliveredSignature == signature) {
      _desiredSignature = signature;
      _clearPending();
      return;
    }

    final active = _active;
    if (active != null &&
        active.epoch == _epoch &&
        active.signature == signature) {
      // The workspace returned to the state already being computed. Let that
      // worker satisfy the request and discard any newer pending snapshot.
      _desiredSignature = signature;
      _clearPending();
      return;
    }

    final pending = _pending;
    if (pending != null &&
        pending.epoch == _epoch &&
        pending.signature == signature) {
      return;
    }

    _desiredSignature = signature;
    _pending = _PreviewRequest(
      signature: signature,
      epoch: _epoch,
      lazyWork: lazyWork,
      onResult: onResult,
    );
    _pendingReady = false;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      if (_disposed || _suspended || _pending == null) return;
      _pendingReady = true;
      _pump();
    });
  }

  /// Invalidates pending work and prevents the active request from publishing.
  /// A later request must still wait for that active Future to finish.
  void invalidate() {
    if (_disposed) return;
    _epoch++;
    _desiredSignature = null;
    _lastDeliveredSignature = null;
    _clearPending();
  }

  /// Suppresses scheduling during a gesture or while the source is changing.
  void suspend() {
    if (_disposed) return;
    _suspended = true;
    invalidate();
  }

  /// Allows scheduling again. The caller should submit the current snapshot.
  void resume() {
    if (_disposed) return;
    _suspended = false;
  }

  /// Stops future work and drops callbacks. An active Future is allowed to end.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _desiredSignature = null;
    _lastDeliveredSignature = null;
    _clearPending();
  }

  void _clearPending() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _pendingReady = false;
  }

  void _pump() {
    if (_disposed || _suspended || _active != null || !_pendingReady) {
      return;
    }

    final request = _pending;
    if (request == null) return;
    if (request.epoch != _epoch || request.signature != _desiredSignature) {
      _clearPending();
      return;
    }

    _pending = null;
    _pendingReady = false;
    _active = request;
    _inFlight = _run(request);
    unawaited(_inFlight);
  }

  Future<void> _run(_PreviewRequest request) async {
    try {
      final bytes = await request.lazyWork();
      if (_canPublish(request)) {
        request.onResult(request.signature, bytes);
        if (_canPublish(request)) {
          _lastDeliveredSignature = request.signature;
        }
      }
    } catch (error, stackTrace) {
      if (_canPublish(request)) {
        try {
          onError?.call(request.signature, error, stackTrace);
        } catch (_) {
          // A diagnostic callback must not leave the single-worker gate stuck.
        }
      }
    } finally {
      if (identical(_active, request)) _active = null;
      _pump();
    }
  }

  bool _canPublish(_PreviewRequest request) =>
      !_disposed &&
      !_suspended &&
      request.epoch == _epoch &&
      request.signature == _desiredSignature;
}

class _PreviewRequest {
  const _PreviewRequest({
    required this.signature,
    required this.epoch,
    required this.lazyWork,
    required this.onResult,
  });

  final String signature;
  final int epoch;
  final InpaintPreviewWork lazyWork;
  final InpaintPreviewResultCallback onResult;
}
