import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/core/services/quantum_plugin_service.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/ui_customizer_modal.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

/// Configuration definition for a terminal action bar key/button.
class TerminalActionKey {
  final String id;
  final String label;
  final String value;
  final String iconName;
  final bool isToggle;
  final bool isCommand;
  final bool isPlugin;
  final bool isEnabled;
  final String? tooltip;

  const TerminalActionKey({
    required this.id,
    required this.label,
    required this.value,
    this.iconName = '',
    this.isToggle = false,
    this.isCommand = false,
    this.isPlugin = false,
    this.isEnabled = true,
    this.tooltip,
  });

  TerminalActionKey copyWith({
    String? id,
    String? label,
    String? value,
    String? iconName,
    bool? isToggle,
    bool? isCommand,
    bool? isPlugin,
    bool? isEnabled,
    String? tooltip,
  }) {
    return TerminalActionKey(
      id: id ?? this.id,
      label: label ?? this.label,
      value: value ?? this.value,
      iconName: iconName ?? this.iconName,
      isToggle: isToggle ?? this.isToggle,
      isCommand: isCommand ?? this.isCommand,
      isPlugin: isPlugin ?? this.isPlugin,
      isEnabled: isEnabled ?? this.isEnabled,
      tooltip: tooltip ?? this.tooltip,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'value': value,
        'iconName': iconName,
        'isToggle': isToggle,
        'isCommand': isCommand,
        'isPlugin': isPlugin,
        'isEnabled': isEnabled,
        'tooltip': tooltip,
      };

  factory TerminalActionKey.fromJson(Map<String, dynamic> json) => TerminalActionKey(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        value: json['value'] as String? ?? '',
        iconName: json['iconName'] as String? ?? '',
        isToggle: json['isToggle'] as bool? ?? false,
        isCommand: json['isCommand'] as bool? ?? false,
        isPlugin: json['isPlugin'] as bool? ?? false,
        isEnabled: json['isEnabled'] as bool? ?? true,
        tooltip: json['tooltip'] as String?,
      );

  IconData? get icon {
    if (iconName.isEmpty) return null;
    return PluginIconRegistry.getIconByName(iconName);
  }
}

/// State of the Quantum Terminal Action Bar
class QuantumTerminalBarState {
  final List<TerminalActionKey> keys;
  final bool showMoreButton;
  final bool isCompact;

  const QuantumTerminalBarState({
    required this.keys,
    this.showMoreButton = true,
    this.isCompact = false,
  });

  QuantumTerminalBarState copyWith({
    List<TerminalActionKey>? keys,
    bool? showMoreButton,
    bool? isCompact,
  }) {
    return QuantumTerminalBarState(
      keys: keys ?? this.keys,
      showMoreButton: showMoreButton ?? this.showMoreButton,
      isCompact: isCompact ?? this.isCompact,
    );
  }
}

/// Riverpod notifier managing customizable terminal keys, plugin buttons and toggle states
class QuantumTerminalBarNotifier extends StateNotifier<QuantumTerminalBarState> {
  static const String _prefsKey = 'quantum_terminal_action_bar_v3';

  QuantumTerminalBarNotifier() : super(const QuantumTerminalBarState(keys: [])) {
    _loadConfiguration();
  }

