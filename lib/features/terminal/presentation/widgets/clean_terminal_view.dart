import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kterm/kterm.dart' as xt;

import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/theme/terminal_themes.dart';

/// Clean, robust terminal view based on Roxum IDE architecture.
/// Eliminates conflicting input interceptors, autocomplete buffer desyncs,
/// and complex layout hacks.
class CleanTerminalView extends ConsumerStatefulWidget {
  final List<TerminalSession> sessions;
  final TerminalTabsNotifier notifier;

  const CleanTerminalView({
    super.key,
    required this.sessions,
    required this.notifier,
  });

  @override
  ConsumerState<CleanTerminalView> createState() => _CleanTerminalViewState();
}

class _CleanTerminalViewState extends ConsumerState<CleanTerminalView> {
  TerminalSession? _currentAttachedSession;

  @override
  void initState() {
    super.initState();
    _checkAndAttachSession();
  }

  @override
  void didUpdateWidget(covariant CleanTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkAndAttachSession();
  }

  void _checkAndAttachSession() {
    if (widget.sessions.isEmpty) return;
    final index = widget.notifier.currentIndex.clamp(0, widget.sessions.length - 1);
    final activeSession = widget.sessions[index];

    if (_currentAttachedSession != activeSession) {
      _currentAttachedSession = activeSession;
      _setupTerminalOutput(activeSession);
    }
  }

  void _setupTerminalOutput(
    TerminalSession session, {
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    VoidCallback? resetCallback,
  }) {
    session.xtermTerminal.onOutput = (data) {
      String seq = '';

      if (ctrl) {
        if (data.length == 1) {
          final int code = data.toUpperCase().codeUnitAt(0);
          if (code >= 65 && code <= 90) {
            seq = String.fromCharCode(code - 64);
          } else {
            seq = data;
          }
        } else {
          seq = data;
        }
      } else if (alt) {
        seq = '\x1b$data';
      } else if (shift) {
        seq = data.toUpperCase();
      } else {
        seq = data;
      }

      if (seq.isNotEmpty) {
        session.pty.write(Uint8List.fromList(utf8.encode(seq)));
      }

      if ((ctrl || alt || shift) && resetCallback != null) {
        resetCallback();
        _setupTerminalOutput(session);
      }
    };
  }

  void _sendToPty(TerminalSession session, String sequence) {
    session.pty.write(Uint8List.fromList(utf8.encode(sequence)));
  }

