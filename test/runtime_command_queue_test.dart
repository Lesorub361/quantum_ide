import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/core/services/runtime/runtime_command_queue.dart';

void main() {
  group('RuntimeCommandQueue', () {
    test('enforces maxConcurrent limit and wakes waiters in FIFO order', () async {
      final queue = RuntimeCommandQueue(maxConcurrent: 2);

      await queue.acquire();
      await queue.acquire();
      expect(queue.runningCount, 2);
      expect(queue.queuedCount, 0);

      final order = <int>[];
      final third = queue.acquire().then((_) => order.add(3));
      final fourth = queue.acquire().then((_) => order.add(4));
      await Future<void>.delayed(Duration.zero);

      expect(queue.runningCount, 2);
      expect(queue.queuedCount, 2);

      queue.release();
      await third;
      expect(queue.runningCount, 2);
      expect(queue.queuedCount, 1);

      queue.release();
      await fourth;
      expect(order, [3, 4]);

      queue.release();
      queue.release();
      expect(queue.runningCount, 0);
    });
  });
}