  static List<TerminalActionKey> getDefaultKeys() => [
        // Ряд 1: Основные клавиши управления и модификаторы
        const TerminalActionKey(id: 'esc', label: 'ESC', value: '\x1b', tooltip: 'Escape'),
        const TerminalActionKey(id: 'tab', label: 'TAB', value: '\t', tooltip: 'Tab / Autocomplete'),
        const TerminalActionKey(id: 'ctrl', label: 'CTRL', value: 'ctrl', isToggle: true, tooltip: 'Hold Ctrl'),
        const TerminalActionKey(id: 'alt', label: 'ALT', value: 'ALT', isToggle: true, tooltip: 'Hold Alt'),
        const TerminalActionKey(id: 'shift', label: 'SHIFT', value: 'SHIFT', isToggle: true, tooltip: 'Hold Shift'),
        const TerminalActionKey(id: 'enter', label: 'ENTER', value: '\r', iconName: 'corner_down_left', tooltip: 'Enter / Confirm'),
        const TerminalActionKey(id: 'paste', label: 'PASTE', value: 'paste', iconName: 'clipboard_paste', tooltip: 'Paste from clipboard'),
        const TerminalActionKey(id: 'cc', label: 'C-C', value: 'ctrl+c', tooltip: 'Interrupt process (Ctrl+C)'),
        const TerminalActionKey(id: 'del', label: 'DEL', value: '\x7f', iconName: 'delete', tooltip: 'Delete'),
        const TerminalActionKey(id: 'arr_u', label: '↑', value: '\x1b[A', iconName: 'arrow_up', tooltip: 'Up (History)'),
        const TerminalActionKey(id: 'end', label: 'END', value: '\x1b[F', tooltip: 'End'),

        // Ряд 2: Спецсимволы и стрелки навигации
        const TerminalActionKey(id: 'sym_tilde', label: '~', value: '~'),
        const TerminalActionKey(id: 'sym_slash', label: '/', value: '/'),
        const TerminalActionKey(id: 'sym_dash', label: '-', value: '-'),
        const TerminalActionKey(id: 'sym_underscore', label: '_', value: '_'),
        const TerminalActionKey(id: 'sym_pipe', label: '|', value: '|'),
        const TerminalActionKey(id: 'sym_backslash', label: '\\', value: '\\'),
        const TerminalActionKey(id: 'sym_quote', label: '"', value: '"'),
        const TerminalActionKey(id: 'sym_singlequote', label: '\'', value: '\''),
        const TerminalActionKey(id: 'sym_colon', label: ':', value: ':'),
        const TerminalActionKey(id: 'sym_semicolon', label: ';', value: ';'),
        const TerminalActionKey(id: 'sym_equal', label: '=', value: '='),
        const TerminalActionKey(id: 'sym_dot', label: '.', value: '.'),
        const TerminalActionKey(id: 'arr_l', label: '←', value: '\x1b[D', iconName: 'arrow_left', tooltip: 'Left'),
        const TerminalActionKey(id: 'arr_d', label: '↓', value: '\x1b[B', iconName: 'arrow_down', tooltip: 'Down'),
        const TerminalActionKey(id: 'arr_r', label: '→', value: '\x1b[C', iconName: 'arrow_right', tooltip: 'Right'),
      ];

  Future<void> _loadConfiguration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final Map<String, dynamic> data = jsonDecode(raw);
        final bool showMore = data['showMoreButton'] as bool? ?? true;
        final bool compact = data['isCompact'] as bool? ?? false;
        final List rawKeys = data['keys'] as List? ?? [];
        final loadedKeys = rawKeys.map((e) => TerminalActionKey.fromJson(e as Map<String, dynamic>)).toList();

        // Ensure baseline keys exist if missing
        final defaults = getDefaultKeys();
        for (final def in defaults) {
          if (!loadedKeys.any((k) => k.id == def.id)) {
            loadedKeys.add(def);
          }
        }

