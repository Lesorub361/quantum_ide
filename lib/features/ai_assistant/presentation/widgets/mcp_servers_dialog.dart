import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:quantum_ide/core/services/mcp_service.dart';

class McpServersDialog extends ConsumerStatefulWidget {
  const McpServersDialog({super.key});

  @override
  ConsumerState<McpServersDialog> createState() => _McpServersDialogState();
}

class McpPreset {
  final String name;
  final String id;
  final String description;
  final String command;
  final List<String> args;
  final List<String> requiredEnvKeys;
  final List<String> requiredArgLabels;

  McpPreset({
    required this.name,
    required this.id,
    required this.description,
    required this.command,
    required this.args,
    this.requiredEnvKeys = const [],
    this.requiredArgLabels = const [],
  });
}

class _McpServersDialogState extends ConsumerState<McpServersDialog> {
  final _nameController = TextEditingController();
  final _commandController = TextEditingController();
  final _argsController = TextEditingController();
  final _urlController = TextEditingController();
  
  // Custom inputs for preset installation
  final Map<String, TextEditingController> _presetControllers = {};
  
  McpServerType _selectedType = McpServerType.stdio;
  bool _isAddingManual = false;
  McpPreset? _installingPreset;
  int _activeTab = 0; // 0 = Servers, 1 = Marketplace

