import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/core/services/lsp/lsp_frame_parser.dart';

List<int> _encodeLspFrame(String payload) {
  final bodyBytes = utf8.encode(payload);
  final headerBytes = ascii.encode('Content-Length: ${bodyBytes.length}\r\n\r\n');
  return [...headerBytes, ...bodyBytes];
}

void main() {
  group('LspFrameParser', () {
    test('parses single complete ASCII frame', () {
      final parser = LspFrameParser();
      const payload = '{"jsonrpc":"2.0","id":1,"result":null}';

      final messages = parser.addBytes(_encodeLspFrame(payload));

      expect(messages, [payload]);
    });

    test('parses multi-byte UTF-8 (Cyrillic & emoji) using byte length', () {
      final parser = LspFrameParser();
      const payload = '{"jsonrpc":"2.0","message":"Привет мир 🚀"}';

      final messages = parser.addBytes(_encodeLspFrame(payload));

      expect(messages, [payload]);
    });

    test('handles split chunks and multiple frames in one buffer', () {
      final parser = LspFrameParser();
      const first = '{"id":1,"text":"Первый"}';
      const second = '{"id":2,"text":"Второй"}';
      final combined = [..._encodeLspFrame(first), ..._encodeLspFrame(second)];

      final splitAt = combined.length ~/ 2;
      expect(parser.addBytes(combined.sublist(0, splitAt)), isEmpty);
      final rest = parser.addBytes(combined.sublist(splitAt));

      expect(rest, [first, second]);
    });

    test('recovers from malformed header without Content-Length', () {
      final parser = LspFrameParser();
      const valid = '{"id":3}';
      final bytes = [
        ...ascii.encode('X-Junk: true\r\n\r\n'),
        ..._encodeLspFrame(valid),
      ];

      expect(parser.addBytes(bytes), [valid]);
    });

    test('clear drops incomplete buffered bytes', () {
      final parser = LspFrameParser();
      final partial = _encodeLspFrame('{"id":4}').sublist(0, 10);
      expect(parser.addBytes(partial), isEmpty);

      parser.clear();
      const fresh = '{"id":5}';
      expect(parser.addBytes(_encodeLspFrame(fresh)), [fresh]);
    });
  });
}