        state = QuantumTerminalBarState(
          keys: loadedKeys,
          showMoreButton: showMore,
          isCompact: compact,
        );
        return;
      }
    } catch (_) {}

    state = QuantumTerminalBarState(keys: getDefaultKeys());
  }

  Future<void> _saveConfiguration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'showMoreButton': state.showMoreButton,
        'isCompact': state.isCompact,
        'keys': state.keys.map((k) => k.toJson()).toList(),
      };
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (_) {}
  }

  /// Toggle button visibility on the action bar
  void toggleKeyVisibility(String id) {
    state = state.copyWith(
      keys: state.keys.map((k) => k.id == id ? k.copyWith(isEnabled: !k.isEnabled) : k).toList(),
    );
    _saveConfiguration();
  }

  /// Toggle the 'More' («Ещё») button visibility
  void toggleShowMoreButton() {
    state = state.copyWith(showMoreButton: !state.showMoreButton);
    _saveConfiguration();
  }

  /// Toggle compact single-row mode vs standard mode
  void toggleCompactMode() {
    state = state.copyWith(isCompact: !state.isCompact);
    _saveConfiguration();
  }

  /// Add a custom user command button
  void addCustomCommandKey({
    required String label,
    required String command,
    String iconName = 'terminal',
    String? tooltip,
  }) {
    final newKey = TerminalActionKey(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      label: label,
      value: command.endsWith('\n') ? command : '$command\n',
      iconName: iconName,
      isCommand: true,
      isEnabled: true,
      tooltip: tooltip ?? 'Выполнить: $command',
    );

    state = state.copyWith(keys: [...state.keys, newKey]);
    _saveConfiguration();
  }

  /// Delete a custom button
  void removeKey(String id) {
    state = state.copyWith(
      keys: state.keys.where((k) => k.id != id).toList(),
    );
    _saveConfiguration();
  }

  /// Reorder buttons
  void reorderKeys(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.keys.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final items = List<TerminalActionKey>.from(state.keys);
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);
    state = state.copyWith(keys: items);
    _saveConfiguration();
  }

  /// Synchronize dynamic buttons declared by user plugins and extensions
  void syncPluginButtons(List<CustomTerminalCommand> pluginCommands, List<CustomUiButton> uiButtons) {
    final currentKeys = List<TerminalActionKey>.from(state.keys);
    bool changed = false;

    // 1. Process custom terminal commands from plugins
    for (final cmd in pluginCommands) {
      final pluginKeyId = 'plugin_cmd_${cmd.name.toLowerCase().replaceAll(' ', '_')}';
      if (!currentKeys.any((k) => k.id == pluginKeyId)) {
        currentKeys.add(TerminalActionKey(
          id: pluginKeyId,
          label: cmd.name,
          value: cmd.command.endsWith('\n') ? cmd.command : '${cmd.command}\n',
          iconName: cmd.iconName,
          isCommand: true,
          isPlugin: true,
          isEnabled: true,
          tooltip: 'Плагин: ${cmd.description.isNotEmpty ? cmd.description : cmd.command}',
        ));
        changed = true;
      }
    }

    // 2. Process UI buttons from plugins targeted at terminal
    for (final btn in uiButtons) {
      if (btn.action == 'command') {
        final btnId = 'plugin_btn_${btn.id}';
        if (!currentKeys.any((k) => k.id == btnId)) {
          currentKeys.add(TerminalActionKey(
            id: btnId,
            label: btn.label,
            value: btn.payload.endsWith('\n') ? btn.payload : '${btn.payload}\n',
            iconName: btn.iconName,
            isCommand: true,
            isPlugin: true,
            isEnabled: true,
            tooltip: 'Плагин: ${btn.tooltip.isNotEmpty ? btn.tooltip : btn.label}',
          ));
          changed = true;
        }
      }
    }

    if (changed) {
      state = state.copyWith(keys: currentKeys);
      _saveConfiguration();
    }
  }

  /// Reset all buttons to factory defaults
  void resetToDefaults() {
    state = QuantumTerminalBarState(
      keys: getDefaultKeys(),
      showMoreButton: true,
      isCompact: false,
    );
    _saveConfiguration();
  }
}

final quantumTerminalBarProvider =
    StateNotifierProvider<QuantumTerminalBarNotifier, QuantumTerminalBarState>((ref) {
  return QuantumTerminalBarNotifier();
});

/// Interactive Action Bar View rendered below/above the terminal
class QuantumTerminalActionBarView extends ConsumerWidget {
  final Function(String) onKeyTap;
  final Set<String> activeKeys;

