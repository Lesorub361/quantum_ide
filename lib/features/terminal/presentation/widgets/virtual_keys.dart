import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class VirtualKey {
  final String label;
  final String? value;
  final IconData? icon;
  final bool isToggle;
  final bool isCommand;
  final String? tooltip;

  const VirtualKey({
    required this.label,
    this.value,
    this.icon,
    this.isToggle = false,
    this.isCommand = false,
    this.tooltip,
  });
}

class VirtualKeysView extends ConsumerStatefulWidget {
  final Function(String) onKeyTap;
  final Set<String> activeKeys;
  final bool isCompact;

  const VirtualKeysView({
    super.key,
    required this.onKeyTap,
    this.activeKeys = const {},
    this.isCompact = false,
  });

  @override
  ConsumerState<VirtualKeysView> createState() => _VirtualKeysViewState();
}

class _VirtualKeysViewState extends ConsumerState<VirtualKeysView> {
  static const List<VirtualKey> _compactKeys = [
    VirtualKey(label: 'ESC', value: '\x1b', tooltip: 'Escape'),
    VirtualKey(label: 'TAB', value: '\t', tooltip: 'Tab / Автодополнение'),
    VirtualKey(label: 'CTRL', value: 'ctrl', isToggle: true, tooltip: 'Зажать Ctrl'),
    VirtualKey(label: 'ALT', value: 'ALT', isToggle: true, tooltip: 'Зажать Alt'),
    VirtualKey(label: 'C-C', value: 'ctrl+c', tooltip: 'Прервать процесс (Ctrl+C)'),
    VirtualKey(label: 'PASTE', value: 'paste', icon: LucideIcons.clipboard_paste, tooltip: 'Вставить из буфера'),
    VirtualKey(label: '←', value: '\x1b[D', icon: LucideIcons.arrow_left, tooltip: 'Влево'),
    VirtualKey(label: '↓', value: '\x1b[B', icon: LucideIcons.arrow_down, tooltip: 'Вниз'),
    VirtualKey(label: '↑', value: '\x1b[A', icon: LucideIcons.arrow_up, tooltip: 'Вверх'),
    VirtualKey(label: '→', value: '\x1b[C', icon: LucideIcons.arrow_right, tooltip: 'Вправо'),
  ];

  static const List<VirtualKey> _row1Keys = [
    VirtualKey(label: 'ESC', value: '\x1b', tooltip: 'Escape'),
    VirtualKey(label: 'TAB', value: '\t', tooltip: 'Tab / Автодополнение'),
    VirtualKey(label: 'CTRL', value: 'ctrl', isToggle: true, tooltip: ' Зажать Ctrl'),
    VirtualKey(label: 'ALT', value: 'ALT', isToggle: true, tooltip: 'Зажать Alt'),
    VirtualKey(label: 'SHIFT', value: 'SHIFT', isToggle: true, tooltip: 'Зажать Shift'),
    VirtualKey(label: '←', value: '\x1b[D', icon: LucideIcons.arrow_left, tooltip: 'Влево'),
    VirtualKey(label: '↓', value: '\x1b[B', icon: LucideIcons.arrow_down, tooltip: 'Вниз'),
    VirtualKey(label: '↑', value: '\x1b[A', icon: LucideIcons.arrow_up, tooltip: 'Вверх'),
    VirtualKey(label: '→', value: '\x1b[C', icon: LucideIcons.arrow_right, tooltip: 'Вправо'),
    VirtualKey(label: 'KEYB', value: 'toggle_keyboard', icon: LucideIcons.keyboard, tooltip: 'Показать/скрыть клавиатуру'),
  ];

  static const List<VirtualKey> _row2Keys = [
    VirtualKey(label: 'PASTE', value: 'paste', icon: LucideIcons.clipboard_paste, tooltip: 'Вставить из буфера'),
    VirtualKey(label: 'C-C', value: 'ctrl+c', tooltip: 'Прервать процесс (Ctrl+C)'),
    VirtualKey(label: '~', value: '~'),
    VirtualKey(label: '/', value: '/'),
    VirtualKey(label: '-', value: '-'),
    VirtualKey(label: '_', value: '_'),
    VirtualKey(label: '|', value: '|'),
    VirtualKey(label: '\\', value: '\\'),
    VirtualKey(label: '"', value: '"'),
    VirtualKey(label: '\'', value: '\''),
    VirtualKey(label: ':', value: ':'),
    VirtualKey(label: '.', value: '.'),
  ];

