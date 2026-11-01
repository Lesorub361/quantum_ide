import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xterm/xterm.dart' as xt;
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/features/terminal/engine/quantum_link_detector.dart';

/// Quantum Terminal Engine Controller
/// Central hub handling terminal streams, selection, clipboard, and interactive links.
class QuantumTerminalEngine {
  /// Cleans and sanitizes raw ANSI terminal output chunks to prevent staircase artifacts
  static String sanitizeChunk(String chunk, {bool hasPendingCr = false}) {
    if (chunk.isEmpty) return chunk;

    // Normalize orphaned carriage returns
    String result = chunk;
    if (result.contains('\r\n')) {
      // Standard CRLF is good
    } else if (result.contains('\n') && !result.contains('\r')) {
      // Missing CR before LF on some shells causes staircasing
      result = result.replaceAll('\n', '\r\n');
    }

    return result;
  }

  /// Copies currently selected text from terminal session to system clipboard
  static Future<bool> copySelection(TerminalSession session) async {
    final selection = session.xtermViewController.selection;
    if (selection == null) return false;

    try {
      final text = session.xtermTerminal.buffer.getText(selection);
      if (text.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: text));
        HapticFeedback.lightImpact();
        session.xtermViewController.clearSelection();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Pastes clipboard text directly into the terminal PTY stream
  static Future<bool> pasteClipboard(TerminalSession session) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && data!.text!.isNotEmpty) {
        final text = data.text!;
        if (session.xtermTerminal.bracketedPasteMode) {
          session.xtermTerminal.paste(text);
        } else {
          session.pty.write(Uint8List.fromList(utf8.encode(text)));
        }
        HapticFeedback.lightImpact();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Selects all visible text currently loaded in terminal buffer
  static void selectAll(TerminalSession session) {
    try {
      final buffer = session.xtermTerminal.buffer;
      if (buffer.height == 0 || buffer.lines.isEmpty) return;
      final firstLine = buffer.lines[0];
      final lastLine = buffer.lines[buffer.height - 1];
      final base = xt.CellAnchor(0, owner: firstLine);
      final extent = xt.CellAnchor(lastLine.length, owner: lastLine);
      session.xtermViewController.setSelection(base, extent);
      HapticFeedback.selectionClick();
    } catch (_) {}
  }
}

/// Floating Quick Action Toolbar for Quantum Terminal
/// Appears when text is selected or on long tap, providing 1-tap Copy, Paste, Open Link, and Select All.
class QuantumTerminalQuickToolbar extends ConsumerWidget {
  final TerminalSession session;
  final VoidCallback? onDismiss;

  const QuantumTerminalQuickToolbar({
    super.key,
    required this.session,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedBuilder(
      animation: session.xtermViewController,
      builder: (context, _) {
        final selection = session.xtermViewController.selection;
        if (selection == null) return const SizedBox.shrink();

        String selectedText = '';
        try {
          selectedText = session.xtermTerminal.buffer.getText(selection);
        } catch (_) {}

        final trimmed = selectedText.trim();
        final detectedLink = trimmed.isNotEmpty ? QuantumLinkDetector.findLinkAt(trimmed, 0) : null;

        return Positioned(
          top: 10,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF131722).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 1. Copy
                  _QuickChip(
                    icon: LucideIcons.copy,
                    label: 'Копировать',
                    color: Colors.cyanAccent,
                    onTap: () async {
                      await QuantumTerminalEngine.copySelection(session);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Текст скопирован в буфер обмена'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                      onDismiss?.call();
                    },
                  ),

                  // 2. Paste
                  _QuickChip(
                    icon: LucideIcons.clipboard_paste,
                    label: 'Вставить',
                    color: Colors.greenAccent,
                    onTap: () async {
                      await QuantumTerminalEngine.pasteClipboard(session);
                      session.xtermViewController.clearSelection();
                      onDismiss?.call();
                    },
                  ),

                  // 3. Open Link (if applicable)
                  if (detectedLink != null) ...[
                    _QuickChip(
                      icon: detectedLink.icon,
                      label: detectedLink.type == QuantumLinkType.filePath ? 'К коду' : 'Открыть',
                      color: Colors.amberAccent,
                      onTap: () async {
                        await QuantumLinkDetector.handleLinkTap(context, ref, detectedLink);
                        session.xtermViewController.clearSelection();
                        onDismiss?.call();
                      },
                    ),
                  ],

                  // 4. Select All
                  _QuickChip(
                    icon: LucideIcons.check_check,
                    label: 'Всё',
                    color: Colors.white70,
                    onTap: () {
                      QuantumTerminalEngine.selectAll(session);
                    },
                  ),

                  // 5. Close
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 16, color: Colors.white54),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () {
                      session.xtermViewController.clearSelection();
                      onDismiss?.call();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuickChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
