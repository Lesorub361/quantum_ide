import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:path/path.dart' as p;
import 'package:xterm/xterm.dart' as xt;
import 'package:image_picker/image_picker.dart';

import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/ai_settings_dialog.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/mcp_servers_dialog.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/ai_chat_messages.dart';
import 'package:quantum_ide/core/services/mcp_service.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/system_stats_service.dart';
import 'package:quantum_ide/core/services/package_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_diff_page.dart';
import 'package:quantum_ide/core/services/local_inference_service.dart';

import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/models/chat_message.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';
import 'package:quantum_ide/core/models/ai_provider_config.dart';

final activeAiModelProvider = StateProvider<String>((ref) {
  final aiSvc = ref.read(aiServiceProvider);
  return aiSvc.selectedModel;
});

final activeAiProviderIdProvider = StateProvider<String>((ref) {
  final aiSvc = ref.read(aiServiceProvider);
  return aiSvc.selectedProviderId;
});

final availableModelsProvider = FutureProvider.family<List<String>, String>((ref, providerId) async {
  final aiSvc = ref.watch(aiServiceProvider);
  try {
    return await aiSvc.fetchAvailableModels(providerId);
  } catch (_) {
    return AiProviders.byId(providerId).defaultModels;
  }
});

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
  bool _showSlashCommands = false;
  String? _selectedImagePath;
  String? _selectedImageBase64;

  @override
  void initState() {
    super.initState();
    _aiChatController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final text = _aiChatController.text;
    if (text.startsWith('/') && text.length < 15 && !text.contains(' ')) {
      if (!_showSlashCommands) setState(() => _showSlashCommands = true);
    } else {
      if (_showSlashCommands) setState(() => _showSlashCommands = false);
    }
  }

  @override
  void dispose() {
    _aiChatController.removeListener(_onTextChanged);
    _aiChatController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file != null) {
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      setState(() {
        _selectedImagePath = file.path;
        _selectedImageBase64 = base64String;
      });
    }
  }

  void _clearImage() {
    setState(() {
      _selectedImagePath = null;
      _selectedImageBase64 = null;
    });
  }

  Widget _buildSlashCommands() {
    final commands = [
      {'cmd': '/goal', 'desc': 'Set a long-running goal for Autopilot'},
      {'cmd': '/explain', 'desc': 'Explain the active file or selected code'},
      {'cmd': '/fix', 'desc': 'Fix issues in the active file'},
      {'cmd': '/dream', 'desc': 'Generate a UI based on prompt'},
    ];
    
    final query = _aiChatController.text.substring(1).toLowerCase();
    final filtered = query.isEmpty 
        ? commands 
        : commands.where((c) => c['cmd']!.toLowerCase().contains(query)).toList();

    if (filtered.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 150),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2230),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final cmd = filtered[index];
          return InkWell(
            onTap: () {
              _aiChatController.text = '${cmd['cmd']} ';
              _aiChatController.selection = TextSelection.fromPosition(
                TextPosition(offset: _aiChatController.text.length),
              );
              setState(() => _showSlashCommands = false);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Text(
                    cmd['cmd']!,
                    style: GoogleFonts.inter(
                      color: Colors.cyanAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      cmd['desc']!,
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
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

  @override
  Widget build(BuildContext context) {
    final aiState = ref.watch(aiProvider);
    final mode = ref.watch(aiPanelModeProvider);
    final selectedAgent = ref.watch(selectedAgentProvider);
    final packages = ref.watch(packageServiceProvider);
    final editorState = ref.watch(editorProvider);
    final isMobile = MediaQuery.of(context).size.width < 800;
    final rightWidth = widget.isInline 
        ? ref.watch(rightPanelWidthProvider) 
        : (isMobile ? double.infinity : 340.0);
    final l10n = AppLocalizations.of(context)!;


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
                    l10n.chatWithAi,
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
                  onPressed: () => _showChatHistoryDialog(context, ref),
                  tooltip: l10n.chatHistory,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
                const SizedBox(width: 4),
                // New Chat Button
                IconButton(
                  icon: const Icon(LucideIcons.plus, size: 14, color: Colors.cyanAccent),
                  onPressed: () {
                    ref.read(aiProvider.notifier).startNewSession();
                  },
                  tooltip: l10n.newChat,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
                const SizedBox(width: 4),
                // Settings Button
                IconButton(
                  icon: const Icon(LucideIcons.sliders_horizontal, size: 14, color: Colors.cyanAccent),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const AISettingsDialog(),
                    );
                  },
                  tooltip: l10n.settings,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
                const SizedBox(width: 8),
                // Options menu
                _buildOptionsMenu(context, ref),
                const SizedBox(width: 4),
                // Close button
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 14, color: Colors.white60),
                  onPressed: () {
                    ref.read(rightChatPanelOpenProvider.notifier).state = false;
                  },
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
                            _buildAIModeTab(mode, AIPanelMode.chat, l10n.chat, LucideIcons.message_square),
                            _buildAIModeTab(mode, AIPanelMode.cli, l10n.agents, LucideIcons.bot),
                          ],
                        ),
                      ),

                      // Messages / Agents Content
                      Expanded(
                        child: mode == AIPanelMode.chat
                            ? Column(
                                children: [
                                  _buildStatusRow(context, ref, aiState),
                                  Expanded(child: AIChatMessages(aiState: aiState)),
                                ],
                              )
                            : _buildAIAgentsList(packages),
                      ),

                      // Proposed Actions & Input (Only in Chat Mode)
                      if (mode == AIPanelMode.chat) ...[
                        if (aiState.proposedActions.isNotEmpty)
                          _buildProposedActionsStickyPanel(aiState),
                        _buildAIChatInput(context, ref, aiState),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );

    if (widget.isInline) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E2230).withValues(alpha: 0.85),
          border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
        ),
        child: content,
      );
    }

    return Container(
      width: rightWidth,
      color: const Color(0xFF0D0F14),
      child: content,
    );
  }

  Widget _buildOptionsMenu(BuildContext context, WidgetRef ref) {
    final mcpService = ref.watch(mcpServiceProvider.notifier);
    final internetAccess = mcpService.internetAccess;
    final l10n = AppLocalizations.of(context)!;

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
                l10n.internetAccess,
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
                l10n.mcpServers,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildStatusRow(BuildContext context, WidgetRef ref, AIState aiState) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Loading status & Stop button
          Expanded(
            child: aiState.isLoading
                ? Row(
                    children: [
                      if (aiState.isAutopilot) ...[
                        InkWell(
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
                                  l10n.stop,
                                  style: GoogleFonts.inter(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ] else ...[
                        const SizedBox(
                          width: 8,
                          height: 8,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.purpleAccent,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          aiState.currentStatusMessage ?? (aiState.isAutopilot ? 'Autopilot running...' : 'Thinking...'),
                           style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : const SizedBox(),
          ),
          
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

  Widget _buildTokenBadge(AIState aiState) {
    final prompt = aiState.lastPromptTokens;
    final completion = aiState.lastCompletionTokens;
    final hasRealTokens = prompt > 0 || completion > 0;
    final displayText = hasRealTokens
        ? '$prompt↓ $completion↑'
        : '${aiState.totalTokens}';
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
          Tooltip(
            message: hasRealTokens
                ? 'Prompt: $prompt tokens | Completion: $completion tokens'
                : 'Estimated: ${aiState.totalTokens} tokens',
            child: Text(
              displayText,
              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
            ),
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
          Icon(LucideIcons.cpu, size: 12, color: cpuColor),
          const SizedBox(width: 2),
          Text(
            '${(stats.cpuUsage * 100).toStringAsFixed(0)}%',
            style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          Container(width: 1, height: 8, color: Colors.white12),
          const SizedBox(width: 4),
          Icon(LucideIcons.memory_stick, size: 12, color: ramColor),
          const SizedBox(width: 2),
          Text(
            '${(stats.ramUsage * 100).toStringAsFixed(0)}%',
            style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold),
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
                AppLocalizations.of(context)!.agentsNotInstalled,
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                AppLocalizations.of(context)!.installGeminiCliInSettings,
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
              final String cmd = pkg.id == 'antigravity-cli' ? 'agy' : pkg.id;
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
                      fontFamily: 'jetBrainsMono',
                      fontFamilyFallback: const [
                        'monospace',
                        'sans-serif',
                        'Roboto Mono',
                        'Droid Sans Mono',
                        'Noto Sans Mono',
                      ],
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
                    child: Text(AppLocalizations.of(context)!.stopAgent, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
    final l10n = AppLocalizations.of(context)!;
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
                    l10n.filesCount(fileCount),
                    style: GoogleFonts.inter(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.withChanges,
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
                      l10n.rejectAll,
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
                      l10n.acceptAll,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // File list
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
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
          width: MediaQuery.of(context).size.width * 0.75,
          height: MediaQuery.of(context).size.height * 0.5,
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

  Widget _buildQuickActionChips(BuildContext context, WidgetRef ref) {
    final chips = [
      {'label': '💡 Объяснить', 'prompt': '/explain Объясни выделенный код и данный файл'},
      {'label': '🔧 Исправить', 'prompt': '/fix Найди и исправь возможные ошибки и баги'},
      {'label': '⚡ Рефакторинг', 'prompt': '/refactor Проведи рефакторинг и оптимизируй этот код'},
      {'label': '🧪 Тесты', 'prompt': '/tests Напиши юнит-тесты для функций данного файла'},
      {'label': '📝 Документация', 'prompt': '/doc Добавь подробные docstring и комментарии'},
    ];

    return Container(
      height: 28,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 5),
        itemBuilder: (context, index) {
          final item = chips[index];
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              final promptText = item['prompt']!;
              _aiChatController.text = promptText;
              _sendMessage(context, ref);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF131824),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.cyanAccent.withValues(alpha: 0.25),
                  width: 0.8,
                ),
              ),
              child: Text(
                item['label']!,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAIChatInput(BuildContext context, WidgetRef ref, AIState aiState) {
    final l10n = AppLocalizations.of(context)!;
    final editor = ref.watch(editorProvider);
    final hasActiveFile = editor.activeFilePath != null;
    final currentFileName = editor.activeFilePath?.split('/').last ?? '';

    String dynamicHint;
    switch (aiState.interactionMode) {
      case AiInteractionMode.chat:
        dynamicHint = 'Спросите ИИ о коде... (#file:путь для контекста)';
        break;
      case AiInteractionMode.autopilot:
        dynamicHint = 'Опишите сложную задачу для агента...';
        break;
      case AiInteractionMode.refactor:
        dynamicHint = 'Что исправить в выделенном фрагменте?';
        break;
      case AiInteractionMode.plan:
        dynamicHint = 'Опишите идею проекта — ИИ составит план...';
        break;
    }

    final isInternetEnabled = ref.watch(mcpServiceProvider.notifier).internetAccess;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildQuickActionChips(context, ref),
          
          // Active file attachment indicator (above input)
          if (_attachActiveFile && hasActiveFile)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.file_code, size: 12, color: Colors.cyanAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Файл прикреплен: $currentFileName',
                      style: GoogleFonts.inter(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _attachActiveFile = false),
                    child: const Icon(LucideIcons.x, size: 12, color: Colors.white60),
                  ),
                ],
              ),
            ),
            
          // Attached image indicator
          if (_selectedImagePath != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.purpleAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(_selectedImagePath!),
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Изображение прикреплено',
                      style: GoogleFonts.inter(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                  ),
                  GestureDetector(
                    onTap: _clearImage,
                    child: const Icon(LucideIcons.x, size: 12, color: Colors.white60),
                  ),
                ],
              ),
            ),
          // Unified Premium Input Card
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF161B22).withValues(alpha: 0.8), // Glass panel background from Stitch
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1), // Stitch border
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_showSlashCommands) _buildSlashCommands(),
                // Top Row: Attachments + TextField + Send
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Attachment button (Add image / Add file)
                    PopupMenuButton<String>(
                      tooltip: 'Прикрепить файл или фото',
                      icon: const Icon(
                        LucideIcons.plus, 
                        size: 20, 
                        color: Colors.white60,
                      ),
                      color: const Color(0xFF1E2230),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      onSelected: (value) {
                        if (value == 'image') {
                          _pickImage();
                        } else if (value == 'file' && hasActiveFile) {
                          setState(() {
                            _attachActiveFile = !_attachActiveFile;
                          });
                        } else if (value == 'internet') {
                          ref.read(mcpServiceProvider.notifier).setInternetAccess(!isInternetEnabled);
                        }
                      },
                      itemBuilder: (context) => [
                        if (hasActiveFile)
                          PopupMenuItem(
                            value: 'file',
                            child: Row(
                              children: [
                                Icon(LucideIcons.paperclip, size: 14, color: _attachActiveFile ? Colors.cyanAccent : Colors.white60),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Активный файл: $currentFileName', 
                                    style: TextStyle(
                                      fontSize: 11, 
                                      color: _attachActiveFile ? Colors.cyanAccent : Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        PopupMenuItem(
                          value: 'image',
                          child: Row(
                            children: [
                              Icon(LucideIcons.image, size: 14, color: _selectedImagePath != null ? Colors.purpleAccent : Colors.white60),
                              const SizedBox(width: 8),
                              const Text('Прикрепить фото', style: TextStyle(fontSize: 11, color: Colors.white)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'internet',
                          child: Row(
                            children: [
                              Icon(isInternetEnabled ? LucideIcons.circle_check : LucideIcons.circle, size: 14, color: isInternetEnabled ? Colors.cyanAccent : Colors.white60),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l10n.internetAccess, 
                                  style: TextStyle(
                                    fontSize: 11, 
                                    color: isInternetEnabled ? Colors.cyanAccent : Colors.white,
                                    fontWeight: isInternetEnabled ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    // Borderless Text Field
                    Expanded(
                      child: TextField(
                        controller: _aiChatController,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                        maxLines: 4,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: dynamicHint,
                          hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 11.5),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Send Button
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.purpleAccent, Colors.cyanAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.purpleAccent.withValues(alpha: 0.25),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(LucideIcons.send, color: Colors.white, size: 13),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _sendMessage(context, ref),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 4),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 6),

                // Provider & Status Row
                _buildProviderRow(context, ref, aiState),
                const SizedBox(height: 4),
                // Bottom Row: Dropdowns (Mode, Model, Autonomy)
                Row(
                  children: [
                    // 1. Bot Mode selector
                    Expanded(
                      child: _buildInputPillDropdown<AiInteractionMode>(
                        context: context,
                        label: _getModeLabel(aiState.interactionMode),
                        icon: _getModeIcon(aiState.interactionMode),
                        accentColor: _getModeColor(aiState.interactionMode),
                        onSelected: (mode) {
                          ref.read(aiProvider.notifier).setInteractionMode(mode);
                        },
                        items: [
                          _buildDropdownItem(AiInteractionMode.chat, 'Чат', LucideIcons.message_square, Colors.cyanAccent),
                          _buildDropdownItem(AiInteractionMode.autopilot, 'Агент', LucideIcons.bot, Colors.orangeAccent),
                          _buildDropdownItem(AiInteractionMode.refactor, 'Редактор', LucideIcons.code, Colors.purpleAccent),
                          _buildDropdownItem(AiInteractionMode.plan, 'Планер', LucideIcons.map, Colors.tealAccent),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 2. Model Selector
                    Expanded(
                      flex: 2,
                      child: _buildModelSelectorDropdown(context, ref),
                    ),
                    const SizedBox(width: 6),
                    // 3. Autonomy selector
                    Expanded(
                      child: _buildInputPillDropdown<AiApprovalMode>(
                        context: context,
                        label: _getApprovalLabel(aiState.approvalMode),
                        icon: _getApprovalIcon(aiState.approvalMode),
                        accentColor: _getApprovalColor(aiState.approvalMode),
                        onSelected: (mode) {
                          ref.read(aiProvider.notifier).setApprovalMode(mode);
                        },
                        items: [
                          _buildDropdownItem(AiApprovalMode.manual, 'Ручной', LucideIcons.sliders_horizontal, Colors.greenAccent),
                          _buildDropdownItem(AiApprovalMode.semiAutonomous, 'Полу-авто', LucideIcons.shield_check, Colors.amberAccent),
                          _buildDropdownItem(AiApprovalMode.fullAutonomous, 'Автономно', LucideIcons.zap, Colors.redAccent),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage(BuildContext context, WidgetRef ref) async {
    final value = _aiChatController.text.trim();
    if (value.isEmpty && _selectedImageBase64 == null) return;
    
    final editor = ref.read(editorProvider);
    final hasActiveFile = editor.activeFilePath != null;
    final currentFileName = editor.activeFilePath?.split('/').last ?? '';
    final activeFile = editor.openFiles.isNotEmpty && editor.activeTabIndex < editor.openFiles.length ? editor.openFiles[editor.activeTabIndex] : null;
    final currentCode = activeFile?.controller.text ?? '';

    final lowerVal = value.toLowerCase();
    final isActionChip = lowerVal.startsWith('/fix') || 
                        lowerVal.startsWith('/refactor') || 
                        lowerVal.startsWith('/explain') || 
                        lowerVal.startsWith('/tests') || 
                        lowerVal.startsWith('/doc') ||
                        lowerVal.contains('исправь');

    final shouldIncludeFile = (_attachActiveFile || isActionChip) && hasActiveFile;

    String fullPrompt = value;
    if (shouldIncludeFile && currentCode.isNotEmpty) {
      fullPrompt = '⚠️ Рабочий файл: **$currentFileName**\n'
          'Исходный код ($currentFileName):\n```dart\n$currentCode\n```\n\n'
          'Инструкция: $value\n'
          'ОБЯЗАТЕЛЬНО: Предложи рабочий код и внеси исправления!';
    }

    List<String> contextFiles = [];
    if (shouldIncludeFile && editor.activeFilePath != null) {
      contextFiles.add(editor.activeFilePath!);
    }

    // Process @codebase / @search mentions
    final lowerPrompt = fullPrompt.toLowerCase();
    if (lowerPrompt.contains('@codebase') || lowerPrompt.contains('@search')) {
      final workspacePath = ref.read(workspaceProvider).currentPath;
      if (workspacePath != null) {
        final dir = Directory(workspacePath);
        final fileEntries = <String>[];
        if (await dir.exists()) {
          try {
            final entities = dir.listSync(recursive: true);
            for (final entity in entities) {
              if (entity is File) {
                final ext = p.extension(entity.path).toLowerCase();
                if (['.dart', '.yaml', '.json', '.md', '.gradle', '.xml'].contains(ext) &&
                    !entity.path.contains('.git/') &&
                    !entity.path.contains('.dart_tool/') &&
                    !entity.path.contains('build/')) {
                  fileEntries.add(p.relative(entity.path, from: workspacePath));
                }
              }
              if (fileEntries.length >= 30) break;
            }
          } catch (e) {
            debugPrint('Failed to scan codebase: $e');
          }
        }
        final treePreview = fileEntries.map((f) => '- $f').join('\n');
        fullPrompt = fullPrompt
            .replaceAll(RegExp(r'@codebase', caseSensitive: false), '### ИНДЕКС ФАЙЛОВ ПРОЕКТА (@codebase):\n$treePreview\n')
            .replaceAll(RegExp(r'@search', caseSensitive: false), '### ИНДЕКС ФАЙЛОВ ПРОЕКТА:\n$treePreview\n');
      }
    }

    // Process #-mentions for file context
    final mentionPattern = RegExp(r'#file:([^\s]+)', caseSensitive: false);
    final mentions = mentionPattern.allMatches(fullPrompt);
    if (mentions.isNotEmpty) {
      final workspacePath = ref.read(workspaceProvider).currentPath;
      if (workspacePath != null) {
        for (final match in mentions) {
          final filePath = match.group(1)!;
          final fullPath = filePath.startsWith('/')
              ? filePath
              : '$workspacePath/$filePath';
          final file = File(fullPath);
          if (await file.exists()) {
            contextFiles.add(fullPath);
            final content = await file.readAsString();
            final preview = content.length > 2000
                ? '${content.substring(0, 2000)}\n... (truncated)'
                : content;
            final replacement = '**File: $filePath**\n```dart\n$preview\n```';
            fullPrompt = fullPrompt.replaceAll(match.group(0)!, replacement);
          }
        }
      }
    }

    ref.read(aiProvider.notifier).askAI(
      fullPrompt,
      imageBase64: _selectedImageBase64,
      contextFiles: contextFiles.isNotEmpty ? contextFiles : null,
    );
    _aiChatController.clear();
    setState(() {
      _attachActiveFile = false;
      _selectedImagePath = null;
      _selectedImageBase64 = null;
    });
  }

  String _getModeLabel(AiInteractionMode mode) {
    switch (mode) {
      case AiInteractionMode.chat: return 'Чат';
      case AiInteractionMode.autopilot: return 'Агент';
      case AiInteractionMode.refactor: return 'Редактор';
      case AiInteractionMode.plan: return 'Планер';
    }
  }

  IconData _getModeIcon(AiInteractionMode mode) {
    switch (mode) {
      case AiInteractionMode.chat: return LucideIcons.message_square;
      case AiInteractionMode.autopilot: return LucideIcons.bot;
      case AiInteractionMode.refactor: return LucideIcons.code;
      case AiInteractionMode.plan: return LucideIcons.map;
    }
  }

  Color _getModeColor(AiInteractionMode mode) {
    switch (mode) {
      case AiInteractionMode.chat: return Colors.cyanAccent;
      case AiInteractionMode.autopilot: return Colors.orangeAccent;
      case AiInteractionMode.refactor: return Colors.purpleAccent;
      case AiInteractionMode.plan: return Colors.tealAccent;
    }
  }

  String _getApprovalLabel(AiApprovalMode mode) {
    switch (mode) {
      case AiApprovalMode.manual: return 'Ручной';
      case AiApprovalMode.semiAutonomous: return 'Полу-авто';
      case AiApprovalMode.fullAutonomous: return 'Автономно';
    }
  }

  IconData _getApprovalIcon(AiApprovalMode mode) {
    switch (mode) {
      case AiApprovalMode.manual: return LucideIcons.sliders_horizontal;
      case AiApprovalMode.semiAutonomous: return LucideIcons.shield_check;
      case AiApprovalMode.fullAutonomous: return LucideIcons.zap;
    }
  }

  Color _getApprovalColor(AiApprovalMode mode) {
    switch (mode) {
      case AiApprovalMode.manual: return Colors.greenAccent;
      case AiApprovalMode.semiAutonomous: return Colors.amberAccent;
      case AiApprovalMode.fullAutonomous: return Colors.redAccent;
    }
  }

  Widget _buildInputPillDropdown<T>({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color accentColor,
    required ValueChanged<T> onSelected,
    required List<PopupMenuEntry<T>> items,
  }) {
    return PopupMenuButton<T>(
      tooltip: '',
      color: const Color(0xFF1E2230),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: onSelected,
      itemBuilder: (context) => items,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 11, color: accentColor),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            const Icon(LucideIcons.chevron_down, size: 10, color: Colors.white30),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<T> _buildDropdownItem<T>(T value, String label, IconData icon, Color color) {
    return PopupMenuItem<T>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderRow(BuildContext context, WidgetRef ref, AIState aiState) {
    final activeProviderId = ref.watch(activeAiProviderIdProvider);
    final currentProvider = AiProviders.byId(activeProviderId);
    final localInferenceState = ref.watch(localInferenceProvider);
    final isLocalEdge = activeProviderId == 'local_edge';
    
    final statusColor = isLocalEdge
        ? (localInferenceState.status == LocalModelStatus.ready
            ? Colors.greenAccent
            : (localInferenceState.status == LocalModelStatus.loading
                ? Colors.amberAccent
                : Colors.white30))
        : Colors.cyanAccent;
    
    final statusText = isLocalEdge
        ? (localInferenceState.status == LocalModelStatus.ready
            ? '${localInferenceState.loadedModel?.name ?? "Ready"}'
            : (localInferenceState.status == LocalModelStatus.loading
                ? 'Loading...'
                : 'Stopped'))
        : currentProvider.displayName;
    
    final contextInfo = isLocalEdge && localInferenceState.status == LocalModelStatus.ready
        ? '${localInferenceState.contextTokensUsed}/${localInferenceState.contextTokensTotal} ctx'
        : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
              boxShadow: [BoxShadow(color: statusColor, blurRadius: 4, spreadRadius: 1)],
            ),
          ),
          const SizedBox(width: 6),
          Icon(currentProvider.logoEmoji.runes.first > 0x10000 ? LucideIcons.cpu : LucideIcons.cpu, size: 11, color: statusColor),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              statusText,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Context info badge
          if (contextInfo.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                contextInfo,
                style: GoogleFonts.jetBrainsMono(fontSize: 8, color: Colors.greenAccent, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 4),
          ],
          // Provider switcher
          PopupMenuButton<String>(
            tooltip: '',
            color: const Color(0xFF1E2230),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onSelected: (providerId) async {
              final aiSvc = ref.read(aiServiceProvider);
              await aiSvc.setProvider(providerId);
              ref.read(activeAiProviderIdProvider.notifier).state = providerId;
              final model = aiSvc.selectedModel;
              ref.read(activeAiModelProvider.notifier).state = model;
            },
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[];
              for (final p in AiProviders.all) {
                final isSelected = p.id == activeProviderId;
                items.add(PopupMenuItem<String>(
                  value: p.id,
                  child: Row(
                    children: [
                      Icon(isSelected ? LucideIcons.circle_check : LucideIcons.circle, size: 11, color: isSelected ? Colors.cyanAccent : Colors.white30),
                      const SizedBox(width: 8),
                      Text(p.displayName, style: GoogleFonts.inter(fontSize: 11, color: Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                    ],
                  ),
                ));
              }
              return items;
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentProvider.displayName,
                    style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: statusColor),
                  ),
                  const SizedBox(width: 2),
                  Icon(LucideIcons.chevron_down, size: 9, color: statusColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelSelectorDropdown(BuildContext context, WidgetRef ref) {
    final activeModel = ref.watch(activeAiModelProvider);
    final activeProviderId = ref.watch(activeAiProviderIdProvider);
    final localInferenceState = ref.watch(localInferenceProvider);
    
    final currentProvider = AiProviders.byId(activeProviderId);
    final isLocalEdge = activeProviderId == 'local_edge';
    
    String displayName = activeModel;
    if (displayName.startsWith('gemini-')) {
      displayName = displayName.replaceAll('gemini-', 'Gemini ');
    } else if (displayName.startsWith('gpt-')) {
      displayName = displayName.toUpperCase();
    } else if (displayName.startsWith('claude-')) {
      displayName = displayName.replaceAll('claude-', 'Claude ');
    }

    // Build combined model list: cloud models + native inference models
    final availableModelsAsync = ref.watch(availableModelsProvider(activeProviderId));
    final defaultModels = currentProvider.defaultModels;
    final List<String> cloudModels = availableModelsAsync.maybeWhen(
      data: (list) => list.isNotEmpty ? list : defaultModels,
      orElse: () => defaultModels,
    );
    
    final List<String> nativeModels = [];
    if (isLocalEdge) {
      for (final m in localInferenceState.availableModels) {
        nativeModels.add(m.filename);
      }
    }
    
    final hasNative = nativeModels.isNotEmpty;
    final isNativeActive = isLocalEdge && localInferenceState.loadedModel != null && localInferenceState.status == LocalModelStatus.ready;
    
    return PopupMenuButton<String>(
      tooltip: 'Выбрать модель',
      color: const Color(0xFF1E2230),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (val) async {
        final aiSvc = ref.read(aiServiceProvider);
        await aiSvc.setModel(val);
        ref.read(activeAiModelProvider.notifier).state = val;
        
        // If selecting a native model, load it
        if (isLocalEdge && nativeModels.contains(val)) {
          final model = localInferenceState.availableModels.firstWhere((x) => x.filename == val);
          final isDownloaded = localInferenceState.downloadedFiles.contains(model.filename);
          if (!isDownloaded) {
            await ref.read(localInferenceProvider.notifier).downloadModel(model);
          } else {
            await ref.read(localInferenceProvider.notifier).loadModel(model);
          }
        }
      },
      itemBuilder: (context) {
        final List<PopupMenuEntry<String>> items = [];
        
        // Native inference models section
        if (hasNative) {
          items.add(PopupMenuItem<String>(
            enabled: false,
            child: Row(
              children: [
                Icon(LucideIcons.smartphone, size: 10, color: Colors.greenAccent.shade100),
                const SizedBox(width: 6),
                Text(
                  'НА ТЕЛЕФОНЕ',
                  style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.greenAccent.shade100),
                ),
              ],
            ),
          ));
          
          for (final m in nativeModels) {
            final modelInfo = localInferenceState.availableModels.firstWhere((x) => x.filename == m);
            final isLoaded = localInferenceState.loadedModel?.filename == m && isNativeActive;
            items.add(PopupMenuItem<String>(
              value: m,
              child: Row(
                children: [
                  Icon(isLoaded ? LucideIcons.circle_check : LucideIcons.circle, size: 11, color: isLoaded ? Colors.greenAccent : Colors.white30),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(modelInfo.name, style: GoogleFonts.inter(fontSize: 11, color: isLoaded ? Colors.greenAccent.shade100 : Colors.white70, fontWeight: isLoaded ? FontWeight.bold : FontWeight.normal)),
                        Text('${modelInfo.size} · ${modelInfo.description}', style: GoogleFonts.inter(fontSize: 8, color: Colors.white30), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ));
          }
          
          if (cloudModels.isNotEmpty) {
            items.add(const PopupMenuDivider(height: 8));
          }
        }
        
        // Cloud/server models section
        if (cloudModels.isNotEmpty) {
          items.add(PopupMenuItem<String>(
            enabled: false,
            child: Text(
              'МОДЕЛИ: ${currentProvider.displayName.toUpperCase()}',
              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.purpleAccent.shade100),
            ),
          ));
          
          for (final m in cloudModels) {
            final isSelected = m == activeModel && !isNativeActive;
            items.add(PopupMenuItem<String>(
              value: m,
              child: Row(
                children: [
                  const Icon(LucideIcons.cpu, size: 11, color: Colors.purpleAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(m, style: GoogleFonts.inter(fontSize: 11, color: isSelected ? Colors.purpleAccent.shade100 : Colors.white70, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 4),
                    const Icon(LucideIcons.check, size: 12, color: Colors.purpleAccent),
                  ],
                ],
              ),
            ));
          }
        }
        
        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: isNativeActive ? Colors.greenAccent.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isNativeActive ? Colors.greenAccent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isNativeActive ? LucideIcons.smartphone : LucideIcons.cpu, size: 11, color: isNativeActive ? Colors.greenAccent : Colors.cyanAccent),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                displayName,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            const Icon(LucideIcons.chevron_down, size: 10, color: Colors.white30),
          ],
        ),
      ),
    );
  }

  void _showChatHistoryDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final aiState = ref.watch(aiProvider);
            final notifier = ref.read(aiProvider.notifier);
            final l10n = AppLocalizations.of(context)!;
            
            return AlertDialog(
              backgroundColor: const Color(0xFF1E2230),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(LucideIcons.history, color: Colors.cyanAccent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    l10n.chatHistory,
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
                          l10n.noHistoryFound,
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
                                session.title.isNotEmpty ? session.title : l10n.untitled,
                                style: TextStyle(
                                  color: isCurrent ? Colors.cyanAccent : Colors.white,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${l10n.messagesCount(session.messages.length)} • ${_formatDate(session.createdAt)}',
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
                  child: Text(l10n.close, style: const TextStyle(color: Colors.cyanAccent)),
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
