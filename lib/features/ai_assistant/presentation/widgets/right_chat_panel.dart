import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/ai_settings_dialog.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/cli_agent_settings_dialog.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/mcp_servers_dialog.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/ai_chat_messages.dart';
import 'package:quantum_ide/core/services/mcp_service.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/system_stats_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_diff_page.dart';

import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/models/chat_message.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';
import 'package:quantum_ide/core/models/agent_activity_item.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/agent_activity_widgets.dart';
import 'package:quantum_ide/core/models/ai_provider_config.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/model_selection_sheet.dart';
import 'package:quantum_ide/core/services/cli_installer_service.dart';

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
  bool _isSendingMessage = false;
  String? _selectedImagePath;
  String? _selectedImageBase64;

  @override
  void initState() {
    super.initState();
    _aiChatController.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cliInstallerProvider.notifier).refreshInstalledAgents();
    });
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

  String _getContextWindowLabel(String model) {
    final lower = model.toLowerCase();
    if (lower.contains('gemini')) return '1M';
    if (lower.contains('claude')) return '200k';
    if (lower.contains('deepseek')) return '128k';
    return '128k';
  }

  String _formatTokenCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '$count';
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
      {'cmd': '/plan', 'desc': 'Составить пошаговый план разработки'},
      {'cmd': '/clear', 'desc': 'Сбросить контекст диалога и начать сначала'},
      {'cmd': '/diff', 'desc': 'Показать diff текущих изменений файлов'},
      {'cmd': '/rollback', 'desc': 'Откатить изменения проекта (Git)'},
      {'cmd': '/explain', 'desc': 'Объяснить код открытого файла'},
      {'cmd': '/fix', 'desc': 'Найти и исправить ошибки в активном файле'},
      {'cmd': '/init', 'desc': 'Создать конфигурацию .quantum/AGENTS.md'},
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
    final isMobile = MediaQuery.of(context).size.width < 800;
    final rightWidth = widget.isInline 
        ? ref.watch(rightPanelWidthProvider) 
        : (isMobile ? double.infinity : 360.0);
    final content = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Top Bar: Title + Status + Settings + Close
          _buildChatHeader(context, ref, aiState),

          // 2. Visible Provider & Model Selector Bar
          _buildProviderAndModelBar(context, ref, aiState),

          const Divider(height: 1, color: Colors.white10),

          // 3. Live Agent Process Banner (if running)
          if (aiState.isLoading)
            _buildLiveAgentStatusBanner(context, ref, aiState)
          else
            _buildStatusRow(context, ref, aiState),

          // 4. Main Chat Messages or Welcome Hero
          Expanded(
            child: aiState.messages.isEmpty
                ? _buildEmptyAgentHero(context, ref, aiState)
                : AIChatMessages(aiState: aiState),
          ),

          // 5. Proposed Actions Sticky Panel (if any)
          if (aiState.proposedActions.isNotEmpty)
            _buildProposedActionsStickyPanel(aiState),

          // 6. Input Card
          _buildChatInput(context, ref, aiState),
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

  Widget _buildChatHeader(BuildContext context, WidgetRef ref, AIState aiState) {
    final l10n = AppLocalizations.of(context)!;
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 10, vertical: isMobile ? 4 : 6),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.purpleAccent, Colors.cyanAccent],
                  ).createShader(bounds),
                  child: const Icon(LucideIcons.sparkles, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 6),
                Text(
                  'Quantum AI',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: _buildAgentSelector(context, ref, aiState.activeAgentKind),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Action Buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // New Chat Button
              IconButton(
                icon: const Icon(LucideIcons.plus, size: 14, color: Colors.cyanAccent),
                onPressed: () => ref.read(aiProvider.notifier).startNewSession(),
                tooltip: l10n.newChat,
                padding: const EdgeInsets.all(5),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              // History Button
              if (!isMobile || MediaQuery.of(context).size.width >= 390)
                IconButton(
                  icon: const Icon(LucideIcons.history, size: 14, color: Colors.white70),
                  onPressed: () => _showChatHistoryDialog(context, ref),
                  tooltip: l10n.chatHistory,
                  padding: const EdgeInsets.all(5),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              // Settings Button (AISettingsDialog / CliAgentSettingsDialog)
              IconButton(
                icon: const Icon(LucideIcons.sliders_horizontal, size: 14, color: Colors.white70),
                onPressed: () {
                  if (aiState.activeAgentKind != AgentKind.native) {
                    CliAgentSettingsDialog.show(context, initialKind: aiState.activeAgentKind);
                  } else {
                    showDialog(
                      context: context,
                      builder: (context) => const AISettingsDialog(),
                    );
                  }
                },
                tooltip: aiState.activeAgentKind != AgentKind.native ? 'Настройки CLI-агентов' : l10n.settings,
                padding: const EdgeInsets.all(5),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              // Options menu
              _buildOptionsMenu(context, ref),
              // Close button
              IconButton(
                icon: const Icon(LucideIcons.x, size: 14, color: Colors.white60),
                onPressed: () {
                  ref.read(rightChatPanelOpenProvider.notifier).state = false;
                },
                padding: const EdgeInsets.all(5),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAgentSelector(BuildContext context, WidgetRef ref, AgentKind currentKind) {
    return PopupMenuButton<String>(
      tooltip: 'Выбрать AI-агента',
      offset: const Offset(0, 28),
      color: const Color(0xFF1E2230),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      onSelected: (value) {
        if (value == 'settings') {
          CliAgentSettingsDialog.show(context, initialKind: currentKind);
        } else {
          final kind = AgentKind.values.firstWhere(
            (k) => k.name == value,
            orElse: () => AgentKind.native,
          );
          ref.read(aiProvider.notifier).setAgentKind(kind);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: currentKind.brandColor.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: currentKind.brandColor.withValues(alpha: 0.4),
            width: 0.9,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(currentKind.icon, size: 11, color: currentKind.brandColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                currentKind == AgentKind.native ? 'Native AI' : currentKind.title,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: currentKind.brandColor.withValues(alpha: 0.95),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              LucideIcons.chevron_down,
              size: 10,
              color: currentKind.brandColor.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        ...AgentKind.values.map((kind) {
          final isSelected = kind == currentKind;
          return PopupMenuItem<String>(
            value: kind.name,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: kind.brandColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(kind.icon, size: 13, color: kind.brandColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        kind == AgentKind.native ? 'Quantum Native AI' : kind.title,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? kind.brandColor : Colors.white,
                        ),
                      ),
                      Text(
                        kind.subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          color: Colors.white54,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(LucideIcons.check, size: 14, color: kind.brandColor),
              ],
            ),
          );
        }),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(LucideIcons.sliders_horizontal, size: 13, color: Colors.cyanAccent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Настройки CLI-агентов...',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.cyanAccent,
                      ),
                    ),
                    Text(
                      'API-ключи, модели, установка',
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getDefaultModelForAgent(AgentKind kind) {
    switch (kind) {
      case AgentKind.antigravity:
        return 'gemini-3.8-flash-high';
      case AgentKind.claudeCode:
        return 'claude-3-7-sonnet-20250219';
      case AgentKind.deepseekHarness:
        return 'deepseek-chat';
      case AgentKind.native:
        return '';
    }
  }

  void _showCliAgentModelPicker(BuildContext context, WidgetRef ref, AgentKind kind) {
    List<String> models;
    switch (kind) {
      case AgentKind.antigravity:
        models = [
          'gemini-3.8-flash-high',
          'gemini-3.8-flash-medium',
          'gemini-3.8-flash-low',
          'gemini-3.7-flash-high',
          'gemini-3.1-pro-high',
          'claude-sonnet-4-6',
          'claude-opus-4-6-thinking',
          'gpt-oss-120b-medium',
        ];
        break;
      case AgentKind.claudeCode:
        models = [
          'claude-3-7-sonnet-20250219',
          'claude-3-5-sonnet-20241022',
          'claude-3-5-haiku-20241022',
          'anthropic/claude-3.7-sonnet',
          'deepseek/deepseek-chat',
        ];
        break;
      case AgentKind.deepseekHarness:
        models = [
          'deepseek-chat',
          'deepseek-reasoner',
          'google/gemma-4-31b-it:free',
          'meta-llama/llama-3.3-70b-instruct',
        ];
        break;
      case AgentKind.native:
        return;
    }

    final currentModel = ref.read(activeAiModelProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131824),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(kind.icon, size: 16, color: kind.brandColor),
                        const SizedBox(width: 8),
                        Text(
                          'Модели ${kind.title}',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 16, color: Colors.white54),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: models.length,
                    separatorBuilder: (_, _) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (_, index) {
                      final m = models[index];
                      final isSelected = m == currentModel;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        title: Text(
                          m,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? kind.brandColor : Colors.white,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(LucideIcons.check, size: 14, color: kind.brandColor)
                            : null,
                        onTap: () {
                          ref.read(activeAiModelProvider.notifier).state = m;
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProviderAndModelBar(BuildContext context, WidgetRef ref, AIState aiState) {
    final activeProviderId = ref.watch(activeAiProviderIdProvider);
    final activeModel = ref.watch(activeAiModelProvider);
    final currentProvider = AiProviders.byId(activeProviderId);
    final aiSvc = ref.watch(aiServiceProvider);
    final isCliAgent = aiState.activeAgentKind != AgentKind.native;
    final agentKind = aiState.activeAgentKind;

    final String effectiveModel = activeModel.isNotEmpty 
        ? activeModel 
        : (isCliAgent ? _getDefaultModelForAgent(agentKind) : aiSvc.selectedModel);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF131824),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.8),
      ),
      child: Row(
        children: [
          if (isCliAgent) ...[
            InkWell(
              onTap: () => CliAgentSettingsDialog.show(context, initialKind: agentKind),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                decoration: BoxDecoration(
                  color: agentKind.brandColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: agentKind.brandColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(agentKind.icon, size: 11, color: agentKind.brandColor),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: Text(
                        agentKind.title,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: agentKind.brandColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(LucideIcons.sliders_horizontal, size: 9, color: agentKind.brandColor.withValues(alpha: 0.8)),
                  ],
                ),
              ),
            ),
          ] else ...[
            // 1. Universal Provider Selector Dropdown Chip with all providers
            PopupMenuButton<String>(
              tooltip: 'Сменить AI-провайдера',
              color: const Color(0xFF1E2230),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Colors.white12),
              ),
              onSelected: (pId) async {
                await ref.read(aiServiceProvider).setProvider(pId);
                ref.read(activeAiProviderIdProvider.notifier).state = pId;
                final newModel = ref.read(aiServiceProvider).selectedModel;
                ref.read(activeAiModelProvider.notifier).state = newModel;
              },
              itemBuilder: (ctx) => [
                for (final p in AiProviders.all)
                  PopupMenuItem<String>(
                    value: p.id,
                    child: Row(
                      children: [
                        Text(p.logoEmoji, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.displayName,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: p.id == activeProviderId ? FontWeight.bold : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (p.id == activeProviderId) ...[
                          const SizedBox(width: 4),
                          const Icon(LucideIcons.check, size: 12, color: Colors.cyanAccent),
                        ],
                      ],
                    ),
                  ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(currentProvider.logoEmoji, style: const TextStyle(fontSize: 11)),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 100),
                      child: Text(
                        currentProvider.displayName,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFD8B4FE),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(LucideIcons.chevron_down, size: 10, color: Color(0xFF8B5CF6)),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(width: 8),
          Container(width: 1, height: 12, color: Colors.white12),
          const SizedBox(width: 8),

          // 2. Model Selector (Searchable, API discovery, Custom Model ID)
          Text(
            'Модель:',
            style: GoogleFonts.inter(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              onTap: () async {
                if (isCliAgent) {
                  _showCliAgentModelPicker(context, ref, agentKind);
                } else {
                  final apiKey = ref.read(aiServiceProvider).getApiKey(activeProviderId);
                  final selected = await showModelPickerModal(
                    context,
                    providerId: activeProviderId,
                    currentModel: effectiveModel,
                    apiKey: apiKey,
                  );
                  if (selected != null && selected.isNotEmpty) {
                    ref.read(activeAiModelProvider.notifier).state = selected;
                    await ref.read(aiServiceProvider).setModel(selected);
                  }
                }
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        effectiveModel,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: effectiveModel.endsWith(':free') ? const Color(0xFF10B981) : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(LucideIcons.chevron_down, size: 10, color: Colors.white60),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),
          // Status indicator dot
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: aiState.isLoading ? Colors.amberAccent : Colors.greenAccent,
              boxShadow: [
                BoxShadow(
                  color: (aiState.isLoading ? Colors.amberAccent : Colors.greenAccent).withValues(alpha: 0.6),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }





  Widget _buildLiveAgentStatusBanner(BuildContext context, WidgetRef ref, AIState aiState) {
    final elapsedSec = aiState.taskStartedAt != null
        ? DateTime.now().difference(aiState.taskStartedAt!).inSeconds
        : 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1528),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const AnimatedThinkingDots(dotColor: Colors.purpleAccent, size: 4),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              aiState.currentStatusMessage ?? 'AI Ассистент выполняет задачу...',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.purpleAccent, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (elapsedSec > 0) ...[
            Text(
              '${elapsedSec}s',
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white38),
            ),
            const SizedBox(width: 8),
          ],
          InkWell(
            onTap: () => ref.read(aiProvider.notifier).stopActiveAgent(),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.square, size: 9, color: Colors.redAccent),
                  const SizedBox(width: 4),
                  Text(
                    'Остановить',
                    style: GoogleFonts.inter(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyAgentHero(BuildContext context, WidgetRef ref, AIState aiState) {
    final kind = aiState.activeAgentKind;
    final isCli = kind != AgentKind.native;

    final heroTitle = isCli ? kind.title : 'Quantum AI Ассистент';
    final heroSubtitle = isCli 
        ? kind.subtitle
        : 'Интеллектуальный помощник для кодовой базы. Анализирует файлы, пишет код, исправляет ошибки и отвечает на вопросы.';
    final heroIcon = kind.icon;
    final heroColor = kind.brandColor;

    List<String> promptChips;
    switch (kind) {
      case AgentKind.antigravity:
        promptChips = [
          '🛠️ Проанализируй проект и найди ошибки',
          '📝 Напиши модульные тесты для логики',
          '⚡ Реализуй недостающий функционал',
          '🐛 Исправь проблемы сборки и линтера',
        ];
        break;
      case AgentKind.claudeCode:
        promptChips = [
          '🔍 Проведи архитектурный аудит проекта',
          '⚡ Отрефактори код и очисти дубликаты',
          '🧪 Напиши тесты для моделей и сервисов',
          '🛠️ Исправь баги и улучши производительность',
        ];
        break;
      case AgentKind.deepseekHarness:
        promptChips = [
          '🧠 Составь план реализации новой фичи',
          '🐛 Найди утечки памяти и логические ошибки',
          '⚡ Оптимизируй алгоритмы и зависимости',
          '📝 Прокомментируй и документируй код',
        ];
        break;
      case AgentKind.native:
        promptChips = [
          '🧪 Запусти тесты и исправь ошибки',
          '🔍 Проанализируй проект и напиши план',
          '⚡ Оптимизируй код и удали неиспользуемое',
          '🐛 Найди возможные утечки памяти и баги',
        ];
        break;
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [heroColor, Colors.cyanAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: heroColor.withValues(alpha: 0.35),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(heroIcon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              heroTitle,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              heroSubtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Colors.white54,
                height: 1.4,
              ),
            ),
            // Prominent Agent Selector Cards (instantly shows installed status & switch)
            _buildAgentSelectorCardGrid(context, ref, aiState),
            if (isCli) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => CliAgentSettingsDialog.show(context, initialKind: kind),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: heroColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: heroColor.withValues(alpha: 0.4), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.sliders_horizontal, size: 11, color: heroColor),
                      const SizedBox(width: 5),
                      Text(
                        'Настроить ${kind.title}',
                        style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: heroColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: promptChips.map((c) => _buildPromptChip(c, ref)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentSelectorCardGrid(BuildContext context, WidgetRef ref, AIState aiState) {
    final installer = ref.watch(cliInstallerProvider);
    final activeKind = aiState.activeAgentKind;

    final agents = [
      (AgentKind.antigravity, 'Antigravity CLI', 'Gemini Code Assist', LucideIcons.sparkles, Colors.purpleAccent),
      (AgentKind.claudeCode, 'Claude Code', 'Anthropic Agent', LucideIcons.bot, Colors.amberAccent),
      (AgentKind.deepseekHarness, 'DeepSeek Harness', 'Open DeepSeek', LucideIcons.brain_circuit, Colors.cyanAccent),
      (AgentKind.native, 'Native AI', 'Quantum Assistant', LucideIcons.cpu, const Color(0xFF8B5CF6)),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Доступные ИИ-агенты:',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                    letterSpacing: 0.3,
                  ),
                ),
                InkWell(
                  onTap: () => CliAgentSettingsDialog.show(context, initialKind: activeKind),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.sliders_horizontal, size: 11, color: Colors.cyanAccent),
                      const SizedBox(width: 4),
                      Text(
                        'Настройки CLI',
                        style: GoogleFonts.inter(fontSize: 10.5, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: agents.map((agentData) {
                final kind = agentData.$1;
                final title = agentData.$2;
                final subtitle = agentData.$3;
                final icon = agentData.$4;
                final color = agentData.$5;

                final isSelected = activeKind == kind;
                final isInstalled = kind == AgentKind.native || installer.installedVersions[kind] != null;
                final version = installer.installedVersions[kind];

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () {
                      ref.read(aiProvider.notifier).setAgentKind(kind);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 140,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isSelected ? color.withValues(alpha: 0.16) : const Color(0xFF161B26),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? color : Colors.white.withValues(alpha: 0.08),
                          width: isSelected ? 1.5 : 0.8,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(icon, size: 14, color: color),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isInstalled ? Colors.greenAccent : Colors.white24).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isInstalled ? (version != null && version != 'installed' ? '✅ $version' : '✅ Готов') : '🔴 Не устан.',
                                  style: GoogleFonts.inter(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                    color: isInstalled ? Colors.greenAccent : Colors.white54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            title,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: GoogleFonts.inter(fontSize: 9.5, color: Colors.white54),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected ? color.withValues(alpha: 0.25) : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              isSelected ? '✓ Выбран' : 'Выбрать',
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? color : Colors.white38,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptChip(String label, WidgetRef ref) {
    return InkWell(
      onTap: () {
        _aiChatController.text = label.substring(label.indexOf(' ') + 1);
        _sendMessage(context, ref);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white70),
        ),
      ),
    );
  }

  Widget _buildOptionsMenu(BuildContext context, WidgetRef ref) {
    final mcpService = ref.watch(mcpServiceProvider.notifier);
    final internetAccess = mcpService.internetAccess;
    final aiState = ref.watch(aiProvider);
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
        } else if (value == 'rollback') {
          ref.read(aiProvider.notifier).rollbackAgentChanges();
        } else if (value == 'init') {
          ref.read(aiProvider.notifier).askAI('/init');
        } else if (value == 'cli_settings') {
          CliAgentSettingsDialog.show(context, initialKind: aiState.activeAgentKind);
        } else if (value == 'history') {
          _showChatHistoryDialog(context, ref);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'history',
          child: Row(
            children: [
              const Icon(LucideIcons.history, size: 12, color: Colors.amberAccent),
              const SizedBox(width: 8),
              Text(
                l10n.chatHistory,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'cli_settings',
          child: Row(
            children: [
              Icon(LucideIcons.sliders_horizontal, size: 12, color: Colors.cyanAccent),
              SizedBox(width: 8),
              Text(
                'Настройки CLI-агентов',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
        ),
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
        if (aiState.isAutopilot || aiState.isLoading)
          const PopupMenuItem(
            value: 'rollback',
            child: Row(
              children: [
                Icon(LucideIcons.rotate_ccw, size: 12, color: Colors.amberAccent),
                SizedBox(width: 8),
                Text(
                  'Откатить изменения агента',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'init',
          child: Row(
            children: [
              Icon(LucideIcons.file_text, size: 12, color: Colors.tealAccent),
              SizedBox(width: 8),
              Text(
                'Создать .quantum/AGENTS.md',
                style: TextStyle(color: Colors.white, fontSize: 11),
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
        children: [
          // Loading status & Stop button
          Expanded(
            child: aiState.isLoading
                ? Row(
                    children: [
                      if (aiState.isAutopilot || (aiState.isLoading && aiState.activeAgentKind != AgentKind.native)) ...[
                        InkWell(
                          onTap: () => ref.read(aiProvider.notifier).stopActiveAgent(),
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
                          _getAgentStatusText(aiState),
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          
          const SizedBox(width: 6),

          // Token and System Stats Badges (Horizontally scrollable to avoid 110px overflow)
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Agent Pipeline Status (Autopilot only)
                  if (aiState.interactionMode == AiInteractionMode.autopilot || aiState.interactionMode == AiInteractionMode.debug) ...[
                    _buildAgentPipelineBadge(aiState),
                    const SizedBox(width: 4),
                  ],
                  _buildTokenBadge(aiState),
                  const SizedBox(width: 4),
                  _buildSystemStatsBadge(ref),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getAgentStatusText(AIState aiState) {
    final role = aiState.activeAgentRole;
    if (role == null) return aiState.currentStatusMessage ?? (aiState.isAutopilot ? 'Autopilot running...' : 'Thinking...');
    switch (role.toLowerCase()) {
      case 'planner': return '🧠 Планирование...';
      case 'coder': return '⚙️ Генерация кода...';
      case 'validator': return '🔍 Валидация...';
      case 'judge': return '✅ Проверка результата...';
      case 'debugger': return '🐛 Диагностика...';
      default: return aiState.currentStatusMessage ?? '$role...';
    }
  }

  Widget _buildAgentPipelineBadge(AIState aiState) {
    final role = aiState.activeAgentRole?.toLowerCase();
    final steps = aiState.interactionMode == AiInteractionMode.debug
        ? ['debugger']
        : ['planner', 'coder', 'validator', 'judge'];
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            _PipelineDot(step: steps[i], currentRole: role),
            if (i < steps.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Icon(LucideIcons.chevron_right, size: 8, color: Colors.white.withValues(alpha: 0.3)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildTokenBadge(AIState aiState) {
    final prompt = aiState.lastPromptTokens;
    final completion = aiState.lastCompletionTokens;
    final hasRealTokens = prompt > 0 || completion > 0;
    final total = aiState.totalTokens;
    final cost = _estimateCost(prompt, completion);
    final displayText = hasRealTokens
        ? '$prompt↓ $completion↑'
        : '$total';
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
                ? 'Prompt: $prompt | Completion: $completion\nОценка стоимости: $cost'
                : 'Estimated: $total tokens',
            child: Text(
              displayText,
              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  String _estimateCost(int promptTokens, int completionTokens) {
    const promptPricePer1k = 0.00015;
    const completionPricePer1k = 0.0006;
    final promptCost = (promptTokens / 1000) * promptPricePer1k;
    final completionCost = (completionTokens / 1000) * completionPricePer1k;
    final total = promptCost + completionCost;
    if (total < 0.001) return '< 0.001 USD';
    return '\$ ${total.toStringAsFixed(4)}';
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

  String _formatRussianFilesCount(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 19) return '$count файлов с изменениями';
    if (mod10 == 1) return '$count файл с изменениями';
    if (mod10 >= 2 && mod10 <= 4) return '$count файла с изменениями';
    return '$count файлов с изменениями';
  }

  Widget _buildProposedActionsStickyPanel(AIState aiState) {
    final l10n = AppLocalizations.of(context)!;
    final fileCount = aiState.proposedActions.where((a) => a.type != 'command').length;
    final label = _formatRussianFilesCount(fileCount > 0 ? fileCount : aiState.proposedActions.length);

    final isMobile = MediaQuery.of(context).size.width < 700;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF141724),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          InkWell(
            onTap: () {
              if (aiState.proposedActions.isNotEmpty) {
                _showDiffDialog(aiState.proposedActions.first);
              }
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E6FE6).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF1E6FE6).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.file_diff, size: 12, color: Color(0xFF58A6FF)),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: const Color(0xFF58A6FF),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () {
                  for (final action in List<AIAction>.from(aiState.proposedActions)) {
                    ref.read(aiProvider.notifier).removeAction(action);
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(l10n.rejectAll, style: const TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: () async {
                  await ref.read(aiProvider.notifier).executeActionsManually(aiState.proposedActions);
                },
                icon: const Icon(LucideIcons.check, size: 13, color: Colors.white),
                label: Text(
                  l10n.acceptAll,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E6FE6),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ],
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

  Widget _buildChatInput(BuildContext context, WidgetRef ref, AIState aiState) {
    final editor = ref.watch(editorProvider);
    final hasActiveFile = editor.activeFilePath != null;
    final currentFileName = editor.activeFilePath?.split('/').last ?? '';
    final isInternetEnabled = ref.watch(mcpServiceProvider.notifier).internetAccess;
    final agentKind = aiState.activeAgentKind;
    final isBusy = aiState.isLoading;
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Padding(
      padding: EdgeInsets.fromLTRB(isMobile ? 6 : 8, 2, isMobile ? 6 : 8, isMobile ? 4 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Active file attachment indicator
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
                children: [
                  const Icon(LucideIcons.file_code, size: 12, color: Colors.cyanAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Файл в контексте: $currentFileName',
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

          // Input Box
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(isMobile ? 10 : 14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 8, vertical: isMobile ? 2 : 4),
            child: Column(
              children: [
                if (_showSlashCommands) _buildSlashCommands(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Attachment button
                    PopupMenuButton<String>(
                      tooltip: 'Прикрепить контекст',
                      icon: const Icon(LucideIcons.paperclip, size: 16, color: Colors.white60),
                      color: const Color(0xFF1E2230),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      onSelected: (value) {
                        if (value == 'image') {
                          _pickImage();
                        } else if (value == 'file' && hasActiveFile) {
                          setState(() => _attachActiveFile = !_attachActiveFile);
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
                                Icon(LucideIcons.file_code, size: 14, color: _attachActiveFile ? Colors.cyanAccent : Colors.white60),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Файл: $currentFileName',
                                    style: TextStyle(fontSize: 11, color: _attachActiveFile ? Colors.cyanAccent : Colors.white),
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
                              Text(
                                'Доступ в Интернет',
                                style: TextStyle(fontSize: 11, color: isInternetEnabled ? Colors.cyanAccent : Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    // Input TextField
                    Expanded(
                      child: TextField(
                        controller: _aiChatController,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) {
                          if (!isBusy) _sendMessage(context, ref);
                        },
                        decoration: InputDecoration(
                          hintText: 'Задача для ${agentKind.title}... (#file:путь, @codebase)',
                          hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 11.5),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Send or Stop Button
                    if (isBusy)
                      InkWell(
                        onTap: () => ref.read(aiProvider.notifier).stopActiveAgent(),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(LucideIcons.square, color: Colors.white, size: 12),
                        ),
                      )
                    else
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [agentKind.brandColor, Colors.cyanAccent],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: agentKind.brandColor.withValues(alpha: 0.3),
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
              ],
            ),
          ),

          // Token & Context Counter Bar
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2, left: 2, right: 2),
            child: Row(
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Context window badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.cpu, size: 10, color: Colors.cyanAccent),
                              const SizedBox(width: 4),
                              Text(
                                'Контекст: ${_getContextWindowLabel(ref.watch(activeAiModelProvider))}',
                                style: GoogleFonts.jetBrainsMono(fontSize: 9.5, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        if (aiState.totalTokens > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: agentKind.brandColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: agentKind.brandColor.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.sparkles, size: 9, color: agentKind.brandColor),
                                const SizedBox(width: 3),
                                Text(
                                  'Токены: ${_formatTokenCount(aiState.totalTokens)}',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${aiState.messages.length} сообщ.',
                  style: GoogleFonts.inter(fontSize: 9.5, color: Colors.white30),
                ),
              ],
            ),
          ),

          // Quick Command Chips
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['/fix', '/explain', '/plan', '/diff', '/clear'].map((cmd) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        _aiChatController.text = cmd;
                        _sendMessage(context, ref);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.6),
                        ),
                        child: Text(
                          cmd,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage(BuildContext context, WidgetRef ref) async {
    if (_isSendingMessage) return;
    final value = _aiChatController.text.trim();
    if (value.isEmpty && _selectedImageBase64 == null) return;

    _isSendingMessage = true;
    _aiChatController.clear();

    try {
      final editor = ref.read(editorProvider);
    final hasActiveFile = editor.activeFilePath != null;
    final currentFileName = editor.activeFilePath?.split('/').last ?? '';
    final activeFile = editor.openFiles.isNotEmpty && editor.activeTabIndex < editor.openFiles.length ? editor.openFiles[editor.activeTabIndex] : null;
    final currentCode = activeFile?.controller.text ?? '';

    final lowerVal = value.toLowerCase();

    if (lowerVal == '/clear') {
      _aiChatController.clear();
      ref.read(aiProvider.notifier).startNewSession();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Контекст очищен. Начата новая сессия.'), duration: Duration(seconds: 1)),
      );
      return;
    }

    if (lowerVal == '/model' || lowerVal == '/models') {
      _aiChatController.clear();
      final activeProviderId = ref.read(activeAiProviderIdProvider);
      final activeModel = ref.read(activeAiModelProvider);
      final apiKey = ref.read(aiServiceProvider).getApiKey(activeProviderId);
      final selected = await showModelPickerModal(
        context,
        providerId: activeProviderId,
        currentModel: activeModel,
        apiKey: apiKey,
      );
      if (selected != null && selected.isNotEmpty) {
        ref.read(activeAiModelProvider.notifier).state = selected;
        await ref.read(aiServiceProvider).setModel(selected);
      }
      return;
    }

    if (lowerVal == '/stats') {
      _aiChatController.clear();
      final aiState = ref.read(aiProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Токены сессии: ${aiState.totalTokens} | Вход: ${aiState.lastPromptTokens} | Выход: ${aiState.lastCompletionTokens} | Сообщений: ${aiState.messages.length}'),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    if (lowerVal == '/rollback') {
      _aiChatController.clear();
      ref.read(aiProvider.notifier).rollbackAgentChanges();
      return;
    }

    final isActionChip = lowerVal.startsWith('/fix') || 
                        lowerVal.startsWith('/refactor') || 
                        lowerVal.startsWith('/explain') || 
                        lowerVal.startsWith('/tests') || 
                        lowerVal.startsWith('/doc') ||
                        lowerVal.contains('исправь');

    final shouldIncludeFile = (_attachActiveFile || isActionChip) && hasActiveFile;

    final suggestedMode = _suggestMode(value, hasActiveFile, activeFile);
    if (suggestedMode != null) {
      final currentMode = ref.read(aiProvider).interactionMode;
      if (suggestedMode != currentMode) {
        _showModeSuggestionDialog(context, ref, suggestedMode, value);
        return;
      }
    }

    String fullPrompt = value;
    if (shouldIncludeFile && currentCode.isNotEmpty) {
      fullPrompt = '⚠️ Рабочий файл: **$currentFileName**\n'
          'Исходный код ($currentFileName):\n```dart\n$currentCode\n```\n\n'
          'Инструкция: $value\n'
          'ОБЯЗАТЕЛЬНО: Предложи рабочий код и внеси исправления!';
    }

    final List<String> contextFiles = [];
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

    final activeKind = ref.read(aiProvider).activeAgentKind;
    if (activeKind != AgentKind.native) {
      ref.read(aiProvider.notifier).executeCliTask(
        fullPrompt,
        imageBase64: _selectedImageBase64,
        contextFiles: contextFiles.isNotEmpty ? contextFiles : null,
      );
    } else {
      ref.read(aiProvider.notifier).askAI(
        fullPrompt,
        imageBase64: _selectedImageBase64,
        contextFiles: contextFiles.isNotEmpty ? contextFiles : null,
      );
    }
    setState(() {
      _attachActiveFile = false;
      _selectedImagePath = null;
      _selectedImageBase64 = null;
    });
    } finally {
      _isSendingMessage = false;
    }
  }

  String _getModeLabel(AiInteractionMode mode) {
    switch (mode) {
      case AiInteractionMode.chat: return 'Чат';
      case AiInteractionMode.ask: return 'Запроc';
      case AiInteractionMode.autopilot: return 'Агент';
      case AiInteractionMode.refactor: return 'Редактор';
      case AiInteractionMode.plan: return 'Планер';
      case AiInteractionMode.debug: return 'Дебаг';
    }
  }

  IconData _getModeIcon(AiInteractionMode mode) {
    switch (mode) {
      case AiInteractionMode.chat: return LucideIcons.message_square;
      case AiInteractionMode.ask: return LucideIcons.search;
      case AiInteractionMode.autopilot: return LucideIcons.bot;
      case AiInteractionMode.refactor: return LucideIcons.code;
      case AiInteractionMode.plan: return LucideIcons.map;
      case AiInteractionMode.debug: return LucideIcons.bug;
    }
  }

  Color _getModeColor(AiInteractionMode mode) {
    switch (mode) {
      case AiInteractionMode.chat: return Colors.cyanAccent;
      case AiInteractionMode.ask: return Colors.blueAccent;
      case AiInteractionMode.autopilot: return Colors.orangeAccent;
      case AiInteractionMode.refactor: return Colors.purpleAccent;
      case AiInteractionMode.plan: return Colors.tealAccent;
      case AiInteractionMode.debug: return Colors.redAccent;
    }
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

  AiInteractionMode? _suggestMode(String prompt, bool hasActiveFile, dynamic activeFile) {
    final lower = prompt.toLowerCase();
    bool hasSelection = false;
    if (activeFile != null) {
      try {
        final sel = activeFile.controller.selection;
        hasSelection = !sel.isCollapsed;
      } catch (_) {
        hasSelection = false;
      }
    }
    
    if (lower.contains('спроектируй') || lower.contains('архитектур') || lower.contains('планировщ') || lower.contains('plan') || lower.contains('design')) {
      return AiInteractionMode.plan;
    }
    if (lower.contains('исправь') || lower.contains('fix') || lower.contains('ошибк') || lower.contains('bug')) {
      return AiInteractionMode.refactor;
    }
    if (lower.contains('отлад') || lower.contains('debug') || lower.contains('падени') || lower.contains('trace')) {
      return AiInteractionMode.debug;
    }
    if (lower.contains('сделай') || lower.contains('создай') || lower.contains('напиши') || lower.contains('build') || lower.contains('implement')) {
      return AiInteractionMode.autopilot;
    }
    if (hasActiveFile && hasSelection && (lower.contains('что это') || lower.contains('объясни') || lower.contains('explain'))) {
      return AiInteractionMode.ask;
    }
    return null;
  }

  void _showModeSuggestionDialog(BuildContext context, WidgetRef ref, AiInteractionMode suggestedMode, String originalPrompt) {
    final l10n = AppLocalizations.of(context)!;
    final modeLabel = _getModeLabel(suggestedMode);
    final modeIcon = _getModeIcon(suggestedMode);
    final modeColor = _getModeColor(suggestedMode);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2230),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(modeIcon, color: modeColor, size: 18),
            const SizedBox(width: 8),
            Text(
              'Рекомендуемый режим: $modeLabel',
              style: TextStyle(color: modeColor, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Похоже, этот запрос лучше обработать в режиме "$modeLabel". Переключиться?',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _sendMessage(context, ref);
            },
            child: Text(l10n.cancel, style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(aiProvider.notifier).setInteractionMode(suggestedMode);
              _sendMessage(context, ref);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: modeColor.withValues(alpha: 0.2),
              foregroundColor: modeColor,
            ),
            child: Text('Переключить в $modeLabel'),
          ),
        ],
      ),
    );
  }
}

class _PipelineDot extends StatelessWidget {
  final String step;
  final String? currentRole;

  const _PipelineDot({required this.step, this.currentRole});

  @override
  Widget build(BuildContext context) {
    final isActive = currentRole == step;
    final isDone = currentRole != null && _isStepDone(step, currentRole!);
    Color color;
    String label;
    switch (step) {
      case 'planner':
        color = Colors.tealAccent;
        label = '🧠';
        break;
      case 'coder':
        color = Colors.orangeAccent;
        label = '⚙️';
        break;
      case 'validator':
        color = Colors.cyanAccent;
        label = '🔍';
        break;
      case 'judge':
        color = Colors.greenAccent;
        label = '✅';
        break;
      case 'debugger':
        color = Colors.redAccent;
        label = '🐛';
        break;
      default:
        color = Colors.white30;
        label = '•';
    }

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.2) : (isDone ? color.withValues(alpha: 0.1) : Colors.transparent),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isActive ? color : (isDone ? color.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.2)),
          width: isActive ? 1.5 : 0.8,
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(fontSize: isActive ? 11 : 9),
        ),
      ),
    );
  }

  bool _isStepDone(String step, String currentRole) {
    final order = {'planner': 0, 'coder': 1, 'validator': 2, 'judge': 3, 'debugger': 0};
    return (order[step] ?? 0) < (order[currentRole] ?? 0);
  }
}
