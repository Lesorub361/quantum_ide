import 'package:flutter/material.dart';
import 'package:quantum_ide/core/theme/vscode_colors.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:quantum_ide/core/services/quantum_ai_agent_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'dart:io';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/ai_diff_dialog.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/agent_terminal_card.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/mcp_manager_dialog.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';

class QuantumAiAgentPanel extends ConsumerStatefulWidget {
  const QuantumAiAgentPanel({super.key, this.onClose});

  /// Если задан — в шапке показывается кнопка закрытия (режим правой док-панели).
  final VoidCallback? onClose;

  @override
  ConsumerState<QuantumAiAgentPanel> createState() => _QuantumAiAgentPanelState();
}

class _QuantumAiAgentPanelState extends ConsumerState<QuantumAiAgentPanel> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool force = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final pos = _scrollController.position;
        // При стриминге не перебиваем пользователя, если он листает историю вверх.
        if (!force && pos.maxScrollExtent - pos.pixels > 160) return;
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
    if (agent.isGenerating || agent.messages.any((m) => m.actions.any((a) => a.isRunning))) {
      _scrollToBottom(force: false);
    }
    final settings = ref.watch(settingsProvider);
    final workspace = ref.watch(workspaceProvider);
    final projectName = workspace.currentPath?.split('/').where((s) => s.isNotEmpty).lastOrNull ?? 'Проект';

    return Container(
      color: Vs.sideBar,
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

          // ── Bottom Input Bar ────────────────────────────────────────────────
          _buildInputBar(context, agent),
        ],
      ),
    );
  }

  String _fmtTokens(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  Widget _buildModeBar(BuildContext context, QuantumAiAgentService agent) {
    final undo = agent.undoableCount;
    final hasPlan = agent.mode == AgentMode.plan &&
        !agent.isGenerating &&
        agent.messages.any((m) => m.role == MessageRole.assistant && m.text.contains('План готов'));
    final fill = agent.contextFill;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      color: Vs.sideBar,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Vs.input,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final m in AgentMode.values)
                      Tooltip(
                        message: m.hint,
                        child: GestureDetector(
                          onTap: agent.isGenerating ? null : () => agent.setMode(m),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(7),
                              gradient: agent.mode == m
                                  ? const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)])
                                  : null,
                            ),
                            child: Text(
                              m.label,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: agent.mode == m ? Colors.white : Colors.white54,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Spacer(),
              PopupMenuButton<AgentEngine>(
                tooltip: 'Кто выполняет задачу',
                enabled: !agent.isGenerating,
                padding: EdgeInsets.zero,
                onSelected: agent.setEngine,
                itemBuilder: (_) => [
                  for (final e in AgentEngine.values)
                    PopupMenuItem(value: e, child: Text(e.label + (e == AgentEngine.builtin ? '' : ' (CLI)'))),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(LucideIcons.bot, size: 12, color: Colors.white54),
                    const SizedBox(width: 3),
                    Text(agent.engine.label, style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Токены сессии: вход ${agent.promptTokens}, выход ${agent.completionTokens}'
                    '${agent.usageEstimated ? ' (оценка)' : ''}\nКонтекст заполнен на ${(agent.contextFill * 100).toStringAsFixed(0)}%',
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(LucideIcons.coins, size: 12, color: Colors.white38),
                  const SizedBox(width: 3),
                  Text('${agent.usageEstimated ? '~' : ''}${_fmtTokens(agent.sessionTokens)}',
                      style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: Colors.white54)),
                ]),
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
                  label: Text('Откатить ($undo)', style: const TextStyle(fontSize: 10.5)),
                  onPressed: () async {
                    final n = await agent.undoAllAgentChanges();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Откачено правок агента: $n')));
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
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: const Color(0xFF8B5CF6),
                ),
                icon: const Icon(LucideIcons.play, size: 13),
                label: const Text('Выполнить план', style: TextStyle(fontSize: 11.5)),
                onPressed: agent.runPlan,
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
        color: Vs.sideBar,
        border: Border(bottom: BorderSide(color: Vs.border)),
      ),
      child: Row(
        children: [
          // Glowing Sparkle Icon
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
            ),
            child: const Icon(LucideIcons.sparkles, size: 13, color: Color(0xFFA78BFA)),
          ),
          const SizedBox(width: 8),

          // Interactive Model Selector Pill Button
          InkWell(
            onTap: () => _showModelSelectorDialog(context, agent),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Vs.input,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      currentModel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (currentModel.badge != null) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Color(currentModel.badgeColorValue ?? 0xFF8B5CF6).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        currentModel.badge!,
                        style: TextStyle(
                          color: Color(currentModel.badgeColorValue ?? 0xFFA78BFA),
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  const Icon(LucideIcons.chevron_down, size: 12, color: Colors.white60),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Project Chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.folder, size: 10, color: Colors.cyanAccent),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 90),
                  child: Text(
                    projectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Clear Chat
          IconButton(
            icon: const Icon(LucideIcons.trash_2, size: 13, color: Colors.white60),
            tooltip: 'Очистить историю чата',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            onPressed: () => agent.clearChat(),
          ),

          // MCP Manager
          IconButton(
            icon: const Icon(LucideIcons.blocks, size: 14, color: Vs.accentLight),
            tooltip: 'Инструменты MCP (Model Context Protocol)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            onPressed: () => McpManagerDialog.show(context),
          ),
          const SizedBox(width: 2),

          // Settings (API Keys)
          IconButton(
            icon: const Icon(LucideIcons.settings_2, size: 13, color: Colors.white60),
            tooltip: 'Настроить API Ключи и Провайдеры',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            onPressed: () => _showApiKeysDialog(context, settings),
          ),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(LucideIcons.x, size: 14, color: Colors.white60),
              tooltip: 'Закрыть панель',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 26, height: 26),
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  void _showModelSelectorDialog(BuildContext context, QuantumAiAgentService agent) {
    String searchQuery = '';
    String selectedCategory = 'Все';
    final customModelCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final categories = [
            'Все',
            'Популярные',
            'Рассуждения',
            'Кодинг',
            'Бесплатные',
            'Флагманы',
            'Прямой API',
          ];

          final allModels = agent.availableModels.isNotEmpty
              ? agent.availableModels
              : QuantumModelItem.predefinedModels;
          final filteredModels = allModels.where((m) {
            final matchesCategory = selectedCategory == 'Все' || m.category == selectedCategory;
            final matchesQuery = searchQuery.isEmpty ||
                m.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
                m.id.toLowerCase().contains(searchQuery.toLowerCase()) ||
                (m.badge != null && m.badge!.toLowerCase().contains(searchQuery.toLowerCase()));
            return matchesCategory && matchesQuery;
          }).toList();

          return AlertDialog(
            backgroundColor: Vs.sideBar,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  child: const Icon(LucideIcons.cpu, color: Color(0xFFA78BFA), size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Каталог ИИ-Моделей',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        agent.isLoadingModels ? 'Обновление списка с OpenRouter...' : 'Все модели доступны по ключу OpenRouter',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: agent.isLoadingModels
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFA78BFA)),
                        )
                      : const Icon(LucideIcons.refresh_cw, size: 16, color: Color(0xFFA78BFA)),
                  tooltip: 'Обновить модели с OpenRouter',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                  onPressed: agent.isLoadingModels
                      ? null
                      : () async {
                          await agent.fetchLiveOpenRouterModels(force: true);
                          setDialogState(() {});
                        },
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 16, color: Colors.white54),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
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
                      color: Vs.input,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.search, size: 14, color: Colors.white38),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            onChanged: (val) {
                              setDialogState(() {
                                searchQuery = val.trim();
                              });
                            },
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                            decoration: const InputDecoration(
                              hintText: 'Поиск (DeepSeek, Claude, Free, Coder)...',
                              hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
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
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
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
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.25)
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
                                color: isSelected ? const Color(0xFFA78BFA) : Colors.white70,
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                            ),
                          )
                        : ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            itemCount: filteredModels.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.05),
                            ),
                            itemBuilder: (context, idx) {
                              final item = filteredModels[idx];
                              final isCurrent = agent.selectedModel.id == item.id;
                              final badgeColor = Color(item.badgeColorValue ?? 0xFF8B5CF6);

                              return InkWell(
                                onTap: () {
                                  agent.selectModel(item);
                                  Navigator.pop(ctx);
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? const Color(0xFF8B5CF6).withValues(alpha: 0.15)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                                if (item.badge != null) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 1.5,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: badgeColor.withValues(alpha: 0.2),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(
                                                        color: badgeColor.withValues(alpha: 0.4),
                                                        width: 0.5,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      item.badge!,
                                                      style: TextStyle(
                                                        color: badgeColor,
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
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
                      color: Vs.input,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: customModelCtrl,
                            style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11),
                            decoration: const InputDecoration(
                              hintText: 'Кастомный slug (напр. moonshotai/...)',
                              hintStyle: TextStyle(color: Colors.white38, fontSize: 10.5),
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
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                          ),
                          onPressed: () {
                            final slug = customModelCtrl.text.trim();
                            if (slug.isNotEmpty) {
                              agent.setCustomModel(slug);
                              Navigator.pop(ctx);
                            }
                          },
                          child: const Text('Применить', style: TextStyle(fontSize: 11)),
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
      '🔍 Найди ошибки в коде',
      '⚡ Оптимизируй производительность',
      '📝 Напиши тесты',
      '🚀 Объясни архитектуру проекта',
    ];

    return Container(
      height: 32,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemCount: suggestions.length,
        itemBuilder: (context, i) {
          final prompt = suggestions[i];
          return ActionChip(
            backgroundColor: Vs.sideBar,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
            label: Text(
              prompt,
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 10.5),
            ),
            onPressed: () {
              _textController.text = prompt;
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

    // Результат команды уже показан в карточке терминала — не дублируем.
    if (msg.hiddenInUi) return const SizedBox.shrink();

    // Результат инструмента: компактная плашка вместо большого пузыря.
    if (msg.toolLabel != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 27),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            dense: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            childrenPadding: const EdgeInsets.all(8),
            collapsedBackgroundColor: Colors.white.withValues(alpha: 0.04),
            backgroundColor: Colors.white.withValues(alpha: 0.04),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            leading: const Icon(LucideIcons.wrench, size: 13, color: Color(0xFF8B5CF6)),
            title: Text(msg.toolLabel!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white70)),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  msg.text.length > 2500 ? '${msg.text.substring(0, 2500)}…' : msg.text,
                  style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: Colors.white60),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Пустой пузырь (ответ состоял только из вызова инструмента) не показываем.
    if (!isUser && !msg.isStreaming && _cleanText(msg.text).isEmpty &&
        (msg.thinking == null || msg.thinking!.isEmpty) && msg.actions.isEmpty) {
      return const SizedBox.shrink();
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🧠 Collapsible Thinking Block (DeepSeek R1 / o3-mini)
        if (msg.thinking != null && msg.thinking!.isNotEmpty) _buildThinkingBlock(msg),

        // Main Text Content
        if (msg.text.isNotEmpty && _cleanText(msg.text).isNotEmpty)
          GptMarkdown(
            _cleanText(msg.text),
            style: GoogleFonts.inter(color: const Color(0xFFE5E7EB), fontSize: 12.5, height: 1.5),
            onLinkTap: (url, title) => launchUrlString(url),
          )
        else if (msg.isStreaming)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(color: Color(0xFF8B5CF6), strokeWidth: 1.8),
              ),
              const SizedBox(width: 8),
              Text(
                msg.isThinking ? 'Думает…' : 'Печатает…',
                style: GoogleFonts.inter(color: Colors.white60, fontSize: 11.5),
              ),
            ],
          ),

        // Action Cards (write_file, run_command)
        if (msg.actions.isNotEmpty) ...msg.actions.map((act) => _buildActionCard(context, agent, act)),
      ],
    );

    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14, left: 28),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2B3354), Color(0xFF232A47)],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(4),
              ),
              border: Border.all(color: const Color(0xFF4F5B7F).withValues(alpha: 0.7)),
            ),
            child: SelectableText(
              msg.text,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5, height: 1.45),
            ),
          ),
        ),
      );
    }

    // Ответ ассистента: без пузыря, на всю ширину панели (как в чатах IDE).
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF3B82F6)]),
                ),
                child: const Icon(LucideIcons.sparkles, size: 10, color: Colors.white),
              ),
              const SizedBox(width: 7),
              Text('Quantum',
                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white70)),
              const SizedBox(width: 6),
              Text(
                '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 10, color: Colors.white30),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(padding: const EdgeInsets.only(left: 27), child: body),
        ],
      ),
    );
  }

  Widget _buildThinkingBlock(ChatMessage msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.25)),
      ),
      child: ExpansionTile(
        initiallyExpanded: msg.isThinking,
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        childrenPadding: const EdgeInsets.all(8),
        leading: const Icon(LucideIcons.brain, size: 13, color: Color(0xFFA78BFA)),
        title: Text(
          msg.isThinking ? 'Размышления DeepSeek R1...' : 'Цепочка мыслей (R1)',
          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFA78BFA), fontWeight: FontWeight.w600),
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
              style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 10.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    QuantumAiAgentService agent,
    AgentAction action,
  ) {
    if (action.type == 'write_file') {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF091410),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.file_code, size: 14, color: Colors.greenAccent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Файл: ${action.path}  (${(action.content ?? '').split('\n').length} стр.)',
                style: GoogleFonts.jetBrainsMono(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!action.isExecuted) ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFA78BFA),
                  side: const BorderSide(color: Color(0xFF8B5CF6), width: 0.8),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(LucideIcons.git_compare, size: 11),
                label: const Text('Diff', style: TextStyle(fontSize: 10.5)),
                onPressed: () async {
                  String oldContent = '';
                  final ws = ref.read(workspaceProvider).currentPath;
                  if (ws != null) {
                    final fullPath = File(action.path ?? '').isAbsolute
                        ? (action.path ?? '')
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
                        filePath: action.path ?? '',
                        oldContent: oldContent,
                        newContent: action.content ?? '',
                        onApply: () async {
                          final ok = await agent.executeWriteAction(action);
                          if (ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Файл ${action.path} успешно записан!')),
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
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: action.isExecuted ? Colors.white12 : Colors.greenAccent,
                foregroundColor: action.isExecuted ? Colors.white60 : Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: Icon(action.isExecuted ? LucideIcons.check : LucideIcons.save, size: 12),
              label: Text(action.isExecuted ? 'Записан' : (action.isUndone ? 'Применить снова' : 'Применить'), style: const TextStyle(fontSize: 10.5)),
              onPressed: action.isExecuted
                  ? null
                  : () async {
                      final ok = await agent.executeWriteAction(action);
                      if (ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Файл ${action.path} успешно записан!')),
                        );
                      }
                    },
            ),
            if (action.isExecuted && action.backupTaken)
              IconButton(
                tooltip: 'Откатить этот файл',
                visualDensity: VisualDensity.compact,
                iconSize: 15,
                color: Colors.orangeAccent,
                icon: const Icon(LucideIcons.undo_2),
                onPressed: () => agent.undoWriteAction(action),
              ),
          ],
        ),
      );
    } else if (action.type == 'run_command') {
      return AgentTerminalCard(
        command: action.command ?? '',
        output: action.output,
        isRunning: action.isRunning,
        exitCode: action.exitCode,
        duration: action.duration,
        canRun: !action.isRunning && !agent.isGenerating,
        onRun: () => agent.executeCommandAction(action),
        onStop: () => agent.cancelCommandAction(action),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildInputBar(BuildContext context, QuantumAiAgentService agent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: Vs.sideBar,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Vs.sideBar,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _focusNode.hasFocus
                ? const Color(0xFF8B5CF6).withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.10)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Focus(
                  // Enter — отправить, Shift+Enter — новая строка.
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      _sendMessage(agent);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    maxLines: 6,
                    minLines: 1,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5),
                    decoration: const InputDecoration(
                      hintText: 'Спросите агента или поставьте задачу…',
                      hintStyle: TextStyle(color: Colors.white30, fontSize: 12.5),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 9),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (agent.isGenerating)
                _sendBtn(
                  icon: LucideIcons.square,
                  tooltip: 'Остановить',
                  color: Colors.redAccent,
                  onTap: agent.stopGeneration,
                )
              else
                _sendBtn(
                  icon: LucideIcons.arrow_up,
                  tooltip: 'Отправить',
                  gradient: const [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                  onTap: () => _sendMessage(agent),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sendBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
    List<Color>? gradient,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: color?.withValues(alpha: 0.18),
            gradient: gradient == null ? null : LinearGradient(colors: gradient),
          ),
          child: Icon(icon, size: 16, color: color ?? Colors.white),
        ),
      ),
    );
  }

  void _sendMessage(QuantumAiAgentService agent) {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    _textController.clear();
    agent.sendMessage(text);
    _scrollToBottom();
  }

  String _cleanText(String raw) {
    // Убираем теги <action> из основного текста чтобы они не дублировались с карточками
    return raw
        .replaceAll(RegExp(r'<action[\s\S]*?<\/action>'), '')
        .replaceAll(RegExp(r'<tool\s+name="\w+"(?:\s+\w+="[^"]*")*\s*(?:/>|>[\s\S]*?</tool>)'), '')
        .replaceAll(RegExp(r'<think>[\s\S]*?<\/think>'), '')
        .trim();
  }

  void _showApiKeysDialog(BuildContext context, SettingsState settings) {
    final dsCtrl = TextEditingController(text: settings.deepseekApiKey);
    final orCtrl = TextEditingController(text: settings.openrouterApiKey);
    final oaCtrl = TextEditingController(text: settings.openaiApiKey);
    final anCtrl = TextEditingController(text: settings.anthropicApiKey);
    final groqCtrl = TextEditingController(text: settings.getProviderApiKey('groq'));
    final mistralCtrl = TextEditingController(text: settings.getProviderApiKey('mistral'));
    final kimiCtrl = TextEditingController(text: settings.getProviderApiKey('kimi'));
    final pplxCtrl = TextEditingController(text: settings.getProviderApiKey('perplexity'));
    final togetherCtrl = TextEditingController(text: settings.getProviderApiKey('together'));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Vs.sideBar,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(LucideIcons.key, color: Vs.accentLight, size: 18),
            const SizedBox(width: 8),
            Text(
              'API Ключи ИИ-Провайдеров',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Vs.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Vs.accent.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.sparkles, color: Vs.accentLight, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '💡 OpenRouter дает доступ сразу к 200+ моделям. Если есть прямой ключ (Groq, Mistral, DeepSeek), укажите его ниже для максимальной скорости и минимальных задержек!',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Универсальные хабы и флагманы:',
                  style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildField('OpenRouter Key (универсальный ключ ко всем моделям)', orCtrl),
                const SizedBox(height: 8),
                _buildField('DeepSeek API Key (DEEPSEEK_API_KEY)', dsCtrl),
                const SizedBox(height: 8),
                _buildField('OpenAI Key (OPENAI_API_KEY)', oaCtrl),
                const SizedBox(height: 8),
                _buildField('Anthropic Claude Key (ANTHROPIC_API_KEY)', anCtrl),
                const SizedBox(height: 14),
                const Text(
                  'Быстрые выводы и специализированные провайдеры:',
                  style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildField('Groq API Key (LPU сверхбыстрый вывод 500 т/с)', groqCtrl),
                const SizedBox(height: 8),
                _buildField('Mistral AI Key (Codestral & Mistral Large)', mistralCtrl),
                const SizedBox(height: 8),
                _buildField('Moonshot Kimi Key (256k контекст)', kimiCtrl),
                const SizedBox(height: 8),
                _buildField('Perplexity Key (Sonar поиск в интернете)', pplxCtrl),
                const SizedBox(height: 8),
                _buildField('Together AI Key (Открытые модели)', togetherCtrl),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Vs.accent, foregroundColor: Colors.white),
            onPressed: () {
              final sn = ref.read(settingsProvider.notifier);
              sn.setDeepseekApiKey(dsCtrl.text.trim());
              sn.setOpenrouterApiKey(orCtrl.text.trim());
              sn.setOpenaiApiKey(oaCtrl.text.trim());
              sn.setAnthropicApiKey(anCtrl.text.trim());
              sn.setProviderApiKey('groq', groqCtrl.text.trim());
              sn.setProviderApiKey('mistral', mistralCtrl.text.trim());
              sn.setProviderApiKey('kimi', kimiCtrl.text.trim());
              sn.setProviderApiKey('perplexity', pplxCtrl.text.trim());
              sn.setProviderApiKey('together', togetherCtrl.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
  Widget _buildField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 3),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: Vs.input,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextField(
            controller: controller,
            obscureText: true,
            style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true),
          ),
        ),
      ],
    );
  }
}
