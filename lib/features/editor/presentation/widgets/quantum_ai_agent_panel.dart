import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:quantum_ide/core/services/quantum_ai_agent_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';

class QuantumAiAgentPanel extends ConsumerStatefulWidget {
  const QuantumAiAgentPanel({super.key});

  @override
  ConsumerState<QuantumAiAgentPanel> createState() => _QuantumAiAgentPanelState();
}

class _QuantumAiAgentPanelState extends ConsumerState<QuantumAiAgentPanel> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

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
    final projectName = workspace.currentPath?.split('/').where((s) => s.isNotEmpty).lastOrNull ?? 'Проект';

    return Container(
      color: const Color(0xFF0C0E15),
      child: Column(
        children: [
          // ── Header Bar ──────────────────────────────────────────────────────
          _buildTopBar(context, agent, settings, projectName),

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

  Widget _buildTopBar(
    BuildContext context,
    QuantumAiAgentService agent,
    SettingsState settings,
    String projectName,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
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

          // Provider & Model Dropdown
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0D14),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AiProvider>(
                value: agent.selectedProvider,
                dropdownColor: const Color(0xFF161A26),
                icon: const Icon(LucideIcons.chevron_down, size: 12, color: Colors.white60),
                style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600),
                items: AiProvider.values.map((p) {
                  return DropdownMenuItem<AiProvider>(
                    value: p,
                    child: Text(p.label),
                  );
                }).toList(),
                onChanged: (p) {
                  if (p != null) agent.selectProvider(p);
                },
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
                  constraints: const BoxConstraints(maxWidth: 80),
                  child: Text(
                    projectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 10.5),
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

          // Settings (API Keys)
          IconButton(
            icon: const Icon(LucideIcons.settings_2, size: 13, color: Colors.white60),
            tooltip: 'Настроить API Ключи',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            onPressed: () => _showApiKeysDialog(context, settings),
          ),
        ],
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
            backgroundColor: const Color(0xFF131722),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 26,
              height: 26,
              margin: const EdgeInsets.only(right: 8, top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF3B82F6)],
                ),
              ),
              child: const Icon(LucideIcons.sparkles, size: 12, color: Colors.white),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF2E3856) : const Color(0xFF131722),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isUser
                      ? const Color(0xFF4F5B7F)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🧠 Collapsible Thinking Block (DeepSeek R1 / o3-mini)
                  if (msg.thinking != null && msg.thinking!.isNotEmpty)
                    _buildThinkingBlock(msg),

                  // Main Text Content
                  if (msg.text.isNotEmpty)
                    MarkdownBody(
                      data: _cleanText(msg.text),
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: GoogleFonts.inter(color: Colors.white, fontSize: 12.5, height: 1.45),
                        code: GoogleFonts.jetBrainsMono(
                          backgroundColor: const Color(0xFF090C14),
                          color: Colors.cyanAccent,
                          fontSize: 11,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: const Color(0xFF090C14),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                      ),
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
                          msg.isThinking ? 'Мысли модели (R1)...' : 'Печатает...',
                          style: GoogleFonts.inter(color: Colors.white60, fontSize: 11.5),
                        ),
                      ],
                    ),

                  // Action Cards (write_file, run_command)
                  if (msg.actions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...msg.actions.map((act) => _buildActionCard(context, agent, act)),
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
                color: Color(0xFF3B82F6),
              ),
              child: const Icon(LucideIcons.user, size: 12, color: Colors.white),
            ),
          ],
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
            const Icon(LucideIcons.file_code_2, size: 14, color: Colors.greenAccent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Файл: ${action.path}',
                style: GoogleFonts.jetBrainsMono(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
              label: Text(action.isExecuted ? 'Записан' : 'Применить', style: const TextStyle(fontSize: 10.5)),
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
          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.terminal, size: 14, color: Colors.cyanAccent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                action.command ?? '',
                style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: action.isExecuted ? Colors.white12 : Colors.cyanAccent,
                foregroundColor: action.isExecuted ? Colors.white60 : Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: Icon(action.isExecuted ? LucideIcons.check : LucideIcons.play, size: 12),
              label: Text(action.isExecuted ? 'Выполнено' : 'Запустить', style: const TextStyle(fontSize: 10.5)),
              onPressed: action.isExecuted
                  ? null
                  : () async {
                      await agent.executeCommandAction(action);
                    },
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildInputBar(BuildContext context, QuantumAiAgentService agent) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0D14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  maxLines: 4,
                  minLines: 1,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5),
                  decoration: const InputDecoration(
                    hintText: 'Спросите AI Агента о коде или задаче...',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: (_) => _sendMessage(agent),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (agent.isGenerating)
              IconButton(
                icon: const Icon(LucideIcons.square, size: 15, color: Colors.redAccent),
                tooltip: 'Остановить',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                ),
                onPressed: () => agent.stopGeneration(),
              )
            else
              IconButton(
                icon: const Icon(LucideIcons.send, size: 15, color: Colors.white),
                tooltip: 'Отправить',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                ),
                onPressed: () => _sendMessage(agent),
              ),
          ],
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
        .replaceAll(RegExp(r'<think>[\s\S]*?<\/think>'), '')
        .trim();
  }

  void _showApiKeysDialog(BuildContext context, SettingsState settings) {
    final dsCtrl = TextEditingController(text: settings.deepseekApiKey);
    final orCtrl = TextEditingController(text: settings.openrouterApiKey);
    final oaCtrl = TextEditingController(text: settings.openaiApiKey);
    final anCtrl = TextEditingController(text: settings.anthropicApiKey);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131722),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(LucideIcons.key, color: Color(0xFFA78BFA), size: 18),
            const SizedBox(width: 8),
            Text(
              'API Ключи ИИ-Провайдеров',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ключи сохраняются локально и шифруются на устройстве:',
                style: TextStyle(color: Colors.white60, fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              _buildField('DeepSeek API Key (DEEPSEEK_API_KEY)', dsCtrl),
              const SizedBox(height: 8),
              _buildField('OpenRouter Key (доступ ко всем моделям)', orCtrl),
              const SizedBox(height: 8),
              _buildField('OpenAI Key (OPENAI_API_KEY)', oaCtrl),
              const SizedBox(height: 8),
              _buildField('Anthropic Key (ANTHROPIC_API_KEY)', anCtrl),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6), foregroundColor: Colors.white),
            onPressed: () {
              final sn = ref.read(settingsProvider.notifier);
              sn.setDeepseekApiKey(dsCtrl.text.trim());
              sn.setOpenrouterApiKey(orCtrl.text.trim());
              sn.setOpenaiApiKey(oaCtrl.text.trim());
              sn.setAnthropicApiKey(anCtrl.text.trim());
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
            color: const Color(0xFF0A0D14),
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
