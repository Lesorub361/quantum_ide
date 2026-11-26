import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/core/services/crdt_sync_service.dart';

void main() {
  group('VectorClock', () {
    test('increment and merge preserve causal maximums', () {
      final a = VectorClock()..increment('peerA')..increment('peerA');
      final b = VectorClock()..increment('peerB');

      expect(a.concurrentlyWith(b), isTrue);

      a.merge(b);
      expect(a['peerA'], 2);
      expect(a['peerB'], 1);
      expect(a.concurrentlyWith(b), isFalse);
    });

    test('JSON round-trip preserves clock entries', () {
      final original = VectorClock({'p1': 3, 'p2': 7});
      final restored = VectorClock.fromJson(original.toJson());

      expect(restored['p1'], 3);
      expect(restored['p2'], 7);
    });
  });

  group('CrdtDocument', () {
    test('applies insert and delete operations and ignores duplicate ids', () {
      final doc = CrdtDocument(text: 'hello');
      final op1 = CrdtOperation(
        id: 'op-1',
        peerId: 'p1',
        type: 'insert',
        position: 5,
        content: ' world',
        clock: VectorClock({'p1': 1}),
      );

      expect(doc.applyOperation(op1), isTrue);
      expect(doc.text, 'hello world');
      expect(doc.applyOperation(op1), isFalse);

      final op2 = CrdtOperation(
        id: 'op-2',
        peerId: 'p1',
        type: 'delete',
        position: 5,
        length: 6,
        clock: VectorClock({'p1': 2}),
      );
      expect(doc.applyOperation(op2), isTrue);
      expect(doc.text, 'hello');
    });
  });
}
