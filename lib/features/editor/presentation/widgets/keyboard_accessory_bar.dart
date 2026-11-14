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
import 'package:quantum_ide/core/theme/conduit_palette.dart';
import 'package:quantum_ide/features/terminal/conduit/conduit_appearance_sheet.dart';

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

  void _showSnippetPicker(BuildContext context, AppPalette? palette) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final brightness = theme.brightness;
    final sheetBg = palette?.panelFor(brightness) ?? colorScheme.surfaceContainer;
    final accent = palette?.accent ?? colorScheme.primary;
    final fg = palette?.foregroundFor(brightness) ?? colorScheme.onSurface;
    final mutedFg =
        palette?.mutedForegroundFor(brightness) ?? colorScheme.onSurfaceVariant;
    final dividerColor =
        palette?.hairlineFor(brightness) ?? theme.dividerColor.withValues(alpha: 0.2);

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
      backgroundColor: sheetBg,
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
                Icon(
                  LucideIcons.code_xml,
                  color: accent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Быстрые сниппеты кода',
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    LucideIcons.x,
                    size: 16,
                    color: mutedFg,
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
                    Divider(color: dividerColor, height: 1),
                itemBuilder: (context, index) {
                  final s = snippets[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    title: Text(
                      s.title,
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      s.desc,
                      style: TextStyle(
                        color: mutedFg,
                        fontSize: 11,
                      ),
                    ),
                    trailing: Icon(
                      LucideIcons.corner_down_left,
                      color: accent,
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

  void _showGoToLineDialog(BuildContext context, AppPalette? palette) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final brightness = theme.brightness;
    final dialogBg =
        palette?.panelElevatedFor(brightness) ?? colorScheme.surfaceContainerHigh;
    final inputBg = palette?.canvasFor(brightness) ?? colorScheme.surface;
    final accent = palette?.accent ?? colorScheme.primary;
    final fg = palette?.foregroundFor(brightness) ?? colorScheme.onSurface;
    final mutedFg =
        palette?.mutedForegroundFor(brightness) ?? colorScheme.onSurfaceVariant;
    final accentText =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? Colors.white
            : Colors.black;

    final textCtrl = TextEditingController();
    final totalLines = controller.codeLines.length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(LucideIcons.navigation, color: accent, size: 16),
            const SizedBox(width: 8),
            Text(
              'Перейти к строке (1–$totalLines)',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: fg,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: TextField(
          controller: textCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: GoogleFonts.jetBrainsMono(color: fg, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Номер строки...',
            hintStyle: TextStyle(color: mutedFg),
            filled: true,
            fillColor: inputBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onSubmitted: (val) {
            final target = int.tryParse(val.trim());
            if (target != null && target >= 1 && target <= totalLines) {
              controller.selection = CodeLineSelection.collapsed(
                index: target - 1,
                offset: 0,
              );
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: mutedFg)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: accentText,
            ),
            onPressed: () {
              final target = int.tryParse(textCtrl.text.trim());
              if (target != null && target >= 1 && target <= totalLines) {
                controller.selection = CodeLineSelection.collapsed(
                  index: target - 1,
                  offset: 0,
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Перейти', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final brightness = theme.brightness;
    final palette = settings.syncAppWithTerminalPalette
        ? resolveConduitPalette(settings.terminalTheme)
        : null;

    final barBg = palette?.panelFor(brightness) ??
        (brightness == Brightness.dark
            ? colorScheme.surfaceContainerLow
            : colorScheme.surfaceContainer);
    final elevatedBg =
        palette?.panelElevatedFor(brightness) ?? colorScheme.surfaceContainerHigh;
    final topBorderColor =
        palette?.borderFor(brightness) ?? theme.dividerColor.withValues(alpha: 0.25);
    final hairlineColor =
        palette?.hairlineFor(brightness) ?? theme.dividerColor.withValues(alpha: 0.2);
    final accentColor = palette?.accent ?? colorScheme.primary;
    final tabColor = palette?.accentSecondary ?? palette?.accent ?? colorScheme.secondary;
    final fgColor = palette?.foregroundFor(brightness) ?? colorScheme.onSurface;
    final iconColor =
        palette?.mutedForegroundFor(brightness) ?? colorScheme.onSurfaceVariant;

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
                color: color ?? iconColor,
              ),
            ),
          ),
        ),
      );
    }

    Color getSymbolColor(String sym) {
      if (sym == 'TAB') return tabColor;
      return fgColor;
    }

    if (!isKeyboardOpen) {
      return Container(
        height: 30,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: barBg,
          border: Border(
            top: BorderSide(
              color: topBorderColor,
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
                    return InkWell(
                      onTap: () => _showGoToLineDialog(context, palette),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: elevatedBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: accentColor.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          'Стр $line:$col • ${settings.fontSize.toInt()} px',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: accentColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
        color: barBg,
        border: Border(
          top: BorderSide(
            color: topBorderColor,
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
              _showSnippetPicker(context, palette);
            },
          ),
          buildBtn(
            icon: LucideIcons.volume_2,
            tooltip: 'Звук клавиатуры (ASMR)',
            onPressed: () {
              KeyboardSoundService.showSwitchSelectorDialog(context);
            },
          ),
          ValueListenableBuilder<CodeLineEditingValue>(
            valueListenable: controller,
            builder: (context, val, _) {
              final line = val.selection.extentIndex + 1;
              final col = val.selection.extentOffset + 1;
              return InkWell(
                onTap: () => _showGoToLineDialog(context, palette),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: elevatedBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: accentColor.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    '$line:$col',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: accentColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
          Container(
            width: 1,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            color: hairlineColor,
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
                      backgroundColor: elevatedBg,
                      foregroundColor: symColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                        side: BorderSide(
                          color: isTab
                              ? tabColor.withValues(alpha: 0.4)
                              : hairlineColor,
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
