import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/models/ai_provider_config.dart';
import 'package:quantum_ide/core/services/local_ai_service.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/ai_chat_messages.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/services/system_stats_service.dart';

import 'package:quantum_ide/models/chat_message.dart';

class AIAgentPanel extends ConsumerStatefulWidget {
  const AIAgentPanel({super.key});

  @override
  ConsumerState<AIAgentPanel> createState() => _AIAgentPanelState();
}

class _AIAgentPanelState extends ConsumerState<AIAgentPanel> {
  final TextEditingController _aiChatController = TextEditingController();
  bool _attachActiveFile = false;
  bool _showSettingsMobile = false;

  // Settings states
  late String _selectedProviderId;
  late String _selectedModel;
  late LocalAiEngine _selectedLocalEngine;
  final _keyController = TextEditingController();
  final _urlController = TextEditingController();
  List<String> _availableModels = [];
  bool _isLoadingModels = false;
  bool _obscureKey = true;
  bool _ollamaReachable = false;
  bool _checkingOllama = false;

  // Local AI parameters
  int _localThreads = 4;
  int _localGpuLayers = 0;
  bool _localUseFlashAttn = false;

  @override
  void initState() {
    super.initState();
    _initSettings();
  }

  void _initSettings() {
    final aiSvc = ref.read(aiServiceProvider);
    _selectedProviderId = aiSvc.selectedProviderId;
    _selectedModel = aiSvc.selectedModel;
    _selectedLocalEngine = aiSvc.selectedLocalEngine;
    _keyController.text = aiSvc.getApiKey(_selectedProviderId);
    _urlController.text = aiSvc.getBaseUrl(_selectedProviderId);
    
    final localAiState = ref.read(localAiServiceProvider);
    _localThreads = localAiState.threads;
    _localGpuLayers = localAiState.gpuLayers;
    _localUseFlashAttn = localAiState.useFlashAttn;

    _loadModels();
    if (_selectedProviderId == 'local_edge' && _selectedLocalEngine == LocalAiEngine.ollama) {
      _checkOllamaStatus();
    }
  }

  Future<void> _checkOllamaStatus() async {
    if (!mounted) return;
    setState(() => _checkingOllama = true);
    try {
      final aiSvc = ref.read(aiServiceProvider);
      final models = await aiSvc.fetchAvailableModels('local_edge');
      if (mounted) {
        setState(() {
          _ollamaReachable = models.isNotEmpty;
          _checkingOllama = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _ollamaReachable = false;
          _checkingOllama = false;
        });
      }
    }
  }

