import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/quantum_ai_agent_service.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';

enum TerminalToolTab {
  aiAssistant,
  filePicker,
  commandHistory,
  processManager,
}

class QuantumTerminalToolsModal extends ConsumerStatefulWidget {
  final TerminalSession session;
  final TerminalToolTab initialTab;

  const QuantumTerminalToolsModal({
    super.key,
    required this.session,
    this.initialTab = TerminalToolTab.aiAssistant,
  });

  static Future<void> show(
    BuildContext context,
    TerminalSession session, {
    TerminalToolTab initialTab = TerminalToolTab.aiAssistant,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QuantumTerminalToolsModal(
        session: session,
        initialTab: initialTab,
      ),
    );
  }

  @override
  ConsumerState<QuantumTerminalToolsModal> createState() => _QuantumTerminalToolsModalState();
}

class _QuantumTerminalToolsModalState extends ConsumerState<QuantumTerminalToolsModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _aiPromptController = TextEditingController();
  final TextEditingController _fileSearchController = TextEditingController();
  final TextEditingController _historySearchController = TextEditingController();

  List<String> _workspaceFiles = [];
  bool _isLoadingFiles = false;
  List<String> _commandHistory = [];
  bool _isAiGenerating = false;

  String _detectedErrorContext = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );
    _extractRecentError();
    _loadWorkspaceFiles();
    _loadCommandHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _aiPromptController.dispose();
    _fileSearchController.dispose();
    _historySearchController.dispose();
    super.dispose();
  }

  void _extractRecentError() {
    final buffer = widget.session.xtermTerminal.buffer;
    final lines = <String>[];
    final count = buffer.lines.length;
    final start = (count - 80).clamp(0, count);
    for (int i = start; i < count; i++) {
      final line = buffer.lines[i].toString().trimRight();
      if (line.isNotEmpty) lines.add(line);
    }

    final fullText = lines.join('\n');
    final hasErrorMarkers = fullText.contains('Error') ||
        fullText.contains('FAILURE') ||
        fullText.contains('Exception') ||
        fullText.contains('fatal') ||
        fullText.contains('panic') ||
        fullText.contains('FAILED');

    if (hasErrorMarkers && lines.length > 5) {
      _detectedErrorContext = lines.sublist((lines.length - 40).clamp(0, lines.length)).join('\n');
    }
  }

  Future<void> _loadWorkspaceFiles() async {
    setState(() => _isLoadingFiles = true);
    final wsPath = ref.read(workspaceProvider).currentPath ?? widget.session.workingDir;
    if (wsPath.isEmpty || !Directory(wsPath).existsSync()) {
      setState(() => _isLoadingFiles = false);
      return;
    }

    final results = <String>[];
    try {
      final dir = Directory(wsPath);
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final rel = p.relative(entity.path, from: wsPath);
          // Skip hidden and build heavy dirs
          if (!rel.startsWith('.') &&
              !rel.startsWith('build/') &&
              !rel.startsWith('.dart_tool/') &&
              !rel.contains('/.')) {
            results.add(rel);
            if (results.length >= 500) break;
          }
        }
      }
    } catch (_) {}

    results.sort();
    if (mounted) {
      setState(() {
        _workspaceFiles = results;
        _isLoadingFiles = false;
      });
    }
  }

  Future<void> _loadCommandHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('quantum_terminal_history_v1') ?? [];
    if (history.isEmpty) {
      _commandHistory = [
        'flutter build apk --release --split-per-abi',
        'lazygit',
        'micro',
        'htop',
        'git status',
        'git diff',
        'flutter pub get',
        'flutter clean',
        './build.sh release android-split',
        'df -h && free -m',
      ];
    } else {
      _commandHistory = history;
    }
    if (mounted) setState(() {});
  }

  void _sendToTerminal(String text, {bool execute = false}) {
    final payload = execute ? '$text\n' : text;
    widget.session.pty.write(Uint8List.fromList(utf8.encode(payload)));
    _saveCommandToHistory(text.trim());
    Navigator.of(context).pop();
  }

  Future<void> _saveCommandToHistory(String cmd) async {
    if (cmd.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('quantum_terminal_history_v1') ?? [];
    list.remove(cmd);
    list.insert(0, cmd);
    if (list.length > 50) list.removeLast();
    await prefs.setStringList('quantum_terminal_history_v1', list);
  }

  void _explainErrorWithAi(String errorLog) {
    Navigator.of(context).pop();
    final prompt = 'Пожалуйста, проанализируй эту ошибку терминала и предложи точное решение:\n\n```text\n$errorLog\n```';
    ref.read(panelProvider.notifier).selectTab(PanelTab.aiAgent);
    ref.read(quantumAiAgentServiceProvider).sendMessage(prompt);
  }

  void _generateAiCommand(String request) async {
    if (request.trim().isEmpty) return;
    setState(() => _isAiGenerating = true);
    
    // Quick smart heuristic offline generator for common actions
    String generatedCmd = '';
    final lower = request.toLowerCase();
    if (lower.contains('split') || lower.contains('несколько версий') || lower.contains('v7') || lower.contains('v8')) {
      generatedCmd = 'flutter build apk --release --split-per-abi';
    } else if (lower.contains('gradle') && lower.contains('kill')) {
      generatedCmd = 'pkill -9 -f gradle';
    } else if (lower.contains('node') && lower.contains('kill')) {
      generatedCmd = 'killall -9 node';
    } else if (lower.contains('память') || lower.contains('ram')) {
      generatedCmd = 'free -m && ps aux --sort=-%mem | head -n 10';
    } else if (lower.contains('git') && (lower.contains('визуальн') || lower.contains('интерфейс'))) {
      generatedCmd = 'lazygit';
    } else if (lower.contains('редактор') || lower.contains('micro')) {
      generatedCmd = 'micro';
    } else if (lower.contains('найти') && lower.contains('файл')) {
      generatedCmd = 'find . -name "*.dart"';
    }

    if (generatedCmd.isNotEmpty) {
      setState(() => _isAiGenerating = false);
      _sendToTerminal(generatedCmd, execute: false);
      return;
    }

    // Otherwise delegate to Quantum AI Agent
    Navigator.of(context).pop();
    final prompt = 'Сгенерируй только Bash команду для Linux/PRoot терминала: $request';
    ref.read(panelProvider.notifier).selectTab(PanelTab.aiAgent);
    ref.read(quantumAiAgentServiceProvider).sendMessage(prompt);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header & Tab Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(LucideIcons.terminal, color: Colors.cyanAccent, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Quantum Terminal Hub',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(LucideIcons.x, color: Colors.white54, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.cyanAccent,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.cyanAccent,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
            tabs: const [
              Tab(icon: Icon(LucideIcons.bot, size: 14), text: 'AI Помощник'),
              Tab(icon: Icon(LucideIcons.folder, size: 14), text: 'Вставить путь'),
              Tab(icon: Icon(LucideIcons.history, size: 14), text: 'История'),
              Tab(icon: Icon(LucideIcons.cpu, size: 14), text: 'Процессы'),
            ],
          ),
          const Divider(height: 1, color: Colors.white10),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAiTab(),
                _buildFilePickerTab(),
                _buildCommandHistoryTab(),
                _buildProcessManagerTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 1. AI Tab ─────────────────────────────────────────────────────────────
  Widget _buildAiTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_detectedErrorContext.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.triangle_alert, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'В терминале обнаружена ошибка!',
                        style: GoogleFonts.inter(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(LucideIcons.bot, size: 14),
                        label: const Text('Разобрать с ИИ', style: TextStyle(fontSize: 11)),
                        onPressed: () => _explainErrorWithAi(_detectedErrorContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 90),
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        _detectedErrorContext,
                        style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          Text(
            'Генератор команд на естественном языке:',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _aiPromptController,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Например: собери apk для всех архитектур или очисти кэш...',
              hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 11.5),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              suffixIcon: IconButton(
                icon: _isAiGenerating
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.sparkles, color: Colors.cyanAccent, size: 16),
                onPressed: () => _generateAiCommand(_aiPromptController.text),
              ),
            ),
            onSubmitted: _generateAiCommand,
          ),
          const SizedBox(height: 12),

          Text(
            'Быстрые умные сценарии:',
            style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildQuickActionChip(
                'Сборка Split APKs (v7/v8/x64)',
                LucideIcons.boxes,
                () => _sendToTerminal('flutter build apk --release --split-per-abi', execute: true),
              ),
              _buildQuickActionChip(
                'Визуальный Git (Lazygit)',
                LucideIcons.git_branch,
                () => _sendToTerminal('lazygit', execute: true),
              ),
              _buildQuickActionChip(
                'Сенсорный редактор (Micro)',
                LucideIcons.file_text,
                () => _sendToTerminal('micro', execute: true),
              ),
              _buildQuickActionChip(
                'Диагностика системы (Doctor)',
                LucideIcons.stethoscope,
                () => _sendToTerminal('/tmp/quantum_doctor.sh', execute: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionChip(String label, IconData icon, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 13, color: Colors.cyanAccent),
      label: Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 11)),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onPressed: onTap,
    );
  }

  // ── 2. File Picker Tab ────────────────────────────────────────────────────
  Widget _buildFilePickerTab() {
    final query = _fileSearchController.text.toLowerCase();
    final filtered = query.isEmpty
        ? _workspaceFiles
        : _workspaceFiles.where((f) => f.toLowerCase().contains(query)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _fileSearchController,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Поиск файлов в проекте...',
              hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
              prefixIcon: const Icon(LucideIcons.search, size: 16, color: Colors.white54),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (_isLoadingFiles)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (filtered.isEmpty)
          Expanded(
            child: Center(
              child: Text('Файлы не найдены', style: GoogleFonts.inter(color: Colors.white38)),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final file = filtered[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(LucideIcons.file, size: 15, color: Colors.cyanAccent),
                  title: Text(
                    file,
                    style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.copy, size: 14, color: Colors.white54),
                        tooltip: 'Вставить в терминал',
                        onPressed: () => _sendToTerminal(file, execute: false),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.pencil, size: 14, color: Colors.amberAccent),
                        tooltip: 'Редактировать в Micro',
                        onPressed: () => _sendToTerminal('micro "$file"', execute: true),
                      ),
                    ],
                  ),
                  onTap: () => _sendToTerminal(file, execute: false),
                );
              },
            ),
          ),
      ],
    );
  }

  // ── 3. Command History Tab ────────────────────────────────────────────────
  Widget _buildCommandHistoryTab() {
    final query = _historySearchController.text.toLowerCase();
    final filtered = query.isEmpty
        ? _commandHistory
        : _commandHistory.where((c) => c.toLowerCase().contains(query)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _historySearchController,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Поиск по истории команд...',
              hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
              prefixIcon: const Icon(LucideIcons.history, size: 16, color: Colors.white54),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final cmd = filtered[index];
              return ListTile(
                dense: true,
                leading: const Icon(LucideIcons.terminal, size: 14, color: Colors.white60),
                title: Text(
                  cmd,
                  style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent, fontSize: 11),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.corner_down_left, size: 14, color: Colors.white54),
                      tooltip: 'Вставить',
                      onPressed: () => _sendToTerminal(cmd, execute: false),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.play, size: 14, color: Colors.greenAccent),
                      tooltip: 'Выполнить',
                      onPressed: () => _sendToTerminal(cmd, execute: true),
                    ),
                  ],
                ),
                onTap: () => _sendToTerminal(cmd, execute: true),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── 4. Process Manager Tab ────────────────────────────────────────────────
  Widget _buildProcessManagerTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Экстренное завершение фоновых задач:',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 10),
          _buildProcessActionButton(
            title: 'Завершить демоны Gradle',
            subtitle: 'Освобождает 1.5–3 GB памяти от зависших Gradle Daemons',
            icon: LucideIcons.trash_2,
            color: Colors.redAccent,
            onTap: () => _sendToTerminal('pkill -9 -f gradle 2>/dev/null; echo "✓ Gradle daemons killed"', execute: true),
          ),
          const SizedBox(height: 8),
          _buildProcessActionButton(
            title: 'Завершить процессы Node.js',
            subtitle: 'Убивает зависшие локальные серверы и фоновые скрипты',
            icon: LucideIcons.power,
            color: Colors.orangeAccent,
            onTap: () => _sendToTerminal('killall -9 node 2>/dev/null; echo "✓ Node processes killed"', execute: true),
          ),
          const SizedBox(height: 8),
          _buildProcessActionButton(
            title: 'Очистить кэш RAM и диска',
            subtitle: 'Вызывает sync, drop_caches и apt-get clean',
            icon: LucideIcons.sparkles,
            color: Colors.greenAccent,
            onTap: () => _sendToTerminal('sync; apt-get clean 2>/dev/null; free -m', execute: true),
          ),
          const SizedBox(height: 16),
          Text(
            'Интерактивные TUI инструменты:',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTileButton(
                  title: 'Lazygit',
                  subtitle: 'Git TUI',
                  icon: LucideIcons.git_branch,
                  color: Colors.purpleAccent,
                  onTap: () => _sendToTerminal('lazygit', execute: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTileButton(
                  title: 'Micro',
                  subtitle: 'Тач-редактор',
                  icon: LucideIcons.pencil,
                  color: Colors.blueAccent,
                  onTap: () => _sendToTerminal('micro', execute: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTileButton(
                  title: 'Htop',
                  subtitle: 'Монитор CPU',
                  icon: LucideIcons.activity,
                  color: Colors.cyanAccent,
                  onTap: () => _sendToTerminal('htop', execute: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProcessActionButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  Text(subtitle, style: GoogleFonts.inter(color: Colors.white54, fontSize: 10)),
                ],
              ),
            ),
            Icon(LucideIcons.chevron_right, color: color, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTileButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(title, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
            Text(subtitle, style: GoogleFonts.inter(color: Colors.white54, fontSize: 9)),
          ],
        ),
      ),
    );
  }
}
