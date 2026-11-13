import 'dart:async';
import 'package:dio/dio.dart';

class AgentRunControl {
  final cancelToken = CancelToken();
  final _stopped = Completer<void>();
  bool get isStopped => cancelToken.isCancelled;
  void stop() {
    if (isStopped) return;
    cancelToken.cancel('用户停止');
    _stopped.complete();
  }

  void check() {
    if (isStopped) throw const AgentStopped();
  }

  Future<T> wait<T>(Future<T> work) {
    check();
    return Future.any(
        [work, _stopped.future.then<T>((_) => throw const AgentStopped())]);
  }
}

class AgentStopped implements Exception {
  const AgentStopped();
  @override
  String toString() => '已停止';
}
