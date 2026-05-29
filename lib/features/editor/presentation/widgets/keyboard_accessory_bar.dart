import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:quantum_ide/core/services/settings_service.dart';

class KeyboardAccessoryBar extends ConsumerWidget {
  final CodeLineEditingController controller;

  const KeyboardAccessoryBar({
    super.key,
    required this.controller,
  });

  void _insertText(String text) {
    if (text == 'TAB') {
      controller.replaceSelection('  ');
    } else {
      controller.replaceSelection(text);
    }
  }

  void _triggerHaptic(WidgetRef ref) {
    if (ref.read(settingsProvider).hapticFeedback) {
      HapticFeedback.lightImpact();
    }
  }

  void _moveCursorLeft(WidgetRef ref) {
    _triggerHaptic(ref);
    final selection = controller.selection;
    final extent = selection.extent;
    final text = controller.text;
    final lines = text.split('\n');
    
    int line = extent.index;
    int col = extent.offset;
    
    if (col > 0) {
      col--;
    } else if (line > 0) {
      line--;
      col = lines[line].length;
    }
    
    controller.selection = CodeLineSelection.fromPosition(
      position: CodeLinePosition(index: line, offset: col),
    );
  }

  void _moveCursorRight(WidgetRef ref) {
    _triggerHaptic(ref);
    final selection = controller.selection;
    final extent = selection.extent;
    final text = controller.text;
    final lines = text.split('\n');
    
    int line = extent.index;
    int col = extent.offset;
    
    if (col < lines[line].length) {
      col++;
    } else if (line < lines.length - 1) {
      line++;
      col = 0;
    }
    
    controller.selection = CodeLineSelection.fromPosition(
      position: CodeLinePosition(index: line, offset: col),
    );
  }

  void _moveCursorUp(WidgetRef ref) {
    _triggerHaptic(ref);
    final selection = controller.selection;
    final extent = selection.extent;
    final text = controller.text;
    final lines = text.split('\n');
    
    int line = extent.index;
    int col = extent.offset;
    
    if (line > 0) {
      line--;
      if (col > lines[line].length) {
        col = lines[line].length;
      }
    }
    
    controller.selection = CodeLineSelection.fromPosition(
      position: CodeLinePosition(index: line, offset: col),
    );
  }

