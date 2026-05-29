import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:path/path.dart' as p;
import 'package:xterm/xterm.dart' as xt;

import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/ai_settings_dialog.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/mcp_servers_dialog.dart';
import 'package:quantum_ide/core/services/mcp_service.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/system_stats_service.dart';
import 'package:quantum_ide/core/services/package_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/terminal_panel_content.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_diff_page.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/models/chat_message.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';
import 'package:quantum_ide/core/models/ai_provider_config.dart';

class RightChatPanel extends ConsumerStatefulWidget {
  final bool isInline;

  const RightChatPanel({
    super.key,
    required this.isInline,
  });

  @override
  ConsumerState<RightChatPanel> createState() => _RightChatPanelState();
}

class _RightChatPanelState extends ConsumerState<RightChatPanel> {
  final TextEditingController _aiChatController = TextEditingController();
  bool _attachActiveFile = false;
  bool _isResizingHovered = false;

  @override
  void dispose() {
    _aiChatController.dispose();
    // Synchronize global open provider state when panel is disposed (like when closing Drawer manually)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rightChatPanelOpenProvider.notifier).state = false;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aiState = ref.watch(aiProvider);
    final mode = ref.watch(aiPanelModeProvider);
    final selectedAgent = ref.watch(selectedAgentProvider);
    final packages = ref.watch(packageServiceProvider);
    final editorState = ref.watch(editorProvider);
    final rightWidth = widget.isInline ? ref.watch(rightPanelWidthProvider) : 340.0;
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    final content = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header of the Chat
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.purpleAccent, Colors.cyanAccent],
                  ).createShader(bounds),
                  child: const Icon(LucideIcons.bot, color: Colors.white, size: 15),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isRu ? 'ЧАТ С ИИ' : 'CHAT WITH AI',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                  ),
                ),
                // Chat History Button
                IconButton(
                  icon: const Icon(LucideIcons.history, size: 14, color: Colors.cyanAccent),
                  onPressed: () => _showChatHistoryDialog(context, ref, isRu),
                  tooltip: isRu ? 'История чатов' : 'Chat History',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                // New Chat Button
                IconButton(
                  icon: const Icon(LucideIcons.plus, size: 14, color: Colors.cyanAccent),
                  onPressed: () {
                    ref.read(aiProvider.notifier).startNewSession();
                  },
                  tooltip: isRu ? 'Новый чат' : 'New Chat',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                // Options menu
                _buildOptionsMenu(context, ref, isRu),
                const SizedBox(width: 8),
                // Close button
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 14, color: Colors.white60),
                  onPressed: () {
                    ref.read(rightChatPanelOpenProvider.notifier).state = false;
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10, indent: 8, endIndent: 8),

          // Main View switcher
          Expanded(
            child: selectedAgent != null
                ? _buildAgentTerminalView(selectedAgent, editorState)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Provider/Model Selection Card
                      _buildProviderModelCard(context, ref, isRu),

                      // Status row: Autopilot & Badges
                      _buildStatusRow(context, ref, aiState, isRu),

                      const SizedBox(height: 4),

                      // Mode Selector Tab (Chat vs Agents)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            _buildAIModeTab(mode, AIPanelMode.chat, isRu ? 'Чат' : 'Chat', LucideIcons.message_square),
                            _buildAIModeTab(mode, AIPanelMode.cli, isRu ? 'Агенты' : 'Agents', LucideIcons.bot),
                          ],
                        ),
                      ),

                      // Messages / Agents Content
                      Expanded(
                        child: mode == AIPanelMode.chat
                            ? AIChatMessages(aiState: aiState)
                            : _buildAIAgentsList(packages),
                      ),

                      // Proposed Actions & Input (Only in Chat Mode)
                      if (mode == AIPanelMode.chat) ...[
                        if (aiState.proposedActions.isNotEmpty)
                          _buildProposedActionsStickyPanel(aiState),
                        _buildAIChatInput(context, ref),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );

    if (widget.isInline) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: rightWidth,
            decoration: BoxDecoration(
              color: const Color(0xFF1E2230).withValues(alpha: 0.85),
              border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
            ),
            child: content,
          ),
          Positioned(
            left: -3,
            top: 0,
            bottom: 0,
            width: 6,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              onEnter: (_) => setState(() => _isResizingHovered = true),
              onExit: (_) => setState(() => _isResizingHovered = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
                  final currentWidth = ref.read(rightPanelWidthProvider);
                  final newWidth = (currentWidth - details.primaryDelta!).clamp(240.0, 600.0);
                  ref.read(rightPanelWidthProvider.notifier).state = newWidth;
                },
                child: Container(
                  color: _isResizingHovered ? Colors.cyanAccent.withValues(alpha: 0.4) : Colors.transparent,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return GlassContainer(
      blur: 30,
      opacity: 0.15,
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
      border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
      child: Drawer(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: content,
      ),
    );
  }

  Widget _buildOptionsMenu(BuildContext context, WidgetRef ref, bool isRu) {
    final mcpService = ref.watch(mcpServiceProvider.notifier);
    final internetAccess = mcpService.internetAccess;

    return PopupMenuButton<String>(
      icon: const Icon(LucideIcons.ellipsis_vertical, size: 14, color: Colors.white60),
      color: const Color(0xFF1E2230),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onSelected: (value) {
        if (value == 'mcp') {
          showDialog(
            context: context,
            builder: (context) => const McpServersDialog(),
          );
        } else if (value == 'internet') {
          ref.read(mcpServiceProvider.notifier).setInternetAccess(!internetAccess);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'internet',
          child: Row(
            children: [
              Icon(
                internetAccess ? LucideIcons.circle_check : LucideIcons.circle,
                size: 12,
                color: internetAccess ? Colors.cyanAccent : Colors.white54,
              ),
              const SizedBox(width: 8),
              Text(
                isRu ? 'Доступ в интернет' : 'Internet Access',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'mcp',
          child: Row(
            children: [
              const Icon(LucideIcons.terminal, size: 12, color: Colors.cyanAccent),
              const SizedBox(width: 8),
              Text(
                isRu ? 'MCP Серверы' : 'MCP Servers',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProviderModelCard(BuildContext context, WidgetRef ref, bool isRu) {
    final aiSvc = ref.watch(aiServiceProvider);
    final provider = AiProviders.byId(aiSvc.selectedProviderId);

    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => const AISettingsDialog(),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Text(provider.logoEmoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.displayName,
                    style: GoogleFonts.inter(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    aiSvc.selectedModel,
                    style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.cyanAccent, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevron_down, size: 12, color: Colors.cyanAccent),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(BuildContext context, WidgetRef ref, AIState aiState, bool isRu) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Autopilot Approval Mode
          _buildAutopilotModeBadge(context, ref, aiState, isRu),
          
          // Token and System Stats Badges
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTokenBadge(aiState),
              const SizedBox(width: 4),
              _buildSystemStatsBadge(ref),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAutopilotModeBadge(BuildContext context, WidgetRef ref, AIState aiState, bool isRu) {
    if (aiState.isLoading && aiState.isAutopilot) {
      return InkWell(
        onTap: () => ref.read(aiProvider.notifier).stopAutopilot(),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.8), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.square, size: 10, color: Colors.redAccent),
              const SizedBox(width: 4),
              Text(
                isRu ? 'Стоп' : 'Stop',
                style: GoogleFonts.inter(fontSize: 9, color: Colors.redAccent, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    IconData modeIcon;
    Color modeColor;
    String modeLabel;
    
    switch (aiState.approvalMode) {
      case AiApprovalMode.manual:
        modeIcon = LucideIcons.user;
        modeColor = Colors.white38;
        modeLabel = isRu ? 'Ручной' : 'Manual';
        break;
      case AiApprovalMode.semiAutonomous:
        modeIcon = LucideIcons.bot;
        modeColor = Colors.purpleAccent;
        modeLabel = isRu ? 'Авто:Безопасный' : 'Auto:Safe';
        break;
      case AiApprovalMode.fullAutonomous:
        modeIcon = LucideIcons.zap;
        modeColor = Colors.orangeAccent;
        modeLabel = isRu ? 'Авто:Полный' : 'Auto:Full';
        break;
    }

    return PopupMenuButton<AiApprovalMode>(
      onSelected: (mode) {
        ref.read(aiProvider.notifier).setApprovalMode(mode);
      },
      color: const Color(0xFF1E2230),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: AiApprovalMode.manual,
          child: Row(
            children: [
              const Icon(LucideIcons.user, size: 12, color: Colors.white54),
              const SizedBox(width: 8),
              Text(isRu ? 'Ручной режим' : 'Manual Mode', style: const TextStyle(color: Colors.white, fontSize: 11)),
            ],
          ),
        ),
        PopupMenuItem(
          value: AiApprovalMode.semiAutonomous,
          child: Row(
            children: [
              const Icon(LucideIcons.bot, size: 12, color: Colors.purpleAccent),
              const SizedBox(width: 8),
              Text(isRu ? 'Безопасный автопилот' : 'Safe Autopilot', style: const TextStyle(color: Colors.white, fontSize: 11)),
            ],
          ),
        ),
        PopupMenuItem(
          value: AiApprovalMode.fullAutonomous,
          child: Row(
            children: [
              const Icon(LucideIcons.zap, size: 12, color: Colors.orangeAccent),
              const SizedBox(width: 8),
              Text(isRu ? 'Полная автономность' : 'Full Autonomy', style: const TextStyle(color: Colors.white, fontSize: 11)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: modeColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: modeColor.withValues(alpha: 0.8), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(modeIcon, size: 10, color: modeColor),
            const SizedBox(width: 4),
            Text(
              modeLabel,
              style: GoogleFonts.inter(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTokenBadge(AIState aiState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.purpleAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.coins, size: 10, color: Colors.purpleAccent),
          const SizedBox(width: 4),
          Text(
            '${aiState.totalTokens}',
            style: GoogleFonts.jetBrainsMono(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemStatsBadge(WidgetRef ref) {
    final stats = ref.watch(systemStatsProvider);
    final cpuColor = _getStatsBadgeColor(stats.cpuUsage);
    final ramColor = _getStatsBadgeColor(stats.ramUsage);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.cpu, size: 10, color: cpuColor),
          const SizedBox(width: 2),
          Text(
            '${(stats.cpuUsage * 100).toStringAsFixed(0)}%',
            style: GoogleFonts.jetBrainsMono(fontSize: 8, color: Colors.white70, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          Container(width: 1, height: 6, color: Colors.white12),
          const SizedBox(width: 4),
          Icon(LucideIcons.memory_stick, size: 10, color: ramColor),
          const SizedBox(width: 2),
          Text(
            '${(stats.ramUsage * 100).toStringAsFixed(0)}%',
            style: GoogleFonts.jetBrainsMono(fontSize: 8, color: Colors.white70, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Color _getStatsBadgeColor(double value) {
    if (value < 0.6) return Colors.greenAccent;
    if (value < 0.85) return Colors.amberAccent;
    return Colors.redAccent;
  }

  Widget _buildAIModeTab(AIPanelMode current, AIPanelMode target, String label, IconData icon) {
    final isSelected = current == target;
    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(aiPanelModeProvider.notifier).state = target,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: isSelected ? Colors.cyanAccent : Colors.white38),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: isSelected ? Colors.white : Colors.white38,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAIAgentsList(List<dynamic> packages) {
    final agents = packages.where((p) => p.isInstalled && (p.id.contains('cli') || p.id.contains('ai'))).toList();

    if (agents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.package_search, size: 36, color: Colors.white.withValues(alpha: 0.1)),
              const SizedBox(height: 12),
              Text(
                'Агенты не установлены',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                'Установите gemini-cli в настройках',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white24, fontSize: 10),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: agents.length,
      itemBuilder: (context, index) {
        final pkg = agents[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            leading: const Icon(LucideIcons.bot, color: Colors.cyanAccent, size: 16),
            title: Text(pkg.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)),
            subtitle: Text(pkg.id, style: GoogleFonts.inter(fontSize: 9, color: Colors.white38)),
            trailing: const Icon(LucideIcons.chevron_right, color: Colors.white24, size: 14),
            onTap: () {
              ref.read(selectedAgentProvider.notifier).state = pkg.name;
              String cmd = pkg.id == 'gemini-cli' ? 'gemini chat' : pkg.id;
              ref.read(editorProvider.notifier).runAgentCommand(cmd);
            },
          ),
        );
      },
    );
  }

  Widget _buildAgentTerminalView(String agentName, EditorState state) {
    final terminalFontSize = ref.watch(settingsProvider).terminalFontSize;
    final terminalThemeName = ref.watch(settingsProvider).terminalTheme;
    final theme = _getTerminalTheme(terminalThemeName);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Colors.black12,
          child: Row(
            children: [
              Text(agentName, style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11)),
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.undo_2, size: 14, color: Colors.white60),
                onPressed: () => ref.read(selectedAgentProvider.notifier).state = null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            clipBehavior: Clip.antiAlias,
            child: state.aiXtermTerminal == null
                ? const Center(child: CircularProgressIndicator(color: Colors.purpleAccent))
                : xt.TerminalView(
                    state.aiXtermTerminal!,
                    controller: state.aiXtermViewController,
                    autofocus: true,
                    theme: theme,
                    backgroundOpacity: 0,
                    textStyle: xt.TerminalStyle(
                      fontSize: terminalFontSize * 0.9,
                      fontFamily: GoogleFonts.jetBrainsMono().fontFamily ?? 'monospace',
                    ),
                    keyboardType: TextInputType.visiblePassword,
                    deleteDetection: true,
                  ),
          ),
        ),
        if (state.isAgentRunning)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                      foregroundColor: Colors.redAccent,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                      ),
                    ),
                    onPressed: () => ref.read(editorProvider.notifier).stopAgent(),
                    child: const Text('ОСТАНОВИТЬ АГЕНТА', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  xt.TerminalTheme _getTerminalTheme(String themeName) {
    Color bg;
    Color fg = Colors.white;
    switch (themeName) {
      case 'dracula':
        bg = const Color(0xFF282A36);
        fg = const Color(0xFFF8F8F2);
        break;
      case 'monokai':
        bg = const Color(0xFF272822);
        fg = const Color(0xFFF8F8F2);
        break;
      case 'dark':
        bg = const Color(0xFF0D0F14);
        fg = const Color(0xFFE0E0E0);
        break;
      case 'ubuntu':
      default:
        bg = const Color(0xFF300A24);
        fg = Colors.white;
        break;
    }

    return xt.TerminalTheme(
      cursor: fg,
      selection: fg.withValues(alpha: 0.25),
      foreground: fg,
      background: bg,
      black: Colors.black,
      red: const Color(0xFFCC0000),
      green: const Color(0xFF4E9A06),
      yellow: const Color(0xFFC4A000),
      blue: const Color(0xFF3465A4),
      magenta: const Color(0xFF75507B),
      cyan: const Color(0xFF06989A),
      white: const Color(0xFFD3D7CF),
      brightBlack: const Color(0xFF555753),
      brightRed: const Color(0xFFEF2929),
      brightGreen: const Color(0xFF8AE234),
      brightYellow: const Color(0xFFFCE94F),
      brightBlue: const Color(0xFF729FCF),
      brightMagenta: const Color(0xFFAD7FA8),
      brightCyan: const Color(0xFF34E2E2),
      brightWhite: const Color(0xFFEEEEEC),
      searchHitBackground: Colors.yellow,
      searchHitBackgroundCurrent: Colors.orange,
      searchHitForeground: Colors.black,
    );
  }

  Widget _buildProposedActionsStickyPanel(AIState aiState) {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final fileCount = aiState.proposedActions.where((a) => a.type != 'command').length;
    
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12151F),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row — VS Code style
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
            ),
            child: Row(
              children: [
                // File count badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '$fileCount ${isRu ? (fileCount == 1 ? 'файл' : fileCount < 5 ? 'файла' : 'файлов') : (fileCount == 1 ? 'file' : 'files')}',
                    style: GoogleFonts.inter(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isRu ? 'с изменениями' : 'with changes',
                  style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
                ),
                const Spacer(),
                // Reject All
                InkWell(
                  onTap: () {
                    for (final action in List<AIAction>.from(aiState.proposedActions)) {
                      ref.read(aiProvider.notifier).removeAction(action);
                    }
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      isRu ? 'Отклонить все' : 'Reject all',
                      style: GoogleFonts.inter(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Accept All — VS Code blue button
                InkWell(
                  onTap: () async {
                    await ref.read(aiProvider.notifier).executeActionsManually(aiState.proposedActions);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E6FE6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isRu ? 'Принять все' : 'Accept all',
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // File list — no height limit
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: aiState.proposedActions.length,
              itemBuilder: (context, index) {
                final action = aiState.proposedActions[index];
                return AIActionFileItem(
                  action: action,
                  onShowDiff: () => _showDiffDialog(action),
                  onRemove: () => ref.read(aiProvider.notifier).removeAction(action),
                );
              },
            ),
          ),
        ],
      ),
    );
  }


  void _showDiffDialog(AIAction action) async {
    final file = File(action.path);
    String originalContent = '';
    if (await file.exists()) {
      originalContent = await file.readAsString();
    }

    if (!mounted) return;

    final workspacePath = ref.read(workspaceProvider).currentPath;
    final relPath = (workspacePath != null && action.path.startsWith(workspacePath))
        ? p.relative(action.path, from: workspacePath)
        : action.path;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D27),
        title: Text(AppLocalizations.of(context)!.changesInFile(action.path.split('/').last), style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.7,
          child: GitDiffPage(
            relativePath: relPath, 
            initiallyStaged: false,
            originalOverride: originalContent,
            previewContent: action.content,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.close)),
          ElevatedButton(
            onPressed: () {
              ref.read(aiProvider.notifier).applyAction(action);
              Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context)!.apply),
          ),
        ],
      ),
    );
  }

  Widget _buildAIChatInput(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final aiSvc = ref.watch(aiServiceProvider);
    final provider = AiProviders.byId(aiSvc.selectedProviderId);
    final editor = ref.watch(editorProvider);
    final hasActiveFile = editor.activeFilePath != null;
    final currentFileName = editor.activeFilePath?.split('/').last ?? '';
    final activeFile = editor.openFiles.isNotEmpty ? editor.openFiles[editor.activeTabIndex] : null;
    final currentCode = activeFile?.controller.text ?? "";

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_attachActiveFile && hasActiveFile)
            GestureDetector(
              onTap: () {
                setState(() {
                  _attachActiveFile = false;
                });
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.file_code, size: 12, color: Colors.cyanAccent),
                    const SizedBox(width: 4),
                    Text(
                      currentFileName,
                      style: GoogleFonts.inter(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 4),
                    const Icon(LucideIcons.x, size: 10, color: Colors.white60),
                  ],
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: TextField(
              controller: _aiChatController,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              maxLines: 4,
              minLines: 1,
              decoration: InputDecoration(
                hintText: l10n.askAiHint(provider.displayName),
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                prefixIcon: hasActiveFile
                    ? IconButton(
                        icon: Icon(
                          LucideIcons.paperclip,
                          color: _attachActiveFile ? Colors.cyanAccent : Colors.white38,
                          size: 15,
                        ),
                        onPressed: () {
                          setState(() {
                            _attachActiveFile = !_attachActiveFile;
                          });
                        },
                        tooltip: Localizations.localeOf(context).languageCode == 'ru'
                            ? 'Прикрепить открытый файл'
                            : 'Attach open file',
                      )
                    : null,
                suffixIcon: IconButton(
                  icon: const Icon(LucideIcons.send, color: Colors.purpleAccent, size: 15),
                  onPressed: () {
                    final value = _aiChatController.text;
                    if (value.isEmpty) return;

                    final fullPrompt = (_attachActiveFile && hasActiveFile)
                        ? l10n.workingOnFile(currentFileName, currentCode, value)
                        : value;

                    ref.read(aiProvider.notifier).askAI(fullPrompt);
                    _aiChatController.clear();
                    setState(() {
                      _attachActiveFile = false;
                    });
                  },
                ),
              ),
              onSubmitted: (value) {
                if (value.isEmpty) return;

                final fullPrompt = (_attachActiveFile && hasActiveFile)
                    ? l10n.workingOnFile(currentFileName, currentCode, value)
                    : value;

                ref.read(aiProvider.notifier).askAI(fullPrompt);
                _aiChatController.clear();
                setState(() {
                  _attachActiveFile = false;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showChatHistoryDialog(BuildContext context, WidgetRef ref, bool isRu) {
    showDialog(
      context: context,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final aiState = ref.watch(aiProvider);
            final notifier = ref.read(aiProvider.notifier);
            
            return AlertDialog(
              backgroundColor: const Color(0xFF1E2230),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(LucideIcons.history, color: Colors.cyanAccent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    isRu ? 'История чатов' : 'Chat History',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                height: 400,
                child: aiState.sessions.isEmpty
                    ? Center(
                        child: Text(
                          isRu ? 'История пуста' : 'No history found',
                          style: const TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        itemCount: aiState.sessions.length,
                        itemBuilder: (context, index) {
                          final session = aiState.sessions[index];
                          final isCurrent = session.id == aiState.currentSessionId;
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isCurrent 
                                  ? Colors.cyanAccent.withValues(alpha: 0.08) 
                                  : Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isCurrent 
                                    ? Colors.cyanAccent.withValues(alpha: 0.3) 
                                    : Colors.white.withValues(alpha: 0.05),
                              ),
                            ),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                session.title.isNotEmpty ? session.title : (isRu ? 'Без названия' : 'Untitled'),
                                style: TextStyle(
                                  color: isCurrent ? Colors.cyanAccent : Colors.white,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${session.messages.length} ${isRu ? "сообщений" : "messages"} • ${_formatDate(session.createdAt)}',
                                style: const TextStyle(color: Colors.white30, fontSize: 9.5),
                              ),
                              onTap: () {
                                notifier.selectSession(session.id);
                                Navigator.pop(context);
                              },
                              trailing: IconButton(
                                icon: const Icon(LucideIcons.trash_2, size: 14, color: Colors.redAccent),
                                onPressed: () {
                                  notifier.deleteSession(session.id);
                                },
                              ),
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(isRu ? 'Закрыть' : 'Close', style: const TextStyle(color: Colors.cyanAccent)),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