  final List<McpPreset> _presets = [
    McpPreset(
      name: 'GitHub MCP Server',
      id: 'github',
      description: 'Интеграция с репозиториями, тикетами (issues) и PR на GitHub.',
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-github'],
      requiredEnvKeys: ['GITHUB_PERSONAL_ACCESS_TOKEN'],
    ),
    McpPreset(
      name: 'Google Search Server',
      id: 'google-search',
      description: 'Позволяет ИИ-агенту производить живой поиск в Google.',
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-google-search'],
      requiredEnvKeys: ['API_KEY', 'CX'],
    ),
    McpPreset(
      name: 'Web Fetch Reader',
      id: 'fetch',
      description: 'Скачивание веб-страниц и автоматический перевод их в Markdown.',
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-fetch'],
    ),
    McpPreset(
      name: 'PostgreSQL Database Client',
      id: 'postgres',
      description: 'Подключение, чтение структуры таблиц и выполнение SQL-запросов к PostgreSQL.',
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-postgres'],
      requiredArgLabels: ['Ссылка для подключения (postgresql://...)'],
    ),
    McpPreset(
      name: 'SQLite Database Client',
      id: 'sqlite',
      description: 'Подключение и инспектирование баз данных SQLite в вашем проекте.',
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-sqlite', '--db'],
      requiredArgLabels: ['Путь к файлу БД SQLite (например: db.sqlite)'],
    ),
    McpPreset(
      name: 'Long-term Memory Server',
      id: 'memory',
      description: 'Семантическое хранилище долговременной памяти для вашего ИИ-агента.',
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-memory'],
    ),
    McpPreset(
      name: 'Brave Search Server',
      id: 'brave-search',
      description: 'Позволяет ИИ-агенту выполнять веб-поиск с использованием Brave API.',
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-brave-search'],
      requiredEnvKeys: ['BRAVE_API_KEY'],
    ),
    McpPreset(
      name: 'Puppeteer Browser Automation',
      id: 'puppeteer',
      description: 'Автоматизация браузера, создание скриншотов, клики по элементам и скрапинг веб-страниц.',
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-puppeteer'],
    ),
    McpPreset(
      name: 'Firecrawl Web Scraper',
      id: 'firecrawl',
      description: 'Преобразование любого веб-сайта в чистый Markdown или структурированный JSON.',
      command: 'npx',
      args: ['-y', '@firecrawl/mcp-server'],
      requiredEnvKeys: ['FIRECRAWL_API_KEY'],
    ),
    McpPreset(
      name: 'Notion Integration Server',
      id: 'notion',
      description: 'Позволяет читать, изменять страницы, базы данных и комментарии в Notion.',
      command: 'npx',
      args: ['-y', 'notion-mcp-server'],
      requiredEnvKeys: ['NOTION_TOKEN'],
    ),
    McpPreset(
      name: 'Slack Client Server',
      id: 'slack',
      description: 'Предоставляет возможность читать каналы, общаться и отправлять уведомления в Slack.',
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-slack'],
      requiredEnvKeys: ['SLACK_BOT_TOKEN', 'SLACK_TEAM_ID'],
    ),
    McpPreset(
      name: 'Git Integration Server',
      id: 'git',
      description: 'Просмотр коммитов, сравнение версий, поиск по коммитам и файлам Git локально.',
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-git'],
    ),
    McpPreset(
      name: 'GitLab MCP Server',
      id: 'gitlab',
      description: 'Управление проектами GitLab, тикетами, PR и CI/CD пайплайнами.',
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-gitlab'],
      requiredEnvKeys: ['GITLAB_PERSONAL_ACCESS_TOKEN'],
    ),
    McpPreset(
      name: 'Sentry Error Tracker',
      id: 'sentry',
      description: 'Получение логов ошибок и инспектирование сбоев вашего приложения на Sentry.',
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-sentry'],
      requiredEnvKeys: ['SENTRY_AUTH_TOKEN', 'SENTRY_ORG'],
    ),
    McpPreset(
      name: 'Airtable Database Client',
      id: 'airtable',
      description: 'Чтение, создание и обновление записей в базах данных и таблицах Airtable.',
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-airtable'],
      requiredEnvKeys: ['AIRTABLE_PERSONAL_ACCESS_TOKEN'],
    ),
    McpPreset(
      name: 'Sequential Thinking Server',
      id: 'sequential-thinking',
      description: 'Организация размышлений ИИ-агента для структурированного решения сложных задач.',
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-sequential-thinking'],
    ),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    _argsController.dispose();
    _urlController.dispose();
    for (final controller in _presetControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _clearForm() {
    _nameController.clear();
    _commandController.clear();
    _argsController.clear();
    _urlController.clear();
    for (final controller in _presetControllers.values) {
      controller.dispose();
    }
    _presetControllers.clear();
    setState(() {
      _selectedType = McpServerType.stdio;
      _isAddingManual = false;
      _installingPreset = null;
    });
  }

  void _setupPresetControllers(McpPreset preset) {
    _presetControllers.clear();
    for (final key in preset.requiredEnvKeys) {
      _presetControllers['env_$key'] = TextEditingController();
    }
    for (int i = 0; i < preset.requiredArgLabels.length; i++) {
      _presetControllers['arg_$i'] = TextEditingController();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mcpServers = ref.watch(mcpServiceProvider);
    final mcpService = ref.read(mcpServiceProvider.notifier);

    Widget header = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Модули ИИ: MCP Серверы',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        IconButton(
          icon: const Icon(LucideIcons.x, color: Colors.white54, size: 18),
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );

    Widget tabHeader = Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(0, 'Активные серверов (${mcpServers.length})'),
          ),
          Expanded(
            child: _buildTabButton(1, 'Репозиторий'),
          ),
        ],
      ),
    );

    Widget content;

    if (_installingPreset != null) {
      content = _buildPresetInstallationForm(mcpService);
    } else if (_isAddingManual) {
      content = _buildManualInstallationForm(mcpService);
    } else if (_activeTab == 0) {
      content = _buildServersList(mcpServers, mcpService);
    } else {
      content = _buildMarketplace();
    }

    return Dialog(
      backgroundColor: const Color(0xFF1E2230),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            maxWidth: 500,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const Divider(color: Colors.white10, height: 16),
              if (_installingPreset == null && !_isAddingManual) tabHeader,
              const SizedBox(height: 8),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, String label) {
    final isSelected = _activeTab == index;
    return InkWell(
      onTap: () {
        setState(() {
          _activeTab = index;
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF3C3C).withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF3C3C).withValues(alpha: 0.3) : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: isSelected ? const Color(0xFFFF3C3C) : Colors.white60,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildServersList(List<McpServerConfig> servers, McpService service) {
    if (servers.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.bot, size: 48, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
          Text(
            'Нет добавленных MCP серверов',
            style: GoogleFonts.inter(color: Colors.white30, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white10),
                  ),
                  onPressed: () => setState(() => _activeTab = 1),
                  child: const Text('Перейти в Репозиторий', style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3C3C).withValues(alpha: 0.15),
                    foregroundColor: const Color(0xFFFF3C3C),
                    elevation: 0,
                    side: const BorderSide(color: Color(0x3FFF3C3C)),
                  ),
                  onPressed: () => setState(() => _isAddingManual = true),
                  child: const Text('Добавить вручную', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          )
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: servers.length,
            itemBuilder: (context, index) {
              final s = servers[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Row(
                  children: [
                    Icon(
                      s.type == McpServerType.stdio ? LucideIcons.terminal : LucideIcons.globe,
                      size: 16,
                      color: s.isEnabled ? Colors.cyanAccent : Colors.white30,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                s.name,
                                style: GoogleFonts.inter(
                                  color: s.isEnabled ? Colors.white : Colors.white30,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              if (s.env.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'KEY',
                                    style: TextStyle(color: Colors.cyanAccent, fontSize: 7, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            s.type == McpServerType.stdio ? '${s.command} ${s.args.join(' ')}' : s.url,
                            style: GoogleFonts.jetBrainsMono(
                              color: s.isEnabled ? Colors.white38 : Colors.white10,
                              fontSize: 9.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: s.isEnabled,
                      activeTrackColor: Colors.cyanAccent.withValues(alpha: 0.3),
                      activeThumbColor: Colors.cyanAccent,
                      onChanged: (_) => service.toggleServer(s.name),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.trash_2, color: Colors.redAccent, size: 15),
                      onPressed: () => service.removeServer(s.name),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.04),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size.fromHeight(36),
          ),
          icon: const Icon(LucideIcons.plus, size: 14),
          label: const Text('Добавить сервер вручную', style: TextStyle(fontSize: 11)),
          onPressed: () => setState(() => _isAddingManual = true),
        ),
      ],
    );
  }

  Widget _buildMarketplace() {
    return ListView.builder(
      itemCount: _presets.length,
      itemBuilder: (context, index) {
        final preset = _presets[index];
        final isInstalled = ref.watch(mcpServiceProvider).any((s) => s.name == preset.name);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    preset.name,
                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const Spacer(),
                  if (isInstalled)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'УСТАНОВЛЕН',
                        style: GoogleFonts.inter(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold),
                      ),
                    )
                  else
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3C3C).withValues(alpha: 0.15),
                        foregroundColor: const Color(0xFFFF3C3C),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: const BorderSide(color: Color(0x3FFF3C3C)),
                      ),
                      onPressed: () {
                        _setupPresetControllers(preset);
                        setState(() {
                          _installingPreset = preset;
                        });
                      },
                      child: const Text('Установить', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                preset.description,
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 10.5),
              ),
              const SizedBox(height: 6),
              Text(
                'Пакет: ${preset.args.last}',
                style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent.withValues(alpha: 0.5), fontSize: 9),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPresetInstallationForm(McpService service) {
    final preset = _installingPreset!;
    final List<Widget> fields = [];

    // Render Env Variable Fields
    for (final envKey in preset.requiredEnvKeys) {
      final controller = _presetControllers['env_$envKey']!;
      fields.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Параметр авторизации: $envKey', style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12),
                decoration: _inputDecoration('Введите значение для $envKey'),
              ),
            ],
          ),
        ),
      );
    }

    // Render Argument Fields
    for (int i = 0; i < preset.requiredArgLabels.length; i++) {
      final label = preset.requiredArgLabels[i];
      final controller = _presetControllers['arg_$i']!;
      fields.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                decoration: _inputDecoration('Введите $label'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Установка: ${preset.name}',
          style: GoogleFonts.inter(color: const Color(0xFFFF3C3C), fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          preset.description,
          style: GoogleFonts.inter(color: Colors.white38, fontSize: 10.5),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: fields,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _clearForm,
                child: const Text('Назад'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3C3C).withValues(alpha: 0.15),
                  foregroundColor: const Color(0xFFFF3C3C),
                  elevation: 0,
                  side: const BorderSide(color: Color(0x3FFF3C3C)),
                ),
                onPressed: () {
                  final finalArgs = List<String>.from(preset.args);
                  final Map<String, String> finalEnv = {};

                  // Collect Env parameters
                  for (final envKey in preset.requiredEnvKeys) {
                    final val = _presetControllers['env_$envKey']?.text.trim() ?? '';
                    finalEnv[envKey] = val;
                  }

                  // Collect custom arguments
                  for (int i = 0; i < preset.requiredArgLabels.length; i++) {
                    final val = _presetControllers['arg_$i']?.text.trim() ?? '';
                    if (val.isNotEmpty) {
                      finalArgs.add(val);
                    }
                  }

                  final config = McpServerConfig(
                    name: preset.name,
                    type: McpServerType.stdio,
                    command: preset.command,
                    args: finalArgs,
                    env: finalEnv,
                    isEnabled: true,
                  );

                  service.addServer(config);
                  _clearForm();
                },
                child: const Text('Установить'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildManualInstallationForm(McpService service) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Добавление вручную',
          style: GoogleFonts.inter(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Имя сервера', style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameController,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                  decoration: _inputDecoration('Например: local-search'),
                ),
                const SizedBox(height: 12),

                Text('Тип подключения', style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Stdio (Локальный процесс)'),
                        selected: _selectedType == McpServerType.stdio,
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedType = McpServerType.stdio);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('SSE (HTTP-поток)'),
                        selected: _selectedType == McpServerType.sse,
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedType = McpServerType.sse);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (_selectedType == McpServerType.stdio) ...[
                  Text('Команда запуска', style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _commandController,
                    style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12),
                    decoration: _inputDecoration('Например: node или npx или python3'),
                  ),
                  const SizedBox(height: 12),

                  Text('Аргументы (через пробел)', style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _argsController,
                    style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12),
                    decoration: _inputDecoration('/path/to/server.js arg1 arg2'),
                  ),
                ] else ...[
                  Text('SSE URL', style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _urlController,
                    style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12),
                    decoration: _inputDecoration('http://localhost:3000/sse'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _clearForm,
                child: const Text('Назад'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
                onPressed: () {
                  final name = _nameController.text.trim();
                  if (name.isEmpty) return;

                  final config = McpServerConfig(
                    name: name,
                    type: _selectedType,
                    command: _selectedType == McpServerType.stdio ? _commandController.text.trim() : '',
                    args: _selectedType == McpServerType.stdio 
                        ? _argsController.text.trim().split(' ').where((s) => s.isNotEmpty).toList()
                        : [],
                    url: _selectedType == McpServerType.sse ? _urlController.text.trim() : '',
                    isEnabled: true,
                  );
                  service.addServer(config);
                  _clearForm();
                },
                child: const Text('Добавить'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.cyanAccent)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      isDense: true,
    );
  }
}