  const QuantumTerminalActionBarView({
    super.key,
    required this.onKeyTap,
    required this.activeKeys,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final barState = ref.watch(quantumTerminalBarProvider);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final l10n = AppLocalizations.of(context);
    final kbLabel = l10n?.keypadKb ?? 'KB';

    final enabledKeys = barState.keys.where((k) => k.isEnabled).toList();

    final isKeybActive = activeKeys.contains('KEYB') ||
        activeKeys.contains('toggle_keyboard') ||
        activeKeys.contains('Клава') ||
        activeKeys.contains('KB') ||
        activeKeys.contains(kbLabel);

    final keybButton = _ActionKeyButton(
      fixedWidth: 46,
      label: kbLabel,
      icon: LucideIcons.keyboard,
      tooltip: isRu ? 'Клавиатура' : 'Keyboard',
      isActive: isKeybActive,
      isHighlighted: true,
      onTap: () => onKeyTap('toggle_keyboard'),
    );

    final moreButton = barState.showMoreButton
        ? _ActionKeyButton(
            fixedWidth: 46,
            label: l10n?.keypadMore ?? 'More',
            icon: LucideIcons.layout_grid,
            tooltip: isRu ? 'Все команды и настройки панели' : 'More commands & panel settings',
            isActive: false,
            onTap: () => _showCustomizerSheet(context, ref, isRu),
          )
        : null;

    final configButton = _ActionKeyButton(
      fixedWidth: 38,
      label: '',
      icon: LucideIcons.settings_2,
      tooltip: isRu ? 'Настроить кнопки' : 'Configure buttons',
      isActive: false,
      onTap: () => _showCustomizerSheet(context, ref, isRu),
    );

    if (barState.isCompact) {
      return SafeArea(
        top: false,
        bottom: false,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF090B10).withValues(alpha: 0.98),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.6)),
          ),
          child: Row(
            children: [
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  physics: const BouncingScrollPhysics(),
                  itemCount: enabledKeys.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 4),
                  itemBuilder: (context, i) {
                    final key = enabledKeys[i];
                    final isActive = activeKeys.contains(key.label) || activeKeys.contains(key.value);
                    return _ActionKeyButton(
                      label: key.label,
                      icon: key.icon,
                      tooltip: key.tooltip,
                      isActive: isActive,
                      isPlugin: key.isPlugin,
                      onTap: () => onKeyTap(key.value),
                      onLongPress: () => _showCustomizerSheet(context, ref, isRu),
                    );
                  },
                ),
              ),
              Container(
                width: 1,
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                color: Colors.white.withValues(alpha: 0.1),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    keybButton,
                    if (moreButton != null) ...[
                      const SizedBox(width: 3),
                      moreButton,
                    ] else ...[
                      const SizedBox(width: 3),
                      configButton,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Two-row standard layout
    final half = (enabledKeys.length / 2).ceil();
    final row1Keys = enabledKeys.take(half).toList();
    final row2Keys = enabledKeys.skip(half).toList();

    return SafeArea(
      top: false,
      bottom: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF090B10).withValues(alpha: 0.98),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      physics: const BouncingScrollPhysics(),
                      itemCount: row1Keys.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 4),
                      itemBuilder: (context, i) {
                        final key = row1Keys[i];
                        final isActive = activeKeys.contains(key.label) || activeKeys.contains(key.value);
                        return _ActionKeyButton(
                          label: key.label,
                          icon: key.icon,
                          tooltip: key.tooltip,
                          isActive: isActive,
                          isPlugin: key.isPlugin,
                          onTap: () => onKeyTap(key.value),
                          onLongPress: () => _showCustomizerSheet(context, ref, isRu),
                        );
                      },
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 18,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: keybButton,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      physics: const BouncingScrollPhysics(),
                      itemCount: row2Keys.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 4),
                      itemBuilder: (context, i) {
                        final key = row2Keys[i];
                        final isActive = activeKeys.contains(key.label) || activeKeys.contains(key.value);
                        return _ActionKeyButton(
                          label: key.label,
                          icon: key.icon,
                          tooltip: key.tooltip,
                          isActive: isActive,
                          isPlugin: key.isPlugin,
                          onTap: () => onKeyTap(key.value),
                          onLongPress: () => _showCustomizerSheet(context, ref, isRu),
                        );
                      },
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 18,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: moreButton ?? configButton,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomizerSheet(BuildContext context, WidgetRef ref, bool isRu) {
    TerminalBarCustomizerSheet.show(context, isRu: isRu);
  }
}

