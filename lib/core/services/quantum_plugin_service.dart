import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/utils/file_icon_helper.dart';

/// Icon & color configuration for custom file/folder rules.
class CustomIconDef {
  final String iconName;
  final String colorHex;

  const CustomIconDef({
    required this.iconName,
    required this.colorHex,
  });

  Map<String, dynamic> toJson() => {
        'icon': iconName,
        'color': colorHex,
      };

  factory CustomIconDef.fromJson(Map<String, dynamic> json) {
    return CustomIconDef(
      iconName: json['icon'] as String? ?? 'folder',
      colorHex: json['color'] as String? ?? '#4CAF50',
    );
  }

  Color get color {
    try {
      final hex = colorHex.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      } else if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    } catch (_) {}
    return Colors.cyanAccent;
  }

  IconData get icon {
    return PluginIconRegistry.getIconByName(iconName);
  }
}

/// Custom command defined in a plugin for quick terminal execution.
class CustomTerminalCommand {
  final String name;
  final String command;
  final String iconName;
  final String description;

  const CustomTerminalCommand({
    required this.name,
    required this.command,
    this.iconName = 'terminal',
    this.description = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'command': command,
        'icon': iconName,
        'description': description,
      };

  factory CustomTerminalCommand.fromJson(Map<String, dynamic> json) {
    return CustomTerminalCommand(
      name: json['name'] as String? ?? 'Command',
      command: json['command'] as String? ?? '',
      iconName: json['icon'] as String? ?? 'terminal',
      description: json['description'] as String? ?? '',
    );
  }

  String get label => name;
  IconData get icon => PluginIconRegistry.getIconByName(iconName);
}

/// Custom top-bar / action button defined by a user plugin.
class CustomUiButton {
  final String id;
  final String label;
  final String iconName;
  final String action; // 'command', 'ai_prompt', 'open_tab', 'custom'
  final String payload;
  final String tooltip;

  const CustomUiButton({
    required this.id,
    required this.label,
    this.iconName = 'sparkles',
    this.action = 'command',
    this.payload = '',
    this.tooltip = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'icon': iconName,
        'action': action,
        'payload': payload,
        'tooltip': tooltip,
      };

  factory CustomUiButton.fromJson(Map<String, dynamic> json) {
    return CustomUiButton(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? 'Button',
      iconName: json['icon'] as String? ?? 'sparkles',
      action: json['action'] as String? ?? 'command',
      payload: json['payload'] as String? ?? '',
      tooltip: json['tooltip'] as String? ?? '',
    );
  }

  IconData get icon => PluginIconRegistry.getIconByName(iconName);
}

/// Custom AI assistant persona defined by a plugin.
class CustomAiBotPersona {
  final String id;
  final String name;
  final String avatarIcon;
  final String role;
  final String description;
  final String systemPrompt;
  final String initialGreeting;

