# conduit_vt

**conduit_vt** is [Conduit](https://github.com/gwitko/Conduit)'s Flutter
terminal emulator. It is a fork of [xterm.dart](https://github.com/TerminalStudio/xterm.dart)
that keeps the same terminal core while adding the small mobile- and
Mosh-oriented APIs Conduit needs, such as terminal state accessors and
transient cell overlays for predictive echo.

This package is maintained for Conduit and is consumed as a git dependency. It
is not published to pub.dev and is not intended as a drop-in replacement for
`xterm`. If you want a general-purpose Flutter terminal, use the upstream
[`xterm`](https://pub.dev/packages/xterm) package instead.

Requires Flutter `>=3.19.0`.

## What this fork adds

- Terminal state accessors used to position predictive overlays (absolute
  cursor row, view metrics, alternate-buffer state, cell code points).
- `TerminalCellOverlay`: transient cells painted over the buffer without
  mutating terminal state, used for predictive local echo. Overlays support an
  `erase` flag for predicted deletions.

## Usage

Create a terminal and attach it to a view:

```dart
import 'package:conduit_vt/conduit_vt.dart';

final terminal = Terminal();

terminal.onOutput = (output) {
  // forward user input to the transport (SSH, Mosh, ...)
};

// in a widget tree:
TerminalView(terminal);

// write received bytes:
terminal.write('Hello, world!\r\n');
```

Paint predictive cells over the buffer without changing terminal state:

```dart
TerminalView(
  terminal,
  overlays: const [
    TerminalCellOverlay(row: 0, column: 0, text: 'l', opacity: 0.62),
    TerminalCellOverlay(row: 0, column: 1, text: '', erase: true),
  ],
);
```

See `example/` for a runnable terminal.

## License

MIT. This is a fork of xterm.dart; the original work is

```
Copyright (c) 2020 xuty
```

Fork modifications are

```
Copyright (c) 2026 gwitko
```

The full license text, covering both, is in [`LICENSE`](LICENSE).
