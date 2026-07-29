import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class AgentToolOutputStore {
  static const int maxLines = 2000;
  static const int maxBytes = 50 * 1024;
  static const Duration retention = Duration(days: 7);
  static const String managedDirectory = 'tool_output';

  Future<String> bound(String sessionId, String toolCallId, String output) async {
    final lines = output.split('\n');
    if (lines.length <= maxLines && output.length <= maxBytes) {
      return output;
    }

    final dir = Directory(p.join(Directory.systemTemp.path, 'quantum_ide', managedDirectory));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'tool_${toolCallId}_$sessionId'));
    await file.writeAsString(output);

    final marker = '... output truncated; full content saved to ${file.path} ...';
    final bounded = _boundedPreview(output, marker, maxLines, maxBytes);
    return bounded;
  }

  Future<void> cleanup() async {
    try {
      final dir = Directory(p.join(Directory.systemTemp.path, 'quantum_ide', managedDirectory));
      if (!await dir.exists()) return;
      final cutoff = DateTime.now().subtract(retention);
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains('/tool_')) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }

  String _boundedPreview(String text, String marker, int maxLines, int maxBytes) {
    final lines = text.split('\n');
    if (lines.length <= maxLines && text.length <= maxBytes) return text;

    final headLines = maxLines ~/ 2;
    final tailLines = maxLines - headLines;
    final head = lines.take(headLines).join('\n');
    final tail = tailLines > 0 ? lines.skip(lines.length - tailLines).join('\n') : '';
    final sampled = tail.isEmpty ? head : '$head\n\n$marker\n\n$tail';

    if (sampled.length <= maxBytes) return sampled;
    final headBytes = maxBytes ~/ 2;
    final tailBytes = maxBytes - headBytes;
    final headPart = _takePrefix(sampled, headBytes);
    final tailPart = _takeSuffix(sampled, tailBytes);
    return '$headPart\n\n$marker\n\n$tailPart';
  }

  String _takePrefix(String input, int maxBytes) {
    int bytes = 0;
    String content = '';
    for (final codeUnit in input.codeUnits) {
      final size = utf8.encode(String.fromCharCode(codeUnit)).length;
      if (bytes + size > maxBytes) break;
      content += String.fromCharCode(codeUnit);
      bytes += size;
    }
    return content;
  }

  String _takeSuffix(String input, int maxBytes) {
    final reversed = input.codeUnits.reversed.toList();
    int bytes = 0;
    final content = <int>[];
    for (final codeUnit in reversed) {
      final size = utf8.encode(String.fromCharCode(codeUnit)).length;
      if (bytes + size > maxBytes) break;
      content.insert(0, codeUnit);
      bytes += size;
    }
    return String.fromCharCodes(content);
  }
}
