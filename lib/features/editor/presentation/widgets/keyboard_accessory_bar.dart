import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final l10n = AppLocalizations.of(context)!;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottomInset > 0;

    final symbols = <String>[
      'TAB', '{', '}', '(', ')', '[', ']', ';', '<', '>', '/', '\\', '"', "'", ':', '=', '_', '\$', '!', '&', '|', '#'
    ];

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
              width: 36,
              height: 36,
              alignment: Alignment.center,
              child: Icon(icon, size: 17, color: color ?? Colors.white70),
            ),
          ),
        ),
      );
    }

    if (!isKeyboardOpen) {
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
              children: [
                buildBtn(
                  icon: LucideIcons.undo_2,
                  tooltip: l10n.undo,
                  onPressed: () {
                    _triggerHaptic(ref);
                    try { controller.undo(); } catch (_) {}
                  },
                ),
                buildBtn(
                  icon: LucideIcons.redo_2,
                  tooltip: l10n.redo,
                  onPressed: () {
                    _triggerHaptic(ref);
                    try { controller.redo(); } catch (_) {}
                  },
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${settings.fontSize.toInt()} px',
                  style: const TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                buildBtn(
                  icon: LucideIcons.keyboard,
                  tooltip: l10n.edit,
                  color: Colors.cyanAccent,
                  onPressed: () {
                    _triggerHaptic(ref);
                    FocusManager.instance.primaryFocus?.requestFocus();
                  },
                ),
              ],
            ),
          ],
        ),
      );
    }

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
          buildBtn(
            icon: LucideIcons.undo_2,
            tooltip: l10n.undo,
            onPressed: () {
              _triggerHaptic(ref);
              try { controller.undo(); } catch (_) {}
            },
          ),
          buildBtn(
            icon: LucideIcons.redo_2,
            tooltip: l10n.redo,
            onPressed: () {
              _triggerHaptic(ref);
              try { controller.redo(); } catch (_) {}
            },
          ),
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: Colors.white.withValues(alpha: 0.08),
          ),
          Expanded(
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
        ],
      ),
    );
  }
}