  Future<void> _loadModels() async {
    if (!mounted) return;
    setState(() {
      _isLoadingModels = true;
    });
    try {
      final aiSvc = ref.read(aiServiceProvider);
      final models = await aiSvc.fetchAvailableModels(_selectedProviderId);
      if (mounted) {
        setState(() {
          _availableModels = models;
          if (!_availableModels.contains(_selectedModel)) {
            _selectedModel = _availableModels.isNotEmpty ? _availableModels.first : '';
          }
        });
      }
    } catch (e) {
      final isOllamaProvider = _selectedProviderId == 'local_edge' &&
          _selectedLocalEngine == LocalAiEngine.ollama;
      if (mounted) {
        setState(() {
          _availableModels = isOllamaProvider
              ? []
              : AiProviders.byId(_selectedProviderId).defaultModels;
          if (!_availableModels.contains(_selectedModel)) {
            _selectedModel = _availableModels.isNotEmpty ? _availableModels.first : '';
          }
          _ollamaReachable = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingModels = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    final aiSvcNotifier = ref.read(aiServiceProvider);

    await aiSvcNotifier.setProvider(_selectedProviderId);

    if (_selectedModel.isNotEmpty) {
      await aiSvcNotifier.setModel(_selectedModel);
    }

    if (AiProviders.byId(_selectedProviderId).requiresApiKey) {
      await aiSvcNotifier.setApiKey(_selectedProviderId, _keyController.text.trim());
    }

    if (_urlController.text.trim().isNotEmpty) {
      await aiSvcNotifier.setBaseUrl(_selectedProviderId, _urlController.text.trim());
    }

    if (_selectedProviderId == 'local_edge') {
      await aiSvcNotifier.setLocalEngine(_selectedLocalEngine);
      await ref.read(localAiServiceProvider.notifier).updateSettings(
        threads: _localThreads,
        gpuLayers: _localGpuLayers,
        useFlashAttn: _localUseFlashAttn,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI Settings Saved Successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _aiChatController.dispose();
    _keyController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aiState = ref.watch(aiProvider);
    final l10n = AppLocalizations.of(context)!;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 750;

    return Container(
      color: const Color(0xFF0D0F14),
      child: Column(
        children: [
          // Sub-header controls for session and mobile view switcher
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.15),
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
            ),
            child: Row(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.purpleAccent, Colors.cyanAccent],
                  ).createShader(bounds),
                  child: const Icon(LucideIcons.bot, color: Colors.white, size: 14),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.aiAgent,
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                // Start New Session Button
                IconButton(
                  icon: const Icon(LucideIcons.plus, size: 13, color: Colors.cyanAccent),
                  onPressed: () {
                    ref.read(aiProvider.notifier).startNewSession();
                  },
                  tooltip: l10n.newChat,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                ),
                const SizedBox(width: 8),
                // Mobile View Switcher (Chat vs Settings)
                if (!isDesktop) ...[
                  IconButton(
                    icon: Icon(
                      _showSettingsMobile ? LucideIcons.message_square : LucideIcons.sliders_horizontal,
                      size: 13,
                      color: Colors.cyanAccent,
                    ),
                    onPressed: () {
                      setState(() {
                        _showSettingsMobile = !_showSettingsMobile;
                      });
                    },
                    tooltip: _showSettingsMobile ? l10n.chat : l10n.settings,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  ),
                ],
              ],
            ),
          ),
          
          // Main Body
          Expanded(
            child: isDesktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Chat Section
                      Expanded(
                        flex: 6,
                        child: _buildChatSection(aiState, l10n),
                      ),
                      // Divider
                      Container(
                        width: 1,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                      // Settings Section
                      Expanded(
                        flex: 4,
                        child: _buildSettingsSection(l10n),
                      ),
                    ],
                  )
                : (_showSettingsMobile
                    ? _buildSettingsSection(l10n)
                    : _buildChatSection(aiState, l10n)),
          ),
        ],
      ),
    );
  }

  Widget _buildChatSection(AIState aiState, AppLocalizations l10n) {
    return Column(
      children: [
        _buildStatusRow(aiState, l10n),
        Expanded(
          child: AIChatMessages(aiState: aiState),
        ),
        if (aiState.proposedActions.isNotEmpty)
          _buildProposedActionsStickyPanel(aiState, l10n),
        _buildAIChatInput(l10n, aiState: aiState),
      ],
    );
  }

  Widget _buildInteractionModeSelector(AIState aiState) {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    String modeLabel;
    IconData modeIcon;
    Color modeColor;
    switch (aiState.interactionMode) {
      case AiInteractionMode.chat:
        modeLabel = isRu ? 'Чат' : 'Chat';
        modeIcon = LucideIcons.message_square;
        modeColor = Colors.cyanAccent;
      case AiInteractionMode.refactor:
        modeLabel = isRu ? 'Рефактор' : 'Refactor';
        modeIcon = LucideIcons.code;
        modeColor = Colors.purpleAccent;
      case AiInteractionMode.autopilot:
        modeLabel = isRu ? 'Автопилот' : 'Autopilot';
        modeIcon = LucideIcons.zap;
        modeColor = Colors.orangeAccent;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: GestureDetector(
        onTap: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: const Color(0xFF1E2230),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 12),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                  _buildModeOption(ctx, isRu ? 'Чат' : 'Chat', LucideIcons.message_square, Colors.cyanAccent, AiInteractionMode.chat, aiState.interactionMode),
                  _buildModeOption(ctx, isRu ? 'Рефактор' : 'Refactor', LucideIcons.code, Colors.purpleAccent, AiInteractionMode.refactor, aiState.interactionMode),
                  _buildModeOption(ctx, isRu ? 'Автопилот' : 'Autopilot', LucideIcons.zap, Colors.orangeAccent, AiInteractionMode.autopilot, aiState.interactionMode),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: modeColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: modeColor.withValues(alpha: 0.2), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(modeIcon, size: 12, color: modeColor),
              const SizedBox(width: 4),
              Text(
                modeLabel,
                style: GoogleFonts.inter(fontSize: 10, color: modeColor, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 2),
              Icon(LucideIcons.chevron_down, size: 10, color: modeColor.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeOption(BuildContext ctx, String label, IconData icon, Color color, AiInteractionMode target, AiInteractionMode current) {
    final isSelected = current == target;
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 18, color: isSelected ? color : Colors.white54),
      title: Text(label, style: GoogleFonts.inter(color: isSelected ? color : Colors.white70, fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
      trailing: isSelected ? Icon(LucideIcons.check, size: 16, color: color) : null,
      onTap: () {
        ref.read(aiProvider.notifier).setInteractionMode(target);
        Navigator.pop(ctx);
      },
    );
  }

  Widget _buildStatusRow(AIState aiState, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: aiState.isLoading
                ? Row(
                    children: [
                      if (aiState.isAutopilot) ...[
                        InkWell(
                          onTap: () => ref.read(aiProvider.notifier).stopAutopilot(),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6), width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.square, size: 8, color: Colors.redAccent),
                                const SizedBox(width: 3),
                                Text(
                                  l10n.stop,
                                  style: GoogleFonts.inter(fontSize: 8.5, color: Colors.redAccent, fontWeight: FontWeight.bold),
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
                            strokeWidth: 1.2,
                            color: Colors.purpleAccent,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          aiState.currentStatusMessage ?? (aiState.isAutopilot ? 'Autopilot running...' : 'Thinking...'),
                          style: GoogleFonts.inter(fontSize: 9, color: Colors.white38),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : const SizedBox(),
          ),
          
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTokenBadge(aiState),
              const SizedBox(width: 4),
              _buildSystemStatsBadge(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTokenBadge(AIState aiState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.purpleAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.coins, size: 9, color: Colors.purpleAccent),
          const SizedBox(width: 3),
          Text(
            '${aiState.totalTokens}',
            style: GoogleFonts.jetBrainsMono(fontSize: 8.5, color: Colors.white70, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemStatsBadge() {
    final stats = ref.watch(systemStatsProvider);
    final cpuColor = _getStatsBadgeColor(stats.cpuUsage);
    final ramColor = _getStatsBadgeColor(stats.ramUsage);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.cpu, size: 9, color: cpuColor),
          const SizedBox(width: 2),
          Text(
            '${(stats.cpuUsage * 100).toStringAsFixed(0)}%',
            style: GoogleFonts.jetBrainsMono(fontSize: 8, color: Colors.white54, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          Container(width: 0.5, height: 6, color: Colors.white12),
          const SizedBox(width: 4),
          Icon(LucideIcons.memory_stick, size: 9, color: ramColor),
          const SizedBox(width: 2),
          Text(
            '${(stats.ramUsage * 100).toStringAsFixed(0)}%',
            style: GoogleFonts.jetBrainsMono(fontSize: 8, color: Colors.white54, fontWeight: FontWeight.bold),
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

  Widget _buildProposedActionsStickyPanel(AIState aiState, AppLocalizations l10n) {
    final fileCount = aiState.proposedActions.where((a) => a.type != 'command').length;
    
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12151F),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    l10n.filesCount(fileCount),
                    style: GoogleFonts.inter(color: Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.withChanges,
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    for (final action in List<AIAction>.from(aiState.proposedActions)) {
                      ref.read(aiProvider.notifier).removeAction(action);
                    }
                  },
                  child: Text(l10n.rejectAll, style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: () => ref.read(aiProvider.notifier).executeActionsManually(aiState.proposedActions),
                  child: Text(l10n.acceptAll, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIChatInput(AppLocalizations l10n, {required AIState aiState}) {
    final aiSvc = ref.watch(aiServiceProvider);
    final provider = AiProviders.byId(aiSvc.selectedProviderId);
    final editor = ref.watch(editorProvider);
    final hasActiveFile = editor.activeFilePath != null;
    final currentFileName = editor.activeFilePath?.split('/').last ?? '';
    final activeFile = editor.openFiles.isNotEmpty ? editor.openFiles[editor.activeTabIndex] : null;
    final currentCode = activeFile?.controller.text ?? "";

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
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
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.file_code, size: 10, color: Colors.cyanAccent),
                    const SizedBox(width: 4),
                    Text(
                      currentFileName,
                      style: GoogleFonts.inter(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 4),
                    const Icon(LucideIcons.x, size: 9, color: Colors.white60),
                  ],
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: TextField(
              controller: _aiChatController,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
              maxLines: 4,
              minLines: 1,
              decoration: InputDecoration(
                hintText: l10n.askAiHint(provider.id == 'local_edge' ? l10n.localAiDisplayName : provider.displayName),
                hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 11.5),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                prefixIcon: hasActiveFile
                    ? IconButton(
                        icon: Icon(
                          LucideIcons.paperclip,
                          color: _attachActiveFile ? Colors.cyanAccent : Colors.white38,
                          size: 14,
                        ),
                        onPressed: () {
                          setState(() {
                            _attachActiveFile = !_attachActiveFile;
                          });
                        },
                        tooltip: l10n.attachOpenFile,
                      )
                    : null,
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.purpleAccent, Colors.cyanAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(LucideIcons.send, color: Colors.white, size: 12),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () {
                        final value = _aiChatController.text.trim();
                        if (value.isEmpty) return;

                        String finalPrompt = value;
                        if (_attachActiveFile && hasActiveFile) {
                          finalPrompt = "In file: $currentFileName\nCode:\n```\n$currentCode\n```\n\n$value";
                        }
                        
                        ref.read(aiProvider.notifier).askAI(finalPrompt);
                        _aiChatController.clear();
                        setState(() {
                          _attachActiveFile = false;
                        });
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Mode selector row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _buildInteractionModeSelector(aiState),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(AppLocalizations l10n) {
    final aiSvc = ref.watch(aiServiceProvider);
    final isLocalEdge = _selectedProviderId == 'local_edge';
    final isOllamaEngine = isLocalEdge && _selectedLocalEngine == LocalAiEngine.ollama;

    // Watch local AI state and notifier
    final localAiState = ref.watch(localAiServiceProvider);
    final localAiNotifier = ref.read(localAiServiceProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(12.0),
      color: Colors.black.withValues(alpha: 0.05),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Provider Selector
            Text(l10n.provider, style: GoogleFonts.inter(color: Colors.white54, fontSize: 10)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedProviderId,
                  dropdownColor: const Color(0xFF1E2230),
                  isExpanded: true,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                  items: AiProviders.all.map((p) {
                    return DropdownMenuItem<String>(
                      value: p.id,
                      child: Text('${p.logoEmoji}  ${p.displayName}'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedProviderId = val;
                        _keyController.text = aiSvc.getApiKey(val);
                        _urlController.text = aiSvc.getBaseUrl(val);
                        _selectedModel = AiProviders.byId(val).defaultModels.first;
                        _ollamaReachable = false;
                      });
                      _loadModels();
                      if (val == 'local_edge' && _selectedLocalEngine == LocalAiEngine.ollama) {
                        _checkOllamaStatus();
                      }
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),

            if (isLocalEdge) ...[
              // Local AI Engine Selector
              Row(
                children: [
                  Text(
                    'Local AI Engine',
                    style: GoogleFonts.inter(color: Colors.white54, fontSize: 10),
                  ),
                  const Spacer(),
                  if (isOllamaEngine) ...[
                    if (_checkingOllama)
                      const SizedBox(
                        width: 8, height: 8,
                        child: CircularProgressIndicator(strokeWidth: 1.2, color: Colors.cyanAccent),
                      )
                    else
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _ollamaReachable
                              ? const Color(0xFF10B981)
                              : Colors.redAccent,
                        ),
                      ),
                    const SizedBox(width: 4),
                    Text(
                      _ollamaReachable ? 'Running' : 'Not found',
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        color: _ollamaReachable ? const Color(0xFF10B981) : Colors.redAccent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        _checkOllamaStatus();
                        _loadModels();
                      },
                      child: const Icon(LucideIcons.refresh_cw, size: 10, color: Colors.white38),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<LocalAiEngine>(
                    value: _selectedLocalEngine,
                    dropdownColor: const Color(0xFF1E2230),
                    isExpanded: true,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                    items: LocalAiEngine.values.map((engine) {
                      return DropdownMenuItem<LocalAiEngine>(
                        value: engine,
                        child: Text(engine.displayName),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedLocalEngine = val;
                          _ollamaReachable = false;
                          _availableModels = [];
                          _selectedModel = '';
                          _urlController.text = val.defaultBaseUrl;
                        });
                        ref.read(aiServiceProvider).setLocalEngine(val).then((_) {
                          _loadModels();
                          if (val == LocalAiEngine.ollama) {
                            _checkOllamaStatus();
                          }
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Server controls/runtime installer when llamaServer is chosen
              if (_selectedLocalEngine == LocalAiEngine.llamaServer) ...[
                // Binary Runtime Status Card
                if (!localAiState.isBinaryInstalled) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.triangle_alert, color: Colors.redAccent, size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'llama-server runtime not found.',
                                style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'You need to download and compile the llama-server library to run models offline.',
                          style: GoogleFonts.inter(color: Colors.white54, fontSize: 10),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                            ),
                            onPressed: localAiState.isBinaryInstalling ? null : () => localAiNotifier.installBinary(),
                            icon: localAiState.isBinaryInstalling
                                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation(Colors.white)))
                                : const Icon(LucideIcons.download, size: 12),
                            label: Text(localAiState.isBinaryInstalling ? 'Installing...' : 'Install AI Runtime', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ] else if (localAiState.isBinaryInstalling) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation(Colors.cyanAccent))),
                        const SizedBox(width: 8),
                        Text('Installing llama-server runtime...', style: GoogleFonts.inter(color: Colors.cyanAccent, fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Server Status & Switch
                if (localAiState.isBinaryInstalled) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: localAiState.isRunning
                                ? const Color(0xFF10B981)
                                : localAiState.isStarting
                                    ? Colors.amberAccent
                                    : Colors.white24,
                            boxShadow: localAiState.isRunning
                                ? [BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.5), blurRadius: 4, spreadRadius: 1)]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          localAiState.isRunning
                              ? 'Local Server: ACTIVE'
                              : localAiState.isStarting
                                  ? 'Local Server: STARTING...'
                                  : 'Local Server: STOPPED',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: localAiState.isRunning
                                ? const Color(0xFF10B981)
                                : localAiState.isStarting
                                    ? Colors.amberAccent
                                    : Colors.white54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (localAiState.isRunning || localAiState.isStarting)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              minimumSize: Size.zero,
                            ),
                            onPressed: () => localAiNotifier.stopServer(),
                            icon: const Icon(LucideIcons.square, size: 10),
                            label: const Text('Stop', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                          )
                        else if (localAiState.isModelDownloaded)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.greenAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              minimumSize: Size.zero,
                            ),
                            onPressed: () => localAiNotifier.startServer(),
                            icon: const Icon(LucideIcons.play, size: 10),
                            label: const Text('Start', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Hardware / NPU Acceleration Settings
                Text(
                  'Hardware/NPU Acceleration',
                  style: GoogleFonts.inter(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('CPU Threads', style: GoogleFonts.inter(color: Colors.white70, fontSize: 10)),
                    Text('$_localThreads', style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.purpleAccent,
                    inactiveTrackColor: Colors.white10,
                    thumbColor: Colors.cyanAccent,
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _localThreads.toDouble(),
                    min: 1,
                    max: 16,
                    divisions: 15,
                    onChanged: (val) {
                      setState(() {
                        _localThreads = val.toInt();
                      });
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('GPU/NPU Layers', style: GoogleFonts.inter(color: Colors.white70, fontSize: 10)),
                    Text(
                      _localGpuLayers == 0 ? 'CPU-only' : '$_localGpuLayers',
                      style: GoogleFonts.jetBrainsMono(
                        color: _localGpuLayers == 0 ? Colors.white38 : Colors.cyanAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.purpleAccent,
                    inactiveTrackColor: Colors.white10,
                    thumbColor: Colors.cyanAccent,
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _localGpuLayers.toDouble(),
                    min: 0,
                    max: 99,
                    divisions: 99,
                    onChanged: (val) {
                      setState(() {
                        _localGpuLayers = val.toInt();
                      });
                    },
                  ),
                ),
                SwitchListTile(
                  title: Text('Flash Attention', style: GoogleFonts.inter(color: Colors.white70, fontSize: 10)),
                  value: _localUseFlashAttn,
                  activeThumbColor: Colors.cyanAccent,
                  activeTrackColor: Colors.purpleAccent.withValues(alpha: 0.5),
                  inactiveThumbColor: Colors.white38,
                  inactiveTrackColor: Colors.white10,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onChanged: (val) {
                    setState(() {
                      _localUseFlashAttn = val;
                    });
                  },
                ),
                const SizedBox(height: 10),
              ],

              // Models Downloader and List
              Text(
                'Available Offline Models',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              
              if (localAiState.error != null) ...[
                Text(
                  localAiState.error!,
                  style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 10),
                ),
                const SizedBox(height: 4),
              ],

              Column(
                children: availableLocalModels
                    .where((m) => m.engine == _selectedLocalEngine)
                    .map((model) {
                  final isDownloaded = localAiState.downloadedModels[model.id] == true;
                  final isDownloading = localAiState.downloadingModelId == model.id;
                  final isAnyDownloading = localAiState.downloadingModelId != null;
                  final isActive = localAiState.selectedModelFilename == model.filename;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isActive
                            ? Colors.cyanAccent.withValues(alpha: 0.35)
                            : Colors.white.withValues(alpha: 0.05),
                        width: isActive ? 1.2 : 0.8,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          model.name,
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11.5,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isActive && isDownloaded) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: Colors.greenAccent.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'ACTIVE',
                                            style: GoogleFonts.inter(
                                              color: Colors.greenAccent,
                                              fontSize: 8,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    model.description,
                                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 9.5),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                // Size info
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(LucideIcons.hard_drive, size: 9, color: Colors.white38),
                                      const SizedBox(width: 3),
                                      Text(
                                        '${model.sizeGb.toStringAsFixed(2)} GB',
                                        style: GoogleFonts.jetBrainsMono(fontSize: 8, color: Colors.white54),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // RAM required info
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(LucideIcons.memory_stick, size: 9, color: Colors.white38),
                                      const SizedBox(width: 3),
                                      Text(
                                        'RAM: ${model.ramRequiredGb.toStringAsFixed(1)} GB',
                                        style: GoogleFonts.jetBrainsMono(fontSize: 8, color: Colors.white54),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            
                            // Download/Cancel/Delete Actions
                            if (isDownloading) ...[
                              IconButton(
                                icon: const Icon(LucideIcons.circle_stop, color: Colors.redAccent, size: 14),
                                onPressed: () => localAiNotifier.cancelDownload(),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ] else if (isDownloaded) ...[
                              Row(
                                children: [
                                  if (!isActive)
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        minimumSize: Size.zero,
                                      ),
                                      onPressed: () => localAiNotifier.selectModel(model.id),
                                      child: Text('Use', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                                    ),
                                  IconButton(
                                    icon: const Icon(LucideIcons.trash_2, color: Colors.redAccent, size: 14),
                                    onPressed: () => localAiNotifier.deleteModel(model.id),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            ] else ...[
                              ElevatedButton.icon(
                                onPressed: isAnyDownloading ? null : () => localAiNotifier.downloadModel(model.id),
                                icon: const Icon(LucideIcons.download, size: 9),
                                label: Text(_selectedLocalEngine == LocalAiEngine.ollama ? 'Pull' : 'Download', style: GoogleFonts.inter(fontSize: 9.5)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.cyanAccent.withValues(alpha: 0.1),
                                  foregroundColor: Colors.cyanAccent,
                                  elevation: 0,
                                  side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.2)),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                ),
                              ),
                            ],
                          ],
                        ),
                        
                        // Download progress bar
                        if (isDownloading) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: localAiState.downloadProgress,
                                    backgroundColor: Colors.white10,
                                    color: Colors.cyanAccent,
                                    minHeight: 4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(localAiState.downloadProgress * 100).toStringAsFixed(0)}%',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.cyanAccent,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
            ] else ...[
              // Standard Model Selector for Cloud Providers
              Text(l10n.model, style: GoogleFonts.inter(color: Colors.white54, fontSize: 10)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: _isLoadingModels
                    ? const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Center(
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.cyanAccent),
                          ),
                        ),
                      )
                    : _availableModels.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No models available',
                              style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedModel.isNotEmpty && _availableModels.contains(_selectedModel)
                                  ? _selectedModel
                                  : null,
                              dropdownColor: const Color(0xFF1E2230),
                              isExpanded: true,
                              style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent, fontSize: 11),
                              items: _availableModels.map((m) {
                                return DropdownMenuItem<String>(
                                  value: m,
                                  child: Text(m),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedModel = val;
                                  });
                                }
                              },
                            ),
                          ),
              ),
              const SizedBox(height: 10),
            ],

            // API Key (if required)
            if (AiProviders.byId(_selectedProviderId).requiresApiKey) ...[
              Text(l10n.apiKey, style: GoogleFonts.inter(color: Colors.white54, fontSize: 10)),
              const SizedBox(height: 4),
              TextField(
                controller: _keyController,
                obscureText: _obscureKey,
                style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11.5),
                decoration: InputDecoration(
                  hintText: AiProviders.byId(_selectedProviderId).apiKeyHint,
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.03),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.cyanAccent, width: 0.8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(_obscureKey ? LucideIcons.eye : LucideIcons.eye_off,
                        size: 14, color: Colors.white38),
                    onPressed: () {
                      setState(() {
                        _obscureKey = !_obscureKey;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Custom Base URL
            Text(l10n.customBaseUrl, style: GoogleFonts.inter(color: Colors.white54, fontSize: 10)),
            const SizedBox(height: 4),
            TextField(
              controller: _urlController,
              style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11.5),
              decoration: InputDecoration(
                hintText: isLocalEdge
                    ? _selectedLocalEngine.defaultBaseUrl
                    : l10n.defaultHint(AiProviders.byId(_selectedProviderId).baseUrl),
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.03),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.cyanAccent, width: 0.8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),

            // Save Settings Button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: _saveSettings,
              child: Text(
                l10n.save,
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