  const CustomAiBotPersona({
    required this.id,
    required this.name,
    this.avatarIcon = 'bot',
    this.role = 'Assistant',
    this.description = '',
    required this.systemPrompt,
    this.initialGreeting = 'Привет! Чем я могу помочь вам сегодня?',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatarIcon': avatarIcon,
        'role': role,
        'description': description,
        'systemPrompt': systemPrompt,
        'initialGreeting': initialGreeting,
      };

  factory CustomAiBotPersona.fromJson(Map<String, dynamic> json) {
    return CustomAiBotPersona(
      id: json['id'] as String? ?? 'bot',
      name: json['name'] as String? ?? 'AI Bot',
      avatarIcon: json['avatarIcon'] as String? ?? 'bot',
      role: json['role'] as String? ?? 'Assistant',
      description: json['description'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      initialGreeting: json['initialGreeting'] as String? ?? 'Привет!',
    );
  }

  IconData get icon => PluginIconRegistry.getIconByName(avatarIcon);
}

/// Custom tab in ActivityBar or Panel defined by a plugin.
class CustomIdeTab {
  final String id;
  final String title;
  final String iconName;
  final String markdownContent;

  const CustomIdeTab({
    required this.id,
    required this.title,
    this.iconName = 'file_text',
    this.markdownContent = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'icon': iconName,
        'markdownContent': markdownContent,
      };

  factory CustomIdeTab.fromJson(Map<String, dynamic> json) {
    return CustomIdeTab(
      id: json['id'] as String? ?? 'custom_tab',
      title: json['title'] as String? ?? 'Custom Tab',
      iconName: json['icon'] as String? ?? 'file_text',
      markdownContent: json['markdownContent'] as String? ?? '',
    );
  }

  IconData get icon => PluginIconRegistry.getIconByName(iconName);
}

/// Custom Virtual Key definition for terminal action bar.
class CustomVirtualKey {
  final String id;
  final String label;
  final String value;
  final String iconName;
  final bool isToggle;
  final bool isEnabled;
  final int row; // 1 or 2 (0 = auto)
  final String? tooltip;

  const CustomVirtualKey({
    required this.id,
    required this.label,
    required this.value,
    this.iconName = '',
    this.isToggle = false,
    this.isEnabled = true,
    this.row = 1,
    this.tooltip,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'value': value,
        'iconName': iconName,
        'isToggle': isToggle,
        'isEnabled': isEnabled,
        'row': row,
        if (tooltip != null) 'tooltip': tooltip,
      };

  factory CustomVirtualKey.fromJson(Map<String, dynamic> json) => CustomVirtualKey(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        value: json['value'] as String? ?? '',
        iconName: json['iconName'] as String? ?? '',
        isToggle: json['isToggle'] as bool? ?? false,
        isEnabled: json['isEnabled'] as bool? ?? true,
        row: json['row'] as int? ?? 1,
        tooltip: json['tooltip'] as String?,
      );

  CustomVirtualKey copyWith({
    String? id,
    String? label,
    String? value,
    String? iconName,
    bool? isToggle,
    bool? isEnabled,
    int? row,
    String? tooltip,
  }) {
    return CustomVirtualKey(
      id: id ?? this.id,
      label: label ?? this.label,
      value: value ?? this.value,
      iconName: iconName ?? this.iconName,
      isToggle: isToggle ?? this.isToggle,
      isEnabled: isEnabled ?? this.isEnabled,
      row: row ?? this.row,
      tooltip: tooltip ?? this.tooltip,
    );
  }

  IconData? get icon {
    if (iconName.isEmpty) return null;
    return PluginIconRegistry.getIconByName(iconName);
  }
}

/// Terminal UI layout and virtual keys configuration.
class TerminalUiLayoutConfig {
  final bool showVirtualKeys;
  final bool showActionBar;
  final bool isCompact;
  final double keyHeight;
  final double keyFontSize;
  final List<CustomVirtualKey> keys;
  final List<String> panelTabsOrder;
  final List<String> disabledPanelTabs;

  const TerminalUiLayoutConfig({
    this.showVirtualKeys = true,
    this.showActionBar = true,
    this.isCompact = false,
    this.keyHeight = 29.0,
    this.keyFontSize = 11.0,
    this.keys = const [],
    this.panelTabsOrder = const [],
    this.disabledPanelTabs = const [],
  });

  Map<String, dynamic> toJson() => {
        'showVirtualKeys': showVirtualKeys,
        'showActionBar': showActionBar,
        'isCompact': isCompact,
        'keyHeight': keyHeight,
        'keyFontSize': keyFontSize,
        'keys': keys.map((k) => k.toJson()).toList(),
        'panelTabsOrder': panelTabsOrder,
        'disabledPanelTabs': disabledPanelTabs,
      };

  factory TerminalUiLayoutConfig.fromJson(Map<String, dynamic> json) => TerminalUiLayoutConfig(
        showVirtualKeys: json['showVirtualKeys'] as bool? ?? true,
        showActionBar: json['showActionBar'] as bool? ?? true,
        isCompact: json['isCompact'] as bool? ?? false,
        keyHeight: (json['keyHeight'] as num?)?.toDouble() ?? 29.0,
        keyFontSize: (json['keyFontSize'] as num?)?.toDouble() ?? 11.0,
        keys: (json['keys'] as List?)
                ?.map((k) => CustomVirtualKey.fromJson(Map<String, dynamic>.from(k)))
                .toList() ??
            const [],
        panelTabsOrder: (json['panelTabsOrder'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        disabledPanelTabs: (json['disabledPanelTabs'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );

  TerminalUiLayoutConfig copyWith({
    bool? showVirtualKeys,
    bool? showActionBar,
    bool? isCompact,
    double? keyHeight,
    double? keyFontSize,
    List<CustomVirtualKey>? keys,
    List<String>? panelTabsOrder,
    List<String>? disabledPanelTabs,
  }) {
    return TerminalUiLayoutConfig(
      showVirtualKeys: showVirtualKeys ?? this.showVirtualKeys,
      showActionBar: showActionBar ?? this.showActionBar,
      isCompact: isCompact ?? this.isCompact,
      keyHeight: keyHeight ?? this.keyHeight,
      keyFontSize: keyFontSize ?? this.keyFontSize,
      keys: keys ?? this.keys,
      panelTabsOrder: panelTabsOrder ?? this.panelTabsOrder,
      disabledPanelTabs: disabledPanelTabs ?? this.disabledPanelTabs,
    );
  }
}

/// Sidebar tabs and sections layout configuration.
class SidebarUiLayoutConfig {
  final List<String> sectionOrder;
  final List<String> disabledSections;

  const SidebarUiLayoutConfig({
    this.sectionOrder = const [],
    this.disabledSections = const [],
  });

  Map<String, dynamic> toJson() => {
        'sectionOrder': sectionOrder,
        'disabledSections': disabledSections,
      };

  factory SidebarUiLayoutConfig.fromJson(Map<String, dynamic> json) => SidebarUiLayoutConfig(
        sectionOrder: (json['sectionOrder'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        disabledSections: (json['disabledSections'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );

  SidebarUiLayoutConfig copyWith({
    List<String>? sectionOrder,
    List<String>? disabledSections,
  }) {
    return SidebarUiLayoutConfig(
      sectionOrder: sectionOrder ?? this.sectionOrder,
      disabledSections: disabledSections ?? this.disabledSections,
    );
  }
}

/// Mobile bottom navigation layout configuration.
class BottomNavUiLayoutConfig {
  final bool showBottomNav;
  final List<String> disabledButtons;

  const BottomNavUiLayoutConfig({
    this.showBottomNav = true,
    this.disabledButtons = const [],
  });

  Map<String, dynamic> toJson() => {
        'showBottomNav': showBottomNav,
        'disabledButtons': disabledButtons,
      };

  factory BottomNavUiLayoutConfig.fromJson(Map<String, dynamic> json) => BottomNavUiLayoutConfig(
        showBottomNav: json['showBottomNav'] as bool? ?? true,
        disabledButtons: (json['disabledButtons'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );

  BottomNavUiLayoutConfig copyWith({
    bool? showBottomNav,
    List<String>? disabledButtons,
  }) {
    return BottomNavUiLayoutConfig(
      showBottomNav: showBottomNav ?? this.showBottomNav,
      disabledButtons: disabledButtons ?? this.disabledButtons,
    );
  }
}

/// Complete Quantum IDE Plugin representation.
class QuantumPlugin {
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final bool isEnabled;
  final String filePath;
  final Map<String, CustomIconDef> folderIcons;
  final Map<String, CustomIconDef> fileIcons;
  final List<CustomTerminalCommand> terminalCommands;
  final List<CustomUiButton> customButtons;
  final List<CustomAiBotPersona> customBots;
  final List<String> disabledTabs;
  final List<CustomIdeTab> customTabs;
  final TerminalUiLayoutConfig? terminalLayout;
  final SidebarUiLayoutConfig? sidebarLayout;
  final BottomNavUiLayoutConfig? bottomNavLayout;

  const QuantumPlugin({
    required this.id,
    required this.name,
    this.version = '1.0.0',
    this.description = '',
    this.author = 'User',
    this.isEnabled = true,
    this.filePath = '',
    this.folderIcons = const {},
    this.fileIcons = const {},
    this.terminalCommands = const [],
    this.customButtons = const [],
    this.customBots = const [],
    this.disabledTabs = const [],
    this.customTabs = const [],
    this.terminalLayout,
    this.sidebarLayout,
    this.bottomNavLayout,
  });

  QuantumPlugin copyWith({
    String? name,
    String? version,
    String? description,
    String? author,
    bool? isEnabled,
    String? filePath,
    Map<String, CustomIconDef>? folderIcons,
    Map<String, CustomIconDef>? fileIcons,
    List<CustomTerminalCommand>? terminalCommands,
    List<CustomUiButton>? customButtons,
    List<CustomAiBotPersona>? customBots,
    List<String>? disabledTabs,
    List<CustomIdeTab>? customTabs,
    TerminalUiLayoutConfig? terminalLayout,
    SidebarUiLayoutConfig? sidebarLayout,
    BottomNavUiLayoutConfig? bottomNavLayout,
  }) {
    return QuantumPlugin(
      id: id,
      name: name ?? this.name,
      version: version ?? this.version,
      description: description ?? this.description,
      author: author ?? this.author,
      isEnabled: isEnabled ?? this.isEnabled,
      filePath: filePath ?? this.filePath,
      folderIcons: folderIcons ?? this.folderIcons,
      fileIcons: fileIcons ?? this.fileIcons,
      terminalCommands: terminalCommands ?? this.terminalCommands,
      customButtons: customButtons ?? this.customButtons,
      customBots: customBots ?? this.customBots,
      disabledTabs: disabledTabs ?? this.disabledTabs,
      customTabs: customTabs ?? this.customTabs,
      terminalLayout: terminalLayout ?? this.terminalLayout,
      sidebarLayout: sidebarLayout ?? this.sidebarLayout,
      bottomNavLayout: bottomNavLayout ?? this.bottomNavLayout,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'description': description,
        'author': author,
        'isEnabled': isEnabled,
        'folderIcons': folderIcons.map((k, v) => MapEntry(k, v.toJson())),
        'fileIcons': fileIcons.map((k, v) => MapEntry(k, v.toJson())),
        'terminalCommands': terminalCommands.map((c) => c.toJson()).toList(),
        'customButtons': customButtons.map((b) => b.toJson()).toList(),
        'customBots': customBots.map((b) => b.toJson()).toList(),
        'disabledTabs': disabledTabs,
        'customTabs': customTabs.map((t) => t.toJson()).toList(),
        if (terminalLayout != null) 'terminalLayout': terminalLayout!.toJson(),
        if (sidebarLayout != null) 'sidebarLayout': sidebarLayout!.toJson(),
        if (bottomNavLayout != null) 'bottomNavLayout': bottomNavLayout!.toJson(),
      };

  factory QuantumPlugin.fromJson(Map<String, dynamic> json, {String filePath = ''}) {
    final folderIcons = <String, CustomIconDef>{};
    if (json['folderIcons'] is Map) {
      (json['folderIcons'] as Map).forEach((k, v) {
        if (v is Map) {
          folderIcons[k.toString()] = CustomIconDef.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }

    final fileIcons = <String, CustomIconDef>{};
    if (json['fileIcons'] is Map) {
      (json['fileIcons'] as Map).forEach((k, v) {
        if (v is Map) {
          fileIcons[k.toString()] = CustomIconDef.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }

    return QuantumPlugin(
      id: json['id'] as String? ?? 'plugin_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Unnamed Plugin',
      version: json['version'] as String? ?? '1.0.0',
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? 'User',
      isEnabled: json['isEnabled'] as bool? ?? true,
      filePath: filePath,
      folderIcons: folderIcons,
      fileIcons: fileIcons,
      terminalCommands: (json['terminalCommands'] as List?)
              ?.map((c) => CustomTerminalCommand.fromJson(Map<String, dynamic>.from(c)))
              .toList() ??
          [],
      customButtons: (json['customButtons'] as List?)
              ?.map((b) => CustomUiButton.fromJson(Map<String, dynamic>.from(b)))
              .toList() ??
          [],
      customBots: (json['customBots'] as List?)
              ?.map((b) => CustomAiBotPersona.fromJson(Map<String, dynamic>.from(b)))
              .toList() ??
          [],
      disabledTabs: (json['disabledTabs'] as List?)?.map((t) => t.toString()).toList() ?? [],
      customTabs: (json['customTabs'] as List?)
              ?.map((t) => CustomIdeTab.fromJson(Map<String, dynamic>.from(t)))
              .toList() ??
          [],
      terminalLayout: json['terminalLayout'] is Map
          ? TerminalUiLayoutConfig.fromJson(Map<String, dynamic>.from(json['terminalLayout'] as Map))
          : null,
      sidebarLayout: json['sidebarLayout'] is Map
          ? SidebarUiLayoutConfig.fromJson(Map<String, dynamic>.from(json['sidebarLayout'] as Map))
          : null,
      bottomNavLayout: json['bottomNavLayout'] is Map
          ? BottomNavUiLayoutConfig.fromJson(Map<String, dynamic>.from(json['bottomNavLayout'] as Map))
          : null,
    );
  }
}

/// Global helper for mapping Lucide Icon string names.
class PluginIconRegistry {
  static IconData getIconByName(String name) {
    switch (name.toLowerCase()) {
      case 'terminal':
        return LucideIcons.terminal;
      case 'sparkles':
        return LucideIcons.sparkles;
      case 'bot':
      case 'brain':
        return LucideIcons.bot;
      case 'folder':
        return LucideIcons.folder;
      case 'folder_open':
        return LucideIcons.folder_open;
      case 'folder_code':
        return LucideIcons.folder_code;
      case 'folder_git':
      case 'folder_git_2':
        return LucideIcons.folder_git_2;
      case 'folder_cog':
      case 'settings':
        return LucideIcons.folder_cog;
      case 'file':
        return LucideIcons.file;
      case 'file_code':
        return LucideIcons.file_code;
      case 'file_text':
        return LucideIcons.file_text;
      case 'flame':
      case 'fire':
        return LucideIcons.flame;
      case 'zap':
      case 'lightning':
        return LucideIcons.zap;
      case 'package':
        return LucideIcons.package;
      case 'rocket':
        return LucideIcons.rocket;
      case 'heart':
        return LucideIcons.heart;
      case 'star':
        return LucideIcons.star;
      case 'globe':
        return LucideIcons.globe;
      case 'cpu':
        return LucideIcons.cpu;
      case 'play':
        return LucideIcons.play;
      case 'check':
        return LucideIcons.check;
      case 'bug':
        return LucideIcons.bug;
      case 'hammer':
        return LucideIcons.hammer;
      case 'palette':
        return LucideIcons.palette;
      case 'shield':
        return LucideIcons.shield;
      case 'puzzle':
      default:
        return LucideIcons.puzzle;
    }
  }
}

/// State of installed and active Quantum plugins.
class QuantumPluginState {
  final List<QuantumPlugin> plugins;
  final bool isLoading;
  final String? error;

  const QuantumPluginState({
    this.plugins = const [],
    this.isLoading = false,
    this.error,
  });

  /// Active terminal shortcuts aggregated from all enabled plugins
  List<CustomTerminalCommand> get activeTerminalCommands {
    final list = <CustomTerminalCommand>[];
    for (final p in plugins.where((p) => p.isEnabled)) {
      list.addAll(p.terminalCommands);
    }
    return list;
  }

  /// Active custom UI buttons aggregated from all enabled plugins
  List<CustomUiButton> get activeCustomButtons {
    final list = <CustomUiButton>[];
    for (final p in plugins.where((p) => p.isEnabled)) {
      list.addAll(p.customButtons);
    }
    return list;
  }

  /// Active custom AI personas aggregated from all enabled plugins
  List<CustomAiBotPersona> get activeCustomBots {
    final list = <CustomAiBotPersona>[];
    for (final p in plugins.where((p) => p.isEnabled)) {
      list.addAll(p.customBots);
    }
    return list;
  }

  /// Set of tabs that should be hidden from UI
  Set<String> get disabledTabIds {
    final set = <String>{};
    for (final p in plugins.where((p) => p.isEnabled)) {
      set.addAll(p.disabledTabs);
      if (p.sidebarLayout != null) {
        set.addAll(p.sidebarLayout!.disabledSections);
      }
    }
    return set;
  }

  /// Effective Terminal UI layout config from enabled plugins
  TerminalUiLayoutConfig? get terminalLayout {
    final active = plugins.where((p) => p.isEnabled && p.terminalLayout != null).toList();
    if (active.isEmpty) return null;
    final last = active.last.terminalLayout!;
    final allDisabled = <String>{};
    for (final p in active) {
      allDisabled.addAll(p.terminalLayout!.disabledPanelTabs);
    }
    return last.copyWith(disabledPanelTabs: allDisabled.toList());
  }

  /// Effective Sidebar UI layout config from enabled plugins
  SidebarUiLayoutConfig? get sidebarLayout {
    final active = plugins.where((p) => p.isEnabled && p.sidebarLayout != null).toList();
    if (active.isEmpty) return null;
    final last = active.last.sidebarLayout!;
    final allDisabled = <String>{};
    for (final p in active) {
      allDisabled.addAll(p.sidebarLayout!.disabledSections);
    }
    return last.copyWith(disabledSections: allDisabled.toList());
  }

  /// Effective Mobile Bottom Nav layout config from enabled plugins
  BottomNavUiLayoutConfig? get bottomNavLayout {
    final active = plugins.where((p) => p.isEnabled && p.bottomNavLayout != null).toList();
    if (active.isEmpty) return null;
    final last = active.last.bottomNavLayout!;
    final allDisabled = <String>{};
    bool show = true;
    for (final p in active) {
      allDisabled.addAll(p.bottomNavLayout!.disabledButtons);
      if (!p.bottomNavLayout!.showBottomNav) show = false;
    }
    return last.copyWith(
      showBottomNav: show,
      disabledButtons: allDisabled.toList(),
    );
  }

  QuantumPluginState copyWith({
    List<QuantumPlugin>? plugins,
    bool? isLoading,
    String? error,
  }) {
    return QuantumPluginState(
      plugins: plugins ?? this.plugins,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Service managing discovering, loading, and executing user plugins.
class QuantumPluginService extends StateNotifier<QuantumPluginState> {
  final Ref _ref;
  StreamSubscription<FileSystemEvent>? _wsWatcherSub;
  StreamSubscription<FileSystemEvent>? _globalWatcherSub;
  Timer? _debounceTimer;

  QuantumPluginService(this._ref) : super(const QuantumPluginState()) {
    loadPlugins();
  }

  @override
  void dispose() {
    _wsWatcherSub?.cancel();
    _globalWatcherSub?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  String? get _workspacePath => _ref.read(workspaceProvider).currentPath;

  Directory? get _pluginsDirectory {
    final ws = _workspacePath;
    if (ws == null || ws.isEmpty) return null;
    return Directory(p.join(ws, '.quantum', 'plugins'));
  }

  Directory get _globalPluginsDirectory => Directory('/root/.quantum/plugins');
  Directory get _sdcardPluginsDirectory => Directory('/sdcard/QuantumIDE/.quantum/plugins');

  /// Set up file system watchers on plugin directories so changes made
  /// by AI agents or users in terminal apply dynamically in real time.
  void _setupWatchers(Directory? wsDir) {
    _wsWatcherSub?.cancel();
    _globalWatcherSub?.cancel();

    if (wsDir != null && wsDir.existsSync()) {
      try {
        _wsWatcherSub = wsDir.watch().listen((_) => _onFsEvent());
      } catch (_) {}
    }

    if (_globalPluginsDirectory.existsSync()) {
      try {
        _globalWatcherSub = _globalPluginsDirectory.watch().listen((_) => _onFsEvent());
      } catch (_) {}
    }
  }

  void _onFsEvent() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      loadPlugins();
    });
  }

  /// Reload all plugins from `<workspace>/.quantum/plugins/*.json` and global configs
  Future<void> loadPlugins() async {
    state = state.copyWith(isLoading: true);
    final pluginsDir = _pluginsDirectory;
    final loaded = <QuantumPlugin>[];
    final loadedIds = <String>{};

    // 1. Load from workspace plugins
    if (pluginsDir != null) {
      try {
        if (!await pluginsDir.exists()) {
          await pluginsDir.create(recursive: true);
          await _createDefaultStarterPlugin(pluginsDir.path);
        }

        final files = pluginsDir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
        for (final file in files) {
          try {
            final content = await file.readAsString();
            final jsonMap = jsonDecode(content) as Map<String, dynamic>;
            final plugin = QuantumPlugin.fromJson(jsonMap, filePath: file.path);
            loaded.add(plugin);
            loadedIds.add(plugin.id);
          } catch (e) {
            debugPrint('QuantumPluginService: error parsing ${file.path}: $e');
          }
        }
      } catch (e) {
        debugPrint('QuantumPluginService workspace error: $e');
      }
    }

    // 2. Load from global guest rootfs /root/.quantum/plugins/
    try {
      if (await _globalPluginsDirectory.exists()) {
        final files = _globalPluginsDirectory.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
        for (final file in files) {
          try {
            final content = await file.readAsString();
            final jsonMap = jsonDecode(content) as Map<String, dynamic>;
            final plugin = QuantumPlugin.fromJson(jsonMap, filePath: file.path);
            if (!loadedIds.contains(plugin.id)) {
              loaded.add(plugin);
              loadedIds.add(plugin.id);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 3. Load from /sdcard/QuantumIDE/.quantum/plugins/ if accessible
    try {
      if (await _sdcardPluginsDirectory.exists()) {
        final files = _sdcardPluginsDirectory.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
        for (final file in files) {
          try {
            final content = await file.readAsString();
            final jsonMap = jsonDecode(content) as Map<String, dynamic>;
            final plugin = QuantumPlugin.fromJson(jsonMap, filePath: file.path);
            if (!loadedIds.contains(plugin.id)) {
              loaded.add(plugin);
              loadedIds.add(plugin.id);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    state = state.copyWith(plugins: loaded, isLoading: false);
    _updateCustomIconRegistry();
    _setupWatchers(pluginsDir);
  }

  /// Toggle plugin enabled status
  Future<void> togglePlugin(String pluginId, bool enabled) async {
    final idx = state.plugins.indexWhere((p) => p.id == pluginId);
    if (idx == -1) return;

    final updated = state.plugins[idx].copyWith(isEnabled: enabled);
    await savePlugin(updated);
  }

  /// Save or update a plugin on disk
  Future<void> savePlugin(QuantumPlugin plugin) async {
    Directory targetDir = _pluginsDirectory ?? _globalPluginsDirectory;

    if (!await targetDir.exists()) {
      try {
        await targetDir.create(recursive: true);
      } catch (_) {
        targetDir = _globalPluginsDirectory;
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
      }
    }

    final targetPath = plugin.filePath.isNotEmpty
        ? plugin.filePath
        : p.join(targetDir.path, '${plugin.id}.json');

    final jsonStr = const JsonEncoder.withIndent('  ').convert(plugin.toJson());
    await File(targetPath).writeAsString(jsonStr);

    final updatedList = List<QuantumPlugin>.from(state.plugins);
    final idx = updatedList.indexWhere((p) => p.id == plugin.id);
    if (idx != -1) {
      updatedList[idx] = plugin.copyWith(filePath: targetPath);
    } else {
      updatedList.add(plugin.copyWith(filePath: targetPath));
    }

    state = state.copyWith(plugins: updatedList);
    _updateCustomIconRegistry();
  }

  /// Save unified UI layout configuration plugin (used by visual customizer or terminal agent)
  Future<void> saveUiLayoutPlugin({
    TerminalUiLayoutConfig? terminalLayout,
    SidebarUiLayoutConfig? sidebarLayout,
    BottomNavUiLayoutConfig? bottomNavLayout,
    String? pluginName,
  }) async {
    const layoutPluginId = 'ui_layout_custom';
    final existingIdx = state.plugins.indexWhere((p) => p.id == layoutPluginId);
    QuantumPlugin targetPlugin;

    if (existingIdx != -1) {
      final existing = state.plugins[existingIdx];
      targetPlugin = existing.copyWith(
        terminalLayout: terminalLayout ?? existing.terminalLayout,
        sidebarLayout: sidebarLayout ?? existing.sidebarLayout,
        bottomNavLayout: bottomNavLayout ?? existing.bottomNavLayout,
      );
    } else {
      targetPlugin = QuantumPlugin(
        id: layoutPluginId,
        name: pluginName ?? 'Кастомная раскладка UI & Кнопки',
        description: 'Пользовательская конфигурация расположения клавиш терминала, вкладок и панелей',
        author: 'User & AI',
        isEnabled: true,
        terminalLayout: terminalLayout,
        sidebarLayout: sidebarLayout,
        bottomNavLayout: bottomNavLayout,
      );
    }

    await savePlugin(targetPlugin);
  }

  /// Delete a plugin file
  Future<void> deletePlugin(String pluginId) async {
    final idx = state.plugins.indexWhere((p) => p.id == pluginId);
    if (idx == -1) return;

    final plugin = state.plugins[idx];
    if (plugin.filePath.isNotEmpty) {
      final f = File(plugin.filePath);
      if (await f.exists()) {
        await f.delete();
      }
    }

    final updated = List<QuantumPlugin>.from(state.plugins)..removeAt(idx);
    state = state.copyWith(plugins: updated);
    _updateCustomIconRegistry();
  }

  /// Create a sample plugin by template type ('icons', 'chatbot', 'terminal', 'tabs', 'buttons', 'ui_layout')
  Future<QuantumPlugin> createPluginFromTemplate(String templateType, {String? customName}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    QuantumPlugin newPlugin;

    switch (templateType) {
      case 'ui_layout':
        newPlugin = QuantumPlugin(
          id: 'custom_layout_$timestamp',
          name: customName ?? 'Настраиваемый интерфейс и клавиши',
          description: 'Пользовательская конфигурация кнопок терминала, боковой панели и навигации',
          author: 'Разработчик',
          isEnabled: true,
          terminalLayout: const TerminalUiLayoutConfig(
            showVirtualKeys: true,
            showActionBar: true,
            isCompact: false,
            keyHeight: 30.0,
            keyFontSize: 11.5,
          ),
          sidebarLayout: const SidebarUiLayoutConfig(
            disabledSections: [],
          ),
          bottomNavLayout: const BottomNavUiLayoutConfig(
            showBottomNav: true,
          ),
        );
        break;

      case 'icons':
        newPlugin = QuantumPlugin(
          id: 'custom_icons_$timestamp',
          name: customName ?? 'Моя тема иконок папок и файлов',
          description: 'Кастомные иконки для папок controllers, models, utils и файлов .dart/.json',
          author: 'Разработчик',
          isEnabled: true,
          folderIcons: {
            'controllers': const CustomIconDef(iconName: 'zap', colorHex: '#FF9800'),
            'models': const CustomIconDef(iconName: 'package', colorHex: '#00BCD4'),
            'widgets': const CustomIconDef(iconName: 'palette', colorHex: '#E91E63'),
            'services': const CustomIconDef(iconName: 'cpu', colorHex: '#4CAF50'),
            'bloc': const CustomIconDef(iconName: 'flame', colorHex: '#9C27B0'),
          },
          fileIcons: {
            '.config': const CustomIconDef(iconName: 'settings', colorHex: '#607D8B'),
            '.env': const CustomIconDef(iconName: 'shield', colorHex: '#FFC107'),
          },
        );
        break;

      case 'chatbot':
        newPlugin = QuantumPlugin(
          id: 'flutter_mentor_$timestamp',
          name: customName ?? 'Flutter Senior Ментор',
          description: 'Персональный ИИ-ментор по лучшим практикам Flutter, Riverpod и Clean Architecture',
          author: 'Разработчик',
          isEnabled: true,
          customBots: [
            const CustomAiBotPersona(
              id: 'flutter_mentor',
              name: 'Flutter Senior Ментор',
              avatarIcon: 'brain',
              role: 'Senior Flutter Architect',
              description: 'Консультирует по виджетам, Riverpod, стейт-менеджменту и оптимизации FPS',
              systemPrompt:
                  'Ты — Senior Flutter инженер с 8 годами опыта. Всегда объясняй архитектуру лаконично, предлагай лучшие практики Riverpod 2.0, const конструкторы, минимизацию rebuild и чистый код на русском языке.',
              initialGreeting:
                  'Привет! Я твой персональный Flutter Ментор. Задай мне любой вопрос по коду, архитектуре или виджетам!',
            ),
          ],
        );
        break;

      case 'terminal':
        newPlugin = QuantumPlugin(
          id: 'dev_shortcuts_$timestamp',
          name: customName ?? 'Быстрые команды Flutter & Git',
          description: 'Кнопки быстрого запуска в терминале: pub get, build runner, format, clean',
          author: 'Разработчик',
          isEnabled: true,
          terminalCommands: [
            const CustomTerminalCommand(
              name: 'Pub Get',
              command: 'flutter pub get',
              iconName: 'package',
              description: 'Обновить зависимости проекта',
            ),
            const CustomTerminalCommand(
              name: 'Build Runner',
              command: 'dart run build_runner build --delete-conflicting-outputs',
              iconName: 'hammer',
              description: 'Кодогенерация Freezed, JsonSerializable',
            ),
            const CustomTerminalCommand(
              name: 'Dart Format',
              command: 'dart format lib/',
              iconName: 'sparkles',
              description: 'Автоформатирование всех файлов в lib/',
            ),
            const CustomTerminalCommand(
              name: 'Flutter Clean',
              command: 'flutter clean && flutter pub get',
              iconName: 'flame',
              description: 'Очистить кэш сборки',
            ),
          ],
        );
        break;

      case 'tabs':
        newPlugin = QuantumPlugin(
          id: 'minimal_ui_$timestamp',
          name: customName ?? 'Минималистичный интерфейс',
          description: 'Скрывает неиспользуемые вкладки и оставляет только самое нужное для быстрой работы',
          author: 'Разработчик',
          isEnabled: true,
          disabledTabs: ['disk', 'live_share'],
        );
        break;

      case 'buttons':
      default:
        newPlugin = QuantumPlugin(
          id: 'custom_actions_$timestamp',
          name: customName ?? 'Кнопки быстрых действий',
          description: 'Добавляет полезные кнопки в верхнюю панель IDE',
          author: 'Разработчик',
          isEnabled: true,
          customButtons: [
            const CustomUiButton(
              id: 'btn_format',
              label: 'Форматировать',
              iconName: 'sparkles',
              action: 'command',
              payload: 'dart format lib/',
              tooltip: 'Форматировать весь код (dart format)',
            ),
            const CustomUiButton(
              id: 'btn_ai_review',
              label: 'AI Ревью',
              iconName: 'bot',
              action: 'ai_prompt',
              payload: 'Сделай краткое код-ревью открытого файла: найди баги, утечки памяти и предложи улучшения.',
              tooltip: 'Провести быстрый аудит открытого файла',
            ),
          ],
        );
        break;
    }

    await savePlugin(newPlugin);
    return newPlugin;
  }

  Future<void> _createDefaultStarterPlugin(String pluginsDirPath) async {
    final samplePath = p.join(pluginsDirPath, 'starter_plugin.json');
    if (await File(samplePath).exists()) return;

    const starter = QuantumPlugin(
      id: 'quantum_starter_plugin',
      name: 'Quantum Starter Plugin (Пример)',
      version: '1.0.0',
      description: 'Демонстрационный плагин: кастомные иконки, команды терминала и ИИ-помощник',
      author: 'QuantumIDE Team',
      isEnabled: true,
      folderIcons: {
        'controllers': CustomIconDef(iconName: 'zap', colorHex: '#FF9800'),
        'models': CustomIconDef(iconName: 'package', colorHex: '#00BCD4'),
        'widgets': CustomIconDef(iconName: 'palette', colorHex: '#E91E63'),
      },
      terminalCommands: [
        CustomTerminalCommand(
          name: 'Pub Get',
          command: 'flutter pub get',
          iconName: 'package',
          description: 'Загрузить зависимости',
        ),
        CustomTerminalCommand(
          name: 'Format Code',
          command: 'dart format lib/',
          iconName: 'sparkles',
          description: 'Форматировать код',
        ),
      ],
      customBots: [
        CustomAiBotPersona(
          id: 'flutter_assistant',
          name: 'Flutter Эксперт',
          avatarIcon: 'brain',
          role: 'Flutter Expert',
          description: 'Помогает писать чистый и производительный Flutter-код',
          systemPrompt: 'Ты — профессиональный Flutter инженер. Пиши лаконичный, оптимизированный код с const и комментариями на русском.',
        ),
      ],
      customButtons: [
        CustomUiButton(
          id: 'btn_quick_format',
          label: 'Format',
          iconName: 'sparkles',
          action: 'command',
          payload: 'dart format lib/',
          tooltip: 'Автоформатирование кода (dart format lib/)',
        ),
      ],
      terminalLayout: TerminalUiLayoutConfig(
        showVirtualKeys: true,
        showActionBar: true,
        isCompact: false,
        keyHeight: 29.0,
        keyFontSize: 11.0,
      ),
    );

    final jsonStr = const JsonEncoder.withIndent('  ').convert(starter.toJson());
    await File(samplePath).writeAsString(jsonStr);
  }

  void _updateCustomIconRegistry() {
    final activeFolders = <String, CustomIconDef>{};
    final activeFiles = <String, CustomIconDef>{};

    for (final plugin in state.plugins.where((p) => p.isEnabled)) {
      activeFolders.addAll(plugin.folderIcons);
      activeFiles.addAll(plugin.fileIcons);
    }

    CustomIconResolver.registeredFolderIcons = activeFolders;
    CustomIconResolver.registeredFileIcons = activeFiles;
  }

  /// Active terminal shortcuts aggregated from all enabled plugins
  List<CustomTerminalCommand> get activeTerminalCommands => state.activeTerminalCommands;

  /// Active custom UI buttons aggregated from all enabled plugins
  List<CustomUiButton> get activeCustomButtons => state.activeCustomButtons;

  /// Active custom AI personas aggregated from all enabled plugins
  List<CustomAiBotPersona> get activeCustomBots => state.activeCustomBots;

  /// Set of tabs that should be hidden from UI
  Set<String> get disabledTabIds => state.disabledTabIds;
}

/// Static resolver used by FileIconHelper to query user custom icons.
class CustomIconResolver {
  static Map<String, CustomIconDef> registeredFolderIcons = {};
  static Map<String, CustomIconDef> registeredFileIcons = {};

  static FileIconInfo? resolveFolderIcon(String name, bool isExpanded) {
    if (registeredFolderIcons.isEmpty) return null;
    final lower = name.toLowerCase();
    final segment = lower.contains('/') ? lower.split('/').first : lower;

    final def = registeredFolderIcons[segment] ?? registeredFolderIcons[lower];
    if (def != null) {
      return FileIconInfo(
        isExpanded ? LucideIcons.folder_open : def.icon,
        def.color,
      );
    }
    return null;
  }

  static FileIconInfo? resolveFileIcon(String name) {
    if (registeredFileIcons.isEmpty) return null;
    final lower = name.toLowerCase();

    // Check exact name or extension
    for (final entry in registeredFileIcons.entries) {
      final key = entry.key.toLowerCase();
      if (lower == key || (key.startsWith('.') && lower.endsWith(key))) {
        return FileIconInfo(entry.value.icon, entry.value.color);
      }
    }
    return null;
  }
}

final quantumPluginServiceProvider =
    StateNotifierProvider<QuantumPluginService, QuantumPluginState>((ref) {
  final service = QuantumPluginService(ref);
  ref.listen<WorkspaceState>(workspaceProvider, (prev, next) {
    if (prev?.currentPath != next.currentPath) {
      service.loadPlugins();
    }
  });
  return service;
});
