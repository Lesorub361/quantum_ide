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
    }
    return set;
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

  QuantumPluginService(this._ref) : super(const QuantumPluginState()) {
    loadPlugins();
  }

  String? get _workspacePath => _ref.read(workspaceProvider).currentPath;

  Directory? get _pluginsDirectory {
    final ws = _workspacePath;
    if (ws == null || ws.isEmpty) return null;
    return Directory(p.join(ws, '.quantum', 'plugins'));
  }

  /// Reload all plugins from `<workspace>/.quantum/plugins/*.json`
  Future<void> loadPlugins() async {
    state = state.copyWith(isLoading: true);
    final pluginsDir = _pluginsDirectory;
    if (pluginsDir == null) {
      state = state.copyWith(isLoading: false, plugins: []);
      return;
    }

    try {
      if (!await pluginsDir.exists()) {
        await pluginsDir.create(recursive: true);
        // Create an introductory sample plugin if folder is new!
        await _createDefaultStarterPlugin(pluginsDir.path);
      }

      final files = pluginsDir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
      final loaded = <QuantumPlugin>[];

      for (final file in files) {
        try {
          final content = await file.readAsString();
          final jsonMap = jsonDecode(content) as Map<String, dynamic>;
          final plugin = QuantumPlugin.fromJson(jsonMap, filePath: file.path);
          loaded.add(plugin);
        } catch (e) {
          debugPrint('QuantumPluginService: error parsing ${file.path}: $e');
        }
      }

      state = state.copyWith(plugins: loaded, isLoading: false);
      _updateCustomIconRegistry();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
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
    final pluginsDir = _pluginsDirectory;
    if (pluginsDir == null) return;

    if (!await pluginsDir.exists()) {
      await pluginsDir.create(recursive: true);
    }

    final targetPath = plugin.filePath.isNotEmpty
        ? plugin.filePath
        : p.join(pluginsDir.path, '${plugin.id}.json');

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

  /// Create a sample plugin by template type ('icons', 'chatbot', 'terminal', 'tabs', 'buttons')
  Future<QuantumPlugin> createPluginFromTemplate(String templateType, {String? customName}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    QuantumPlugin newPlugin;

    switch (templateType) {
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
