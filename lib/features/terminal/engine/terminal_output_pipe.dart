import 'dart:async';
import 'dart:convert';

/// Decodes raw PTY bytes into text and delivers it to the terminal in
/// frame-sized batches.
///
/// Why this exists:
///  * Cyrillic (and any non-ASCII) characters are multi-byte in UTF-8. When a
///    chunk ends in the middle of a character a naive decoder emits U+FFFD or
///    duplicates bytes. A chunked [Utf8Decoder] converter keeps the tail.
///  * Writing every tiny chunk straight into xterm triggers a repaint each
///    time, which shows up as flicker / "doubled" text during fast streaming
///    output (AI CLI answers, gradle logs). We coalesce data to ~1 frame.
class TerminalOutputPipe {
  TerminalOutputPipe({
    required this.onText,
    this.flushInterval = const Duration(milliseconds: 16),
    this.maxBatchChars = 64 * 1024,
  }) {
    _sink = const Utf8Decoder(allowMalformed: true).startChunkedConversion(
      _StringSink(_append),
    );
  }

  final void Function(String text) onText;
  final Duration flushInterval;
  final int maxBatchChars;

  late final Sink<List<int>> _sink;
  final StringBuffer _buffer = StringBuffer();
  int _length = 0;
  Timer? _timer;
  bool _closed = false;

  void add(List<int> bytes) {
    if (_closed) return;
    _sink.add(bytes);
  }

  void _append(String s) {
    if (s.isEmpty) return;
    _buffer.write(s);
    _length += s.length;
    if (_length >= maxBatchChars) {
      flush();
      return;
    }
    _timer ??= Timer(flushInterval, flush);
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_length == 0) return;
    final text = _buffer.toString();
    _buffer.clear();
    _length = 0;
    onText(_safeBoundary(text));
  }

  String _pending = '';

  /// Never split an escape sequence or a surrogate pair between two writes,
  /// and strip OSC 8 hyperlink wrappers / DEC 2026 sync markers that cause
  /// xterm.dart parser glitches and duplicated words in TUI apps (Claude Code).
  static final RegExp _completeEscRegex = RegExp(
    r'^\x1b(\[[0-9;?<=>!]*[ -/]*[@-~]|\][^\x07\x1b]*(\x07|\x1b\\)|[P^_][^\x07\x1b]*(\x07|\x1b\\)|[^\[\]P^_])',
  );
  static final RegExp _osc8Regex = RegExp(r'\x1b\]8;[^\x07\x1b]*(?:\x07|\x1b\\)');
  static final RegExp _decSyncRegex = RegExp(r'\x1b\[\?2026[hl]');

  String _safeBoundary(String text) {
    var full = _pending + text;
    _pending = '';
    final esc = full.lastIndexOf('\x1b');
    if (esc != -1 && full.length - esc < 2048) {
      final tail = full.substring(esc);
      // Incomplete CSI/OSC/DCS: ESC alone, or ESC [ / ESC ] without terminator.
      final complete = _completeEscRegex.hasMatch(tail);
      if (!complete) {
        _pending = tail;
        full = full.substring(0, esc);
      }
    }
    if (full.isNotEmpty) {
      final last = full.codeUnitAt(full.length - 1);
      if (last >= 0xD800 && last <= 0xDBFF) {
        _pending = full.substring(full.length - 1) + _pending;
        full = full.substring(0, full.length - 1);
      }
    }
    if (full.contains('\x1b')) {
      full = full.replaceAll(_osc8Regex, '').replaceAll(_decSyncRegex, '');
    }
    return full;
  }

  Future<void> close() async {
    if (_closed) return;
    _sink.close();
    flush();
    if (_pending.isNotEmpty) {
      final rest = _pending;
      _pending = '';
      onText(rest);
    }
    _closed = true;
  }
}

class _StringSink implements Sink<String> {
  _StringSink(this._cb);
  final void Function(String) _cb;
  @override
  void add(String data) => _cb(data);
  @override
  void close() {}
}

/// Drops accidental duplicate input produced by IME composition on Android
/// (the same committed text or partial composition delivered twice within a few milliseconds).
class TerminalInputGuard {
  TerminalInputGuard({this.window = const Duration(milliseconds: 35)});

  final Duration window;
  String? _last;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Returns `true` if [data] should be forwarded to the PTY.
  bool accept(String data) {
    final now = DateTime.now();
    // Control sequences (arrows, enter, ctrl+x) may legitimately repeat fast
    // (key repeat), so only guard printable text.
    final printable = data.isNotEmpty &&
        data.codeUnitAt(0) >= 0x20 &&
        data.codeUnitAt(0) != 0x7f;
    if (printable) {
      final diff = now.difference(_lastAt);
      if (data == _last && diff < (data.length > 1 ? const Duration(milliseconds: 100) : window)) {
        return false;
      }
    }
    _last = data;
    _lastAt = now;
    return true;
  }
}

/// Stream transformer: raw PTY bytes -> UTF-8 safe, frame-batched text.
StreamTransformer<List<int>, String> terminalOutputTransformer() {
  return StreamTransformer<List<int>, String>.fromBind((source) {
    late StreamController<String> controller;
    late TerminalOutputPipe pipe;
    StreamSubscription<List<int>>? sub;
    controller = StreamController<String>(
      onListen: () {
        pipe = TerminalOutputPipe(onText: (t) {
          if (!controller.isClosed && t.isNotEmpty) controller.add(t);
        });
        sub = source.listen(
          pipe.add,
          onError: controller.addError,
          onDone: () async {
            await pipe.close();
            await controller.close();
          },
        );
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  });
}
