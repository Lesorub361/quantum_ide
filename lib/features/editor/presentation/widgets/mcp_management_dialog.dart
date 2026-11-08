import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/mcp_catalog.dart';
import 'package:quantum_ide/core/services/mcp_service.dart';

class McpManagementDialog extends ConsumerStatefulWidget {
  const McpManagementDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const McpManagementDialog(),
    );
  }

  @override
  ConsumerState<McpManagementDialog> createState() => _McpManagementDialogState();
}

class _McpManagementDialogState extends ConsumerState<McpManagementDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _catalogSearchQuery = '';
  String _selectedCategory = 'Все';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final installedServers = ref.watch(mcpServiceProvider);

    return Dialog(
      backgroundColor: const Color(0xFF0F131D),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                    ),
                    child: const Icon(LucideIcons.plug, size: 16, color: Color(0xFFA78BFA)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MCP Серверы и Инструменты',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Model Context Protocol расширяет возможности ИИ агента внешними тулами',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.plus, size: 16, color: Color(0xFF38BDF8)),
                    tooltip: 'Добавить свой сервер',
                    onPressed: () => _showAddCustomServerDialog(context),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 16, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Tab Bar
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF8B5CF6),
                indicatorWeight: 2.5,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Подключенные'),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${installedServers.length}',
                            style: const TextStyle(fontSize: 10, color: Color(0xFFA78BFA)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Tab(text: 'Каталог MCP (50+)'),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildInstalledTab(context, installedServers),
                  _buildCatalogTab(context, installedServers),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstalledTab(BuildContext context, List<McpServerConfig> servers) {
    if (servers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
                child: const Icon(LucideIcons.plug_2, size: 36, color: Colors.white38),
              ),
              const SizedBox(height: 16),
              Text(
                'Нет подключенных MCP серверов',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Подключите инструменты из встроенного каталога (GitHub, Memory, Fetch, SQLite и др.) или добавьте свой сервер.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 11.5),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(LucideIcons.compass, size: 14),
                label: const Text('Открыть каталог MCP'),
                onPressed: () => _tabController.animateTo(1),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: servers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final s = servers[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161B26),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: s.isEnabled ? const Color(0xFF8B5CF6).withValues(alpha: 0.28) : Colors.white10,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s.isEnabled ? const Color(0xFF10B981) : Colors.white24,
                ),
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
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            s.type.name.toUpperCase(),
                            style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      s.type == McpServerType.stdio
                          ? '${s.command} ${s.args.join(" ")}'
                          : s.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        color: Colors.white38,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: s.isEnabled,
                activeThumbColor: const Color(0xFF8B5CF6),
                activeTrackColor: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                onChanged: (_) => ref.read(mcpServiceProvider.notifier).toggleServer(s.name),
              ),
              IconButton(
                icon: const Icon(LucideIcons.trash_2, size: 14, color: Colors.white38),
                tooltip: 'Удалить сервер',
                onPressed: () => ref.read(mcpServiceProvider.notifier).removeServer(s.name),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCatalogTab(BuildContext context, List<McpServerConfig> installedServers) {
    final installedNames = installedServers.map((s) => s.name).toSet();
    final categories = ['Все', 'Память', 'Разработка', 'Веб', 'Базы данных', 'DevOps'];

    final filteredItems = McpCatalog.items.where((item) {
      if (_catalogSearchQuery.isNotEmpty) {
        final query = _catalogSearchQuery.toLowerCase();
        final match = item.name.toLowerCase().contains(query) ||
            item.description.toLowerCase().contains(query) ||
            item.tags.any((t) => t.toLowerCase().contains(query));
        if (!match) return false;
      }
      if (_selectedCategory != 'Все') {
        if (!item.category.toLowerCase().contains(_selectedCategory.toLowerCase())) {
          return false;
        }
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Search & Filter Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              TextField(
                style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: 'Поиск инструментов в каталоге MCP...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                  prefixIcon: const Icon(LucideIcons.search, size: 14, color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF141824),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                ),
                onChanged: (val) => setState(() => _catalogSearchQuery = val),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 28,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, idx) {
                    final cat = categories[idx];
                    final isSel = _selectedCategory == cat;
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _selectedCategory = cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSel ? const Color(0xFF8B5CF6) : const Color(0xFF141824),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSel ? const Color(0xFF8B5CF6) : Colors.white10,
                          ),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            color: isSel ? Colors.white : Colors.white70,
                            fontSize: 11,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // List of Catalog Items
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: filteredItems.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = filteredItems[index];
              final isInstalled = installedNames.contains(item.name);

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF141824),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isInstalled ? const Color(0xFF10B981).withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(item.icon, size: 18, color: const Color(0xFF38BDF8)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                item.name,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item.category,
                                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.description,
                            style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isInstalled ? Colors.white10 : const Color(0xFF8B5CF6),
                        foregroundColor: isInstalled ? const Color(0xFF10B981) : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: isInstalled
                          ? null
                          : () => _installCatalogItem(context, item),
                      child: Text(
                        isInstalled ? 'Подключен' : 'Подключить',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
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

  Future<void> _installCatalogItem(BuildContext context, McpCatalogItem item) async {
    final envValues = <String, String>{};

    if (item.requiredEnvKeys.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final controllers = {
            for (final k in item.requiredEnvKeys) k: TextEditingController(),
          };

          return AlertDialog(
            backgroundColor: const Color(0xFF141824),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text('Настройка ${item.name}', style: const TextStyle(color: Colors.white, fontSize: 15)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Для работы этого MCP инструмента требуются ключи окружения:',
                    style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  for (final key in item.requiredEnvKeys) ...[
                    Text(key, style: GoogleFonts.jetBrainsMono(color: const Color(0xFF38BDF8), fontSize: 11)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: controllers[key],
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: item.envHints[key] ?? 'Введите значение',
                        hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                        filled: true,
                        fillColor: const Color(0xFF0F131D),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                onPressed: () {
                  for (final e in controllers.entries) {
                    if (e.value.text.trim().isNotEmpty) {
                      envValues[e.key] = e.value.text.trim();
                    }
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Сохранить и подключить'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) return;
    }

    final config = item.toConfig(customEnv: envValues);
    await ref.read(mcpServiceProvider.notifier).addServer(config);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ MCP сервер «${item.name}» успешно подключен к ИИ агенту!'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  Future<void> _showAddCustomServerDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final cmdCtrl = TextEditingController(text: 'npx');
    final argsCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    var serverType = McpServerType.stdio;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF141824),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Добавить свой MCP сервер', style: TextStyle(color: Colors.white, fontSize: 15)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: 'Имя сервера (например: my-tools)',
                    labelStyle: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButton<McpServerType>(
                  value: serverType,
                  dropdownColor: const Color(0xFF1E2433),
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: McpServerType.stdio, child: Text('STDIO (команда/процесс)', style: TextStyle(color: Colors.white, fontSize: 12))),
                    DropdownMenuItem(value: McpServerType.sse, child: Text('SSE (HTTP эндпоинт)', style: TextStyle(color: Colors.white, fontSize: 12))),
                  ],
                  onChanged: (val) {
                    if (val != null) setDlgState(() => serverType = val);
                  },
                ),
                const SizedBox(height: 8),
                if (serverType == McpServerType.stdio) ...[
                  TextField(
                    controller: cmdCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Команда запуска (например: npx или python3)',
                      labelStyle: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: argsCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Аргументы (через пробел, например: -y @modelcontextprotocol/server-sqlite)',
                      labelStyle: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: urlCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'SSE URL (например: http://localhost:8080/sse)',
                      labelStyle: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final cfg = McpServerConfig(
                  name: name,
                  type: serverType,
                  command: cmdCtrl.text.trim(),
                  args: argsCtrl.text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList(),
                  url: urlCtrl.text.trim(),
                );
                await ref.read(mcpServiceProvider.notifier).addServer(cfg);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
  }
}
