import 'dart:convert';
import 'dart:typed_data';

/// Byte-accurate LSP JSON-RPC frame parser.
///
/// The LSP specification defines `Content-Length` in UTF-8 bytes, not UTF-16
/// code units. Parsing on raw bytes prevents frame desynchronization when
/// responses contain multi-byte UTF-8 characters (e.g. Cyrillic or emoji).
class LspFrameParser {
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  /// Appends incoming stdout bytes and returns all complete JSON-RPC payloads.
  List<String> addBytes(List<int> bytes) {
    if (bytes.isEmpty) return const [];
    _buffer.add(bytes);
    return _drainMessages();
  }

  /// Clears any buffered incomplete bytes.
  void clear() {
    _buffer.clear();
  }

  List<String> _drainMessages() {
    final messages = <String>[];
    final data = _buffer.takeBytes();
    var offset = 0;

    while (offset < data.length) {
      final headerEnd = _indexOfHeaderSeparator(data, offset);
      if (headerEnd == -1) break;

      final headerBytes = Uint8List.sublistView(data, offset, headerEnd);
      final header = ascii.decode(headerBytes, allowInvalid: true);
      final contentLength = _parseContentLength(header);

      final bodyStart = headerEnd + 4;
      if (contentLength == null || contentLength < 0) {
        // Malformed header — skip past separator to recover stream alignment.
        offset = bodyStart;
        continue;
      }

      if (data.length - bodyStart < contentLength) {
        // Wait for the rest of the payload bytes.
        break;
      }

      final bodyBytes = Uint8List.sublistView(
        data,
        bodyStart,
        bodyStart + contentLength,
      );
      messages.add(utf8.decode(bodyBytes, allowMalformed: true));
      offset = bodyStart + contentLength;
    }

    if (offset < data.length) {
      _buffer.add(Uint8List.sublistView(data, offset));
    }

    return messages;
  }

  static int _indexOfHeaderSeparator(Uint8List data, int start) {
    final limit = data.length - 3;
    for (var i = start; i < limit; i++) {
      if (data[i] == 13 &&
          data[i + 1] == 10 &&
          data[i + 2] == 13 &&
          data[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  static int? _parseContentLength(String header) {
    for (final line in header.split('\r\n')) {
      final colonIndex = line.indexOf(':');
      if (colonIndex == -1) continue;
      final name = line.substring(0, colonIndex).trim().toLowerCase();
      if (name == 'content-length') {
        return int.tryParse(line.substring(colonIndex + 1).trim());
      }
    }
    return null;
  }
}
