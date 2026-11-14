import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher_string.dart';
import 'package:quantum_ide/core/services/quantum_ai_agent_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/ai_diff_dialog.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/mcp_management_dialog.dart';

class QuantumAiAgentPanel extends ConsumerStatefulWidget {
  final VoidCallback? onClose;
  final VoidCallback? onToggleExpand;
  final bool isExpanded;

  const QuantumAiAgentPanel({
    super.key,
    this.onClose,
    this.onToggleExpand,
    this.isExpanded = false,
  });

  @override
  ConsumerState<QuantumAiAgentPanel> createState() =>
      _QuantumAiAgentPanelState();
}

class _QuantumAiAgentPanelState extends ConsumerState<QuantumAiAgentPanel> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  final List<ChatAttachment> _pendingAttachments = [];

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final agent = ref.watch(quantumAiAgentServiceProvider);
    final settings = ref.watch(settingsProvider);
    final workspace = ref.watch(workspaceProvider);
    final projectName =
        workspace.currentPath
            ?.split('/')
            .where((s) => s.isNotEmpty)
            .lastOrNull ??
        'Проект';

    return Container(
      color: const Color(0xFF0D0F14),
      child: Column(
        children: [
          // ── Header Bar ──────────────────────────────────────────────────────
          _buildTopBar(context, agent, settings, projectName),
          _buildModeBar(context, agent),

          // ── Messages List ───────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              itemCount: agent.messages.length,
              itemBuilder: (context, index) {
                final msg = agent.messages[index];
                return _buildMessageItem(context, agent, msg);
              },
            ),
          ),

          // ── Quick Prompt Suggestions ────────────────────────────────────────
          _buildQuickSuggestions(agent),

          // ── Pending Attachments Preview Strip ───────────────────────────────
          if (_pendingAttachments.isNotEmpty) _buildAttachmentPreviewStrip(),

          // ── Bottom Input Bar ────────────────────────────────────────────────
          _buildInputBar(context, agent),
        ],
      ),
    );
  }

  String _fmtTokens(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  Widget _buildModeBar(BuildContext context, QuantumAiAgentService agent) {
    final undo = agent.undoableCount;
    final hasPlan =
        agent.mode == AgentMode.plan &&
        !agent.isGenerating &&
        agent.messages.any(
          (m) =>
              m.role == MessageRole.assistant && m.text.contains('План готов'),
        );
    final fill = agent.contextFill;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1018),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E2433)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Segmented Agent Modes (Ask, Plan, Build)
              for (final m in AgentMode.values) ...[
                Tooltip(
                  message: m.hint,
                  child: ChoiceChip(
                    label: Text(
                      m.label,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: agent.mode == m
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: agent.mode == m
                            ? const Color(0xFFA78BFA)
                            : Colors.white60,
                      ),
                    ),
                    selected: agent.mode == m,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    backgroundColor: const Color(0xFF131722),
                    selectedColor: const Color(0xFF8B5CF6).withValues(alpha: 0.22),
                    side: BorderSide(
                      color: agent.mode == m
                          ? const Color(0xFF8B5CF6).withValues(alpha: 0.45)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                    onSelected: agent.isGenerating
                        ? null
                        : (_) => agent.setMode(m),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              const Spacer(),

              // Session title pill (tappable to view/switch sessions)
              InkWell(
                onTap: () => _showChatHistoryModal(context, agent),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  height: 25,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131722),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.message_square,
                        size: 11,
                        color: Color(0xFFA78BFA),
                      ),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 80),
                        child: Text(
                          agent.currentSessionTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Engine & Tokens Tooltip Badge
              Tooltip(
                message:
                    'Движок: ${agent.engine.label}\nТокены сессии: вход ${agent.promptTokens}, выход ${agent.completionTokens}'
                    '${agent.usageEstimated ? ' (оценка)' : ''}\nКонтекст заполнен на ${(agent.contextFill * 100).toStringAsFixed(0)}%',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.bot,
                        size: 11,
                        color: Color(0xFF818CF8),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${agent.usageEstimated ? '~' : ''}${_fmtTokens(agent.sessionTokens)}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (undo > 0) ...[
                const SizedBox(width: 6),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: Colors.orangeAccent,
                  ),
                  icon: const Icon(LucideIcons.undo_2, size: 12),
                  label: Text(
                    'Откатить ($undo)',
                    style: const TextStyle(fontSize: 10.5),
                  ),
                  onPressed: () async {
                    final n = await agent.undoAllAgentChanges();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Откачено правок агента: $n')),
                      );
                    }
                  },
                ),
              ],
            ],
          ),
          if (fill > 0.6)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: LinearProgressIndicator(
                value: fill,
                minHeight: 2,
                color: fill > 0.85 ? Colors.redAccent : Colors.orangeAccent,
                backgroundColor: Colors.white10,
              ),
            ),
          if (hasPlan)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: const Color(0xFF8B5CF6),
                  ),
                  icon: const Icon(LucideIcons.play, size: 13),
                  label: const Text(
                    'Выполнить план',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  onPressed: agent.runPlan,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    QuantumAiAgentService agent,
    SettingsState settings,
    String projectName,
  ) {
    final currentModel = agent.selectedModel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          // 1. AI Sparkles Gradient Badge
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(7),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: const Icon(
              LucideIcons.sparkles,
              size: 13,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),

          // 2. Interactive Model Selector Pill (Takes all available width)
          Expanded(
            child: InkWell(
              onTap: () => _showModelSelectorDialog(context, agent),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0D14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        currentModel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4.5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: Color(
                          currentModel.badgeColorValue,
                        ).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        currentModel.badge,
                        style: TextStyle(
                          color: Color(currentModel.badgeColorValue),
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      LucideIcons.chevron_down,
                      size: 12,
                      color: Colors.white54,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // 3. Compact Action Buttons Group (Never overflows)
          // New Chat Button
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
              ),
            ),
            child: IconButton(
              icon: const Icon(
                LucideIcons.plus,
                size: 14,
                color: Color(0xFFA78BFA),
              ),
              tooltip: 'Новый диалог',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              onPressed: () => agent.startNewChat(),
            ),
          ),
          const SizedBox(width: 4),

          // History Button
          IconButton(
            icon: const Icon(
              LucideIcons.history,
              size: 14,
              color: Color(0xFF94A3B8),
            ),
            tooltip: 'История (${agent.sessions.length})',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            onPressed: () => _showChatHistoryModal(context, agent),
          ),

          // More Options Menu (Collapses secondary actions: Keys, MCP, Rules, Delete)
          PopupMenuButton<String>(
            tooltip: 'Дополнительные опции',
            color: const Color(0xFF181C26),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Colors.white12),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            icon: const Icon(
              LucideIcons.ellipsis_vertical,
              size: 14,
              color: Color(0xFF94A3B8),
            ),
            onSelected: (val) {
              if (val == 'keys') _showApiKeysDialog(context, settings);
              if (val == 'mcp') McpManagementDialog.show(context);
              if (val == 'rules') _showProjectRulesDialog(context, agent);
              if (val == 'engine') _showEngineSelectorDialog(context, agent);
              if (val == 'delete') {
                _confirmDeleteChat(context, agent, agent.currentSessionId);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'keys',
                height: 38,
                child: Row(
                  children: [
                    Icon(LucideIcons.key, size: 14, color: Color(0xFF38BDF8)),
                    SizedBox(width: 8),
                    Text(
                      'API Ключи и провайдеры',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'mcp',
                height: 38,
                child: Row(
                  children: [
                    Icon(LucideIcons.plug, size: 14, color: Color(0xFFA78BFA)),
                    SizedBox(width: 8),
                    Text(
                      'MCP Серверы и Инструменты',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'rules',
                height: 38,
                child: Row(
                  children: [
                    Icon(LucideIcons.scroll, size: 14, color: Color(0xFF10B981)),
                    SizedBox(width: 8),
                    Text(
                      'Правила проекта (AGENTS.md)',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'engine',
                height: 38,
                child: Row(
                  children: [
                    const Icon(LucideIcons.bot, size: 14, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 8),
                    Text(
                      'Движок: ${agent.engine.label}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(height: 1),
              const PopupMenuItem(
                value: 'delete',
                height: 38,
                child: Row(
                  children: [
                    Icon(LucideIcons.trash_2, size: 14, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text(
                      'Удалить текущий чат',
                      style: TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (widget.onToggleExpand != null)
            IconButton(
              icon: Icon(
                widget.isExpanded
                    ? LucideIcons.minimize_2
                    : LucideIcons.maximize_2,
                size: 14,
                color: const Color(0xFF94A3B8),
              ),
              tooltip: widget.isExpanded
                  ? 'Стандартный вид'
                  : 'На весь экран',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              onPressed: widget.onToggleExpand,
            ),

          if (widget.onClose != null)
            IconButton(
              icon: const Icon(
                LucideIcons.x,
                size: 15,
                color: Color(0xFF94A3B8),
              ),
              tooltip: 'Закрыть',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  void _showEngineSelectorDialog(
    BuildContext context,
    QuantumAiAgentService agent,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xFF131722),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(LucideIcons.bot, color: Color(0xFFA78BFA), size: 18),
            const SizedBox(width: 8),
            Text(
              'Выберите исполнителя задач',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        children: [
          for (final e in AgentEngine.values)
            ListTile(
              dense: true,
              leading: Icon(
                e == agent.engine
                    ? LucideIcons.circle_check
                    : LucideIcons.circle,
                color: e == agent.engine
                    ? const Color(0xFF8B5CF6)
                    : Colors.white38,
                size: 16,
              ),
              title: Text(
                e.label + (e == AgentEngine.builtin ? ' (Встроенный ИИ)' : ' (Внешний CLI)'),
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: e == agent.engine ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              onTap: () {
                agent.setEngine(e);
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    );
  }

  void _showProjectRulesDialog(
    BuildContext context,
    QuantumAiAgentService agent,
  ) {
    final ws = ref.read(workspaceProvider).currentPath;
    String content = '';
    String filePath = '.quantum/AGENTS.md';
    if (ws != null) {
      for (final rel in const ['.quantum/AGENTS.md', 'AGENTS.md']) {
        final f = File(p.join(ws, rel));
        if (f.existsSync()) {
          content = f.readAsStringSync();
          filePath = rel;
          break;
        }
      }
    }

    final ctrl = TextEditingController(text: content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131722),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(LucideIcons.scroll, color: Color(0xFF10B981), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Правила проекта ($filePath)',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Правила и соглашения из этого файла автоматически внедряются в каждый запрос к ИИ-агенту.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                maxLines: 12,
                minLines: 5,
                style: GoogleFonts.jetBrainsMono(
                  color: Colors.white,
                  fontSize: 11.5,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF0A0D14),
                  hintText:
                      '# Правила разработки проекта\n- Стек: Flutter / Node / Python\n- Стиль кода: Clean Architecture\n- Не удалять существующие тесты...',
                  hintStyle: const TextStyle(
                    color: Colors.white30,
                    fontSize: 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (ws != null) {
                final target = File(p.join(ws, filePath));
                target.parent.createSync(recursive: true);
                target.writeAsStringSync(ctrl.text.trim());
              }
              Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Правила проекта сохранены')),
                );
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  void _showModelSelectorDialog(
    BuildContext context,
    QuantumAiAgentService agent,
  ) {
    String searchQuery = '';
    String selectedCategory = 'Все';
    final customModelCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final categories = [
            'Все',
            'Прямой API',
            'Кодинг',
            'Рассуждения',
            'Бесплатные',
            'Флагманы',
            'Популярные',
            'Локальный',
          ];

          final allModels = agent.availableModels.isNotEmpty
              ? agent.availableModels
              : QuantumModelItem.predefinedModels;
          final filteredModels = allModels.where((m) {
            final matchesCategory =
                selectedCategory == 'Все' || m.category == selectedCategory;
            final matchesQuery =
                searchQuery.isEmpty ||
                m.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
                m.id.toLowerCase().contains(searchQuery.toLowerCase()) ||
                m.providerName.toLowerCase().contains(
                  searchQuery.toLowerCase(),
                ) ||
                m.badge.toLowerCase().contains(searchQuery.toLowerCase());
            return matchesCategory && matchesQuery;
          }).toList();

          return AlertDialog(
            backgroundColor: const Color(0xFF131722),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    LucideIcons.cpu,
                    color: Color(0xFFA78BFA),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Каталог ИИ-Моделей и Провайдеров',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        agent.isLoadingModels
                            ? 'Обновление списка с OpenRouter...'
                            : 'OpenRouter, Gemini, Groq, DeepSeek, OpenAI, Claude, Grok, Ollama',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: agent.isLoadingModels
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFA78BFA),
                          ),
                        )
                      : const Icon(
                          LucideIcons.refresh_cw,
                          size: 16,
                          color: Color(0xFFA78BFA),
                        ),
                  tooltip: 'Обновить модели с OpenRouter',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  onPressed: agent.isLoadingModels
                      ? null
                      : () async {
                          await agent.fetchLiveOpenRouterModels(force: true);
                          setDialogState(() {});
                        },
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(
                    LucideIcons.x,
                    size: 16,
                    color: Colors.white54,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 480,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  // Search field
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0D14),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        const Icon(
                          LucideIcons.search,
                          size: 14,
                          color: Colors.white38,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            onChanged: (val) {
                              setDialogState(() {
                                searchQuery = val.trim();
                              });
                            },
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                            decoration: const InputDecoration(
                              hintText:
                                  'Поиск (Gemini, Groq, DeepSeek, Claude, Free)...',
                              hintStyle: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Category horizontal chips
                  SizedBox(
                    height: 28,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemCount: categories.length,
                      itemBuilder: (context, idx) {
                        final cat = categories[idx];
                        final isSelected = selectedCategory == cat;
                        return InkWell(
                          onTap: () {
                            setDialogState(() {
                              selectedCategory = cat;
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(
                                      0xFF8B5CF6,
                                    ).withValues(alpha: 0.25)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF8B5CF6)
                                    : Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFFA78BFA)
                                    : Colors.white70,
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Models List
                  Expanded(
                    child: filteredModels.isEmpty
                        ? Center(
                            child: Text(
                              'Модели не найдены',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 12,
                              ),
                            ),
                          )
                        : ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            itemCount: filteredModels.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.05),
                            ),
                            itemBuilder: (context, idx) {
                              final item = filteredModels[idx];
                              final isCurrent =
                                  agent.selectedModel.id == item.id;
                              final badgeColor = Color(item.badgeColorValue);

                              return InkWell(
                                onTap: () {
                                  agent.selectModel(item);
                                  Navigator.pop(ctx);
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? const Color(
                                            0xFF8B5CF6,
                                          ).withValues(alpha: 0.15)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    item.name,
                                                    style: GoogleFonts.inter(
                                                      color: Colors.white,
                                                      fontSize: 12.5,
                                                      fontWeight: isCurrent
                                                          ? FontWeight.bold
                                                          : FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 1.5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: badgeColor
                                                        .withValues(alpha: 0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                    border: Border.all(
                                                      color: badgeColor
                                                          .withValues(
                                                            alpha: 0.4,
                                                          ),
                                                      width: 0.5,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    item.badge,
                                                    style: TextStyle(
                                                      color: badgeColor,
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${item.providerName} • ${item.id}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.jetBrainsMono(
                                                color: Colors.white38,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isCurrent)
                                        const Icon(
                                          LucideIcons.check,
                                          color: Colors.greenAccent,
                                          size: 16,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  const SizedBox(height: 8),

                  // Custom OpenRouter Model ID input
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0D14),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: customModelCtrl,
                            style: GoogleFonts.jetBrainsMono(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Кастомный slug (напр. moonshotai/...)',
                              hintStyle: TextStyle(
                                color: Colors.white38,
                                fontSize: 10.5,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B5CF6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                          ),
                          onPressed: () {
                            final slug = customModelCtrl.text.trim();
                            if (slug.isNotEmpty) {
                              agent.setCustomModel(slug);
                              Navigator.pop(ctx);
                            }
                          },
                          child: const Text(
                            'Применить',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickSuggestions(QuantumAiAgentService agent) {
    if (agent.messages.length > 2) return const SizedBox.shrink();

    final suggestions = [
      (
        label: '💡 Что улучшить в проекте',
        prompt:
            'Изучи структуру проекта и ключевые файлы. Проведи аудит архитектуры, производительности и кода, и предложи конкретные улучшения с готовыми изменениями.',
      ),
      (
        label: '🔍 Найти ошибки в коде',
        prompt:
            'Запусти get_diagnostics, найди проблемные места в проекте и предложи готовые исправления.',
      ),
      (
        label: '⚡ Оптимизировать скорость',
        prompt:
            'Проанализируй проект на предмет узких мест и предложи оптимизацию производительности и алгоритмов.',
      ),
      (
        label: '📝 Написать тесты',
        prompt:
            'Изучи текущий код и напиши комплексные unit-тесты для ключевой логики проекта.',
      ),
      (
        label: '🚀 Объяснить архитектуру',
        prompt:
            'Изучи структуру файлов и объясни архитектуру, основные компоненты и потоки данных.',
      ),
    ];

    return Container(
      height: 34,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemCount: suggestions.length,
        itemBuilder: (context, i) {
          final item = suggestions[i];
          return ActionChip(
            backgroundColor: const Color(0xFF131722),
            side: BorderSide(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.28),
            ),
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            label: Text(
              item.label,
              style: GoogleFonts.inter(
                color: const Color(0xFFE2E8F0),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            onPressed: () {
              _textController.text = item.prompt;
              _sendMessage(agent);
            },
          );
        },
      ),
    );
  }

  Widget _buildMessageItem(
    BuildContext context,
    QuantumAiAgentService agent,
    ChatMessage msg,
  ) {
    final isUser = msg.role == MessageRole.user;

    // Результат инструмента: компактная плашка вместо большого пузыря.
    if (msg.toolLabel != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 34),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            dense: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            childrenPadding: const EdgeInsets.all(8),
            collapsedBackgroundColor: Colors.white.withValues(alpha: 0.04),
            backgroundColor: Colors.white.withValues(alpha: 0.04),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            leading: const Icon(
              LucideIcons.wrench,
              size: 13,
              color: Color(0xFF8B5CF6),
            ),
            title: Text(
              msg.toolLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: Colors.white70,
              ),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  msg.text.length > 2500
                      ? '${msg.text.substring(0, 2500)}…'
                      : msg.text,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: Colors.white60,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Пустой пузырь (ответ состоял только из вызова инструмента) не показываем.
    if (!isUser &&
        !msg.isStreaming &&
        _cleanText(msg.text).isEmpty &&
        (msg.thinking == null || msg.thinking!.isEmpty) &&
        msg.actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 26,
              height: 26,
              margin: const EdgeInsets.only(right: 8, top: 2),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF3B82F6)],
                ),
              ),
              child: const Icon(
                LucideIcons.sparkles,
                size: 12,
                color: Colors.white,
              ),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFF1E2538)
                    : const Color(0xFF131722),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isUser ? 14 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 14),
                ),
                border: Border.all(
                  color: isUser
                      ? const Color(0xFF334155)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isUser) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Quantum AI',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFA78BFA),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                agent.selectedModel.badge,
                                style: TextStyle(
                                  color: Color(
                                    agent.selectedModel.badgeColorValue,
                                  ),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (msg.text.isNotEmpty)
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: msg.text));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Ответ скопирован'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(
                                LucideIcons.copy,
                                size: 12,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  // 📎 Attached Images & Files inside Message Bubble
                  if (msg.attachments.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: msg.attachments.map((att) {
                        if (att.isImage && att.base64Data != null) {
                          return GestureDetector(
                            onTap: () => _showImagePreviewDialog(context, att),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                base64Decode(att.base64Data!),
                                width: 120,
                                height: 90,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 120,
                                  height: 60,
                                  color: Colors.black26,
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    LucideIcons.image,
                                    color: Colors.white38,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                LucideIcons.file_code,
                                size: 12,
                                color: Color(0xFFA78BFA),
                              ),
                              const SizedBox(width: 5),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 160,
                                ),
                                child: Text(
                                  att.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10.5,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // 🧠 Collapsible Thinking Block (DeepSeek R1 / o3-mini)
                  if (msg.thinking != null && msg.thinking!.isNotEmpty)
                    _buildThinkingBlock(msg),

                  // Main Text Content
                  if (msg.text.isNotEmpty)
                    GptMarkdown(
                      _cleanText(msg.text),
                      style: GoogleFonts.inter(
                        color: const Color(0xFFF1F5F9),
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                      styleSheet: GptMarkdownStyleSheet(
                        codeBlock: CodeBlockStyle(
                          backgroundColor: const Color(0xFF131722),
                          borderColor: const Color(0xFF283145),
                          borderWidth: 1.0,
                          textColor: const Color(0xFFE2E8F0),
                          showCopyButton: true,
                          fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
                          fontSize: 11.5,
                        ),
                        inlineCode: InlineCodeStyle(
                          color: const Color(0xFF38BDF8),
                          backgroundColor: const Color(0xFF1E293B),
                          borderColor: const Color(0xFF334155),
                          borderWidth: 1.0,
                          fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
                          fontSizeFactor: 0.9,
                        ),
                        table: const TableStyle(
                          headerBackground: Color(0xFF1E293B),
                          borderColor: Color(0xFF334155),
                          rowStripeColor: Color(0xFF161B26),
                        ),
                        blockQuote: const BlockQuoteStyle(
                          backgroundColor: Color(0xFF171B26),
                          barColor: Color(0xFF8B5CF6),
                          barWidth: 3.0,
                        ),
                        heading: HeadingStyle(
                          textStyle: GoogleFonts.inter(
                            color: const Color(0xFFF8FAFC),
                            fontWeight: FontWeight.bold,
                          ),
                          dividerColor: const Color(0xFF283145),
                        ),
                        link: const LinkStyle(color: Color(0xFF38BDF8)),
                      ),
                      onLinkTap: (url, title) => launchUrlString(url),
                    )
                  else if (msg.isStreaming)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            color: Color(0xFF8B5CF6),
                            strokeWidth: 1.8,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          msg.isThinking
                              ? 'Мысли модели (R1)...'
                              : 'Печатает...',
                          style: GoogleFonts.inter(
                            color: Colors.white60,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),

                  // Action Cards (write_file, run_command)
                  if (msg.actions.isNotEmpty) ...[
                    _buildActionsHeader(context, agent, msg),
                    ...msg.actions.asMap().entries.map(
                      (entry) => _buildActionCard(
                        context,
                        agent,
                        entry.value,
                        stepIndex: entry.key + 1,
                        totalSteps: msg.actions.length,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) ...[
            Container(
              width: 26,
              height: 26,
              margin: const EdgeInsets.only(left: 8, top: 2),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF334155),
              ),
              child: const Icon(
                LucideIcons.user,
                size: 12,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showImagePreviewDialog(BuildContext context, ChatAttachment att) {
    if (att.base64Data == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0D0F14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.image,
                    size: 14,
                    color: Color(0xFFA78BFA),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      att.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      LucideIcons.x,
                      size: 16,
                      color: Colors.white54,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.memory(
                  base64Decode(att.base64Data!),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingBlock(ChatMessage msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          initiallyExpanded: msg.isThinking,
          dense: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          childrenPadding: const EdgeInsets.all(8),
          leading: const Icon(
            LucideIcons.brain,
            size: 13,
            color: Color(0xFFA78BFA),
          ),
          title: Text(
            msg.isThinking
                ? 'Размышления модели...'
                : 'Цепочка мыслей (Reasoning)',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: const Color(0xFFA78BFA),
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                msg.thinking ?? '',
                style: GoogleFonts.jetBrainsMono(
                  color: Colors.white70,
                  fontSize: 10.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsHeader(
    BuildContext context,
    QuantumAiAgentService agent,
    ChatMessage msg,
  ) {
    final pendingCount = msg.actions.where((a) => !a.isExecuted && a.type == 'write_file').length;
    final total = msg.actions.length;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: pendingCount > 0
              ? const Color(0xFF8B5CF6).withValues(alpha: 0.3)
              : const Color(0xFF10B981).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            pendingCount > 0 ? LucideIcons.list_checks : LucideIcons.circle_check,
            size: 14,
            color: pendingCount > 0 ? const Color(0xFFA78BFA) : const Color(0xFF10B981),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              pendingCount > 0
                  ? 'Этапы изменений ($pendingCount из $total ожидают применения):'
                  : 'Все этапы изменений применены ($total)',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (pendingCount > 1) ...[
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: const Icon(LucideIcons.check_check, size: 12),
              label: const Text('Принять все', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
              onPressed: () async {
                final ws = ref.read(workspaceProvider).currentPath;
                for (final act in msg.actions) {
                  if (!act.isExecuted && act.type == 'write_file') {
                    final ok = await agent.executeWriteAction(act);
                    if (ok && ws != null) {
                      final fullPath = File(act.path).isAbsolute ? act.path : p.join(ws, act.path);
                      await ref.read(editorProvider.notifier).reloadFileFromDisk(fullPath);
                    }
                  }
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Все изменения успешно применены и обновлены в редакторе!'),
                    ),
                  );
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    QuantumAiAgentService agent,
    AgentAction action, {
    int? stepIndex,
    int? totalSteps,
  }) {
    if (action.type == 'write_file') {
      final stepPrefix = (stepIndex != null && totalSteps != null && totalSteps > 1)
          ? 'Этап $stepIndex/$totalSteps • '
          : '';
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF091410),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: action.executionError != null
                ? Colors.redAccent.withValues(alpha: 0.5)
                : const Color(0xFF10B981).withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  LucideIcons.file_code,
                  size: 14,
                  color: Color(0xFF10B981),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$stepPrefix${action.path}  (${(action.content ?? '').split('\n').length} стр.)',
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFF10B981),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!action.isExecuted && !action.isExecuting) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFA78BFA),
                      side: const BorderSide(
                        color: Color(0xFF8B5CF6),
                        width: 0.8,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    icon: const Icon(LucideIcons.git_compare, size: 11),
                    label: const Text('Diff', style: TextStyle(fontSize: 10.5)),
                    onPressed: () async {
                      String oldContent = '';
                      final ws = ref.read(workspaceProvider).currentPath;
                      if (ws != null) {
                        final fullPath = File(action.path).isAbsolute
                            ? action.path
                            : '$ws/${action.path}';
                        final f = File(fullPath);
                        if (await f.exists()) {
                          oldContent = await f.readAsString();
                        }
                      }
                      if (context.mounted) {
                        showDialog(
                          context: context,
                          builder: (_) => AiDiffDialog(
                            filePath: action.path,
                            oldContent: oldContent,
                            newContent: action.content ?? '',
                            onApply: () async {
                              final ok = await agent.executeWriteAction(action);
                              final ws = ref.read(workspaceProvider).currentPath;
                              if (ws != null) {
                                final fullPath = File(action.path).isAbsolute
                                    ? action.path
                                    : p.join(ws, action.path);
                                await ref.read(editorProvider.notifier).reloadFileFromDisk(fullPath);
                              }
                              if (ok && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Файл ${action.path} успешно записан и обновлён!',
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                ],
                if (action.isExecuting) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Запись...',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF10B981),
                      fontSize: 10.5,
                    ),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: action.isExecuted
                          ? Colors.white12
                          : (action.executionError != null
                                ? Colors.redAccent
                                : const Color(0xFF10B981)),
                      foregroundColor: action.isExecuted
                          ? Colors.white60
                          : Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    icon: Icon(
                      action.isExecuted
                          ? LucideIcons.check
                          : (action.executionError != null
                                ? LucideIcons.refresh_cw
                                : LucideIcons.save),
                      size: 12,
                    ),
                    label: Text(
                      action.isExecuted
                          ? 'Записан'
                          : (action.executionError != null
                                ? 'Повторить'
                                : (action.isUndone
                                      ? 'Применить снова'
                                      : 'Применить')),
                      style: const TextStyle(fontSize: 10.5),
                    ),
                    onPressed: action.isExecuted
                        ? null
                        : () async {
                            final ok = await agent.executeWriteAction(action);
                            final ws = ref.read(workspaceProvider).currentPath;
                            if (ws != null) {
                              final fullPath = File(action.path).isAbsolute
                                  ? action.path
                                  : p.join(ws, action.path);
                              await ref.read(editorProvider.notifier).reloadFileFromDisk(fullPath);
                            }
                            if (ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Файл ${action.path} успешно записан и обновлён!',
                                  ),
                                ),
                              );
                            }
                          },
                  ),
                ],
                if (action.isExecuted && action.backupTaken)
                  IconButton(
                    tooltip: 'Откатить этот файл',
                    visualDensity: VisualDensity.compact,
                    iconSize: 15,
                    color: Colors.orangeAccent,
                    icon: const Icon(LucideIcons.undo_2),
                    onPressed: () async {
                      final ok = await agent.undoWriteAction(action);
                      final ws = ref.read(workspaceProvider).currentPath;
                      if (ws != null) {
                        final fullPath = File(action.path).isAbsolute
                            ? action.path
                            : p.join(ws, action.path);
                        await ref.read(editorProvider.notifier).reloadFileFromDisk(fullPath);
                      }
                    },
                  ),
              ],
            ),
            if (action.executionError != null) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.circle_alert,
                      size: 12,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        action.executionError!,
                        style: GoogleFonts.inter(
                          color: Colors.redAccent,
                          fontSize: 10.5,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    } else if (action.type == 'run_command') {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF0A131A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: action.executionError != null
                ? Colors.redAccent.withValues(alpha: 0.5)
                : const Color(0xFF38BDF8).withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  LucideIcons.terminal,
                  size: 14,
                  color: Color(0xFF38BDF8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    action.command ?? '',
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFF38BDF8),
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (action.isExecuting) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Выполняется...',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF38BDF8),
                      fontSize: 10.5,
                    ),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: action.isExecuted
                          ? Colors.white12
                          : (action.executionError != null
                                ? Colors.redAccent
                                : const Color(0xFF0284C7)),
                      foregroundColor: action.isExecuted
                          ? Colors.white60
                          : Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    icon: Icon(
                      action.isExecuted
                          ? LucideIcons.check
                          : (action.executionError != null
                                ? LucideIcons.refresh_cw
                                : LucideIcons.play),
                      size: 12,
                    ),
                    label: Text(
                      action.isExecuted
                          ? 'Выполнено'
                          : (action.executionError != null
                                ? 'Повторить'
                                : 'Запустить'),
                      style: const TextStyle(fontSize: 10.5),
                    ),
                    onPressed: action.isExecuted
                        ? null
                        : () async {
                            await agent.executeCommandAction(action);
                          },
                  ),
                ],
              ],
            ),
            if (action.output != null && action.output!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF050B10),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  action.output!,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFF94A3B8),
                    fontSize: 10,
                  ),
                ),
              ),
            ],
            if (action.executionError != null) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.circle_alert,
                      size: 12,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        action.executionError!,
                        style: GoogleFonts.inter(
                          color: Colors.redAccent,
                          fontSize: 10.5,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildAttachmentPreviewStrip() {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF111520),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _pendingAttachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final att = _pendingAttachments[index];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF181C26),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (att.isImage && att.base64Data != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(
                      base64Decode(att.base64Data!),
                      width: 34,
                      height: 34,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      LucideIcons.file_code,
                      size: 14,
                      color: Color(0xFFA78BFA),
                    ),
                  ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        att.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        att.isImage
                            ? 'Изображение'
                            : '${(att.sizeBytes / 1024).toStringAsFixed(1)} KB',
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () {
                    setState(() {
                      _pendingAttachments.removeAt(index);
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(LucideIcons.x, size: 13, color: Colors.white54),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.pickFiles();
      if (result.isEmpty) return;

      for (final pf in result) {
        final name = pf.name;
        final ext = p.extension(name).toLowerCase();
        final isImg = const [
          '.png',
          '.jpg',
          '.jpeg',
          '.webp',
          '.gif',
          '.bmp',
        ].contains(ext);
        final Uint8List bytes = await pf.readAsBytes();

        if (isImg) {
          final mime = ext == '.png'
              ? 'image/png'
              : ext == '.webp'
              ? 'image/webp'
              : ext == '.gif'
              ? 'image/gif'
              : 'image/jpeg';
          setState(() {
            _pendingAttachments.add(
              ChatAttachment(
                name: name,
                path: pf.path ?? name,
                mimeType: mime,
                isImage: true,
                base64Data: base64Encode(bytes),
                sizeBytes: bytes.length,
              ),
            );
          });
        } else {
          final text = utf8.decode(bytes, allowMalformed: true);
          setState(() {
            _pendingAttachments.add(
              ChatAttachment(
                name: name,
                path: pf.path ?? name,
                mimeType: 'text/plain',
                isImage: false,
                textContent: text,
                sizeBytes: bytes.length,
              ),
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось прикрепить файл: $e')),
        );
      }
    }
  }

  Future<void> _pickPhoto({bool fromCamera = false}) async {
    try {
      final xfile = await _imagePicker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (xfile == null) return;
      final bytes = await xfile.readAsBytes();
      final ext = p.extension(xfile.path).toLowerCase();
      final mime = ext == '.png'
          ? 'image/png'
          : ext == '.webp'
          ? 'image/webp'
          : 'image/jpeg';
      setState(() {
        _pendingAttachments.add(
          ChatAttachment(
            name: p.basename(xfile.path),
            path: xfile.path,
            mimeType: mime,
            isImage: true,
            base64Data: base64Encode(bytes),
            sizeBytes: bytes.length,
          ),
        );
      });
    } catch (e) {
      // Fallback to FilePicker if camera/gallery intent is unavailable on Desktop Linux
      await _pickFiles();
    }
  }

  void _attachActiveEditorFile() {
    final ed = ref.read(editorProvider);
    if (ed.openFiles.isEmpty || ed.activeTabIndex >= ed.openFiles.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('В редакторе нет открытого файла')),
      );
      return;
    }
    final active = ed.openFiles[ed.activeTabIndex];
    final text = active.controller.text;
    setState(() {
      _pendingAttachments.add(
        ChatAttachment(
          name: active.name,
          path: active.path,
          mimeType: 'text/plain',
          isImage: false,
          textContent: text,
          sizeBytes: text.length,
        ),
      );
    });
  }

  Widget _buildInputBar(BuildContext context, QuantumAiAgentService agent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 📎 Attach File / Active Editor File menu
            PopupMenuButton<String>(
              tooltip: 'Прикрепить файл или код',
              color: const Color(0xFF181C26),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              onSelected: (val) {
                if (val == 'file') _pickFiles();
                if (val == 'active') _attachActiveEditorFile();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'active',
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.file_code,
                        size: 15,
                        color: Color(0xFFA78BFA),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Прикрепить открытый файл',
                        style: TextStyle(color: Colors.white, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'file',
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.folder_open,
                        size: 15,
                        color: Color(0xFF94A3B8),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Выбрать файл с устройства...',
                        style: TextStyle(color: Colors.white, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF181C26),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: const Icon(
                  LucideIcons.paperclip,
                  size: 15,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // 🖼️ Attach Photo / Screenshot button
            PopupMenuButton<String>(
              tooltip: 'Прикрепить фото или скриншот',
              color: const Color(0xFF181C26),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              onSelected: (val) {
                if (val == 'gallery') _pickPhoto(fromCamera: false);
                if (val == 'camera') _pickPhoto(fromCamera: true);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'gallery',
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.image,
                        size: 15,
                        color: Color(0xFFA78BFA),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Фото / Скриншот из галереи',
                        style: TextStyle(color: Colors.white, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'camera',
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.camera,
                        size: 15,
                        color: Color(0xFF94A3B8),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Сделать снимок камеры',
                        style: TextStyle(color: Colors.white, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF181C26),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: const Icon(
                  LucideIcons.image,
                  size: 15,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Input Text Field
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0D14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  maxLines: 5,
                  minLines: 1,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: _pendingAttachments.isNotEmpty
                        ? 'Добавьте комментарий к вложениям...'
                        : 'Спросите AI Агента о коде или задаче...',
                    hintStyle: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: (_) => _sendMessage(agent),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Send / Stop Button
            if (agent.isGenerating)
              SizedBox(
                width: 34,
                height: 34,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    LucideIcons.square,
                    size: 14,
                    color: Colors.redAccent,
                  ),
                  tooltip: 'Остановить',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => agent.stopGeneration(),
                ),
              )
            else
              SizedBox(
                width: 34,
                height: 34,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    LucideIcons.send,
                    size: 14,
                    color: Colors.white,
                  ),
                  tooltip: 'Отправить',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _sendMessage(agent),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _sendMessage(QuantumAiAgentService agent) {
    final text = _textController.text;
    if (text.trim().isEmpty && _pendingAttachments.isEmpty) return;
    final attachmentsToSend = List<ChatAttachment>.from(_pendingAttachments);
    _textController.clear();
    setState(() {
      _pendingAttachments.clear();
    });
    agent.sendMessage(text, attachments: attachmentsToSend);
    _scrollToBottom();
  }

  String _cleanText(String raw) {
    var text = raw
        .replaceAll(RegExp(r'<action[\s\S]*?<\/action>'), '')
        .replaceAll(
          RegExp(
            r'<tool\s+name="\w+"(?:\s+\w+="[^"]*")*\s*(?:/>|>[\s\S]*?</tool>)',
          ),
          '',
        )
        .replaceAll(RegExp(r'<think>[\s\S]*?<\/think>'), '');
    text = text.replaceAll(RegExp(r'<action[\s\S]*$'), '');
    text = text.replaceAll(RegExp(r'<tool[\s\S]*$'), '');
    text = text.replaceAll(RegExp(r'<think[\s\S]*$'), '');
    return text.trim();
  }

  void _showApiKeysDialog(BuildContext context, SettingsState settings) {
    final orCtrl = TextEditingController(text: settings.openrouterApiKey);
    final dsCtrl = TextEditingController(text: settings.deepseekApiKey);
    final gmCtrl = TextEditingController(text: settings.geminiApiKey);
    final gqCtrl = TextEditingController(text: settings.groqApiKey);
    final oaCtrl = TextEditingController(text: settings.openaiApiKey);
    final anCtrl = TextEditingController(text: settings.anthropicApiKey);
    final xaCtrl = TextEditingController(text: settings.xaiApiKey);
    final msCtrl = TextEditingController(text: settings.mistralApiKey);
    final cuUrlCtrl = TextEditingController(text: settings.customApiBaseUrl);
    final cuModCtrl = TextEditingController(text: settings.customApiModel);
    final cuKeyCtrl = TextEditingController(text: settings.customApiKey);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131722),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(LucideIcons.key, color: Color(0xFFA78BFA), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Провайдеры ИИ и API Ключи',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.sparkles,
                        color: Color(0xFFA78BFA),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Поддерживаются 9 провайдеров: OpenRouter (единый ключ ко всем моделям), а также прямые ключи Gemini, Groq LPU, DeepSeek, OpenAI, Anthropic, xAI Grok, Mistral и локальный Ollama/LM Studio.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildField(
                  'OpenRouter API Key (универсальный доступ)',
                  orCtrl,
                ),
                const SizedBox(height: 8),
                _buildField(
                  'Google Gemini API Key (AIzaSy... — Gemini 2.5 Pro/Flash)',
                  gmCtrl,
                ),
                const SizedBox(height: 8),
                _buildField(
                  'Groq Cloud API Key (gsk_... — сверхбыстрый Llama 3.3 / R1)',
                  gqCtrl,
                ),
                const SizedBox(height: 8),
                _buildField(
                  'DeepSeek API Key (sk-... — DeepSeek V3 / R1 Direct)',
                  dsCtrl,
                ),
                const SizedBox(height: 8),
                _buildField(
                  'OpenAI API Key (sk-... — GPT-4o / o3-mini)',
                  oaCtrl,
                ),
                const SizedBox(height: 8),
                _buildField(
                  'Anthropic API Key (sk-ant-... — Claude 3.7 / 3.5)',
                  anCtrl,
                ),
                const SizedBox(height: 8),
                _buildField(
                  'xAI Grok API Key (xai-... — Grok 3 / Vision)',
                  xaCtrl,
                ),
                const SizedBox(height: 8),
                _buildField('Mistral / Codestral API Key', msCtrl),
                const SizedBox(height: 14),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 10),
                Text(
                  'Локальный / Custom OpenAI-совместимый сервер (Ollama / LM Studio):',
                  style: GoogleFonts.inter(
                    color: const Color(0xFFA78BFA),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _buildField(
                  'Base URL (например http://127.0.0.1:11434/v1)',
                  cuUrlCtrl,
                  obscure: false,
                ),
                const SizedBox(height: 8),
                _buildField(
                  'Имя модели (например qwen2.5-coder:7b)',
                  cuModCtrl,
                  obscure: false,
                ),
                const SizedBox(height: 8),
                _buildField(
                  'Custom API Key (необязательно для Ollama)',
                  cuKeyCtrl,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Отмена',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final sn = ref.read(settingsProvider.notifier);
              sn.setOpenrouterApiKey(orCtrl.text.trim());
              sn.setDeepseekApiKey(dsCtrl.text.trim());
              sn.setGeminiApiKey(gmCtrl.text.trim());
              sn.setGroqApiKey(gqCtrl.text.trim());
              sn.setOpenaiApiKey(oaCtrl.text.trim());
              sn.setAnthropicApiKey(anCtrl.text.trim());
              sn.setXaiApiKey(xaCtrl.text.trim());
              sn.setMistralApiKey(msCtrl.text.trim());
              sn.setCustomApiBaseUrl(cuUrlCtrl.text.trim());
              sn.setCustomApiModel(cuModCtrl.text.trim());
              sn.setCustomApiKey(cuKeyCtrl.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    bool obscure = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 3),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0D14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  void _confirmDeleteChat(
    BuildContext context,
    QuantumAiAgentService agent,
    String sessionId,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131722),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(LucideIcons.trash_2, color: Colors.redAccent, size: 18),
            const SizedBox(width: 8),
            Text(
              'Удалить диалог?',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const Text(
          'История этого диалога будет безвозвратно удалена.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Отмена',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              agent.deleteSession(sessionId);
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  void _showChatHistoryModal(
    BuildContext context,
    QuantumAiAgentService agent,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ChatHistorySheet(agent: agent),
    );
  }
}

class _ChatHistorySheet extends StatefulWidget {
  final QuantumAiAgentService agent;

  const _ChatHistorySheet({required this.agent});

  @override
  State<_ChatHistorySheet> createState() => _ChatHistorySheetState();
}

class _ChatHistorySheetState extends State<_ChatHistorySheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Сегодня, $h:$m';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day) {
      return 'Вчера, $h:$m';
    }
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} $h:$m';
  }

  void _showRenameDialog(BuildContext context, ChatSession session) {
    final ctrl = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131722),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(LucideIcons.pencil, color: Color(0xFFA78BFA), size: 16),
            const SizedBox(width: 8),
            Text(
              'Переименовать диалог',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Название темы диалога...',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Отмена',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              widget.agent.renameSession(session.id, ctrl.text.trim());
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = widget.agent.sessions;
    final filtered = _query.isEmpty
        ? sessions
        : sessions
              .where(
                (s) => s.title.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: const Color(0xFF0F121C),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
          left: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
          right: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    LucideIcons.history,
                    color: Color(0xFFA78BFA),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'История диалогов',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Всего сохранено: ${sessions.length}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    widget.agent.startNewChat();
                    Navigator.pop(context);
                  },
                  icon: const Icon(LucideIcons.plus, size: 14),
                  label: const Text(
                    'Новый чат',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(
                    LucideIcons.x,
                    size: 18,
                    color: Colors.white54,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.search,
                    size: 14,
                    color: Colors.white38,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v.trim()),
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Поиск диалога по теме...',
                        hintStyle: TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    InkWell(
                      onTap: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                      child: const Icon(
                        LucideIcons.x,
                        size: 14,
                        color: Colors.white38,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Sessions List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.message_square_off,
                          size: 36,
                          color: Colors.white24,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _query.isEmpty
                              ? 'Нет сохранённых диалогов'
                              : 'Ничего не найдено',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    physics: const BouncingScrollPhysics(),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final s = filtered[index];
                      final isActive = s.id == widget.agent.currentSessionId;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF8B5CF6).withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isActive
                                ? const Color(0xFF8B5CF6).withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.07),
                            width: isActive ? 1.2 : 0.8,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            widget.agent.switchSession(s.id);
                            Navigator.pop(context);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? const Color(
                                            0xFF8B5CF6,
                                          ).withValues(alpha: 0.25)
                                        : Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isActive
                                        ? LucideIcons.circle_check
                                        : LucideIcons.message_square,
                                    size: 15,
                                    color: isActive
                                        ? const Color(0xFFA78BFA)
                                        : Colors.white60,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              s.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                color: Colors.white,
                                                fontSize: 12.5,
                                                fontWeight: isActive
                                                    ? FontWeight.w700
                                                    : FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          if (isActive) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 1.5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                  0xFF8B5CF6,
                                                ).withValues(alpha: 0.3),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'АКТИВНЫЙ',
                                                style: GoogleFonts.inter(
                                                  color: const Color(
                                                    0xFFC4B5FD,
                                                  ),
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(
                                            LucideIcons.clock,
                                            size: 10,
                                            color: Colors.white38,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatDate(s.updatedAt),
                                            style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 10.5,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          const Icon(
                                            LucideIcons.message_circle,
                                            size: 10,
                                            color: Colors.white38,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${s.messages.length} сообщ.',
                                            style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 10.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    LucideIcons.pencil,
                                    size: 13,
                                    color: Colors.white38,
                                  ),
                                  tooltip: 'Переименовать',
                                  constraints: const BoxConstraints.tightFor(
                                    width: 26,
                                    height: 26,
                                  ),
                                  padding: EdgeInsets.zero,
                                  onPressed: () =>
                                      _showRenameDialog(context, s),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    LucideIcons.trash_2,
                                    size: 13,
                                    color: Colors.white38,
                                  ),
                                  tooltip: 'Удалить диалог',
                                  constraints: const BoxConstraints.tightFor(
                                    width: 26,
                                    height: 26,
                                  ),
                                  padding: EdgeInsets.zero,
                                  onPressed: () {
                                    widget.agent.deleteSession(s.id);
                                    setState(() {});
                                  },
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
      ),
    );
  }
}
