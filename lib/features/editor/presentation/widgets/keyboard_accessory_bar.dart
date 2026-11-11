import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:re_editor/re_editor.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

import 'package:quantum_ide/features/editor/presentation/widgets/color_picker_dialog.dart';
import 'package:quantum_ide/core/services/keyboard_sound_service.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/code_find_panel.dart';

class KeyboardAccessoryBar extends ConsumerWidget {
  final CodeLineEditingController controller;

  const KeyboardAccessoryBar({super.key, required this.controller});

  void _copy(WidgetRef ref) async {
    _triggerHaptic(ref);
    final text = controller.selectedText;
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
      return;
    }
    final selection = controller.selection;
    if (!selection.isCollapsed) {
      final lines = controller.codeLines;
      int sLine = selection.start.index;
      int sCol = selection.start.offset;
      int eLine = selection.end.index;
      int eCol = selection.end.offset;
      if (sLine > eLine || (sLine == eLine && sCol > eCol)) {
        final tL = sLine;
        final tC = sCol;
        sLine = eLine;
        sCol = eCol;
        eLine = tL;
        eCol = tC;
      }
      if (sLine >= 0 &&
          sLine < lines.length &&
          eLine >= 0 &&
          eLine < lines.length) {
        if (sLine == eLine) {
          final lineText = lines[sLine].text;
          final s = sCol.clamp(0, lineText.length);
          final e = eCol.clamp(0, lineText.length);
          await Clipboard.setData(
            ClipboardData(
              text: s > e ? lineText.substring(e, s) : lineText.substring(s, e),
            ),
          );
        } else {
          final buf = StringBuffer();
          buf.writeln(
            lines[sLine].text.substring(
              sCol.clamp(0, lines[sLine].text.length),
            ),
          );
          for (int i = sLine + 1; i < eLine; i++) {
            buf.writeln(lines[i].text);
          }
          buf.write(
            lines[eLine].text.substring(
              0,
              eCol.clamp(0, lines[eLine].text.length),
            ),
          );
          await Clipboard.setData(ClipboardData(text: buf.toString()));
        }
      }
    } else {
      final lineIdx = selection.extentIndex;
      if (lineIdx >= 0 && lineIdx < controller.codeLines.length) {
        await Clipboard.setData(
          ClipboardData(text: controller.codeLines[lineIdx].text),
        );
      }
    }
  }

  void _paste(WidgetRef ref) async {
    _triggerHaptic(ref);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      controller.replaceSelection(data.text!);
    }
  }

  void _moveCursor(int delta, WidgetRef ref) {
    _triggerHaptic(ref);
    final selection = controller.selection;
    final lines = controller.codeLines;
    if (lines.isEmpty) return;

    int line = selection.extentIndex;
    int col = selection.extentOffset + delta;

    if (delta > 0) {
      if (col > lines[line].text.length) {
        if (line + 1 < lines.length) {
          line += 1;
          col = 0;
        } else {
          col = lines[line].text.length;
        }
      }
    } else if (delta < 0) {
      if (col < 0) {
        if (line > 0) {
          line -= 1;
          col = lines[line].text.length;
        } else {
          col = 0;
        }
      }
    }

    controller.selection = CodeLineSelection.collapsed(
      index: line.clamp(0, lines.length - 1),
      offset: col.clamp(0, lines[line.clamp(0, lines.length - 1)].text.length),
    );
  }

  void _insertText(String text, WidgetRef ref) {
    if (text == 'TAB') {
      controller.replaceSelection('  ');
    } else {
      controller.replaceSelection(text);
    }
  }

  void _triggerHaptic(WidgetRef ref) {
    KeyboardSoundService.playClick();
  }

  void _showSnippetPicker(BuildContext context) {
    final snippets = [
      (
        title: 'HTML5 Boilerplate',
        desc: 'Базовая разметка HTML5 страницы',
        code:
            '<!DOCTYPE html>\n<html lang="en">\n<head>\n  <meta charset="UTF-8">\n  <meta name="viewport" content="width=device-width, initial-scale=1.0">\n  <title>Document</title>\n</head>\n<body>\n  <h1>Hello Quantum</h1>\n</body>\n</html>',
      ),
      (
        title: 'React Component',
        desc: 'Функциональный компонент React',
        code:
            'import React from "react";\n\nexport const Component = () => {\n  return (\n    <div>\n      <h1>Hello World</h1>\n    </div>\n  );\n};',
      ),
      (
        title: 'Flutter StatelessWidget',
        desc: 'Виджет без состояния',
        code:
            'import "package:flutter/material.dart";\n\nclass CustomWidget extends StatelessWidget {\n  const CustomWidget({super.key});\n\n  @override\n  Widget build(BuildContext context) {\n    return Container();\n  }\n}',
      ),
      (
        title: 'Python Main Script',
        desc: 'Точка входа Python скрипта',
        code:
            'def main():\n    print("Hello from QuantumIDE")\n\nif __name__ == "__main__":\n    main()',
      ),
      (
        title: 'Async Fetch JSON',
        desc: 'Запрос данных по REST API',
        code:
            'async function fetchData(url) {\n  const response = await fetch(url);\n  const data = await response.json();\n  return data;\n}',
      ),
      (
        title: 'CSS Flex Center',
        desc: 'Выравнивание по центру',
        code: 'display: flex;\njustify-content: center;\nalign-items: center;',
      ),
      (
        title: 'SQL Create Table',
        desc: 'Создание таблицы пользователей',
        code:
            'CREATE TABLE IF NOT EXISTS users (\n  id INTEGER PRIMARY KEY AUTOINCREMENT,\n  name TEXT NOT NULL,\n  email TEXT UNIQUE\n);',
      ),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161927),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  LucideIcons.code_xml,
                  color: Color(0xFF00E5FF),
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Быстрые сниппеты кода',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    LucideIcons.x,
                    size: 16,
                    color: Colors.white54,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: snippets.length,
                separatorBuilder: (_, _) =>
                    const Divider(color: Colors.white10, height: 1),
                itemBuilder: (context, index) {
                  final s = snippets[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    title: Text(
                      s.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      s.desc,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    trailing: const Icon(
                      LucideIcons.corner_down_left,
                      color: Color(0xFF00E5FF),
                      size: 16,
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      controller.replaceSelection(s.code);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final l10n = AppLocalizations.of(context)!;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottomInset > 0;
    final screenWidth = MediaQuery.sizeOf(context).width;

    // Скрываем только на десктопных ПК (Windows/Linux/macOS) при очень широких экранах мониторов (>= 1200px).
    // На мобильных устройствах (Android/iOS планшеты и смартфоны) панель с Undo/Redo, стрелками навигации
    // и символами всегда доступна.
    if (!isKeyboardOpen && !Platform.isAndroid && !Platform.isIOS && screenWidth >= 1200) {
      return const SizedBox.shrink();
    }

    final symbols = <String>[
      'TAB',
      '{',
      '}',
      '(',
      ')',
      '[',
      ']',
      ';',
      ':',
      '"',
      "'",
      '`',
      '=',
      '<',
      '>',
      '+',
      '-',
      '*',
      '/',
      '\\',
      '=>',
      '!=',
      '==',
      '&&',
      '||',
      '_',
      '\$',
      '?',
      '!',
      '@',
      '#',
      '%',
      '^',
      '&',
      '|',
      '~',
      '.',
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
              child: Icon(
                icon,
                size: 14,
                color: color ?? const Color(0xFF94A3B8),
              ),
            ),
          ),
        ),
      );
    }

    Color getSymbolColor(String sym) {
      if (sym == 'TAB') return const Color(0xFFA78BFA);
      return const Color(0xFFE2E8F0);
    }

    if (!isKeyboardOpen) {
      return Container(
        height: 30,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0F14),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.06),
              width: 0.8,
            ),
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
                    try {
                      controller.undo();
                    } catch (_) {}
                  },
                ),
                buildBtn(
                  icon: LucideIcons.redo_2,
                  tooltip: l10n.redo,
                  onPressed: () {
                    _triggerHaptic(ref);
                    try {
                      controller.redo();
                    } catch (_) {}
                  },
                ),
                buildBtn(
                  icon: LucideIcons.chevron_left,
                  tooltip: 'Курсор влево',
                  onPressed: () => _moveCursor(-1, ref),
                ),
                buildBtn(
                  icon: LucideIcons.chevron_right,
                  tooltip: 'Курсор вправо',
                  onPressed: () => _moveCursor(1, ref),
                ),
                buildBtn(
                  icon: LucideIcons.copy,
                  tooltip: l10n.copy,
                  onPressed: () => _copy(ref),
                ),
                buildBtn(
                  icon: LucideIcons.clipboard,
                  tooltip: l10n.paste,
                  onPressed: () => _paste(ref),
                ),
                buildBtn(
                  icon: LucideIcons.search,
                  tooltip: 'Поиск в файле (Ctrl+F)',
                  onPressed: () {
                    _triggerHaptic(ref);
                    final finder = ref.read(activeFindControllerProvider);
                    if (finder != null) {
                      finder.findMode();
                      finder.focusOnFindInput();
                    }
                  },
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<CodeLineEditingValue>(
                  valueListenable: controller,
                  builder: (context, val, _) {
                    final line = val.selection.extentIndex + 1;
                    final col = val.selection.extentOffset + 1;
                    return Text(
                      'Стр $line:$col • ${settings.fontSize.toInt()} px',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: const Color(0xFF94A3B8),
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 6),
                buildBtn(
                  icon: LucideIcons.keyboard,
                  tooltip: l10n.edit,
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
        color: const Color(0xFF0D0F14),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.6,
          ),
        ),
      ),
      child: Row(
        children: [
          buildBtn(
            icon: LucideIcons.undo_2,
            tooltip: l10n.undo,
            onPressed: () {
              _triggerHaptic(ref);
              try {
                controller.undo();
              } catch (_) {}
            },
          ),
          buildBtn(
            icon: LucideIcons.redo_2,
            tooltip: l10n.redo,
            onPressed: () {
              _triggerHaptic(ref);
              try {
                controller.redo();
              } catch (_) {}
            },
          ),
          buildBtn(
            icon: LucideIcons.chevron_left,
            tooltip: 'Курсор влево',
            onPressed: () => _moveCursor(-1, ref),
          ),
          buildBtn(
            icon: LucideIcons.chevron_right,
            tooltip: 'Курсор вправо',
            onPressed: () => _moveCursor(1, ref),
          ),
          buildBtn(
            icon: LucideIcons.copy,
            tooltip: l10n.copy,
            onPressed: () => _copy(ref),
          ),
          buildBtn(
            icon: LucideIcons.clipboard,
            tooltip: l10n.paste,
            onPressed: () => _paste(ref),
          ),
          buildBtn(
            icon: LucideIcons.search,
            tooltip: 'Поиск в файле (Ctrl+F)',
            onPressed: () {
              _triggerHaptic(ref);
              final finder = ref.read(activeFindControllerProvider);
              if (finder != null) {
                finder.findMode();
                finder.focusOnFindInput();
              }
            },
          ),
          buildBtn(
            icon: LucideIcons.palette,
            tooltip: 'Выбрать цвет (Color Picker)',
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
          buildBtn(
            icon: LucideIcons.code_xml,
            tooltip: 'Быстрые сниппеты кода',
            onPressed: () {
              _triggerHaptic(ref);
              _showSnippetPicker(context);
            },
          ),
          buildBtn(
            icon: LucideIcons.volume_2,
            tooltip: 'Звук клавиатуры (ASMR)',
            onPressed: () {
              KeyboardSoundService.showSwitchSelectorDialog(context);
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
                final symColor = getSymbolColor(symbol);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 1.5,
                    vertical: 2,
                  ),
                  child: TextButton(
                    onPressed: () {
                      _triggerHaptic(ref);
                      _insertText(symbol, ref);
                    },
                    style: TextButton.styleFrom(
                      minimumSize: Size(isTab ? 38 : 26, 26),
                      padding: EdgeInsets.zero,
                      backgroundColor: const Color(0xFF141720),
                      foregroundColor: symColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                        side: BorderSide(
                          color: isTab
                              ? const Color(0xFF8B5CF6).withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.06),
                          width: 0.6,
                        ),
                      ),
                    ),
                    child: Text(
                      symbol,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: isTab ? 9.5 : 12.0,
                        fontWeight: FontWeight.w600,
                        color: symColor,
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
