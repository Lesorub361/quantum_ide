import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:quantum_ide/core/services/wasm_plugin_service.dart';

class WasmPluginsPanel extends ConsumerStatefulWidget {
  const WasmPluginsPanel({super.key});

  @override
  ConsumerState<WasmPluginsPanel> createState() => _WasmPluginsPanelState();
}

class _WasmPluginsPanelState extends ConsumerState<WasmPluginsPanel> {
  final Map<String, bool> _expandedLogs = {};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(wasmPluginServiceProvider);
    final service = ref.read(wasmPluginServiceProvider.notifier);
    final theme = Theme.of(context);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    return Container(
      color: const Color(0xFF0D0F14).withValues(alpha: 0.7),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.purpleAccent, Colors.pinkAccent],
                  ).createShader(bounds),
                  child: const Icon(LucideIcons.puzzle, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isRu ? 'WASM Плагины' : 'WASM Plugins',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.refresh_cw, size: 14, color: Colors.white60),
                  tooltip: isRu ? 'Сбросить плагины' : 'Reset Plugins',
                  onPressed: () => _confirmReset(context, service),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10, indent: 14, endIndent: 14),

          // Action install
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton.icon(
              onPressed: () => _showInstallDialog(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                foregroundColor: theme.colorScheme.primary,
                side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: const Size(double.infinity, 38),
                elevation: 0,
              ),
              icon: const Icon(LucideIcons.plus, size: 14),
              label: Text(
                isRu ? 'Установить .wasm' : 'Install .wasm',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // Plugins list
          Expanded(
            child: state.plugins.isEmpty
                ? _buildEmptyState(isRu)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: state.plugins.length,
                    itemBuilder: (context, index) {
                      final plugin = state.plugins[index];
                      return _buildPluginCard(plugin, service, theme, isRu);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isRu) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.toy_brick, size: 40, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 12),
          Text(
            isRu ? 'Нет установленных плагинов' : 'No plugins installed',
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildPluginCard(WasmPlugin plugin, WasmPluginService service, ThemeData theme, bool isRu) {
    final isLogsExpanded = _expandedLogs[plugin.id] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main card title/toggle
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    plugin.name,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Switch(
                  value: plugin.isEnabled,
                  activeColor: theme.colorScheme.primary,
                  onChanged: (val) => service.togglePlugin(plugin.id, val),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                plugin.description,
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
              ),
            ),
          ),

          // Actions List
          if (plugin.actions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                isRu ? 'Доступные действия:' : 'Available Actions:',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: plugin.actions.map((act) {
                  return Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    label: Text(
                      '${act.id}: ${act.name}',
                      style: GoogleFonts.inter(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // Footer Controls (Logs & Delete)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _expandedLogs[plugin.id] = !isLogsExpanded;
                    });
                  },
                  icon: Icon(
                    isLogsExpanded ? LucideIcons.chevron_up : LucideIcons.chevron_down,
                    size: 13,
                    color: Colors.white70,
                  ),
                  label: Text(
                    isRu ? 'Терминал логов' : 'Logs Terminal',
                    style: GoogleFonts.inter(color: Colors.white70, fontSize: 10.5),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                Row(
                  children: [
                    if (isLogsExpanded)
                      IconButton(
                        icon: const Icon(LucideIcons.trash_2, size: 13, color: Colors.white54),
                        tooltip: isRu ? 'Очистить логи' : 'Clear Logs',
                        onPressed: () => service.clearLogs(plugin.id),
                      ),
                    if (plugin.id != 'text_transformer_demo')
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 13, color: Colors.redAccent),
                        tooltip: isRu ? 'Удалить плагин' : 'Delete Plugin',
                        onPressed: () => service.deletePlugin(plugin.id),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Expandable Logs Panel
          if (isLogsExpanded) ...[
            Container(
              width: double.infinity,
              height: 110,
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF080A0E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: plugin.logs.isEmpty
                  ? Center(
                      child: Text(
                        isRu ? 'Лонгборд логов пуст' : 'No logs captured yet',
                        style: GoogleFonts.jetBrainsMono(color: Colors.white24, fontSize: 9.5),
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: plugin.logs.length,
                      itemBuilder: (context, idx) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            plugin.logs[idx],
                            style: GoogleFonts.jetBrainsMono(
                              color: plugin.logs[idx].contains('Error') || plugin.logs[idx].contains('failed')
                                  ? Colors.redAccent
                                  : Colors.greenAccent,
                              fontSize: 9.5,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmReset(BuildContext context, WasmPluginService service) {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF13151D),
        title: Text(isRu ? 'Сбросить плагины?' : 'Reset Plugins?', style: const TextStyle(color: Colors.white)),
        content: Text(
          isRu
              ? 'Это удалит все пользовательские плагины и восстановит настройки по умолчанию. Продолжить?'
              : 'This will remove all installed custom plugins and restore default plugins. Continue?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isRu ? 'Отмена' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () {
              service.resetToDefaults();
              Navigator.pop(context);
            },
            child: Text(isRu ? 'Сбросить' : 'Reset'),
          ),
        ],
      ),
    );
  }

  void _showInstallDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const WasmInstallDialog(),
    );
  }
}

class WasmInstallDialog extends ConsumerStatefulWidget {
  const WasmInstallDialog({super.key});

  @override
  ConsumerState<WasmInstallDialog> createState() => _WasmInstallDialogState();
}

class _WasmInstallDialogState extends ConsumerState<WasmInstallDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String? _filePath;
  String? _fileName;

  final List<WasmPluginAction> _actions = [
    WasmPluginAction(id: 1, name: 'Transform Action', description: 'Runs custom string logic'),
  ];

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wasm'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _filePath = result.files.single.path;
        _fileName = result.files.single.name;
        if (_nameController.text.isEmpty) {
          _nameController.text = _fileName!.replaceAll('.wasm', '');
        }
      });
    }
  }

  void _addAction() {
    setState(() {
      final nextId = _actions.isEmpty ? 1 : _actions.map((a) => a.id).reduce((a, b) => a > b ? a : b) + 1;
      _actions.add(WasmPluginAction(id: nextId, name: 'New Action', description: 'Description'));
    });
  }

  void _removeAction(int index) {
    setState(() {
      _actions.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    return Dialog(
      backgroundColor: const Color(0xFF13151D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isRu ? 'Установка WASM Плагина' : 'Install WASM Plugin',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // File Picker Section
                      InkWell(
                        onTap: _pickFile,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          height: 70,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.02),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _filePath != null
                                  ? Colors.cyanAccent.withValues(alpha: 0.3)
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _filePath != null ? LucideIcons.file_check : LucideIcons.file_up,
                                color: _filePath != null ? Colors.cyanAccent : Colors.white60,
                                size: 20,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _fileName ?? (isRu ? 'Выбрать .wasm файл' : 'Select .wasm file'),
                                style: GoogleFonts.inter(
                                  color: _filePath != null ? Colors.white : Colors.white60,
                                  fontSize: 11.5,
                                  fontWeight: _filePath != null ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Name Field
                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: isRu ? 'Название плагина' : 'Plugin Name',
                          labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                        validator: (val) => val == null || val.isEmpty
                            ? (isRu ? 'Введите название' : 'Name is required')
                            : null,
                      ),
                      const SizedBox(height: 12),

                      // Description Field
                      TextFormField(
                        controller: _descController,
                        maxLines: 2,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: isRu ? 'Описание' : 'Description',
                          labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                        validator: (val) => val == null || val.isEmpty
                            ? (isRu ? 'Введите описание' : 'Description is required')
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // Actions List Builder
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isRu ? 'Действия плагина' : 'Exposed Actions',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.white70),
                          ),
                          TextButton.icon(
                            onPressed: _addAction,
                            icon: const Icon(LucideIcons.plus, size: 12, color: Colors.cyanAccent),
                            label: Text(
                              isRu ? 'Добавить' : 'Add',
                              style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _actions.length,
                        itemBuilder: (context, index) {
                          final act = _actions[index];
                          final idController = TextEditingController(text: act.id.toString());
                          final nameController = TextEditingController(text: act.name);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.02),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: Row(
                              children: [
                                // ID input
                                SizedBox(
                                  width: 38,
                                  child: TextFormField(
                                    controller: idController,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding: const EdgeInsets.all(6),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                    onChanged: (val) {
                                      final id = int.tryParse(val) ?? act.id;
                                      _actions[index] = WasmPluginAction(id: id, name: act.name, description: act.description);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Name input
                                Expanded(
                                  child: TextFormField(
                                    controller: nameController,
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding: const EdgeInsets.all(6),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                    onChanged: (val) {
                                      _actions[index] = WasmPluginAction(id: act.id, name: val, description: act.description);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(LucideIcons.trash_2, size: 13, color: Colors.white38),
                                  onPressed: () => _removeAction(index),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(isRu ? 'Отмена' : 'Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      if (_filePath == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(isRu ? 'Выберите .wasm файл' : 'Please pick a .wasm file first'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }

                      if (_formKey.currentState!.validate()) {
                        try {
                          await ref.read(wasmPluginServiceProvider.notifier).installPlugin(
                                _nameController.text,
                                _descController.text,
                                _filePath!,
                                _actions,
                              );
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(isRu ? 'Плагин успешно установлен' : 'Plugin installed successfully'),
                                backgroundColor: theme.colorScheme.primary,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(isRu ? 'Ошибка установки: $e' : 'Failed to install: $e'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                      }
                    },
                    child: Text(isRu ? 'Установить' : 'Install'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
