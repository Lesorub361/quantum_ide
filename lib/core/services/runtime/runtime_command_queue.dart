import 'dart:async';

/// Bounded FIFO semaphore limiting concurrent runtime shell invocations.
class RuntimeCommandQueue {
  final int maxConcurrent;
  int _running = 0;
  final List<Completer<void>> _waiters = [];

  RuntimeCommandQueue({this.maxConcurrent = 3});

  int get runningCount => _running;
  int get queuedCount => _waiters.length;

  /// Waits until a command slot is available and marks it as active.
  Future<void> acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
    _running++;
  }

  /// Releases an active command slot and wakes the next queued waiter if any.
  void release() {
    if (_running > 0) {
      _running--;
    }
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    }
  }
}