  void _moveCursorDown(WidgetRef ref) {
    _triggerHaptic(ref);
    final selection = controller.selection;
    final extent = selection.extent;
    final text = controller.text;
    final lines = text.split('\n');
    
    int line = extent.index;
    int col = extent.offset;
    
    if (line < lines.length - 1) {
      line++;
      if (col > lines[line].length) {
        col = lines[line].length;
      }
    }
    
    controller.selection = CodeLineSelection.fromPosition(
      position: CodeLinePosition(index: line, offset: col),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottomInset > 0;

    final symbols = <String>[
      'TAB', '{', '}', '(', ')', '[', ']', ';', '<', '>', '/', '\\', '"', "'", ':', '=', '_', '\$', '!', '&', '|', '#'
    ];

    // Helper builder for small, sleek control buttons
    Widget buildBtn({
      required IconData icon,
      required VoidCallback onPressed,
      required String tooltip,
      Color? color,
    }) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: color ?? Colors.white70),
            ),
          ),
        ),
      );
    }

    final List<Widget> controls = [
      // Zoom controls
      buildBtn(
        icon: LucideIcons.zoom_out,
        tooltip: 'Уменьшить шрифт',
        onPressed: () {
          _triggerHaptic(ref);
          final newSize = (settings.fontSize - 1.0).clamp(10.0, 30.0);
          ref.read(settingsProvider.notifier).setFontSize(newSize);
        },
      ),
      buildBtn(
        icon: LucideIcons.zoom_in,
        tooltip: 'Увеличить шрифт',
        onPressed: () {
          _triggerHaptic(ref);
          final newSize = (settings.fontSize + 1.0).clamp(10.0, 30.0);
          ref.read(settingsProvider.notifier).setFontSize(newSize);
        },
      ),
      Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: Colors.white.withValues(alpha: 0.08),
      ),
      // Undo & Redo controls
      buildBtn(
        icon: LucideIcons.undo_2,
        tooltip: 'Отменить',
        onPressed: () {
          _triggerHaptic(ref);
          try {
            controller.undo();
          } catch (_) {}
        },
      ),
      buildBtn(
        icon: LucideIcons.redo_2,
        tooltip: 'Повторить',
        onPressed: () {
          _triggerHaptic(ref);
          try {
            controller.redo();
          } catch (_) {}
        },
      ),
      Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: Colors.white.withValues(alpha: 0.08),
      ),
      // Cursor navigation controls
      buildBtn(
        icon: LucideIcons.chevron_left,
        tooltip: 'Влево',
        onPressed: () => _moveCursorLeft(ref),
      ),
      buildBtn(
        icon: LucideIcons.chevron_up,
        tooltip: 'Вверх',
        onPressed: () => _moveCursorUp(ref),
      ),
      buildBtn(
        icon: LucideIcons.chevron_down,
        tooltip: 'Вниз',
        onPressed: () => _moveCursorDown(ref),
      ),
      buildBtn(
        icon: LucideIcons.chevron_right,
        tooltip: 'Вправо',
        onPressed: () => _moveCursorRight(ref),
      ),
    ];

    if (!isKeyboardOpen) {
      // If keyboard is closed, show a floating-style glassmorphic control bar at the bottom
      return Container(
        height: 42,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xE610121D),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.8),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: controls,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Small indicator of font size
                Text(
                  '${settings.fontSize.toInt()} px',
                  style: const TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                // Button to open keyboard
                buildBtn(
                  icon: LucideIcons.keyboard,
                  tooltip: 'Редактировать',
                  color: Colors.cyanAccent,
                  onPressed: () {
                    _triggerHaptic(ref);
                    // Focus editor to bring up keyboard
                    FocusManager.instance.primaryFocus?.requestFocus();
                  },
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Keyboard is open: show double-sided controls with scrollable symbols in between
    return Container(
      height: 42,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF161925),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.5)),
      ),
      child: Row(
        children: [
          // Left side: Zoom, Undo, Redo
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildBtn(
                icon: LucideIcons.zoom_out,
                tooltip: 'Уменьшить',
                onPressed: () {
                  _triggerHaptic(ref);
                  final newSize = (settings.fontSize - 1.0).clamp(10.0, 30.0);
                  ref.read(settingsProvider.notifier).setFontSize(newSize);
                },
              ),
              buildBtn(
                icon: LucideIcons.zoom_in,
                tooltip: 'Увеличить',
                onPressed: () {
                  _triggerHaptic(ref);
                  final newSize = (settings.fontSize + 1.0).clamp(10.0, 30.0);
                  ref.read(settingsProvider.notifier).setFontSize(newSize);
                },
              ),
              buildBtn(
                icon: LucideIcons.undo_2,
                tooltip: 'Отменить',
                onPressed: () {
                  _triggerHaptic(ref);
                  try {
                    controller.undo();
                  } catch (_) {}
                },
              ),
              buildBtn(
                icon: LucideIcons.redo_2,
                tooltip: 'Повторить',
                onPressed: () {
                  _triggerHaptic(ref);
                  try {
                    controller.redo();
                  } catch (_) {}
                },
              ),
            ],
          ),
          
          // Center: Scrollable symbol list
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: symbols.length,
                itemBuilder: (context, index) {
                  final symbol = symbols[index];
                  final isTab = symbol == 'TAB';
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    child: TextButton(
                      onPressed: () {
                        _triggerHaptic(ref);
                        _insertText(symbol);
                      },
                      style: TextButton.styleFrom(
                        minimumSize: Size(isTab ? 46 : 32, 32),
                        padding: EdgeInsets.zero,
                        backgroundColor: isTab ? Colors.cyanAccent.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.03),
                        foregroundColor: isTab ? Colors.cyanAccent : Colors.white70,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                          side: isTab 
                            ? BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.15)) 
                            : BorderSide(color: Colors.white.withValues(alpha: 0.04), width: 0.5),
                        ),
                      ),
                      child: Text(
                        symbol,
                        style: TextStyle(
                          fontSize: isTab ? 11 : 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Right side: Navigation arrows
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildBtn(
                icon: LucideIcons.chevron_left,
                tooltip: 'Влево',
                onPressed: () => _moveCursorLeft(ref),
              ),
              buildBtn(
                icon: LucideIcons.chevron_up,
                tooltip: 'Вверх',
                onPressed: () => _moveCursorUp(ref),
              ),
              buildBtn(
                icon: LucideIcons.chevron_down,
                tooltip: 'Вниз',
                onPressed: () => _moveCursorDown(ref),
              ),
              buildBtn(
                icon: LucideIcons.chevron_right,
                tooltip: 'Вправо',
                onPressed: () => _moveCursorRight(ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