  Future<void> _copySelection(TerminalSession session) async {
    final selection = session.xtermViewController.selection;
    if (selection != null) {
      final text = session.xtermTerminal.buffer.getText(selection);
      if (text.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: text));
        session.xtermViewController.clearSelection();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Скопировано в буфер обмена'),
              duration: Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _pasteToPty(TerminalSession session) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      session.pty.write(Uint8List.fromList(utf8.encode(data.text!)));
    }
  }

  void _toggleSoftwareKeyboard() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    if (bottomInset > 20) {
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } else {
      SystemChannels.textInput.invokeMethod('TextInput.show');
    }
  }

  String _getFontFamily(String fontName) {
    final normalized = fontName.toLowerCase().replaceAll(' ', '');
    switch (normalized) {
      case 'jetbrainsmono':
        return 'jetBrainsMono';
      case 'firacode':
        return 'firaCode';
      case 'sourcecodepro':
        return 'sourceCodePro';
      case 'inconsolata':
        return 'inconsolata';
      case 'cascadiacode':
      case 'cascadia':
        return 'cascadia';
      case 'symbolsnerdfont':
      case 'nerdfont':
        return 'SymbolsNerdFont';
      case 'monospace':
        return 'monospace';
      default:
        try {
          return GoogleFonts.getFont(fontName).fontFamily ?? 'monospace';
        } catch (_) {
          return 'monospace';
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sessions.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final currentIndex = widget.notifier.currentIndex.clamp(0, widget.sessions.length - 1);
    final activeSession = widget.sessions[currentIndex];

    final settings = ref.watch(settingsProvider);
    final terminalThemeName = settings.terminalTheme;
    final theme = getTerminalTheme(terminalThemeName);
    final fontSize = settings.terminalFontSize.toDouble();
    final fontFamily = _getFontFamily(settings.terminalFontFamily);

    return Container(
      color: theme.background,
      child: Column(
        children: [
          // Top Tab & Session Bar
          _buildSessionBar(activeSession, currentIndex, theme),

          // Main Terminal View (Clean, Direct)
          Expanded(
            child: xt.TerminalView(
              activeSession.xtermTerminal,
              controller: activeSession.xtermViewController,
              autofocus: true,
              keyboardType: TextInputType.multiline,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              theme: theme,
              textStyle: xt.TerminalStyle(
                fontSize: fontSize,
                fontFamily: fontFamily,
              ),
            ),
          ),

          // Clean Virtual Keyboard Menu (Roxum IDE style)
          CleanTerminalKeyboardMenu(
            onSendSequence: (seq) => _sendToPty(activeSession, seq),
            onToggleKeyboard: _toggleSoftwareKeyboard,
            onModifierChanged: (ctrl, alt, shift, resetCallback) {
              _setupTerminalOutput(
                activeSession,
                ctrl: ctrl,
                alt: alt,
                shift: shift,
                resetCallback: resetCallback,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSessionBar(TerminalSession activeSession, int activeIndex, xt.TerminalTheme theme) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF141721),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Session Tabs List
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: widget.sessions.length,
              itemBuilder: (context, index) {
                final session = widget.sessions[index];
                final isSelected = index == activeIndex;
                final isRunning = !session.isExited;

                return InkWell(
                  onTap: () {
                    widget.notifier.currentIndex = index;
                    setState(() {});
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.cyanAccent.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? Colors.cyanAccent.withValues(alpha: 0.4)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isRunning ? Colors.greenAccent : Colors.redAccent,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          session.title,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white60,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if (widget.sessions.length > 1) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () {
                              widget.notifier.closeSession(index);
                              setState(() {});
                            },
                            child: const Icon(
                              LucideIcons.x,
                              size: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Actions: New Tab, Restart, Paste, Copy
          IconButton(
            icon: const Icon(LucideIcons.plus, size: 16, color: Colors.cyanAccent),
            tooltip: 'Новый терминал',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              widget.notifier.createNewSession();
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(LucideIcons.refresh_cw, size: 15, color: Colors.amberAccent),
            tooltip: 'Перезапустить',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => widget.notifier.restartSession(activeIndex),
          ),
          IconButton(
            icon: const Icon(LucideIcons.clipboard_paste, size: 16, color: Colors.white70),
            tooltip: 'Вставить',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => _pasteToPty(activeSession),
          ),
          IconButton(
            icon: const Icon(LucideIcons.copy, size: 15, color: Colors.white70),
            tooltip: 'Скопировать выделенное',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => _copySelection(activeSession),
          ),
        ],
      ),
    );
  }
}

/// Virtual Keyboard Bar modeled after Roxum IDE TerminalKeyboardMenu
class CleanTerminalKeyboardMenu extends StatefulWidget {
  final Function(String) onSendSequence;
  final VoidCallback onToggleKeyboard;
  final Function(bool ctrl, bool alt, bool shift, VoidCallback resetCallback) onModifierChanged;

  const CleanTerminalKeyboardMenu({
    super.key,
    required this.onSendSequence,
    required this.onToggleKeyboard,
    required this.onModifierChanged,
  });

  @override
  State<CleanTerminalKeyboardMenu> createState() => _CleanTerminalKeyboardMenuState();
}

class _CleanTerminalKeyboardMenuState extends State<CleanTerminalKeyboardMenu> {
  bool isCtrlActive = false;
  bool isAltActive = false;
  bool isShiftActive = false;

  void _resetModifiers() {
    if (mounted) {
      setState(() {
        isCtrlActive = false;
        isAltActive = false;
        isShiftActive = false;
      });
    }
  }

  void _toggleCtrl() {
    setState(() {
      isCtrlActive = !isCtrlActive;
      if (isCtrlActive) {
        isAltActive = false;
        isShiftActive = false;
      }
    });
    widget.onModifierChanged(
      isCtrlActive,
      isAltActive,
      isShiftActive,
      _resetModifiers,
    );
  }

  void _toggleAlt() {
    setState(() {
      isAltActive = !isAltActive;
      if (isAltActive) {
        isCtrlActive = false;
        isShiftActive = false;
      }
    });
    widget.onModifierChanged(
      isCtrlActive,
      isAltActive,
      isShiftActive,
      _resetModifiers,
    );
  }

  void _toggleShift() {
    setState(() {
      isShiftActive = !isShiftActive;
      if (isShiftActive) {
        isCtrlActive = false;
        isAltActive = false;
      }
    });
    widget.onModifierChanged(
      isCtrlActive,
      isAltActive,
      isShiftActive,
      _resetModifiers,
    );
  }

  Widget _buildKeyButton({
    required Widget child,
    required VoidCallback onTap,
    bool isActive = false,
    double minWidth = 44,
  }) {
    return Container(
      height: 34,
      constraints: BoxConstraints(minWidth: minWidth),
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.amber.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive
              ? Colors.amberAccent
              : Colors.white.withValues(alpha: 0.1),
          width: 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildTextKey(String text, {required VoidCallback onTap, bool isActive = false, double minWidth = 44}) {
    return _buildKeyButton(
      isActive: isActive,
      minWidth: minWidth,
      onTap: onTap,
      child: Text(
        text,
        style: TextStyle(
          color: isActive ? Colors.amberAccent : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildIconKey(IconData icon, {required VoidCallback onTap, double minWidth = 40}) {
    return _buildKeyButton(
      minWidth: minWidth,
      onTap: onTap,
      child: Icon(icon, size: 16, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF10121A),
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: CTRL, ALT, HOME, UP, END, TAB, DEL
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTextKey('CTRL', isActive: isCtrlActive, onTap: _toggleCtrl, minWidth: 50),
                _buildTextKey('ALT', isActive: isAltActive, onTap: _toggleAlt, minWidth: 46),
                _buildTextKey('HOME', onTap: () => widget.onSendSequence('\x1b[H'), minWidth: 50),
                _buildIconKey(LucideIcons.arrow_up, onTap: () => widget.onSendSequence('\x1b[A')),
                _buildTextKey('END', onTap: () => widget.onSendSequence('\x1b[F'), minWidth: 46),
                _buildTextKey('TAB', onTap: () => widget.onSendSequence('\t'), minWidth: 46),
                _buildTextKey('DEL', onTap: () => widget.onSendSequence('\x7f'), minWidth: 44),
                _buildTextKey('~', onTap: () => widget.onSendSequence('~'), minWidth: 36),
                _buildTextKey('/', onTap: () => widget.onSendSequence('/'), minWidth: 36),
                _buildTextKey('|', onTap: () => widget.onSendSequence('|'), minWidth: 36),
                _buildTextKey('-', onTap: () => widget.onSendSequence('-'), minWidth: 36),
              ],
            ),
          ),

          // Row 2: ESC, SHIFT, LEFT, DOWN, RIGHT, Soft Keyboard toggle
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTextKey('ESC', onTap: () => widget.onSendSequence('\x1b'), minWidth: 50),
                _buildTextKey('SHIFT', isActive: isShiftActive, onTap: _toggleShift, minWidth: 52),
                _buildIconKey(LucideIcons.arrow_left, onTap: () => widget.onSendSequence('\x1b[D')),
                _buildIconKey(LucideIcons.arrow_down, onTap: () => widget.onSendSequence('\x1b[B')),
                _buildIconKey(LucideIcons.arrow_right, onTap: () => widget.onSendSequence('\x1b[C')),
                _buildIconKey(LucideIcons.keyboard, onTap: widget.onToggleKeyboard, minWidth: 48),
                _buildTextKey(':', onTap: () => widget.onSendSequence(':'), minWidth: 36),
                _buildTextKey('"', onTap: () => widget.onSendSequence('"'), minWidth: 36),
                _buildTextKey("'", onTap: () => widget.onSendSequence("'"), minWidth: 36),
                _buildTextKey(r'$', onTap: () => widget.onSendSequence('\$'), minWidth: 36),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
