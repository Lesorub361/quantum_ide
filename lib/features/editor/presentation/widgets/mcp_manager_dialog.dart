import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/mcp_service.dart';
import 'package:quantum_ide/core/services/mcp_catalog.dart';
import 'package:quantum_ide/core/theme/vscode_colors.dart';

class McpManagerDialog extends ConsumerStatefulWidget {
  const McpManagerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const McpManagerDialog(),
    );
  }

  @override
  ConsumerState<McpManagerDialog> createState() => _McpManagerDialogState();
}

class _McpManagerDialogState extends ConsumerState<McpManagerDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _catalogCategory = 'Все';
  String _catalogQuery = '';

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
    final configuredServers = ref.watch(mcpServiceProvider);
    final mcpNotifier = ref.read(mcpServiceProvider.notifier);

    return Dialog(
      backgroundColor: Vs.sideBar,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Vs.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Vs.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(LucideIcons.blocks, color: Vs.accentLight, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Model Context Protocol (MCP)',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Подключение локальных и удаленных инструментов к ИИ-агенту',
                        style: GoogleFonts.inter(color: Vs.textDim, fontSize: 11),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 16, color: Vs.textDim),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(color: Vs.border, height: 1),

            // Tab Bar
            Container(
              color: Vs.editor,
              child: TabBar(
                controller: _tabController,
                indicatorColor: Vs.accent,
                labelColor: Colors.white,
                unselectedLabelColor: Vs.textDim,
                labelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.server, size: 14),
                        const SizedBox(width: 6),
                        Text('Активные серверы (${configuredServers.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.layout_grid, size: 14),
                        const SizedBox(width: 6),
                        Text('Каталог MCP (${McpCatalog.items.length})'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildConfiguredServersView(configuredServers, mcpNotifier),
                  _buildCatalogView(configuredServers, mcpNotifier),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfiguredServersView(
    List<McpServerConfig> servers,
    McpService notifier,
  ) {
    if (servers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.plug, size: 36, color: Vs.textFaint),
            const SizedBox(height: 12),
            Text(
              'Нет подключенных MCP серверов',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Выберите инструмент из каталога или добавьте свой сервер',
              style: GoogleFonts.inter(color: Vs.textDim, fontSize: 11.5),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Vs.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              icon: const Icon(LucideIcons.plus, size: 14),
              label: const Text('Добавить вручную', style: TextStyle(fontSize: 12)),
              onPressed: () => _showAddCustomServerDialog(context, notifier),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: servers.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == servers.length) {
          return Center(
            child: TextButton.icon(
              icon: const Icon(LucideIcons.plus, size: 14),
              label: const Text('Добавить свой сервер (stdio / SSE)'),
              onPressed: () => _showAddCustomServerDialog(context, notifier),
            ),
          );
        }

        final server = servers[index];
        return Container(
          decoration: BoxDecoration(
            color: Vs.editor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Vs.border),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                server.type == McpServerType.stdio ? LucideIcons.terminal : LucideIcons.globe,
                size: 18,
                color: server.isEnabled ? Vs.accentLight : Vs.textFaint,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          server.name,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            server.type.name.toUpperCase(),
                            style: const TextStyle(fontSize: 9.5, color: Vs.textDim),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      server.type == McpServerType.stdio
                          ? '${server.command} ${server.args.join(" ")}'
                          : server.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Vs.textDim),
                    ),
                  ],
                ),
              ),
              Switch(
                value: server.isEnabled,
                activeTrackColor: Vs.accentLight.withValues(alpha: 0.5),
                activeThumbColor: Vs.accentLight,
                onChanged: (_) => notifier.toggleServer(server.name),
              ),
              IconButton(
                icon: const Icon(LucideIcons.trash_2, size: 15, color: Vs.error),
                onPressed: () => notifier.removeServer(server.name),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCatalogView(
    List<McpServerConfig> configuredServers,
    McpService notifier,
  ) {
    final configuredNames = configuredServers.map((s) => s.name).toSet();
    final categories = McpCatalog.categories;

    final filteredItems = McpCatalog.items.where((item) {
      final matchCategory = _catalogCategory == 'Все' || item.category == _catalogCategory;
      final q = _catalogQuery.toLowerCase().trim();
      final matchQuery = q.isEmpty ||
          item.name.toLowerCase().contains(q) ||
          item.description.toLowerCase().contains(q) ||
          item.tags.any((t) => t.toLowerCase().contains(q));
      return matchCategory && matchQuery;
    }).toList();

    return Column(
      children: [
        // Search & category chips
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              color: Vs.input,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: Vs.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const Icon(LucideIcons.search, size: 14, color: Vs.textDim),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: 'Поиск по каталогу MCP инструментов...',
                      hintStyle: TextStyle(color: Vs.textFaint, fontSize: 12),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _catalogQuery = v),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Categories horizontal list
        SizedBox(
          height: 32,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, idx) {
              final cat = categories[idx];
              final isSel = cat == _catalogCategory;
              return ChoiceChip(
                label: Text(cat, style: const TextStyle(fontSize: 11)),
                selected: isSel,
                visualDensity: VisualDensity.compact,
                selectedColor: Vs.accent.withValues(alpha: 0.35),
                backgroundColor: Vs.editor,
                onSelected: (_) => setState(() => _catalogCategory = cat),
              );
            },
          ),
        ),
        const SizedBox(height: 6),

        // Items list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: filteredItems.length,
            itemBuilder: (context, index) {
              final item = filteredItems[index];
              final isAdded = configuredNames.contains(item.name);

              return Card(
                color: Vs.editor,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Vs.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Vs.sideBar,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(item.icon, size: 20, color: Vs.accentLight),
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
                                if (item.isPopular) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'POPULAR',
                                      style: TextStyle(
                                        color: Colors.orangeAccent,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.description,
                              style: GoogleFonts.inter(color: Vs.textDim, fontSize: 11.5),
                            ),
                            if (item.requiredEnvKeys.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 4,
                                children: item.requiredEnvKeys.map((k) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      'ENV: $k',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 9.5,
                                        color: Vs.textFaint,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      isAdded
                          ? OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Vs.error,
                                side: const BorderSide(color: Vs.border),
                              ),
                              icon: const Icon(LucideIcons.check, size: 12),
                              label: const Text('Установлен', style: TextStyle(fontSize: 11)),
                              onPressed: () => notifier.removeServer(item.name),
                            )
                          : ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Vs.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              icon: const Icon(LucideIcons.download, size: 12),
                              label: const Text('Добавить', style: TextStyle(fontSize: 11)),
                              onPressed: () => _installCatalogItem(context, item, notifier),
                            ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _installCatalogItem(BuildContext context, McpCatalogItem item, McpService notifier) async {
    final Map<String, String> envMap = {};

    if (item.requiredEnvKeys.isNotEmpty) {
      final envControllers = {
        for (final k in item.requiredEnvKeys) k: TextEditingController(),
      };

      final bool? proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Vs.sideBar,
          title: Text('Настройка ${item.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Для работы сервера требуются следующие переменные окружения:',
                style: GoogleFonts.inter(color: Vs.textDim, fontSize: 12),
              ),
              const SizedBox(height: 12),
              for (final k in item.requiredEnvKeys) ...[
                Text(k, style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
                if (item.envHints[k] != null)
                  Text(item.envHints[k]!, style: const TextStyle(fontSize: 10, color: Vs.textFaint)),
                const SizedBox(height: 4),
                TextField(
                  controller: envControllers[k],
                  style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Vs.input,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить и подключить'),
            ),
          ],
        ),
      );

      if (proceed != true) return;
      for (final entry in envControllers.entries) {
        if (entry.value.text.trim().isNotEmpty) {
          envMap[entry.key] = entry.value.text.trim();
        }
      }
    }

    final config = item.toConfig(customEnv: envMap);
    await notifier.addServer(config);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('MCP Сервер ${item.name} успешно добавлен!')),
      );
    }
  }

  void _showAddCustomServerDialog(BuildContext context, McpService notifier) {
    final nameCtrl = TextEditingController();
    final cmdCtrl = TextEditingController(text: 'npx');
    final argsCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    McpServerType type = McpServerType.stdio;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: Vs.sideBar,
          title: const Text('Добавить MCP Сервер'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Имя сервера', hintText: 'my-custom-tool'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<McpServerType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Тип подключения'),
                  items: const [
                    DropdownMenuItem(value: McpServerType.stdio, child: Text('STDIO (командная строка)')),
                    DropdownMenuItem(value: McpServerType.sse, child: Text('SSE (Server-Sent Events URL)')),
                  ],
                  onChanged: (v) => setDlgState(() => type = v ?? McpServerType.stdio),
                ),
                const SizedBox(height: 10),
                if (type == McpServerType.stdio) ...[
                  TextField(
                    controller: cmdCtrl,
                    decoration: const InputDecoration(labelText: 'Команда', hintText: 'npx / python / docker'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: argsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Аргументы (через пробел)',
                      hintText: '-y @modelcontextprotocol/server-...',
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(labelText: 'URL эндпоинта', hintText: 'http://localhost:3000/sse'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final args = argsCtrl.text.trim().isEmpty
                    ? <String>[]
                    : argsCtrl.text.trim().split(RegExp(r'\s+'));
                final cfg = McpServerConfig(
                  name: name,
                  type: type,
                  command: cmdCtrl.text.trim(),
                  args: args,
                  url: urlCtrl.text.trim(),
                  isEnabled: true,
                );
                await notifier.addServer(cfg);
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