/// Key Button with modern glass styling and feedback
class _ActionKeyButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final String? tooltip;
  final bool isActive;
  final bool isHighlighted;
  final bool isPlugin;
  final double? fixedWidth;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ActionKeyButton({
    required this.label,
    this.icon,
    this.tooltip,
    this.isActive = false,
    this.isHighlighted = false,
    this.isPlugin = false,
    this.fixedWidth,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0xFF171B26);
    Color border = const Color(0xFF262C3D);
    Color fg = Colors.white.withValues(alpha: 0.88);

    if (isActive) {
      bg = Colors.cyanAccent.withValues(alpha: 0.25);
      border = Colors.cyanAccent;
      fg = Colors.cyanAccent;
    } else if (isHighlighted) {
      bg = const Color(0xFF1E283D);
      border = Colors.cyanAccent.withValues(alpha: 0.4);
      fg = Colors.cyanAccent;
    } else if (isPlugin) {
      bg = const Color(0xFF201A33);
      border = Colors.purpleAccent.withValues(alpha: 0.4);
      fg = const Color(0xFFD6BBFB);
    }

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: fg),
          if (label.isNotEmpty) const SizedBox(width: 4),
        ],
        if (label.isNotEmpty)
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
      ],
    );

    return Tooltip(
      message: tooltip ?? label,
      waitDuration: const Duration(milliseconds: 600),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: fixedWidth,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: border, width: 0.8),
            ),
            alignment: Alignment.center,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Customization sheet allowing users to add/hide buttons, toggle "More" button, and add custom commands
class TerminalBarCustomizerSheet extends ConsumerStatefulWidget {
  final bool isRu;
  const TerminalBarCustomizerSheet({super.key, required this.isRu});

  static void show(BuildContext context, {required bool isRu}) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF10131B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => TerminalBarCustomizerSheet(isRu: isRu),
    );
  }

  @override
  ConsumerState<TerminalBarCustomizerSheet> createState() => _TerminalBarCustomizerSheetState();
}

class _TerminalBarCustomizerSheetState extends ConsumerState<TerminalBarCustomizerSheet> {
  final TextEditingController _cmdLabelController = TextEditingController();
  final TextEditingController _cmdValueController = TextEditingController();

  @override
  void dispose() {
    _cmdLabelController.dispose();
    _cmdValueController.dispose();
    super.dispose();
  }

