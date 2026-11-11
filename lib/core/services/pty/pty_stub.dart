import 'dart:async';
import 'dart:typed_data';

class Pty {
  final StreamController<Uint8List> _controller = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get output => _controller.stream;

  static Pty start(
    String executable, {
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 25,
    int columns = 80,
  }) {
    final p = Pty();
    Future.delayed(const Duration(milliseconds: 150), () {
      p._controller.add(Uint8List.fromList(
        '\x1b[36mQuantum IDE Terminal (Web Mode)\x1b[0m\r\n'
        '\x1b[90mConnected to virtual PTY shell.\x1b[0m\r\n\$ '.codeUnits,
      ));
    });
    return p;
  }

  void write(Uint8List data) {
    // Echo back in web emulation mode
    _controller.add(data);
  }

  void resize(int rows, int cols) {}

  void kill([int? signal]) {
    _controller.close();
  }
}
