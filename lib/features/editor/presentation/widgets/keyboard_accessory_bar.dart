import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

import 'package:quantum_ide/core/services/ai_autocomplete_service.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/color_picker_dialog.dart';

class KeyboardAccessoryBar extends ConsumerWidget {
  final CodeLineEditingController controller;

  const KeyboardAccessoryBar({
    super.key,
    required this.controller,
  });

  void _insertText(String text, WidgetRef ref) {
    if (text == 'TAB') {
      final aiState = ref.read(aiAutocompleteServiceProvider);
      if (aiState.suggestion != null && aiState.suggestion!.trim().isNotEmpty) {
        var insertText = aiState.suggestion!;
        final word = aiState.triggerWord;
        if (word != null && word.isNotEmpty && insertText.startsWith(word)) {
          insertText = insertText.substring(word.length);
        }
        controller.replaceSelection(insertText);
        ref.read(aiAutocompleteServiceProvider.notifier).clear();
        return;
      }
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
            borderRadius: BorderRadius.circular(5),
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              child: Icon(icon, size: 14, color: color ?? Colors.white70),
            ),
          ),
        ),
      );
    }

    if (!isKeyboardOpen) {
      return Container(
        height: 32,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8),
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
                  style: const TextStyle(fontSize: 10, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),
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
      height: 32,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
          buildBtn(
            icon: LucideIcons.palette,
            tooltip: 'Выбрать цвет (Color Picker)',
            color: Colors.pinkAccent,
            onPressed: () {
              _triggerHaptic(ref);
              ColorPickerDialog.show(
                context,
                onColorSelected: (hexCode, flutterCode) {
                  controller.replaceSelection(hexCode);
                },
              );
            },
          ),
          Container(
            width: 1,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 3),
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
                final aiState = ref.watch(aiAutocompleteServiceProvider);
                final hasAi = isTab && aiState.suggestion != null && aiState.suggestion!.trim().isNotEmpty;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 2),
                  child: TextButton(
                    onPressed: () {
                      _triggerHaptic(ref);
                      _insertText(symbol, ref);
                    },
                    style: TextButton.styleFrom(
                      minimumSize: Size(isTab ? (hasAi ? 46 : 38) : 26, 26),
                      padding: EdgeInsets.zero,
                      backgroundColor: hasAi
                          ? Colors.deepPurpleAccent.withValues(alpha: 0.3)
                          : (isTab ? Colors.cyanAccent.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.03)),
                      foregroundColor: hasAi ? Colors.deepPurpleAccent : (isTab ? Colors.cyanAccent : Colors.white70),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                        side: hasAi
                            ? BorderSide(color: Colors.deepPurpleAccent.withValues(alpha: 0.6))
                            : (isTab
                                ? BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.15))
                                : BorderSide(color: Colors.white.withValues(alpha: 0.04), width: 0.5)),
                      ),
                    ),
                    child: hasAi
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.sparkles, size: 10, color: Colors.deepPurpleAccent),
                              SizedBox(width: 2),
                              Text(
                                'TAB',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurpleAccent,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            symbol,
                            style: TextStyle(
                              fontSize: isTab ? 9.5 : 12.5,
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
