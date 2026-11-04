import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/quantum_plugin_service.dart';
import 'package:quantum_ide/features/terminal/engine/quantum_terminal_action_bar.dart';

/// Modal dialog / bottom sheet for comprehensive, live visual customization
/// of QuantumIDE UI, Virtual Keys, Terminal Tabs, Sidebar, and Mobile Navigation.
class UiCustomizerModal extends ConsumerStatefulWidget {
  final bool isRu;
  const UiCustomizerModal({super.key, required this.isRu});

  static Future<void> show(BuildContext context, {required bool isRu}) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1219),
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => UiCustomizerModal(isRu: isRu),
    );
  }

  @override
  ConsumerState<UiCustomizerModal> createState() => _UiCustomizerModalState();
}

class _UiCustomizerModalState extends ConsumerState<UiCustomizerModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Local editable state for real-time live preview
  late double _keyHeight;
  late double _keyFontSize;
  late bool _isCompact;
  late bool _showVirtualKeys;
  late bool _showMoreButton;
  late List<CustomVirtualKey> _keys;

  // Terminal tabs order & disabled
  late List<String> _panelTabsOrder;
  late Set<String> _disabledPanelTabs;

  // Sidebar order & disabled
  late List<String> _sidebarOrder;
  late Set<String> _disabledSidebarSections;

  // Bottom nav
  late bool _showBottomNav;
  late Set<String> _disabledBottomNavButtons;

  bool _isDirty = false;

  static const List<String> _defaultPanelTabs = [
    'terminal',
    'run',
    'buildLogs',
    'appLogs',
    'problems',
    'git',
    'debug',
    'deviceMirror',
    'aiAgent',
  ];

  static const List<String> _defaultSidebarSections = [
    'explorer',
    'search',
    'structure',
    'disk',
    'problems',
    'git',
    'preview',
    'packages',
    'run',
    'build',
    'liveShare',
    'plugins',
    'appLogs',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _initValues();
  }

  void _initValues() {
    final pluginState = ref.read(quantumPluginServiceProvider);
    final termLayout = pluginState.terminalLayout;
    final sideLayout = pluginState.sidebarLayout;
    final navLayout = pluginState.bottomNavLayout;

    _keyHeight = termLayout?.keyHeight ?? 29.0;
    _keyFontSize = termLayout?.keyFontSize ?? 11.0;
    _isCompact = termLayout?.isCompact ?? false;
    _showVirtualKeys = termLayout?.showVirtualKeys ?? true;
    _showMoreButton = termLayout?.showActionBar ?? true;

    if (termLayout != null && termLayout.keys.isNotEmpty) {
      _keys = List.from(termLayout.keys);
    } else {
      // Default keys baseline
      _keys = _getDefaultCustomVirtualKeys();
    }

    _panelTabsOrder = termLayout != null && termLayout.panelTabsOrder.isNotEmpty
        ? List.from(termLayout.panelTabsOrder)
        : List.from(_defaultPanelTabs);
    // Ensure all default tabs are present
    for (final t in _defaultPanelTabs) {
      if (!_panelTabsOrder.contains(t)) _panelTabsOrder.add(t);
    }

    _disabledPanelTabs = termLayout != null
        ? Set.from(termLayout.disabledPanelTabs)
        : <String>{};

    _sidebarOrder = sideLayout != null && sideLayout.sectionOrder.isNotEmpty
        ? List.from(sideLayout.sectionOrder)
        : List.from(_defaultSidebarSections);
    for (final s in _defaultSidebarSections) {
      if (!_sidebarOrder.contains(s)) _sidebarOrder.add(s);
    }

    _disabledSidebarSections = sideLayout != null
        ? Set.from(sideLayout.disabledSections)
        : Set.from(pluginState.disabledTabIds);

    _showBottomNav = navLayout?.showBottomNav ?? true;
    _disabledBottomNavButtons = navLayout != null
        ? Set.from(navLayout.disabledButtons)
        : <String>{};
  }

  List<CustomVirtualKey> _getDefaultCustomVirtualKeys() {
    final barKeys = QuantumTerminalBarNotifier.getDefaultKeys();
    return barKeys.map((k) {
      return CustomVirtualKey(
        id: k.id,
        label: k.label,
        value: k.value,
        iconName: k.iconName,
        isToggle: k.isToggle,
        isEnabled: k.isEnabled,
        row: k.id.startsWith('sym_') || k.id == 'arr_l' || k.id == 'arr_d' || k.id == 'arr_r' ? 2 : 1,
        tooltip: k.tooltip,
      );
    }).toList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    HapticFeedback.mediumImpact();
    final terminalLayout = TerminalUiLayoutConfig(
      showVirtualKeys: _showVirtualKeys,
      showActionBar: _showMoreButton,
      isCompact: _isCompact,
      keyHeight: _keyHeight,
      keyFontSize: _keyFontSize,
      keys: _keys,
      panelTabsOrder: _panelTabsOrder,
      disabledPanelTabs: _disabledPanelTabs.toList(),
    );

    final sidebarLayout = SidebarUiLayoutConfig(
      sectionOrder: _sidebarOrder,
      disabledSections: _disabledSidebarSections.toList(),
    );

    final bottomNavLayout = BottomNavUiLayoutConfig(
      showBottomNav: _showBottomNav,
      disabledButtons: _disabledBottomNavButtons.toList(),
    );

    await ref.read(quantumPluginServiceProvider.notifier).saveUiLayoutPlugin(
          terminalLayout: terminalLayout,
          sidebarLayout: sidebarLayout,
          bottomNavLayout: bottomNavLayout,
        );

    setState(() => _isDirty = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(LucideIcons.circle_check, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                widget.isRu
                    ? 'Раскладка UI сохранена в .quantum/plugins/ui_layout.json!'
                    : 'UI Layout saved to .quantum/plugins/ui_layout.json!',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }
  }

  String _buildAiPromptJson() {
    final payload = {
      "id": "ui_layout_custom",
      "name": "Пользовательская раскладка QuantumIDE",
      "version": "1.0.0",
      "description": "Конфигурация UI кнопок и панелей",
      "author": "User & AI Agent",
      "isEnabled": true,
      "terminalLayout": {
        "showVirtualKeys": _showVirtualKeys,
        "showActionBar": _showMoreButton,
        "isCompact": _isCompact,
        "keyHeight": _keyHeight,
        "keyFontSize": _keyFontSize,
        "panelTabsOrder": _panelTabsOrder,
        "disabledPanelTabs": _disabledPanelTabs.toList(),
        "keys": _keys.map((k) => k.toJson()).toList(),
      },
      "sidebarLayout": {
        "sectionOrder": _sidebarOrder,
        "disabledSections": _disabledSidebarSections.toList(),
      },
      "bottomNavLayout": {
        "showBottomNav": _showBottomNav,
        "disabledButtons": _disabledBottomNavButtons.toList(),
      }
    };

    const encoder = JsonEncoder.withIndent('  ');
    final jsonStr = encoder.convert(payload);

    return widget.isRu
        ? '''# Инструкция для ИИ-агента в терминале (agy / Antigravity / Claude):
Сохрани следующую JSON-конфигурацию интерфейса в файл:
`.quantum/plugins/ui_layout.json`
(или в `/root/.quantum/plugins/ui_layout.json`)

QuantumIDE автоматически применит все изменения интерфейса на лету!

```json
$jsonStr
```
'''
        : '''# Instruction for In-Terminal AI Agent (agy / Antigravity):
Save the following JSON UI layout configuration to:
`.quantum/plugins/ui_layout.json`
(or to `/root/.quantum/plugins/ui_layout.json`)

QuantumIDE will instantly apply the layout in real time!

```json
$jsonStr
```
''';
  }

  void _copyPromptForAgent() {
    HapticFeedback.lightImpact();
    final text = _buildAiPromptJson();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF8B5CF6),
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const Icon(LucideIcons.clipboard_check, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              widget.isRu
                  ? '📋 Промпт и JSON скопированы! Вставьте агенту в терминал.'
                  : '📋 Prompt and JSON copied! Paste into in-terminal agent.',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _resetToDefaults() {
    setState(() {
      _keyHeight = 29.0;
      _keyFontSize = 11.0;
      _isCompact = false;
      _showVirtualKeys = true;
      _showMoreButton = true;
      _keys = _getDefaultCustomVirtualKeys();
      _panelTabsOrder = List.from(_defaultPanelTabs);
      _disabledPanelTabs = <String>{};
      _sidebarOrder = List.from(_defaultSidebarSections);
      _disabledSidebarSections = <String>{};
      _showBottomNav = true;
      _disabledBottomNavButtons = <String>{};
      _isDirty = true;
    });
  }

  void _showAddCustomKeyDialog() {
    final labelCtrl = TextEditingController();
    final cmdCtrl = TextEditingController();
    int targetRow = 1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF141722),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            widget.isRu ? 'Добавить клавишу в терминал' : 'Add Terminal Key',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: widget.isRu ? 'Название кнопки (например: Git, Run, Cls)' : 'Key Label (e.g. Git, Run)',
                  labelStyle: const TextStyle(color: Colors.white60),
                  enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cmdCtrl,
                style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent),
                decoration: InputDecoration(
                  labelText: widget.isRu ? 'Команда или символ (например: git status)' : 'Command or symbol',
                  labelStyle: const TextStyle(color: Colors.white60),
                  enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    widget.isRu ? 'Ряд:' : 'Row:',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: Text(widget.isRu ? 'Ряд 1 (верх)' : 'Row 1'),
                    selected: targetRow == 1,
                    onSelected: (val) => setDlgState(() => targetRow = 1),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(widget.isRu ? 'Ряд 2 (низ)' : 'Row 2'),
                    selected: targetRow == 2,
                    onSelected: (val) => setDlgState(() => targetRow = 2),
                  ),
                ],
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
                final label = labelCtrl.text.trim();
                final cmd = cmdCtrl.text.trim();
                if (label.isNotEmpty && cmd.isNotEmpty) {
                  setState(() {
                    _keys.add(CustomVirtualKey(
                      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                      label: label,
                      value: cmd.endsWith('\n') ? cmd : '$cmd\n',
                      row: targetRow,
                      iconName: 'terminal',
                      isEnabled: true,
                      tooltip: cmd,
                    ));
                    _isDirty = true;
                  });
                  Navigator.pop(ctx);
                }
              },
              child: Text(
                widget.isRu ? 'Добавить' : 'Add',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(LucideIcons.palette, size: 18, color: Colors.cyanAccent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isRu ? 'Кастомизация UI и кнопок' : 'UI & Keypad Customizer',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        widget.isRu
                            ? 'Изменяйте интерфейс, кнопки и передавайте код ИИ'
                            : 'Live tweak UI & export layout for AI agent',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.rotate_ccw, size: 18, color: Colors.white60),
                  tooltip: widget.isRu ? 'Сбросить по умолчанию' : 'Reset defaults',
                  onPressed: _resetToDefaults,
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isDirty ? Colors.cyanAccent : Colors.cyanAccent.withValues(alpha: 0.8),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(LucideIcons.save, size: 15),
                  label: Text(
                    widget.isRu ? 'Сохранить' : 'Save',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: _saveChanges,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tabs
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: Colors.cyanAccent,
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.cyanAccent,
              unselectedLabelColor: Colors.white60,
              labelStyle: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold),
              tabs: [
                Tab(
                  icon: const Icon(LucideIcons.keyboard, size: 14),
                  text: widget.isRu ? 'Клавиши' : 'Virtual Keys',
                ),
                Tab(
                  icon: const Icon(LucideIcons.layout_grid, size: 14),
                  text: widget.isRu ? 'Терминал' : 'Terminal Tabs',
                ),
                Tab(
                  icon: const Icon(LucideIcons.panel_left, size: 14),
                  text: widget.isRu ? 'Боковая панель' : 'Sidebar',
                ),
                Tab(
                  icon: const Icon(LucideIcons.navigation, size: 14),
                  text: widget.isRu ? 'Навигация' : 'Bottom Nav',
                ),
                Tab(
                  icon: const Icon(LucideIcons.bot, size: 14),
                  text: widget.isRu ? 'ИИ & JSON' : 'AI Prompt & JSON',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildVirtualKeysTab(),
                _buildTerminalTabsTab(),
                _buildSidebarTab(),
                _buildBottomNavTab(),
                _buildAiJsonTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= TAB 1: VIRTUAL KEYS =================
  Widget _buildVirtualKeysTab() {
    final enabledKeys = _keys.where((k) => k.isEnabled).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Live Preview Box
        Text(
          widget.isRu ? 'ЖИВОЙ ПРЕДПРОСМОТР КЛАВИШ:' : 'LIVE KEYPAD PREVIEW:',
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.cyanAccent, letterSpacing: 1),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF090B10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: _keyHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: enabledKeys.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 4),
                  itemBuilder: (context, idx) {
                    final k = enabledKeys[idx];
                    return Container(
                      height: _keyHeight - 5,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (k.icon != null) ...[
                            Icon(k.icon, size: _keyFontSize + 1, color: Colors.cyanAccent),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            k.label,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: _keyFontSize,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.isRu
                        ? 'Высота: ${_keyHeight.round()}px | Шрифт: ${_keyFontSize.toStringAsFixed(1)}px'
                        : 'Height: ${_keyHeight.round()}px | Font: ${_keyFontSize.toStringAsFixed(1)}px',
                    style: GoogleFonts.inter(fontSize: 10, color: Colors.white38),
                  ),
                  Text(
                    '${enabledKeys.length} ${widget.isRu ? "активных кнопок" : "active keys"}',
                    style: GoogleFonts.inter(fontSize: 10, color: Colors.cyanAccent),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Sliders & Toggles Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              // Height Slider
              Row(
                children: [
                  const Icon(LucideIcons.move_vertical, size: 16, color: Colors.cyanAccent),
                  const SizedBox(width: 8),
                  Text(
                    widget.isRu ? 'Высота кнопок' : 'Button Height',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    '${_keyHeight.round()} px',
                    style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Slider(
                value: _keyHeight,
                min: 22.0,
                max: 46.0,
                divisions: 24,
                activeColor: Colors.cyanAccent,
                onChanged: (val) => setState(() {
                  _keyHeight = val;
                  _isDirty = true;
                }),
              ),

              // Font Size Slider
              Row(
                children: [
                  const Icon(LucideIcons.type, size: 16, color: Colors.purpleAccent),
                  const SizedBox(width: 8),
                  Text(
                    widget.isRu ? 'Размер шрифта' : 'Font Size',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    '${_keyFontSize.toStringAsFixed(1)} pt',
                    style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Slider(
                value: _keyFontSize,
                min: 9.0,
                max: 16.0,
                divisions: 14,
                activeColor: Colors.purpleAccent,
                onChanged: (val) => setState(() {
                  _keyFontSize = val;
                  _isDirty = true;
                }),
              ),

              const Divider(color: Colors.white12, height: 16),

              // Compact switch
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.isRu ? 'Компактный 1-рядный режим' : 'Compact 1-row mode',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                ),
                value: _isCompact,
                activeColor: Colors.cyanAccent,
                onChanged: (val) => setState(() {
                  _isCompact = val;
                  _isDirty = true;
                }),
              ),

              // Show more button switch
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.isRu ? 'Кнопка «Ещё» (Сетка всех команд)' : 'Show "More" (Grid) button',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                ),
                value: _showMoreButton,
                activeColor: Colors.cyanAccent,
                onChanged: (val) => setState(() {
                  _showMoreButton = val;
                  _isDirty = true;
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Action Buttons: Add Custom Key
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.cyanAccent,
            side: const BorderSide(color: Colors.cyanAccent, width: 0.8),
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(LucideIcons.plus, size: 16),
          label: Text(
            widget.isRu ? 'Добавить свою клавишу / команду' : 'Add Custom Key / Command',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          onPressed: _showAddCustomKeyDialog,
        ),
        const SizedBox(height: 12),

        Text(
          widget.isRu
              ? 'ПОРЯДОК И ПЕРЕКЛЮЧАТЕЛИ КЛАВИШ (Перетаскивайте для смены порядка):'
              : 'REORDER & TOGGLE KEYS (Drag handle to reorder):',
          style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white60),
        ),
        const SizedBox(height: 6),

        // Reorderable list of keys
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _keys.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = _keys.removeAt(oldIndex);
              _keys.insert(newIndex, item);
              _isDirty = true;
            });
          },
          itemBuilder: (context, index) {
            final key = _keys[index];
            final isCustom = key.id.startsWith('custom_');

            return Container(
              key: ValueKey(key.id),
              margin: const EdgeInsets.only(bottom: 5),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: key.isEnabled ? const Color(0xFF141824) : Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: key.isEnabled ? const Color(0xFF232D42) : Colors.white.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    key.icon ?? (key.isToggle ? LucideIcons.toggle_left : LucideIcons.command),
                    size: 15,
                    color: key.isEnabled ? Colors.cyanAccent : Colors.white24,
                  ),
                  const SizedBox(width: 8),
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
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Ряд ${key.row}',
                                style: const TextStyle(fontSize: 9, color: Colors.white54),
                              ),
                            ),
                          ],
                        ),
                        if (key.tooltip != null)
                          Text(
                            key.tooltip!,
                            style: GoogleFonts.inter(fontSize: 10, color: Colors.white38),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: key.isEnabled,
                    activeColor: Colors.cyanAccent,
                    onChanged: (val) => setState(() {
                      _keys[index] = key.copyWith(isEnabled: val);
                      _isDirty = true;
                    }),
                  ),
                  if (isCustom)
                    IconButton(
                      icon: const Icon(LucideIcons.trash_2, size: 15, color: Colors.redAccent),
                      onPressed: () => setState(() {
                        _keys.removeAt(index);
                        _isDirty = true;
                      }),
                    ),
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(LucideIcons.grip_vertical, size: 16, color: Colors.white38),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ================= TAB 2: TERMINAL TABS =================
  Widget _buildTerminalTabsTab() {
    String getTabName(String id) {
      switch (id) {
        case 'terminal': return widget.isRu ? 'Терминал' : 'Terminal';
        case 'run': return widget.isRu ? 'Запуск (Run)' : 'Run';
        case 'buildLogs': return widget.isRu ? 'Сборка APK / PC' : 'Build Logs';
        case 'appLogs': return widget.isRu ? 'Логи приложения & ADB' : 'App Logs & ADB';
        case 'problems': return widget.isRu ? 'Проблемы и Ошибки' : 'Problems';
        case 'git': return 'Git';
        case 'debug': return widget.isRu ? 'Отладчик' : 'Debugger';
        case 'deviceMirror': return widget.isRu ? 'Экран и USB' : 'Screen & USB';
        case 'aiAgent': return 'Quantum AI Агент';
        default: return id;
      }
    }

    IconData getTabIcon(String id) {
      switch (id) {
        case 'terminal': return LucideIcons.terminal;
        case 'run': return LucideIcons.play;
        case 'buildLogs': return LucideIcons.hammer;
        case 'appLogs': return LucideIcons.list;
        case 'problems': return LucideIcons.circle_alert;
        case 'git': return LucideIcons.git_branch;
        case 'debug': return LucideIcons.bug;
        case 'deviceMirror': return LucideIcons.smartphone;
        case 'aiAgent': return LucideIcons.bot;
        default: return LucideIcons.folder;
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Text(
          widget.isRu
              ? 'ВКЛАДКИ НИЖНЕЙ ПАНЕЛИ ТЕРМИНАЛА (Включить / Выключить / Порядок):'
              : 'TERMINAL PANEL TABS (Toggle visibility & drag to reorder):',
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
        ),
        const SizedBox(height: 8),

        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _panelTabsOrder.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = _panelTabsOrder.removeAt(oldIndex);
              _panelTabsOrder.insert(newIndex, item);
              _isDirty = true;
            });
          },
          itemBuilder: (context, index) {
            final tabId = _panelTabsOrder[index];
            final isEnabled = !_disabledPanelTabs.contains(tabId);

            return Container(
              key: ValueKey(tabId),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isEnabled ? const Color(0xFF141824) : Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isEnabled ? const Color(0xFF232D42) : Colors.white.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                children: [
                  Icon(getTabIcon(tabId), size: 16, color: isEnabled ? Colors.cyanAccent : Colors.white24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      getTabName(tabId),
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isEnabled ? Colors.white : Colors.white38,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: isEnabled,
                    activeColor: Colors.cyanAccent,
                    onChanged: (val) => setState(() {
                      if (val) {
                        _disabledPanelTabs.remove(tabId);
                      } else {
                        _disabledPanelTabs.add(tabId);
                      }
                      _isDirty = true;
                    }),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(LucideIcons.grip_vertical, size: 16, color: Colors.white38),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ================= TAB 3: SIDEBAR =================
  Widget _buildSidebarTab() {
    String getSectionName(String id) {
      switch (id) {
        case 'explorer': return widget.isRu ? 'Проводник файлов' : 'Explorer';
        case 'search': return widget.isRu ? 'Поиск в проекте' : 'Search';
        case 'structure': return widget.isRu ? 'Структура классов' : 'Structure';
        case 'disk': return widget.isRu ? 'Анализ диска' : 'Disk Analyzer';
        case 'problems': return widget.isRu ? 'Диагностика ошибок' : 'Problems';
        case 'git': return 'Git';
        case 'preview': return widget.isRu ? 'Веб-превью' : 'Preview';
        case 'packages': return widget.isRu ? 'Менеджер пакетов' : 'Packages';
        case 'run': return widget.isRu ? 'Быстрый запуск' : 'Run';
        case 'build': return widget.isRu ? 'Сборка APK' : 'Build APK';
        case 'liveShare': return widget.isRu ? 'Совместная разработка' : 'Live Share';
        case 'plugins': return widget.isRu ? 'Плагины & Расширения' : 'Plugins';
        case 'appLogs': return widget.isRu ? 'Логи IDE' : 'IDE Logs';
        default: return id;
      }
    }

    IconData getSectionIcon(String id) {
      switch (id) {
        case 'explorer': return LucideIcons.files;
        case 'search': return LucideIcons.search;
        case 'structure': return LucideIcons.list;
        case 'disk': return LucideIcons.chart_pie;
        case 'problems': return LucideIcons.circle_alert;
        case 'git': return LucideIcons.git_branch;
        case 'preview': return LucideIcons.server;
        case 'packages': return LucideIcons.toy_brick;
        case 'run': return LucideIcons.play;
        case 'build': return LucideIcons.hammer;
        case 'liveShare': return LucideIcons.users;
        case 'plugins': return LucideIcons.puzzle;
        case 'appLogs': return LucideIcons.terminal;
        default: return LucideIcons.box;
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Text(
          widget.isRu
              ? 'РАЗДЕЛЫ БОКОВОЙ ПАНЕЛИ (Включить / Выключить / Порядок):'
              : 'SIDEBAR ACTIVITY BAR (Toggle visibility & drag to reorder):',
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purpleAccent),
        ),
        const SizedBox(height: 8),

        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _sidebarOrder.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = _sidebarOrder.removeAt(oldIndex);
              _sidebarOrder.insert(newIndex, item);
              _isDirty = true;
            });
          },
          itemBuilder: (context, index) {
            final secId = _sidebarOrder[index];
            final isEnabled = !_disabledSidebarSections.contains(secId);

            return Container(
              key: ValueKey(secId),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isEnabled ? const Color(0xFF141824) : Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isEnabled ? const Color(0xFF232D42) : Colors.white.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                children: [
                  Icon(getSectionIcon(secId), size: 16, color: isEnabled ? const Color(0xFFC084FC) : Colors.white24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      getSectionName(secId),
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isEnabled ? Colors.white : Colors.white38,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: isEnabled,
                    activeColor: Colors.purpleAccent,
                    onChanged: (val) => setState(() {
                      if (val) {
                        _disabledSidebarSections.remove(secId);
                      } else {
                        _disabledSidebarSections.add(secId);
                      }
                      _isDirty = true;
                    }),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(LucideIcons.grip_vertical, size: 16, color: Colors.white38),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ================= TAB 4: BOTTOM NAV =================
  Widget _buildBottomNavTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.isRu ? 'Показывать нижнюю панель навигации' : 'Show Mobile Bottom Navigation',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  widget.isRu
                      ? 'Быстрые кнопки переключения внизу экрана смартфона'
                      : 'Quick switcher bar at the bottom of the screen',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                ),
                value: _showBottomNav,
                activeColor: Colors.cyanAccent,
                onChanged: (val) => setState(() {
                  _showBottomNav = val;
                  _isDirty = true;
                }),
              ),
              const Divider(color: Colors.white12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.isRu ? 'Кнопка «Файлы» (Files)' : 'Button "Files"',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                value: !_disabledBottomNavButtons.contains('files'),
                activeColor: Colors.cyanAccent,
                onChanged: (val) => setState(() {
                  if (val) {
                    _disabledBottomNavButtons.remove('files');
                  } else {
                    _disabledBottomNavButtons.add('files');
                  }
                  _isDirty = true;
                }),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.isRu ? 'Кнопка «Редактор» (Editor)' : 'Button "Editor"',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                value: !_disabledBottomNavButtons.contains('editor'),
                activeColor: Colors.cyanAccent,
                onChanged: (val) => setState(() {
                  if (val) {
                    _disabledBottomNavButtons.remove('editor');
                  } else {
                    _disabledBottomNavButtons.add('editor');
                  }
                  _isDirty = true;
                }),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.isRu ? 'Кнопка «Терминал» (Terminal)' : 'Button "Terminal"',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                value: !_disabledBottomNavButtons.contains('terminal'),
                activeColor: Colors.cyanAccent,
                onChanged: (val) => setState(() {
                  if (val) {
                    _disabledBottomNavButtons.remove('terminal');
                  } else {
                    _disabledBottomNavButtons.add('terminal');
                  }
                  _isDirty = true;
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ================= TAB 5: AI PROMPT & JSON =================
  Widget _buildAiJsonTab() {
    final promptText = _buildAiPromptJson();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(LucideIcons.clipboard_copy, size: 16),
                  label: Text(
                    widget.isRu ? 'Скопировать промпт для ИИ-агента' : 'Copy Prompt for AI Agent',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  onPressed: _copyPromptForAgent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.isRu
                ? 'Вы можете запустить агента (agy / Claude) в терминале QuantumIDE и сказать ему, что хотите изменить — агент напрямую отредактирует JSON-плагин, и интерфейс обновится мгновенно!'
                : 'Run an agent (agy / Claude) in the QuantumIDE terminal and ask it to change the UI — it edits the JSON plugin directly and updates live!',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF07090D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  promptText,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: const Color(0xFF80CBC4),
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
