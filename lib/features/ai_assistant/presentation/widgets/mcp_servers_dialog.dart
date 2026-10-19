import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/services/mcp_service.dart';
import 'package:quantum_ide/core/services/mcp_catalog.dart';

typedef McpPreset = McpCatalogItem;

class McpServersDialog extends ConsumerStatefulWidget {
  const McpServersDialog({super.key});

  @override
  ConsumerState<McpServersDialog> createState() => _McpServersDialogState();
}

class _McpServersDialogState extends ConsumerState<McpServersDialog> {
  final _nameController = TextEditingController();
  final _commandController = TextEditingController();
  final _argsController = TextEditingController();
  final _urlController = TextEditingController();
  final _searchController = TextEditingController();

  // Custom inputs for preset installation
  final Map<String, TextEditingController> _presetControllers = {};

  McpServerType _selectedType = McpServerType.stdio;
  bool _isAddingManual = false;
  McpCatalogItem? _installingPreset;
  int _activeTab = 0; // 0 = Servers, 1 = Marketplace
  String _selectedCategory = 'Все';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query != _searchQuery) {
      setState(() => _searchQuery = query);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    _argsController.dispose();
    _urlController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
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

  void _setupPresetControllers(McpCatalogItem preset) {
    _presetControllers.clear();
    for (final key in preset.requiredEnvKeys) {
      _presetControllers['env_$key'] = TextEditingController();
    }
    for (int i = 0; i < preset.requiredArgLabels.length; i++) {
      _presetControllers['arg_$i'] = TextEditingController();
    }
  }

  String _getPresetDescription(BuildContext context, McpCatalogItem preset) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return preset.description;
    switch (preset.id) {
      case 'github':
        return l10n.mcpGithubDesc;
      case 'google-search':
        return l10n.mcpGoogleSearchDesc;
      case 'fetch':
        return l10n.mcpFetchDesc;
      case 'postgres':
        return l10n.mcpPostgresDesc;
      case 'sqlite':
        return l10n.mcpSqliteDesc;
      case 'memory':
        return l10n.mcpMemoryDesc;
      case 'brave-search':
        return l10n.mcpBraveSearchDesc;
      case 'puppeteer':
        return l10n.mcpPuppeteerDesc;
      case 'firecrawl':
        return l10n.mcpFirecrawlDesc;
      case 'notion':
        return l10n.mcpNotionDesc;
      case 'slack':
        return l10n.mcpSlackDesc;
      case 'git':
        return l10n.mcpGitDesc;
      case 'gitlab':
        return l10n.mcpGitlabDesc;
      case 'sentry':
        return l10n.mcpSentryDesc;
      case 'airtable':
        return l10n.mcpAirtableDesc;
      case 'sequential-thinking':
        return l10n.mcpSequentialThinkingDesc;
      default:
        return preset.description;
    }
  }

  String _getArgLabel(BuildContext context, McpCatalogItem preset, String label) {
    final l10n = AppLocalizations.of(context);
    if (l10n != null) {
      if (preset.id == 'postgres') {
        return l10n.mcpPostgresArg;
      } else if (preset.id == 'sqlite') {
        return l10n.mcpSqliteArg;
      }
    }
    return label;
  }

  @override
  Widget build(BuildContext context) {
    final mcpServers = ref.watch(mcpServiceProvider);
    final mcpService = ref.read(mcpServiceProvider.notifier);
    final mediaQuery = MediaQuery.of(context);
    final isMobile = mediaQuery.size.width < 600;
    final dialogWidth = isMobile ? mediaQuery.size.width * 0.96 : 640.0;
    final dialogHeight = isMobile ? mediaQuery.size.height * 0.92 : mediaQuery.size.height * 0.85;

    final Widget header = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3C3C).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(LucideIcons.blocks, size: 16, color: Color(0xFFFF3C3C)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)?.mcpServersTitle ?? 'MCP Серверы (Tools)',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Model Context Protocol • 40+ готовых интеграций',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
          ],
        ),
        IconButton(
          icon: const Icon(LucideIcons.x, color: Colors.white54, size: 18),
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );

    final Widget tabHeader = Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              0,
              '${AppLocalizations.of(context)?.activeServers(mcpServers.length) ?? 'Активные'} (${mcpServers.length})',
              LucideIcons.server,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildTabButton(
              1,
              '${AppLocalizations.of(context)?.repository ?? 'Каталог'} (${McpCatalog.items.length})',
              LucideIcons.store,
            ),
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
      backgroundColor: const Color(0xFF141721),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 24,
        vertical: isMobile ? 12 : 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        padding: EdgeInsets.all(isMobile ? 12.0 : 18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 8),
            if (_installingPreset == null && !_isAddingManual) tabHeader,
            const SizedBox(height: 4),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isSelected = _activeTab == index;
    return InkWell(
      onTap: () {
        setState(() {
          _activeTab = index;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF3C3C).withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF3C3C).withValues(alpha: 0.4) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? const Color(0xFFFF3C3C) : Colors.white54,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: isSelected ? Colors.white : Colors.white60,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServersList(List<McpServerConfig> servers, McpService service) {
    if (servers.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.bot, size: 44, color: Colors.white.withValues(alpha: 0.2)),
          ),
          const SizedBox(height: 14),
          Text(
            AppLocalizations.of(context)?.noMcpServers ?? 'Нет подключенных MCP серверов',
            style: GoogleFonts.inter(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            'Подключите серверы из каталога, чтобы дать AI доступ к файлам, Git, браузеру и базам данных',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: Colors.white30, fontSize: 11),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3C3C).withValues(alpha: 0.18),
                  foregroundColor: const Color(0xFFFF3C3C),
                  elevation: 0,
                  side: const BorderSide(color: Color(0x4FFF3C3C)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                icon: const Icon(LucideIcons.store, size: 14),
                onPressed: () => setState(() => _activeTab = 1),
                label: Text(
                  AppLocalizations.of(context)?.goToRepository ?? 'Открыть каталог MCP (40+)',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                icon: const Icon(LucideIcons.plus, size: 14),
                onPressed: () => setState(() => _isAddingManual = true),
                label: Text(
                  AppLocalizations.of(context)?.addManually ?? 'Свой сервер',
                  style: const TextStyle(fontSize: 11.5),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: s.isEnabled ? Colors.cyanAccent.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: (s.isEnabled ? Colors.cyanAccent : Colors.white24).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        s.type == McpServerType.stdio ? LucideIcons.terminal : LucideIcons.globe,
                        size: 16,
                        color: s.isEnabled ? Colors.cyanAccent : Colors.white30,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                s.name,
                                style: GoogleFonts.inter(
                                  color: s.isEnabled ? Colors.white : Colors.white38,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                              if (s.env.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                                  ),
                                  child: const Text(
                                    'KEY',
                                    style: TextStyle(color: Colors.cyanAccent, fontSize: 8, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
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
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3C3C).withValues(alpha: 0.15),
                  foregroundColor: const Color(0xFFFF3C3C),
                  elevation: 0,
                  side: const BorderSide(color: Color(0x3FFF3C3C)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  minimumSize: const Size.fromHeight(38),
                ),
                icon: const Icon(LucideIcons.store, size: 14),
                label: const Text('Добавить из каталога (40+)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                onPressed: () => setState(() => _activeTab = 1),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                minimumSize: const Size(120, 38),
              ),
              icon: const Icon(LucideIcons.plus, size: 14),
              label: Text(AppLocalizations.of(context)?.addManually ?? 'Вручную', style: const TextStyle(fontSize: 11.5)),
              onPressed: () => setState(() => _isAddingManual = true),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMarketplace() {
    final installedServers = ref.watch(mcpServiceProvider);

    final filtered = McpCatalog.items.where((item) {
      if (_selectedCategory == '🔥 Популярные' && !item.isPopular) return false;
      if (_selectedCategory != 'Все' && _selectedCategory != '🔥 Популярные' && item.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final matchName = item.name.toLowerCase().contains(_searchQuery);
        final matchDesc = item.description.toLowerCase().contains(_searchQuery);
        final matchTag = item.tags.any((t) => t.toLowerCase().contains(_searchQuery));
        final matchArgs = item.args.any((a) => a.toLowerCase().contains(_searchQuery));
        if (!matchName && !matchDesc && !matchTag && !matchArgs) return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Search bar
        Container(
          height: 38,
          margin: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: _searchController,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Поиск по 40+ MCP серверам (GitHub, SQLite, Git, Docker, Puppeteer...)',
              hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
              prefixIcon: const Icon(LucideIcons.search, size: 15, color: Colors.white38),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(LucideIcons.x, size: 13, color: Colors.white38),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            ),
          ),
        ),

        // Categories chip row
        SizedBox(
          height: 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: McpCatalog.categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final cat = McpCatalog.categories[index];
              final isSel = _selectedCategory == cat;
              return InkWell(
                onTap: () => setState(() => _selectedCategory = cat),
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isSel ? const Color(0xFFFF3C3C).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: isSel ? const Color(0xFFFF3C3C).withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Text(
                    cat,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      color: isSel ? const Color(0xFFFF7A7A) : Colors.white60,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 8),

        // Result count header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              Text(
                'Доступно: ${filtered.length} серверов',
                style: GoogleFonts.inter(fontSize: 10, color: Colors.white30),
              ),
              const Spacer(),
              if (_selectedCategory != 'Все' || _searchQuery.isNotEmpty)
                InkWell(
                  onTap: () {
                    setState(() {
                      _selectedCategory = 'Все';
                      _searchController.clear();
                    });
                  },
                  child: Text(
                    'Сбросить фильтры',
                    style: GoogleFonts.inter(fontSize: 10, color: Colors.cyanAccent),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // Server list
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final preset = filtered[index];
              final isInstalled = installedServers.any((s) => s.name == preset.name);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.025),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isInstalled
                        ? Colors.greenAccent.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3C3C).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(preset.icon, size: 16, color: const Color(0xFFFF5252)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      preset.name,
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (preset.isPopular) ...[
                                    const SizedBox(width: 4),
                                    const Text('🔥', style: TextStyle(fontSize: 10)),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      preset.category,
                                      style: GoogleFonts.inter(color: Colors.white54, fontSize: 8.5),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  if (preset.requiredEnvKeys.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '🔑 Нужен ключ',
                                        style: GoogleFonts.inter(color: Colors.amberAccent, fontSize: 8.5, fontWeight: FontWeight.w600),
                                      ),
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.tealAccent.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '⚡ Готов к запуску',
                                        style: GoogleFonts.inter(color: Colors.tealAccent, fontSize: 8.5, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isInstalled)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.check, size: 11, color: Colors.greenAccent),
                                const SizedBox(width: 4),
                                Text(
                                  AppLocalizations.of(context)?.installed ?? 'Установлен',
                                  style: GoogleFonts.inter(
                                    color: Colors.greenAccent,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF3C3C).withValues(alpha: 0.15),
                              foregroundColor: const Color(0xFFFF3C3C),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              side: const BorderSide(color: Color(0x3FFF3C3C)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            icon: const Icon(LucideIcons.plus, size: 12),
                            onPressed: () {
                              _setupPresetControllers(preset);
                              setState(() {
                                _installingPreset = preset;
                              });
                            },
                            label: Text(
                              AppLocalizations.of(context)?.install ?? 'Установить',
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _getPresetDescription(context, preset),
                      style: GoogleFonts.inter(color: Colors.white54, fontSize: 11, height: 1.3),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      preset.type == McpServerType.stdio
                          ? (preset.args.isNotEmpty ? preset.args.last : preset.command)
                          : preset.url,
                      style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent.withValues(alpha: 0.6), fontSize: 9.5),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPresetInstallationForm(McpService service) {
    final preset = _installingPreset!;
    final List<Widget> fields = [];

    // Render Env Variable Fields
    for (final envKey in preset.requiredEnvKeys) {
      final controller = _presetControllers['env_$envKey']!;
      final hint = preset.envHints[envKey] ?? 'Вставьте $envKey';
      final keyUrl = preset.envKeyUrls[envKey];

      fields.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppLocalizations.of(context)?.authParam(envKey) ?? envKey,
                    style: GoogleFonts.jetBrainsMono(
                      color: Colors.cyanAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (keyUrl != null)
                    InkWell(
                      onTap: () async {
                        final uri = Uri.parse(keyUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          children: [
                            Text(
                              'Получить ключ',
                              style: GoogleFonts.inter(
                                color: const Color(0xFFFF5252),
                                fontSize: 10,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(LucideIcons.external_link, size: 10, color: Color(0xFFFF5252)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                hint,
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                obscureText: envKey.toLowerCase().contains('key') ||
                    envKey.toLowerCase().contains('token') ||
                    envKey.toLowerCase().contains('secret'),
                style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12),
                decoration: _inputDecoration(
                  AppLocalizations.of(context)?.enterValueFor(envKey) ?? 'Введите значение $envKey',
                ),
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
              Text(
                _getArgLabel(context, preset, label),
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                decoration: _inputDecoration(
                  AppLocalizations.of(context)?.enterLabel(_getArgLabel(context, preset, label)) ??
                      'Укажите ${_getArgLabel(context, preset, label)}',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3C3C).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(preset.icon, size: 18, color: const Color(0xFFFF3C3C)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)?.installPreset(preset.name) ?? 'Установка: ${preset.name}',
                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    preset.category,
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _getPresetDescription(context, preset),
          style: GoogleFonts.inter(color: Colors.white60, fontSize: 11, height: 1.3),
        ),
        const SizedBox(height: 14),
        const Divider(color: Colors.white10, height: 1),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (fields.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.tealAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.circle_check, size: 16, color: Colors.tealAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Этот сервер не требует API ключей. Нажмите "Установить" для добавления.',
                            style: GoogleFonts.inter(color: Colors.tealAccent, fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...fields,
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white12),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                onPressed: _clearForm,
                child: Text(AppLocalizations.of(context)?.back ?? 'Назад'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3C3C).withValues(alpha: 0.2),
                  foregroundColor: const Color(0xFFFF3C3C),
                  elevation: 0,
                  side: const BorderSide(color: Color(0x4FFF3C3C)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                onPressed: () {
                  final finalArgs = List<String>.from(preset.args);
                  final Map<String, String> finalEnv = {};

                  // Collect Env parameters
                  for (final envKey in preset.requiredEnvKeys) {
                    final val = _presetControllers['env_$envKey']?.text.trim() ?? '';
                    if (val.isNotEmpty) {
                      finalEnv[envKey] = val;
                    }
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
                    type: preset.type,
                    command: preset.command,
                    args: finalArgs,
                    url: preset.url,
                    env: finalEnv,
                    isEnabled: true,
                  );

                  service.addServer(config);
                  _clearForm();
                },
                child: Text(
                  AppLocalizations.of(context)?.install ?? 'Установить сервер',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
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
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(LucideIcons.plus, size: 14, color: Colors.cyanAccent),
            ),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context)?.addServerManually ?? 'Добавить MCP сервер вручную',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppLocalizations.of(context)?.serverName ?? 'Имя сервера',
                  style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameController,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                  decoration: _inputDecoration(
                    AppLocalizations.of(context)?.exampleLocalSearch ?? 'Например: My Custom Tool',
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  AppLocalizations.of(context)?.connectionType ?? 'Тип подключения',
                  style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: Text(AppLocalizations.of(context)?.stdioLocal ?? 'stdio (Локальный процесс)'),
                        selected: _selectedType == McpServerType.stdio,
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedType = McpServerType.stdio);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: Text(AppLocalizations.of(context)?.sseHttp ?? 'SSE (HTTP Server)'),
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
                  Text(
                    AppLocalizations.of(context)?.startCommand ?? 'Команда запуска',
                    style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _commandController,
                    style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12),
                    decoration: _inputDecoration(
                      AppLocalizations.of(context)?.exampleStartCommand ?? 'npx / python / node / docker',
                    ),
                  ),
                  const SizedBox(height: 12),

                  Text(
                    AppLocalizations.of(context)?.argsSpace ?? 'Аргументы (через пробел)',
                    style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _argsController,
                    style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12),
                    decoration: _inputDecoration('-y @modelcontextprotocol/server-postgres'),
                  ),
                ] else ...[
                  Text('SSE URL', style: GoogleFonts.inter(color: Colors.white60, fontSize: 11)),
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
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white12),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                onPressed: _clearForm,
                child: Text(AppLocalizations.of(context)?.back ?? 'Назад'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
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
                child: Text(
                  AppLocalizations.of(context)?.add ?? 'Добавить',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.cyanAccent),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      isDense: true,
    );
  }
}
