import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/todo_tree_service.dart';
import 'package:quantum_ide/core/services/test_runner_service.dart';
import 'package:quantum_ide/core/services/dependency_checker_service.dart';
import 'package:quantum_ide/core/services/quantum_plugin_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/wasm_plugins_panel.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

class ExtensionsPanel extends ConsumerStatefulWidget {
  const ExtensionsPanel({super.key});

  @override
  ConsumerState<ExtensionsPanel> createState() => _ExtensionsPanelState();
}

class _ExtensionsPanelState extends ConsumerState<ExtensionsPanel> {
  int _selectedTabSection = 0; // 0: Плагины пользователя, 1: Встроенные, 2: WASM
  int _selectedExtension = -1;
  bool _isDocExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pluginCount = ref.watch(quantumPluginServiceProvider.select((s) => s.plugins.length));

    return Container(
      color: const Color(0xFF0D0F14).withValues(alpha: 0.7),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.cyanAccent, Colors.purpleAccent],
                  ).createShader(bounds),
                  child: const Icon(LucideIcons.puzzle, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 8),
                Text(
                  'Плагины & Расширения',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Segmented Tabs: [Мои плагины] | [Встроенные] | [WASM]
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              children: [
                _buildSegmentButton(0, 'Мои плагины ($pluginCount)', LucideIcons.blocks),
                const SizedBox(width: 6),
                _buildSegmentButton(1, 'Встроенные', LucideIcons.layout_grid),
                const SizedBox(width: 6),
                _buildSegmentButton(2, 'WASM', LucideIcons.cpu),
              ],
            ),
          ),

          const Divider(height: 1, color: Colors.white10),

          Expanded(
            child: IndexedStack(
              index: _selectedTabSection,
              children: [
                _buildUserPluginsView(),
                _selectedExtension == -1
                    ? _buildExtensionsList(l10n)
                    : _buildExtensionView(_selectedExtension, l10n),
                const WasmPluginsPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton(int index, String label, IconData icon) {
    final isSelected = _selectedTabSection == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _selectedTabSection = index;
          _selectedExtension = -1;
        }),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF8B5CF6).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFF8B5CF6).withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 11, color: isSelected ? const Color(0xFFC084FC) : Colors.white54),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : Colors.white60,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserPluginsView() {
    final pluginState = ref.watch(quantumPluginServiceProvider);
    final pluginService = ref.read(quantumPluginServiceProvider.notifier);

    return RefreshIndicator(
      onRefresh: () => pluginService.loadPlugins(),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _showAddPluginDialog(context),
                  icon: const Icon(LucideIcons.plus, size: 13),
                  label: const Text('Создать плагин', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => pluginService.loadPlugins(),
                icon: const Icon(LucideIcons.refresh_cw, size: 12),
                label: const Text('Обновить', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Text(
            'ПЛАГИНЫ В .QUANTUM/PLUGINS/ (${pluginState.plugins.length})',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white38,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),

          if (pluginState.plugins.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Column(
                children: [
                  const Icon(LucideIcons.puzzle, size: 26, color: Color(0xFFC084FC)),
                  const SizedBox(height: 8),
                  Text(
                    'Нет установленных плагинов',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Нажмите «Создать плагин» выше, чтобы настроить иконки, команды терминала или чат-бота под себя!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white38),
                  ),
                ],
              ),
            ),

          ...pluginState.plugins.map((plugin) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: plugin.isEnabled
                    ? Colors.white.withValues(alpha: 0.035)
                    : Colors.white.withValues(alpha: 0.015),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: plugin.isEnabled
                      ? const Color(0xFF8B5CF6).withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(LucideIcons.puzzle, size: 15, color: Color(0xFFC084FC)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    plugin.name,
                                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'v${plugin.version}',
                                  style: GoogleFonts.jetBrainsMono(fontSize: 9.5, color: Colors.white38),
                                ),
                              ],
                            ),
                            Text(
                              'Автор: ${plugin.author}',
                              style: GoogleFonts.inter(fontSize: 10, color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: plugin.isEnabled,
                        activeThumbColor: const Color(0xFF8B5CF6),
                        onChanged: (val) => pluginService.togglePlugin(plugin.id, val),
                      ),
                    ],
                  ),
                  if (plugin.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      plugin.description,
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.white70, height: 1.3),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      if (plugin.folderIcons.isNotEmpty || plugin.fileIcons.isNotEmpty)
                        _buildFeaturePill(LucideIcons.palette, '${plugin.folderIcons.length + plugin.fileIcons.length} иконок', Colors.cyanAccent),
                      if (plugin.terminalCommands.isNotEmpty)
                        _buildFeaturePill(LucideIcons.terminal, '${plugin.terminalCommands.length} команд', Colors.greenAccent),
                      if (plugin.customBots.isNotEmpty)
                        _buildFeaturePill(LucideIcons.bot, '${plugin.customBots.length} ботов', Colors.amberAccent),
                      if (plugin.customButtons.isNotEmpty)
                        _buildFeaturePill(LucideIcons.sparkles, '${plugin.customButtons.length} кнопок', Colors.purpleAccent),
                      if (plugin.disabledTabs.isNotEmpty)
                        _buildFeaturePill(LucideIcons.eye_off, '${plugin.disabledTabs.length} скрытых вкладок', Colors.orangeAccent),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white10, height: 1),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (plugin.filePath.isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            ref.read(editorProvider.notifier).openFile(plugin.filePath);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Файл плагина открыт в редакторе: ${plugin.name}')),
                            );
                          },
                          icon: const Icon(LucideIcons.file_code, size: 13, color: Colors.cyanAccent),
                          label: const Text('Редактировать код', style: TextStyle(fontSize: 11, color: Colors.cyanAccent)),
                        ),
                      IconButton(
                        icon: const Icon(LucideIcons.trash_2, size: 13, color: Colors.redAccent),
                        tooltip: 'Удалить плагин',
                        onPressed: () => _confirmDeletePlugin(plugin.id, plugin.name),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 12),
          _buildPluginDocumentationCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildFeaturePill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 9.5, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _confirmDeletePlugin(String pluginId, String pluginName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141822),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Удалить плагин?', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        content: Text('Вы действительно хотите удалить плагин "$pluginName"?', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.white60))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(quantumPluginServiceProvider.notifier).deletePlugin(pluginId);
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  void _showAddPluginDialog(BuildContext context) {
    String selectedTemplate = 'icons';
    final nameController = TextEditingController(text: 'Кастомные иконки');

    final templates = [
      {'type': 'icons', 'title': '🎨 Кастомные иконки', 'desc': 'Свои иконки и цвета для папок и файлов'},
      {'type': 'chatbot', 'title': '🤖 Свой ИИ чат-бот', 'desc': 'Кастомный ментор с персональным системным промптом'},
      {'type': 'terminal', 'title': '💻 Команды терминала', 'desc': 'Кнопки быстрого запуска команд в терминале'},
      {'type': 'tabs', 'title': '🎛 Настройка вкладок', 'desc': 'Отключение или добавление вкладок боковой панели'},
      {'type': 'buttons', 'title': '🔘 Кнопки интерфейса', 'desc': 'Свои кнопки быстрых действий на верхней панели IDE'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF141822),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(LucideIcons.puzzle, color: Color(0xFFC084FC), size: 18),
              const SizedBox(width: 8),
              Text(
                'Создать плагин для IDE',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Выберите шаблон функционала:',
                    style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white60),
                  ),
                  const SizedBox(height: 8),
                  for (final t in templates)
                    InkWell(
                      onTap: () {
                        setDlgState(() {
                          selectedTemplate = t['type']!;
                          nameController.text = t['title']!;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: selectedTemplate == t['type']
                              ? const Color(0xFF8B5CF6).withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selectedTemplate == t['type']
                                ? const Color(0xFF8B5CF6)
                                : Colors.white10,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selectedTemplate == t['type'] ? LucideIcons.circle_check : LucideIcons.circle_dot,
                              size: 16,
                              color: selectedTemplate == t['type'] ? const Color(0xFFC084FC) : Colors.white38,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t['title']!, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                                  Text(t['desc']!, style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white54)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Название плагина',
                      labelStyle: const TextStyle(color: Color(0xFFC084FC), fontSize: 11),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
              onPressed: () async {
                Navigator.pop(ctx);
                final service = ref.read(quantumPluginServiceProvider.notifier);
                final p = await service.createPluginFromTemplate(
                  selectedTemplate,
                  customName: nameController.text.trim().isNotEmpty ? nameController.text.trim() : null,
                );
                if (p.filePath.isNotEmpty) {
                  ref.read(editorProvider.notifier).openFile(p.filePath);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Плагин "${p.name}" создан в .quantum/plugins/ и открыт для редактирования!')),
                  );
                }
              },
              icon: const Icon(LucideIcons.check, size: 14),
              label: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPluginDocumentationCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isDocExpanded = !_isDocExpanded),
            child: Row(
              children: [
                const Icon(LucideIcons.book_open, size: 15, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '📖 Как написать свой плагин для Quantum IDE',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                Icon(
                  _isDocExpanded ? LucideIcons.chevron_up : LucideIcons.chevron_down,
                  size: 13,
                  color: Colors.white54,
                ),
              ],
            ),
          ),
          if (_isDocExpanded) ...[
            const SizedBox(height: 10),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 10),
            Text(
              'Все пользовательские плагины хранятся в формате JSON в папке проекта:\n`.quantum/plugins/имя_плагина.json`\n\nВы можете скопировать или отредактировать этот файл прямо в редакторе.',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: SelectableText(
                '{\n'
                '  "id": "my_plugin",\n'
                '  "name": "Мой плагин",\n'
                '  "folderIcons": {\n'
                '    "controllers": {"icon": "zap", "color": "#FF9800"}\n'
                '  },\n'
                '  "terminalCommands": [\n'
                '    {"name": "Pub Get", "command": "flutter pub get"}\n'
                '  ],\n'
                '  "disabledTabs": ["disk", "live_share"]\n'
                '}',
                style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.cyanAccent, height: 1.3),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Поддерживаемые разделы:\n'
              '• "folderIcons" — кастомные иконки для папок\n'
              '• "fileIcons" — кастомные иконки для файлов (.dart, .json и др.)\n'
              '• "terminalCommands" — быстрые кнопки команд для терминала\n'
              '• "customBots" — свои ИИ ассистенты с заданным системным промптом\n'
              '• "disabledTabs" — скрытие ненужных вкладок интерфейса\n'
              '• "customButtons" — свои кнопки на верхней панели IDE',
              style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white60, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExtensionsList(AppLocalizations l10n) {
    final extensions = [
      const _ExtensionData(
        icon: LucideIcons.list_todo,
        name: 'Todo Tree',
        description: 'Find all TODO, FIXME, HACK comments',
        color: Colors.amberAccent,
        badge: null,
      ),
      const _ExtensionData(
        icon: LucideIcons.play,
        name: 'Test Runner',
        description: 'Run and view test results',
        color: Colors.greenAccent,
        badge: null,
      ),
      const _ExtensionData(
        icon: LucideIcons.package,
        name: 'Dependency Checker',
        description: 'Check for outdated packages',
        color: Colors.orangeAccent,
        badge: null,
      ),
      const _ExtensionData(
        icon: LucideIcons.code,
        name: 'Snippets',
        description: 'Code snippets for Flutter/Dart',
        color: Colors.cyanAccent,
        badge: null,
      ),
    ];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: extensions.length,
      itemBuilder: (context, index) {
        final ext = extensions[index];
        return _buildExtensionCard(ext, index);
      },
    );
  }

  Widget _buildExtensionCard(_ExtensionData ext, int index) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedExtension = index),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ext.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(ext.icon, size: 18, color: ext.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ext.name,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ext.description,
                      style: GoogleFonts.inter(color: Colors.white38, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.chevron_right, size: 14, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExtensionView(int index, AppLocalizations l10n) {
    switch (index) {
      case 0:
        return _buildTodoTreeView(l10n);
      case 1:
        return _buildTestRunnerView(l10n);
      case 2:
        return _buildDependencyCheckerView(l10n);
      case 3:
        return _buildSnippetsView(l10n);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () => setState(() => _selectedExtension = -1),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.arrow_left, size: 12, color: Colors.white54),
            const SizedBox(width: 4),
            Text('Back', style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildTodoTreeView(AppLocalizations l10n) {
    final todoState = ref.watch(todoTreeProvider);

    return Column(
      children: [
        _buildBackButton(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => ref.read(todoTreeProvider.notifier).scan(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.refresh_cw, size: 12, color: Colors.amberAccent),
                        const SizedBox(width: 6),
                        Text('Scan Project', style: GoogleFonts.inter(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (todoState.isLoading)
          const Expanded(child: Center(child: CircularProgressIndicator(color: Colors.amberAccent, strokeWidth: 2)))
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: todoState.filtered.length,
              itemBuilder: (context, index) {
                final item = todoState.filtered[index];
                final typeColor = item.type == 'FIXME' || item.type == 'BUG'
                    ? Colors.redAccent
                    : item.type == 'TODO'
                        ? Colors.amberAccent
                        : Colors.purpleAccent;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Clipboard.setData(ClipboardData(text: '${item.filePath}:${item.line}\n${item.text}')),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(item.type, style: GoogleFonts.jetBrainsMono(color: typeColor, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.text,
                                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${item.filePath}:${item.line}',
                                  style: GoogleFonts.jetBrainsMono(color: Colors.white30, fontSize: 9),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTestRunnerView(AppLocalizations l10n) {
    final testState = ref.watch(testRunnerProvider);

    return Column(
      children: [
        _buildBackButton(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: testState.isRunning ? null : () => ref.read(testRunnerProvider.notifier).runAll(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: testState.isRunning
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.greenAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (testState.isRunning)
                          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.greenAccent))
                        else
                          const Icon(LucideIcons.play, size: 12, color: Colors.greenAccent),
                        const SizedBox(width: 6),
                        Text(
                          testState.isRunning ? 'Running...' : 'Run All Tests',
                          style: GoogleFonts.inter(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (testState.results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                _buildTestBadge('${testState.passed} passed', Colors.greenAccent),
                const SizedBox(width: 8),
                _buildTestBadge('${testState.failed} failed', Colors.redAccent),
              ],
            ),
          ),
        Expanded(
          child: testState.results.isEmpty
              ? Center(
                  child: Text(
                    testState.isRunning ? 'Running tests...' : 'No test results yet',
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: testState.results.length,
                  itemBuilder: (context, index) {
                    final result = testState.results[index];
                    final color = result.status == TestStatus.passed
                        ? Colors.greenAccent
                        : result.status == TestStatus.failed
                            ? Colors.redAccent
                            : Colors.orangeAccent;
                    final icon = result.status == TestStatus.passed
                        ? LucideIcons.circle_check
                        : result.status == TestStatus.failed
                            ? LucideIcons.circle_x
                            : LucideIcons.info;

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          Icon(icon, size: 12, color: color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(result.name, style: GoogleFonts.inter(color: Colors.white70, fontSize: 11)),
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

  Widget _buildTestBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: GoogleFonts.inter(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildDependencyCheckerView(AppLocalizations l10n) {
    final depState = ref.watch(dependencyCheckerProvider);

    return Column(
      children: [
        _buildBackButton(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: GestureDetector(
            onTap: depState.isLoading ? null : () => ref.read(dependencyCheckerProvider.notifier).check(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (depState.isLoading)
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.orangeAccent))
                  else
                    const Icon(LucideIcons.refresh_cw, size: 12, color: Colors.orangeAccent),
                  const SizedBox(width: 6),
                  Text(
                    depState.isLoading ? 'Checking...' : 'Check Dependencies',
                    style: GoogleFonts.inter(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: depState.dependencies.isEmpty
              ? Center(
                  child: Text(
                    depState.isLoading ? 'Scanning pubspec.yaml...' : 'No dependencies found',
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: depState.dependencies.length,
                  itemBuilder: (context, index) {
                    final dep = depState.dependencies[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.package, size: 12, color: Colors.orangeAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(dep.name, style: GoogleFonts.inter(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w500)),
                                Text(dep.currentVersion, style: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 9)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: dep.status == DependencyStatus.upToDate
                                  ? Colors.greenAccent.withValues(alpha: 0.1)
                                  : Colors.orangeAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              dep.status == DependencyStatus.upToDate ? 'OK' : 'Outdated',
                              style: GoogleFonts.inter(
                                color: dep.status == DependencyStatus.upToDate ? Colors.greenAccent : Colors.orangeAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
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

  Widget _buildSnippetsView(AppLocalizations l10n) {
    final snippets = [
      const _SnippetData('stless', 'StatelessWidget', Colors.cyanAccent),
      const _SnippetData('stful', 'StatefulWidget', Colors.cyanAccent),
      const _SnippetData('stlessp', 'ConsumerWidget', Colors.purpleAccent),
      const _SnippetData('stfulp', 'ConsumerStatefulWidget', Colors.purpleAccent),
      const _SnippetData('column', 'Column', Colors.white54),
      const _SnippetData('row', 'Row', Colors.white54),
      const _SnippetData('sized', 'SizedBox', Colors.white54),
      const _SnippetData('padding', 'Padding', Colors.white54),
      const _SnippetData('container', 'Container', Colors.white54),
      const _SnippetData('provider', 'StateProvider', Colors.purpleAccent),
      const _SnippetData('notifier', 'StateNotifier', Colors.purpleAccent),
      const _SnippetData('async', 'Async Function', Colors.orangeAccent),
      const _SnippetData('try', 'Try-Catch', Colors.orangeAccent),
      const _SnippetData('push', 'Navigator.push', Colors.greenAccent),
      const _SnippetData('text', 'Text Widget', Colors.white54),
      const _SnippetData('btn', 'ElevatedButton', Colors.white54),
      const _SnippetData('model', 'Data Model', Colors.cyanAccent),
      const _SnippetData('test', 'Test Case', Colors.greenAccent),
      const _SnippetData('testwidget', 'Widget Test', Colors.greenAccent),
    ];

    return Column(
      children: [
        _buildBackButton(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            'Type prefix in editor to insert snippet',
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: snippets.length,
            itemBuilder: (context, index) {
              final s = snippets[index];
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Clipboard.setData(ClipboardData(text: s.prefix)),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: s.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(s.prefix, style: GoogleFonts.jetBrainsMono(color: s.color, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Text(s.name, style: GoogleFonts.inter(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ExtensionData {
  final IconData icon;
  final String name;
  final String description;
  final Color color;
  final String? badge;

  const _ExtensionData({
    required this.icon,
    required this.name,
    required this.description,
    required this.color,
    this.badge,
  });
}

class _SnippetData {
  final String prefix;
  final String name;
  final Color color;

  const _SnippetData(this.prefix, this.name, this.color);
}