  void _showAddCommandDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141722),
        title: Text(
          widget.isRu ? 'Добавить кнопку в терминал' : 'Add Terminal Button',
          style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _cmdLabelController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: widget.isRu ? 'Название кнопки (например: Git, Run, Cls)' : 'Button Label',
                labelStyle: const TextStyle(color: Colors.white60),
                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cmdValueController,
              style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent),
              decoration: InputDecoration(
                labelText: widget.isRu ? 'Команда (например: git status, ls -la)' : 'Command',
                labelStyle: const TextStyle(color: Colors.white60),
                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(widget.isRu ? 'Отмена' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
            onPressed: () {
              final label = _cmdLabelController.text.trim();
              final cmd = _cmdValueController.text.trim();
              if (label.isNotEmpty && cmd.isNotEmpty) {
                ref.read(quantumTerminalBarProvider.notifier).addCustomCommandKey(
                      label: label,
                      command: cmd,
                    );
                Navigator.pop(ctx);
                _cmdLabelController.clear();
                _cmdValueController.clear();
              }
            },
            child: Text(
              widget.isRu ? 'Добавить' : 'Add',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final barState = ref.watch(quantumTerminalBarProvider);
    final notifier = ref.read(quantumTerminalBarProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      expand: false,
      builder: (_, scrollController) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Drag Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title and Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.sliders_horizontal, size: 18, color: Colors.cyanAccent),
                      const SizedBox(width: 8),
                      Text(
                        widget.isRu ? 'Конфигурация кнопок терминала' : 'Terminal Action Bar Setup',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.rotate_ccw, size: 16, color: Colors.white60),
                    tooltip: widget.isRu ? 'Сброс по умолчанию' : 'Reset defaults',
                    onPressed: () => notifier.resetToDefaults(),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Banner to open full UI customizer
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  UiCustomizerModal.show(context, isRu: widget.isRu);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.cyanAccent.withValues(alpha: 0.15),
                        Colors.purpleAccent.withValues(alpha: 0.15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.palette, size: 16, color: Colors.cyanAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.isRu
                              ? '🎨 Полная кастомизация UI, вкладок и код для ИИ'
                              : '🎨 Full UI customizer, tabs & code for AI',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      const Icon(LucideIcons.chevron_right, size: 14, color: Colors.cyanAccent),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Quick Toggles: "Show More Button" and "Compact Row"
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        widget.isRu ? 'Отображать кнопку «Ещё» (Все команды)' : 'Show "More" (Grid) button',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        widget.isRu
                            ? 'Если выключено, освободится место для полезных кнопок'
                            : 'Hide to leave more space for custom command keys',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                      ),
                      value: barState.showMoreButton,
                      activeTrackColor: Colors.cyanAccent.withValues(alpha: 0.5),
                      activeThumbColor: Colors.cyanAccent,
                      onChanged: (_) => notifier.toggleShowMoreButton(),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        widget.isRu ? 'Однострочный компактный режим' : 'Single-row compact mode',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        widget.isRu ? '1 ряд клавиш вместо классических 2 рядов' : 'Single horizontal scroll strip',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                      ),
                      value: barState.isCompact,
                      activeTrackColor: Colors.cyanAccent.withValues(alpha: 0.5),
                      activeThumbColor: Colors.cyanAccent,
                      onChanged: (_) => notifier.toggleCompactMode(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Add custom command button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.cyanAccent,
                    side: const BorderSide(color: Colors.cyanAccent, width: 0.8),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: Text(
                    widget.isRu ? 'Добавить свою команду / скрипт' : 'Add Custom Command / Script',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  onPressed: _showAddCommandDialog,
                ),
              ),
              const SizedBox(height: 12),

              Text(
                widget.isRu ? 'Список кнопок (Включить / Выключить / Удалить):' : 'Keys List (Toggle visibility / Delete):',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
              const SizedBox(height: 6),

              // Reorderable / Toggleable list of keys
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: barState.keys.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final key = barState.keys[index];
                    final isCustom = key.id.startsWith('custom_') || key.isPlugin;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: key.isEnabled
                            ? const Color(0xFF161A25)
                            : Colors.white.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: key.isEnabled
                              ? const Color(0xFF283144)
                              : Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            key.icon ?? (key.isCommand ? LucideIcons.terminal : LucideIcons.command),
                            size: 15,
                            color: key.isEnabled ? Colors.cyanAccent : Colors.white38,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      key.label,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: key.isEnabled ? Colors.white : Colors.white38,
                                      ),
                                    ),
                                    if (key.isPlugin) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.purpleAccent.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'PLUGIN',
                                          style: TextStyle(fontSize: 9, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (key.tooltip != null)
                                  Text(
                                    key.tooltip!,
                                    style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white54),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: key.isEnabled,
                            activeTrackColor: Colors.cyanAccent.withValues(alpha: 0.5),
                            activeThumbColor: Colors.cyanAccent,
                            onChanged: (_) => notifier.toggleKeyVisibility(key.id),
                          ),
                          if (isCustom)
                            IconButton(
                              icon: const Icon(LucideIcons.trash_2, size: 15, color: Colors.redAccent),
                              tooltip: widget.isRu ? 'Удалить' : 'Delete',
                              onPressed: () => notifier.removeKey(key.id),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