  void _showMoreCommandsSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF11131A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.56,
          minChildSize: 0.35,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollController) {
            return _MoreTerminalCommandsSheet(
              scrollController: scrollController,
              onKeyTap: (val) {
                Navigator.of(ctx).pop();
                widget.onKeyTap(val);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildKeyRow(List<VirtualKey> rowKeys, {Widget? trailingFixed}) {
    return SizedBox(
      height: 29,
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // On wider screens stretch keys evenly; on compact screens allow smooth horizontal scroll
                final minTotalWidth = rowKeys.length * 44.0;
                final shouldExpandEvenly = constraints.maxWidth >= minTotalWidth;

                if (shouldExpandEvenly) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        for (int i = 0; i < rowKeys.length; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Expanded(
                            child: _VirtualKeyButton(
                              keyData: rowKeys[i],
                              isActive: widget.activeKeys.contains(rowKeys[i].label) ||
                                  (rowKeys[i].value != null && widget.activeKeys.contains(rowKeys[i].value)),
                              onTap: () => widget.onKeyTap(rowKeys[i].value ?? rowKeys[i].label),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  physics: const BouncingScrollPhysics(),
                  itemCount: rowKeys.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 4),
                  itemBuilder: (context, index) {
                    final key = rowKeys[index];
                    final isActive = widget.activeKeys.contains(key.label) ||
                        (key.value != null && widget.activeKeys.contains(key.value));
                    return _VirtualKeyButton(
                      keyData: key,
                      isActive: isActive,
                      onTap: () => widget.onKeyTap(key.value ?? key.label),
                    );
                  },
                );
              },
            ),
          ),
          if (trailingFixed != null) ...[
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              color: Colors.white.withValues(alpha: 0.1),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 5, left: 2),
              child: trailingFixed,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isCompact) {
      return Container(
        height: 33,
        clipBehavior: Clip.hardEdge,
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0F14).withValues(alpha: 0.98),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.6)),
        ),
        child: _buildKeyRow(
          _compactKeys,
          trailingFixed: _VirtualKeyButton(
            keyData: const VirtualKey(
              label: 'Ещё',
              value: 'more_commands',
              icon: LucideIcons.layout_grid,
              tooltip: 'Все команды, сочетания клавиш и спецсимволы',
            ),
            isActive: false,
            isHighlightedAction: true,
            onTap: () => _showMoreCommandsSheet(context),
          ),
        ),
      );
    }

    return Container(
      height: 56,
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F14).withValues(alpha: 0.98),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildKeyRow(_row1Keys),
          const SizedBox(height: 2),
          _buildKeyRow(
            _row2Keys,
            trailingFixed: _VirtualKeyButton(
              keyData: const VirtualKey(
                label: 'Ещё',
                value: 'more_commands',
                icon: LucideIcons.layout_grid,
                tooltip: 'Все команды, сочетания клавиш и спецсимволы',
              ),
              isActive: false,
              isHighlightedAction: true,
              onTap: () => _showMoreCommandsSheet(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreTerminalCommandsSheet extends StatelessWidget {
  final ScrollController scrollController;
  final Function(String) onKeyTap;

  const _MoreTerminalCommandsSheet({
    required this.scrollController,
    required this.onKeyTap,
  });

  static const List<VirtualKey> _controlKeys = [
    VirtualKey(label: 'Выделить всё', value: 'select_all', icon: LucideIcons.check_check),
    VirtualKey(label: 'Скопировать всё', value: 'copy_all_output', icon: LucideIcons.clipboard_copy),
    VirtualKey(label: 'Окно текста', value: 'selection_mode', icon: LucideIcons.file_text),
    VirtualKey(label: 'Очистить (C-L)', value: 'ctrl+l', icon: LucideIcons.eraser),
    VirtualKey(label: 'C-D (EOF)', value: 'ctrl+d'),
    VirtualKey(label: 'C-Z (Пауза)', value: 'ctrl+z'),
    VirtualKey(label: 'HOME', value: '\x1b[H'),
    VirtualKey(label: 'END', value: '\x1b[F'),
    VirtualKey(label: 'PGUP', value: '\x1b[5~'),
    VirtualKey(label: 'PGDN', value: '\x1b[6~'),
    VirtualKey(label: 'C-A (В начало)', value: '\x01'),
    VirtualKey(label: 'C-E (В конец)', value: '\x05'),
    VirtualKey(label: 'C-U (Стереть строку)', value: '\x15'),
    VirtualKey(label: 'C-W (Стереть слово)', value: '\x17'),
  ];

  static const List<Map<String, String>> _quickSnippets = [
    {'label': 'flutter pub get', 'cmd': 'flutter pub get\n', 'badge': 'Flutter'},
    {'label': 'flutter run', 'cmd': 'flutter run\n', 'badge': 'Flutter'},
    {'label': 'flutter build apk', 'cmd': 'flutter build apk --release --target-platform android-arm64\n', 'badge': 'Build'},
    {'label': 'flutter analyze', 'cmd': 'flutter analyze\n', 'badge': 'Check'},
    {'label': 'flutter clean', 'cmd': 'flutter clean\n', 'badge': 'Clean'},
    {'label': 'git status', 'cmd': 'git status\n', 'badge': 'Git'},
    {'label': 'git log (граф)', 'cmd': 'git log --oneline --graph --decorate -n 20\n', 'badge': 'Git'},
    {'label': 'git pull', 'cmd': 'git pull\n', 'badge': 'Git'},
    {'label': 'git push', 'cmd': 'git push\n', 'badge': 'Git'},
    {'label': 'ls -la', 'cmd': 'ls -la\n', 'badge': 'Shell'},
    {'label': 'df -h & free -m', 'cmd': 'df -h && free -m\n', 'badge': 'Sys'},
    {'label': './gradlew assembleDebug', 'cmd': 'bash ./gradlew assembleDebug\n', 'badge': 'Gradle'},
  ];

  static const List<String> _extraSymbols = [
    '~', '\$', '&', '*', ';', ':', '"', "'", '`',
    '(', ')', '{', '}', '[', ']', '<', '>', '\\',
    '=', '+', '?', '!', '@', '#', '%', '^', ',',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF11131A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
            child: Row(
              children: [
                const Icon(LucideIcons.terminal, size: 16, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                Text(
                  'Дополнительные клавиши и команды',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 16, color: Colors.white54),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(14),
              children: [
                _buildSectionHeader('УПРАВЛЕНИЕ И ВЫДЕЛЕНИЕ', LucideIcons.sliders_horizontal),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _controlKeys.map((k) {
                    return _VirtualKeyButton(
                      keyData: k,
                      isActive: false,
                      onTap: () => onKeyTap(k.value ?? k.label),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                _buildSectionHeader('БЫСТРЫЕ КОМАНДЫ В ТЕРМИНАЛ', LucideIcons.zap),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _quickSnippets.map((item) {
                    return InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onKeyTap('cmd:${item['cmd']!}');
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1E29),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.22)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.cyanAccent.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item['badge']!,
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.cyanAccent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              item['label']!,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                _buildSectionHeader('СПЕЦСИМВОЛЫ', LucideIcons.code),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _extraSymbols.map((sym) {
                    return _VirtualKeyButton(
                      keyData: VirtualKey(label: sym, value: sym),
                      isActive: false,
                      onTap: () => onKeyTap(sym),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 12, color: Colors.white54),
        const SizedBox(width: 6),
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Colors.white54,
          ),
        ),
      ],
    );
  }
}

class _VirtualKeyButton extends StatelessWidget {
  final VirtualKey keyData;
  final bool isActive;
  final bool isHighlightedAction;
  final VoidCallback onTap;

  const _VirtualKeyButton({
    required this.keyData,
    required this.isActive,
    this.isHighlightedAction = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color buttonColor = Colors.white.withValues(alpha: 0.06);
    Color borderColor = Colors.white.withValues(alpha: 0.09);
    Color themeColor = Colors.white.withValues(alpha: 0.82);

    if (isActive) {
      buttonColor = Colors.cyanAccent.withValues(alpha: 0.25);
      borderColor = Colors.cyanAccent.withValues(alpha: 0.6);
      themeColor = Colors.cyanAccent;
    } else if (isHighlightedAction) {
      buttonColor = const Color(0xFF0EA5E9).withValues(alpha: 0.2);
      borderColor = const Color(0xFF38BDF8).withValues(alpha: 0.45);
      themeColor = const Color(0xFF7DD3FC);
    } else if (keyData.value == 'ctrl+c' || keyData.value == 'ctrl+z') {
      buttonColor = Colors.redAccent.withValues(alpha: 0.12);
      borderColor = Colors.redAccent.withValues(alpha: 0.28);
      themeColor = const Color(0xFFFF6B6B);
    } else if (keyData.value == 'copy' ||
        keyData.value == 'paste' ||
        keyData.value == 'select_all' ||
        keyData.value == 'copy_all_output' ||
        keyData.value == 'inline_selection_mode') {
      buttonColor = const Color(0xFF8B5CF6).withValues(alpha: 0.16);
      borderColor = const Color(0xFF8B5CF6).withValues(alpha: 0.34);
      themeColor = const Color(0xFFC084FC);
    }

    final isArrow = keyData.label == '↑' ||
        keyData.label == '↓' ||
        keyData.label == '←' ||
        keyData.label == '→';

    final Widget btn = Material(
      color: buttonColor,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: 24,
          constraints: const BoxConstraints(minWidth: 28),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: borderColor, width: 0.6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (keyData.icon != null) ...[
                Icon(keyData.icon, size: 12, color: themeColor),
                if (keyData.label.isNotEmpty && !isArrow) const SizedBox(width: 3),
              ],
              if (keyData.icon == null || (keyData.label.isNotEmpty && !isArrow))
                Flexible(
                  child: Text(
                    keyData.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      color: themeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (keyData.tooltip != null && keyData.tooltip!.isNotEmpty) {
      return Tooltip(
        message: keyData.tooltip!,
        waitDuration: const Duration(milliseconds: 500),
        child: btn,
      );
    }
    return btn;
  }
}

