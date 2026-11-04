import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:quantum_ide/core/services/quantum_plugin_service.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/ui_customizer_modal.dart';
import 'package:quantum_ide/features/terminal/engine/quantum_terminal_action_bar.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

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
  List<VirtualKey> _getCompactKeys(bool isRu) => [
    VirtualKey(label: 'ESC', value: '\x1b', tooltip: 'Escape'),
    VirtualKey(label: 'TAB', value: '\t', tooltip: isRu ? 'Tab / Автодополнение' : 'Tab / Autocomplete'),
    VirtualKey(label: 'CTRL', value: 'ctrl', isToggle: true, tooltip: isRu ? 'Зажать Ctrl' : 'Toggle Ctrl'),
    VirtualKey(label: 'ALT', value: 'ALT', isToggle: true, tooltip: isRu ? 'Зажать Alt' : 'Toggle Alt'),
    VirtualKey(label: 'C-C', value: 'ctrl+c', tooltip: isRu ? 'Прервать процесс (Ctrl+C)' : 'Interrupt process (Ctrl+C)'),
    VirtualKey(label: 'PASTE', value: 'paste', icon: LucideIcons.clipboard_paste, tooltip: isRu ? 'Вставить из буфера' : 'Paste from clipboard'),
    VirtualKey(label: '←', value: '\x1b[D', icon: LucideIcons.arrow_left, tooltip: isRu ? 'Влево' : 'Left'),
    VirtualKey(label: '↑', value: '\x1b[A', icon: LucideIcons.arrow_up, tooltip: isRu ? 'Вверх' : 'Up'),
    VirtualKey(label: '↓', value: '\x1b[B', icon: LucideIcons.arrow_down, tooltip: isRu ? 'Вниз' : 'Down'),
    VirtualKey(label: '→', value: '\x1b[C', icon: LucideIcons.arrow_right, tooltip: isRu ? 'Вправо' : 'Right'),
  ];

  List<VirtualKey> _getRow1Keys(bool isRu) => [
    VirtualKey(label: 'ESC', value: '\x1b', tooltip: 'Escape'),
    VirtualKey(label: 'TAB', value: '\t', tooltip: isRu ? 'Tab / Автодополнение' : 'Tab / Autocomplete'),
    VirtualKey(label: 'CTRL', value: 'ctrl', isToggle: true, tooltip: isRu ? 'Зажать Ctrl' : 'Toggle Ctrl'),
    VirtualKey(label: 'ALT', value: 'ALT', isToggle: true, tooltip: isRu ? 'Зажать Alt' : 'Toggle Alt'),
    VirtualKey(label: 'SHIFT', value: 'SHIFT', isToggle: true, tooltip: isRu ? 'Зажать Shift' : 'Toggle Shift'),
    VirtualKey(label: 'PASTE', value: 'paste', icon: LucideIcons.clipboard_paste, tooltip: isRu ? 'Вставить из буфера' : 'Paste from clipboard'),
    VirtualKey(label: 'C-C', value: 'ctrl+c', tooltip: isRu ? 'Прервать процесс (Ctrl+C)' : 'Interrupt process (Ctrl+C)'),
  ];

  static const List<VirtualKey> _row2Keys = [
    VirtualKey(label: '~', value: '~'),
    VirtualKey(label: '/', value: '/'),
    VirtualKey(label: '-', value: '-'),
    VirtualKey(label: '_', value: '_'),
    VirtualKey(label: '|', value: '|'),
    VirtualKey(label: '\\', value: '\\'),
    VirtualKey(label: '"', value: '"'),
    VirtualKey(label: '\'', value: '\''),
    VirtualKey(label: ':', value: ':'),
    VirtualKey(label: ';', value: ';'),
    VirtualKey(label: '=', value: '='),
    VirtualKey(label: '.', value: '.'),
  ];

  static String _keyToId(String label) {
    switch (label) {
      case 'ESC': return 'esc';
      case 'TAB': return 'tab';
      case 'CTRL': return 'ctrl';
      case 'ALT': return 'alt';
      case 'SHIFT': return 'shift';
      case 'PASTE': return 'paste';
      case 'C-C': return 'cc';
      case 'DEL': return 'del';
      case 'END': return 'end';
      case '↑': return 'arr_u';
      case '↓': return 'arr_d';
      case '←': return 'arr_l';
      case '→': return 'arr_r';
      case '~': return 'sym_tilde';
      case '/': return 'sym_slash';
      case '-': return 'sym_dash';
      case '_': return 'sym_underscore';
      case '|': return 'sym_pipe';
      case '\\': return 'sym_backslash';
      case '"': return 'sym_quote';
      case '\'': return 'sym_singlequote';
      case ':': return 'sym_colon';
      case ';': return 'sym_semicolon';
      case '=': return 'sym_equal';
      case '.': return 'sym_dot';
      default: return label;
    }
  }

  void _showMoreCommandsSheet(BuildContext context, bool isRu) {
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
          initialChildSize: 0.58,
          minChildSize: 0.35,
          maxChildSize: 0.88,
          expand: false,
          builder: (_, scrollController) {
            return _MoreTerminalCommandsSheet(
              isRu: isRu,
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

  Widget _buildKeyRow(
    List<VirtualKey> rowKeys, {
    Widget? trailingFixed,
    double height = 29,
    double fontSize = 10.5,
  }) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
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
                              height: (height - 5).clamp(20.0, 42.0),
                              fontSize: fontSize,
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
                      height: (height - 5).clamp(20.0, 42.0),
                      fontSize: fontSize,
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
              margin: const EdgeInsets.symmetric(horizontal: 3),
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
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final l10n = AppLocalizations.of(context);
    final kbLabel = l10n?.keypadKb ?? 'KB';
    final isKeybActive = widget.activeKeys.contains('KEYB') ||
        widget.activeKeys.contains('toggle_keyboard') ||
        widget.activeKeys.contains('Клава') ||
        widget.activeKeys.contains('KB') ||
        widget.activeKeys.contains(kbLabel);

    final pluginState = ref.watch(quantumPluginServiceProvider);
    final termLayout = pluginState.terminalLayout;
    if (termLayout != null && !termLayout.showVirtualKeys) {
      return const SizedBox.shrink();
    }

    final double effectiveHeight = termLayout?.keyHeight ?? 29.0;
    final double effectiveFontSize = termLayout?.keyFontSize ?? 10.5;
    final barConfig = ref.watch(quantumTerminalBarProvider);
    final isCompactMode = widget.isCompact || barConfig.isCompact || (termLayout?.isCompact ?? false);
    final showMore = (termLayout?.showActionBar ?? true) && barConfig.showMoreButton;

    final keybButton = _VirtualKeyButton(
      fixedWidth: 50,
      height: (effectiveHeight - 5).clamp(20.0, 42.0),
      fontSize: effectiveFontSize,
      keyData: VirtualKey(
        label: kbLabel,
        value: 'toggle_keyboard',
        icon: LucideIcons.keyboard,
        tooltip: isRu ? 'Клавиатура (удержание — настройки кнопок)' : 'Keyboard (Hold to configure buttons)',
      ),
      isActive: isKeybActive,
      isHighlightedAction: true,
      onTap: () => widget.onKeyTap('toggle_keyboard'),
      onLongPress: () => UiCustomizerModal.show(context, isRu: isRu),
    );

    bool isKeyEnabled(String id) {
      if (termLayout != null && termLayout.keys.isNotEmpty) {
        final match = termLayout.keys.where((k) => k.id == id);
        if (match.isNotEmpty) return match.first.isEnabled;
      }
      final match = barConfig.keys.where((k) => k.id == id);
      if (match.isEmpty) return true;
      return match.first.isEnabled;
    }

    final customKeys = <VirtualKey>[];
    if (termLayout != null && termLayout.keys.isNotEmpty) {
      for (final k in termLayout.keys.where((k) => k.isEnabled && k.id.startsWith('custom_'))) {
        customKeys.add(VirtualKey(
          label: k.label,
          value: k.value,
          icon: k.icon,
          isCommand: true,
          tooltip: k.tooltip,
        ));
      }
    } else {
      for (final k in barConfig.keys.where((k) => k.isEnabled && (k.isCommand || k.isPlugin || k.id.startsWith('custom_')))) {
        customKeys.add(VirtualKey(
          label: k.label,
          value: k.value,
          icon: k.icon,
          isCommand: k.isCommand,
          tooltip: k.tooltip,
        ));
      }
    }

    final moreButton = _VirtualKeyButton(
      fixedWidth: 50,
      height: (effectiveHeight - 5).clamp(20.0, 42.0),
      fontSize: effectiveFontSize,
      keyData: VirtualKey(
        label: l10n?.keypadMore ?? 'More',
        value: 'more_commands',
        icon: LucideIcons.layout_grid,
        tooltip: isRu ? 'Все команды, сочетания клавиш и спецсимволы' : 'All commands, shortcuts & symbols',
      ),
      isActive: false,
      isHighlightedAction: false,
      onTap: () => _showMoreCommandsSheet(context, isRu),
    );

    if (isCompactMode) {
      final compactKeys = _getCompactKeys(isRu).where((k) {
        final id = _keyToId(k.label);
        return isKeyEnabled(id);
      }).toList();

      final trailingCompact = <Widget>[
        keybButton,
        if (showMore) ...[
          const SizedBox(width: 3),
          moreButton,
        ],
      ];

      return SafeArea(
        top: false,
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0F14).withValues(alpha: 0.98),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.6)),
          ),
          child: _buildKeyRow(
            [...compactKeys, ...customKeys],
            height: effectiveHeight,
            fontSize: effectiveFontSize,
            trailingFixed: Row(
              mainAxisSize: MainAxisSize.min,
              children: trailingCompact,
            ),
          ),
        ),
      );
    }

    // Trailing Row 1 (DEL, ↑, END, Keyboard)
    final trailingRow1List = <Widget>[];
    if (isKeyEnabled('del')) {
      trailingRow1List.add(_VirtualKeyButton(
        fixedWidth: 34,
        height: (effectiveHeight - 5).clamp(20.0, 42.0),
        fontSize: effectiveFontSize,
        keyData: VirtualKey(
          label: 'DEL',
          value: '\x7f',
          icon: LucideIcons.delete,
          tooltip: isRu ? 'Удалить символ (Backspace / Delete)' : 'Delete character (Backspace / Delete)',
        ),
        isActive: false,
        onTap: () => widget.onKeyTap('\x7f'),
      ));
    }
    if (isKeyEnabled('arr_u')) {
      if (trailingRow1List.isNotEmpty) trailingRow1List.add(const SizedBox(width: 3));
      trailingRow1List.add(_VirtualKeyButton(
        fixedWidth: 34,
        height: (effectiveHeight - 5).clamp(20.0, 42.0),
        fontSize: effectiveFontSize,
        keyData: VirtualKey(
          label: '↑',
          value: '\x1b[A',
          icon: LucideIcons.arrow_up,
          tooltip: isRu ? 'Вверх (история команд)' : 'Up (Command history)',
        ),
        isActive: false,
        onTap: () => widget.onKeyTap('\x1b[A'),
      ));
    }
    if (isKeyEnabled('end')) {
      if (trailingRow1List.isNotEmpty) trailingRow1List.add(const SizedBox(width: 3));
      trailingRow1List.add(_VirtualKeyButton(
        fixedWidth: 34,
        height: (effectiveHeight - 5).clamp(20.0, 42.0),
        fontSize: effectiveFontSize,
        keyData: VirtualKey(
          label: 'END',
          value: '\x1b[F',
          tooltip: isRu ? 'В конец строки (End)' : 'End of line (End)',
        ),
        isActive: false,
        onTap: () => widget.onKeyTap('\x1b[F'),
      ));
    }
    if (trailingRow1List.isNotEmpty) trailingRow1List.add(const SizedBox(width: 4));
    trailingRow1List.add(keybButton);

    final trailingRow1 = Row(
      mainAxisSize: MainAxisSize.min,
      children: trailingRow1List,
    );

    // Trailing Row 2 (←, ↓, →, More)
    final trailingRow2List = <Widget>[];
    if (isKeyEnabled('arr_l')) {
      trailingRow2List.add(_VirtualKeyButton(
        fixedWidth: 34,
        height: (effectiveHeight - 5).clamp(20.0, 42.0),
        fontSize: effectiveFontSize,
        keyData: VirtualKey(
          label: '←',
          value: '\x1b[D',
          icon: LucideIcons.arrow_left,
          tooltip: isRu ? 'Влево' : 'Left',
        ),
        isActive: false,
        onTap: () => widget.onKeyTap('\x1b[D'),
      ));
    }
    if (isKeyEnabled('arr_d')) {
      if (trailingRow2List.isNotEmpty) trailingRow2List.add(const SizedBox(width: 3));
      trailingRow2List.add(_VirtualKeyButton(
        fixedWidth: 34,
        height: (effectiveHeight - 5).clamp(20.0, 42.0),
        fontSize: effectiveFontSize,
        keyData: VirtualKey(
          label: '↓',
          value: '\x1b[B',
          icon: LucideIcons.arrow_down,
          tooltip: isRu ? 'Вниз' : 'Down',
        ),
        isActive: false,
        onTap: () => widget.onKeyTap('\x1b[B'),
      ));
    }
    if (isKeyEnabled('arr_r')) {
      if (trailingRow2List.isNotEmpty) trailingRow2List.add(const SizedBox(width: 3));
      trailingRow2List.add(_VirtualKeyButton(
        fixedWidth: 34,
        height: (effectiveHeight - 5).clamp(20.0, 42.0),
        fontSize: effectiveFontSize,
        keyData: VirtualKey(
          label: '→',
          value: '\x1b[C',
          icon: LucideIcons.arrow_right,
          tooltip: isRu ? 'Вправо' : 'Right',
        ),
        isActive: false,
        onTap: () => widget.onKeyTap('\x1b[C'),
      ));
    }
    if (showMore) {
      if (trailingRow2List.isNotEmpty) trailingRow2List.add(const SizedBox(width: 4));
      trailingRow2List.add(moreButton);
    }

    final Widget? trailingRow2 = trailingRow2List.isEmpty
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: trailingRow2List,
          );

    final filteredRow1 = _getRow1Keys(isRu).where((k) => isKeyEnabled(_keyToId(k.label))).toList();
    final filteredRow2 = _row2Keys.where((k) => isKeyEnabled(_keyToId(k.label))).toList();

    return SafeArea(
      top: false,
      bottom: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0F14).withValues(alpha: 0.98),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildKeyRow(
              [...filteredRow1, ...customKeys],
              height: effectiveHeight,
              fontSize: effectiveFontSize,
              trailingFixed: trailingRow1,
            ),
            const SizedBox(height: 3),
            _buildKeyRow(
              filteredRow2,
              height: effectiveHeight,
              fontSize: effectiveFontSize,
              trailingFixed: trailingRow2,
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreTerminalCommandsSheet extends StatelessWidget {
  final bool isRu;
  final ScrollController scrollController;
  final Function(String) onKeyTap;

  const _MoreTerminalCommandsSheet({
    required this.isRu,
    required this.scrollController,
    required this.onKeyTap,
  });

  List<VirtualKey> _getControlKeys() => [
    VirtualKey(label: isRu ? 'Клавиатура' : 'Keyboard', value: 'toggle_keyboard', icon: LucideIcons.keyboard, tooltip: isRu ? 'Показать/скрыть клавиатуру' : 'Toggle keyboard'),
    VirtualKey(label: isRu ? 'Выделить всё' : 'Select All', value: 'select_all', icon: LucideIcons.check_check),
    VirtualKey(label: isRu ? 'Скопировать всё' : 'Copy All', value: 'copy_all_output', icon: LucideIcons.clipboard_copy),
    VirtualKey(label: isRu ? 'Окно текста' : 'Text Selection', value: 'selection_mode', icon: LucideIcons.file_text),
    VirtualKey(label: isRu ? 'Очистить (C-L)' : 'Clear (C-L)', value: 'ctrl+l', icon: LucideIcons.eraser),
    const VirtualKey(label: 'C-D (EOF)', value: 'ctrl+d'),
    VirtualKey(label: isRu ? 'C-Z (Пауза)' : 'C-Z (Suspend)', value: 'ctrl+z'),
    const VirtualKey(label: 'HOME', value: '\x1b[H'),
    const VirtualKey(label: 'END', value: '\x1b[F'),
    const VirtualKey(label: 'PGUP', value: '\x1b[5~'),
    const VirtualKey(label: 'PGDN', value: '\x1b[6~'),
    VirtualKey(label: isRu ? 'C-A (В начало)' : 'C-A (Line Start)', value: '\x01'),
    VirtualKey(label: isRu ? 'C-E (В конец)' : 'C-E (Line End)', value: '\x05'),
    VirtualKey(label: isRu ? 'C-U (Стереть строку)' : 'C-U (Erase Line)', value: '\x15'),
    VirtualKey(label: isRu ? 'C-W (Стереть слово)' : 'C-W (Erase Word)', value: '\x17'),
  ];

  List<Map<String, String>> _getQuickSnippets() => [
    {'label': 'flutter pub get', 'cmd': 'flutter pub get\n', 'badge': 'Flutter'},
    {'label': 'flutter run', 'cmd': 'flutter run\n', 'badge': 'Flutter'},
    {'label': 'flutter build apk', 'cmd': 'flutter build apk --release --target-platform android-arm64 --android-skip-build-dependency-validation\n', 'badge': 'Build'},
    {'label': 'flutter build appbundle', 'cmd': 'flutter build appbundle --release --target-platform android-arm64 --android-skip-build-dependency-validation\n', 'badge': 'Build'},
    {'label': 'flutter analyze', 'cmd': 'flutter analyze\n', 'badge': 'Check'},
    {'label': 'flutter clean', 'cmd': 'flutter clean\n', 'badge': 'Clean'},
    {'label': 'git status', 'cmd': 'git status\n', 'badge': 'Git'},
    {'label': isRu ? 'git log (граф)' : 'git log (graph)', 'cmd': 'git log --oneline --graph --decorate -n 20\n', 'badge': 'Git'},
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
                  isRu ? 'Дополнительные клавиши и команды' : 'Additional Keys & Commands',
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
                // Настройка кнопок и плагинов
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: Material(
                    color: Colors.cyanAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        Navigator.of(context).pop();
                        TerminalBarCustomizerSheet.show(context, isRu: isRu);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.sliders_horizontal, size: 16, color: Colors.cyanAccent),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isRu ? 'Настроить кнопки и плагины терминала' : 'Configure Terminal Keys & Plugins',
                                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                                  ),
                                  Text(
                                    isRu ? 'Скрыть/добавить кнопки, убрать кнопку «Ещё», свои команды' : 'Toggle "More" button, add custom commands, manage plugin keys',
                                    style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white60),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(LucideIcons.chevron_right, size: 16, color: Colors.cyanAccent),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                _buildSectionHeader(isRu ? 'УПРАВЛЕНИЕ И ВЫДЕЛЕНИЕ' : 'NAVIGATION & SELECTION', LucideIcons.sliders_horizontal),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _getControlKeys().map((k) {
                    return _VirtualKeyButton(
                      keyData: k,
                      isActive: false,
                      onTap: () => onKeyTap(k.value ?? k.label),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                _buildSectionHeader(isRu ? 'БЫСТРЫЕ КОМАНДЫ В ТЕРМИНАЛ' : 'QUICK COMMANDS', LucideIcons.zap),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _getQuickSnippets().map((item) {
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
                _buildSectionHeader(isRu ? 'СПЕЦСИМВОЛЫ' : 'SPECIAL SYMBOLS', LucideIcons.code),
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
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
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
  final double? fixedWidth;
  final double height;
  final double fontSize;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _VirtualKeyButton({
    required this.keyData,
    required this.isActive,
    this.isHighlightedAction = false,
    this.fixedWidth,
    this.height = 24,
    this.fontSize = 10,
    required this.onTap,
    this.onLongPress,
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
    } else if (keyData.value == 'toggle_keyboard') {
      buttonColor = const Color(0xFF10B981).withValues(alpha: 0.18);
      borderColor = const Color(0xFF34D399).withValues(alpha: 0.45);
      themeColor = const Color(0xFF6EE7B7);
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
        onLongPress: onLongPress != null
            ? () {
                HapticFeedback.mediumImpact();
                onLongPress!();
              }
            : null,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: height,
          width: fixedWidth,
          constraints: fixedWidth == null ? const BoxConstraints(minWidth: 28) : null,
          padding: EdgeInsets.symmetric(horizontal: fixedWidth != null ? 2 : 6),
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
                Icon(keyData.icon, size: (fontSize + 2.0).clamp(11.0, 18.0), color: themeColor),
                if (keyData.label.isNotEmpty && !isArrow && fixedWidth == null) const SizedBox(width: 3),
              ],
              if (keyData.icon == null || (keyData.label.isNotEmpty && !isArrow))
                Flexible(
                  child: Text(
                    keyData.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      color: themeColor,
                      fontSize: isArrow ? (fontSize + 1.5) : fontSize,
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
        waitDuration: const Duration(milliseconds: 400),
        child: btn,
      );
    }
    return btn;
  }
}
