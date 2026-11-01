import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/agent/domain/quantum_agent_models.dart';
import 'package:quantum_ide/features/agent/services/quantum_agent_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/shared/providers/drawer_provider.dart';

class QuantumAgentPanel extends ConsumerStatefulWidget {
  final VoidCallback? onClose;

  const QuantumAgentPanel({super.key, this.onClose});

  @override
  ConsumerState<QuantumAgentPanel> createState() => _QuantumAgentPanelState();
}

class _QuantumAgentPanelState extends ConsumerState<QuantumAgentPanel> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Вкладки панели: 0 = Чат, 1 = Изменения (Diff), 2 = Модели (Cloud & Local), 3 = Настройки & Сервер
  int _activeTab = 0;

  // Состояние для вкладки Моделей
  String _modelScope = 'cloud'; // 'cloud' | 'local'
  String _modelSearchQuery = '';
  final TextEditingController _apiKeyInputCtrl = TextEditingController();
  final TextEditingController _keyNameInputCtrl = TextEditingController();
  final TextEditingController _customUrlCtrl = TextEditingController();
  final TextEditingController _openRouterOrderCtrl = TextEditingController();
  final TextEditingController _customSysPromptCtrl = TextEditingController();
  final TextEditingController _stopSeqCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final st = ref.read(quantumAgentProvider);
      _apiKeyInputCtrl.text = st.apiKey;
      _customUrlCtrl.text = st.customBaseUrl;
      _openRouterOrderCtrl.text = st.openRouterProviderOrder;
      _customSysPromptCtrl.text = st.customSystemPrompt;
      _stopSeqCtrl.text = st.stopSequences.join(', ');
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _apiKeyInputCtrl.dispose();
    _keyNameInputCtrl.dispose();
    _customUrlCtrl.dispose();
    _openRouterOrderCtrl.dispose();
    _customSysPromptCtrl.dispose();
    _stopSeqCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendPrompt([String? presetText]) {
    final text = presetText ?? _inputController.text;
    if (text.trim().isEmpty) return;
    if (presetText == null) {
      _inputController.clear();
    }
    setState(() => _activeTab = 0);
    ref.read(quantumAgentProvider.notifier).sendUserMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(quantumAgentProvider);
    final preset = QuantumAgentProviderPreset.byId(state.providerId);
    final workspacePath = ref.watch(workspaceProvider).currentPath;
    final screenWidth = MediaQuery.of(context).size.width;

    ref.listen<QuantumAgentState>(quantumAgentProvider, (prev, next) {
      if ((prev?.messages.length ?? 0) != next.messages.length || next.isWorking) {
        _scrollToBottom();
      }
    });

    return Container(
      color: const Color(0xFF0B0E14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. ВЕРХНЯЯ ШАПКА С БЫСТРЫМ МАСШТАБОМ ШИРИНЫ И СТАТУСОМ ──────────
          _buildTopHeader(state, preset, screenWidth),

          // ── 2. НАВИГАЦИОННЫЕ ВКЛАДКИ (Chat / Changes / Models / Settings) ──
          _buildNavigationTabs(state),

          // ── 3. КОНТЕНТ АКТИВНОЙ ВКЛАДКИ ────────────────────────────────────
          Expanded(
            child: IndexedStack(
              index: _activeTab,
              children: [
                _buildChatTab(state, preset, workspacePath),
                _buildChangesDiffTab(state, workspacePath),
                _buildModelsHubTab(state, preset),
                _buildSettingsAndServerTab(state),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ШАПКА И НАВИГАЦИЯ ПРАВОЙ ПАНЕЛИ
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTopHeader(
    QuantumAgentState state,
    QuantumAgentProviderPreset preset,
    double screenWidth,
  ) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            preset.brandColor.withValues(alpha: 0.22),
            const Color(0xFF141824),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: preset.brandColor.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: preset.brandColor.withValues(alpha: 0.5), width: 0.8),
            ),
            child: Icon(preset.icon, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _activeTab = 2),
              borderRadius: BorderRadius.circular(6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'QUANTUM AI HUB',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: (state.isLocalServerRunning ? Colors.greenAccent : preset.brandColor)
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          state.inferenceMode == 'local' ? 'LOCAL' : state.selectedHarness.toUpperCase(),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            color: state.isLocalServerRunning ? Colors.greenAccent : Colors.cyanAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${preset.name} · ${state.modelId}',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 9.5, color: Colors.white60),
                  ),
                ],
              ),
            ),
          ),
          // Быстрое изменение ширины правой панели (узкая / половина экрана / широкая)
          _buildHeaderIconBtn(
            icon: LucideIcons.columns_2,
            tooltip: 'Растянуть/сузить панель (50% / 82% / 360px)',
            color: Colors.cyanAccent,
            onTap: () {
              final cur = ref.read(rightAgentPanelWidthProvider);
              final half = (screenWidth * 0.52).clamp(280.0, screenWidth - 40);
              final wide = (screenWidth * 0.84).clamp(320.0, screenWidth - 20);
              if (cur < half - 20) {
                ref.read(rightAgentPanelWidthProvider.notifier).state = half;
              } else if (cur < wide - 20) {
                ref.read(rightAgentPanelWidthProvider.notifier).state = wide;
              } else {
                ref.read(rightAgentPanelWidthProvider.notifier).state = 350.0;
              }
            },
          ),
          _buildHeaderIconBtn(
            icon: LucideIcons.trash_2,
            tooltip: 'Очистить историю чата',
            color: Colors.white54,
            onTap: () => ref.read(quantumAgentProvider.notifier).clearHistory(),
          ),
          _buildHeaderIconBtn(
            icon: LucideIcons.x,
            tooltip: 'Скрыть панель ИИ',
            color: Colors.white70,
            onTap: () {
              if (widget.onClose != null) {
                widget.onClose!();
              } else {
                ref.read(rightAgentPanelOpenProvider.notifier).state = false;
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationTabs(QuantumAgentState state) {
    final changesCount = state.pendingChanges.length;
    final items = [
      (idx: 0, icon: LucideIcons.message_square, label: 'Чат', badge: 0),
      (idx: 1, icon: LucideIcons.git_compare, label: 'Diff', badge: changesCount),
      (idx: 2, icon: LucideIcons.cpu, label: 'Модели', badge: 0),
      (idx: 3, icon: LucideIcons.sliders_horizontal, label: 'Сервер & Настр.', badge: state.isLocalServerRunning ? 1 : 0),
    ];

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF10141E),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.6)),
      ),
      child: Row(
        children: items.map((item) {
          final selected = _activeTab == item.idx;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                onTap: () => setState(() => _activeTab = item.idx),
                borderRadius: BorderRadius.circular(6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.purpleAccent.withValues(alpha: 0.18)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: selected
                          ? Colors.purpleAccent.withValues(alpha: 0.5)
                          : Colors.transparent,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.icon,
                        size: 12,
                        color: selected ? Colors.purpleAccent : Colors.white54,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          item.label,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? Colors.white : Colors.white60,
                          ),
                        ),
                      ),
                      if (item.badge > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                          decoration: BoxDecoration(
                            color: item.idx == 3 ? Colors.greenAccent : Colors.amberAccent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            item.idx == 3 ? 'ON' : '${item.badge}',
                            style: GoogleFonts.inter(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ВКЛАДКА 0: ЧАТ С АВТОНОМНЫМ АГЕНТОМ + THOUGHT DISCLOSURE (<think>)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildChatTab(
    QuantumAgentState state,
    QuantumAgentProviderPreset preset,
    String? workspacePath,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Быстрые кнопки действий
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0E121B),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.5)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildQuickActionChip(
                  icon: LucideIcons.wrench,
                  label: '🔧 Исправить ошибки',
                  color: Colors.orangeAccent,
                  onTap: () => _sendPrompt(
                    'Просканируй проект, проверь все ошибки синтаксиса и сборки APK и исправь их.',
                  ),
                ),
                const SizedBox(width: 6),
                _buildQuickActionChip(
                  icon: LucideIcons.refresh_cw,
                  label: '🔄 Синхр. проект',
                  color: Colors.cyanAccent,
                  onTap: () => _sendPrompt(
                    'Синхронизируй файлы проекта с внешней папкой /storage/emulated/0/QuantumIDE и проверь целостность.',
                  ),
                ),
                const SizedBox(width: 6),
                _buildQuickActionChip(
                  icon: LucideIcons.shield_check,
                  label: '🔍 Проверить код',
                  color: Colors.greenAccent,
                  onTap: () => _sendPrompt(
                    'Выполни полную диагностику всех .dart файлов и конфигурации Gradle.',
                  ),
                ),
                const SizedBox(width: 6),
                _buildQuickActionChip(
                  icon: LucideIcons.package_check,
                  label: '📦 Собрать APK',
                  color: Colors.purpleAccent,
                  onTap: () => _sendPrompt('Собрать APK'),
                ),
              ],
            ),
          ),
        ),

        // Список сообщений
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            itemCount: state.messages.length,
            itemBuilder: (context, index) {
              final msg = state.messages[index];
              return _buildMessageBubble(msg, workspacePath);
            },
          ),
        ),

        // Индикатор работы
        if (state.isWorking)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF151926),
            child: Row(
              children: [
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purpleAccent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.statusText.isEmpty ? 'Quantum Agent выполняет задачу...' : state.statusText,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                  ),
                ),
                InkWell(
                  onTap: () => ref.read(quantumAgentProvider.notifier).stopGeneration(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Стоп',
                      style: GoogleFonts.inter(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Поле ввода сообщения
        Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF121622),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.6)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 110),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0D14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: TextField(
                    controller: _inputController,
                    maxLines: null,
                    style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white),
                    onSubmitted: (_) => _sendPrompt(),
                    decoration: InputDecoration(
                      hintText: 'Напишите задачу (код, баг, команда)...',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: state.isWorking ? null : () => _sendPrompt(),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: state.isWorking
                          ? [Colors.grey.shade800, Colors.grey.shade700]
                          : [const Color(0xFF8B5CF6), const Color(0xFF06B6D4)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(LucideIcons.send, size: 15, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ВКЛАДКА 1: ИЗМЕНЕНИЯ И ПОСТРОЧНЫЙ DIFF (ИЗ Mobile-Harness WorkspaceCheckpoints)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildChangesDiffTab(QuantumAgentState state, String? workspacePath) {
    final changes = state.pendingChanges;
    if (changes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.git_compare, size: 38, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(height: 12),
              Text(
                'Нет ожидающих проверки изменений',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70),
              ),
              const SizedBox(height: 6),
              Text(
                'Когда ИИ-агент изменяет или создаёт файлы, здесь автоматически появляется построчный Diff с кнопками «Принять (Keep)» и «Откатить (Undo)».',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF141824),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
          ),
          child: Row(
            children: [
              Text(
                'Изменено файлов: ${changes.length}',
                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => ref.read(quantumAgentProvider.notifier).undoAllChanges(),
                icon: const Icon(LucideIcons.rotate_ccw, size: 12, color: Colors.redAccent),
                label: Text('Откатить все', style: GoogleFonts.inter(fontSize: 10.5, color: Colors.redAccent)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: () => ref.read(quantumAgentProvider.notifier).acceptAllChanges(),
                icon: const Icon(LucideIcons.check_check, size: 12, color: Colors.black),
                label: Text(
                  'Принять все',
                  style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.black),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: changes.length,
            itemBuilder: (context, index) {
              final item = changes[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF131722),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: ExpansionTile(
                  initiallyExpanded: index == 0,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  iconColor: Colors.white54,
                  collapsedIconColor: Colors.white38,
                  title: Row(
                    children: [
                      const Icon(LucideIcons.file_diff, size: 13, color: Colors.cyanAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            if (workspacePath != null) {
                              ref.read(editorProvider.notifier).openFile(p.join(workspacePath, item.relativePath));
                            }
                          },
                          child: Text(
                            item.relativePath,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.cyanAccent,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        '+${item.additions}',
                        style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: Colors.greenAccent, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '-${item.deletions}',
                        style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: Colors.redAccent, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: () => ref.read(quantumAgentProvider.notifier).acceptChange(item.relativePath),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4), width: 0.6),
                            ),
                            child: Text('✓ Keep (Оставить)', style: GoogleFonts.inter(fontSize: 9.5, color: Colors.greenAccent)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => ref.read(quantumAgentProvider.notifier).undoChange(item.relativePath),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4), width: 0.6),
                            ),
                            child: Text('↺ Undo (Откатить)', style: GoogleFonts.inter(fontSize: 9.5, color: Colors.redAccent)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxHeight: 240),
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF090C12),
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: item.diffLines.take(120).map((line) {
                            Color bg = Colors.transparent;
                            Color fg = Colors.white70;
                            String prefix = ' ';
                            if (line.type == AgentDiffLineType.addition) {
                              bg = Colors.greenAccent.withValues(alpha: 0.12);
                              fg = Colors.greenAccent;
                              prefix = '+';
                            } else if (line.type == AgentDiffLineType.deletion) {
                              bg = Colors.redAccent.withValues(alpha: 0.12);
                              fg = Colors.redAccent;
                              prefix = '-';
                            }
                            return Container(
                              color: bg,
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              child: Text(
                                '$prefix ${line.text}',
                                style: GoogleFonts.jetBrainsMono(fontSize: 10, color: fg),
                              ),
                            );
                          }).toList(),
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

  // ═══════════════════════════════════════════════════════════════════════════
  // ВКЛАДКА 2: ЦЕНТР МОДЕЛЕЙ (Cloud Providers + Harnesses + Local GGUF/LiteRT)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildModelsHubTab(QuantumAgentState state, QuantumAgentProviderPreset activePreset) {
    return Column(
      children: [
        // Переключатель Cloud & Harnesses vs Local On-Device (PrivateLM)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: _buildScopeSegmentButton(
                  label: '☁️ Облако & CLI Харнессы',
                  selected: _modelScope == 'cloud',
                  onTap: () => setState(() => _modelScope = 'cloud'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildScopeSegmentButton(
                  label: '📱 Локальные (PrivateLM)',
                  selected: _modelScope == 'local',
                  onTap: () => setState(() => _modelScope = 'local'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _modelScope == 'cloud'
              ? _buildCloudAndHarnessesView(state, activePreset)
              : _buildLocalModelsCatalogView(state),
        ),
      ],
    );
  }

  Widget _buildCloudAndHarnessesView(
    QuantumAgentState state,
    QuantumAgentProviderPreset activePreset,
  ) {
    final vaultKeys = state.savedKeysByProvider[state.providerId] ?? const [];
    final rawModels = state.discoveredModelsByProvider[state.providerId] ?? activePreset.models;
    final filteredModels = rawModels.where((m) {
      if (_modelSearchQuery.trim().isEmpty) return true;
      return m.toLowerCase().contains(_modelSearchQuery.trim().toLowerCase());
    }).toList();

    if (state.freeModelsFirst) {
      filteredModels.sort((a, b) {
        final aFree = a.contains(':free') || a.contains('free');
        final bFree = b.contains(':free') || b.contains('free');
        if (aFree != bFree) return aFree ? -1 : 1;
        return a.compareTo(b);
      });
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 20),
      children: [
        // 1. Coding Agent Harness (из Mobile-Harness AgentScreen.kt)
        _buildSectionLabel('ДВИЖОК АГЕНТА (MOBILE HARNESS)'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _buildHarnessCard(state, 'native', 'Встроенный Автопилот', LucideIcons.sparkles, const Color(0xFF8B5CF6)),
            _buildHarnessCard(state, 'antigravity', 'Antigravity CLI', LucideIcons.wand, const Color(0xFF9C27B0)),
            _buildHarnessCard(state, 'claude-code', 'Claude Code', LucideIcons.bot, const Color(0xFFD97706)),
            _buildHarnessCard(state, 'deepseek-harness', 'DeepSeek Harness', LucideIcons.brain_circuit, const Color(0xFF0284C7)),
          ],
        ),

        if (state.selectedHarness == 'antigravity' || state.providerId == 'antigravity_doctor') ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Глубина рассуждений (Effort):', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
              const Spacer(),
              for (final eff in ['low', 'medium', 'high'])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: InkWell(
                    onTap: () => ref.read(quantumAgentProvider.notifier).updateConfig(
                          providerId: state.providerId,
                          modelId: state.modelId,
                          apiKey: state.apiKey,
                          antigravityEffort: eff,
                        ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: state.antigravityEffort == eff
                            ? Colors.purpleAccent.withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: state.antigravityEffort == eff ? Colors.purpleAccent : Colors.white12,
                        ),
                      ),
                      child: Text(
                        eff.toUpperCase(),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: state.antigravityEffort == eff ? Colors.white : Colors.white54,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],

        const SizedBox(height: 14),
        // 2. Провайдеры ИИ (из cross-platform-llm-client + Mobile-Harness)
        _buildSectionLabel('ПРОВАЙДЕРЫ ИИ (11 ПРОВАЙДЕРОВ)'),
        SizedBox(
          height: 68,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: QuantumAgentProviderPreset.presets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final pItem = QuantumAgentProviderPreset.presets[index];
              final isSelected = pItem.id == state.providerId;
              return InkWell(
                onTap: () async {
                  final savedKey = await ref.read(quantumAgentProvider.notifier).getSavedKeyForProvider(pItem.id);
                  _apiKeyInputCtrl.text = savedKey;
                  await ref.read(quantumAgentProvider.notifier).updateConfig(
                        providerId: pItem.id,
                        modelId: pItem.models.first,
                        apiKey: savedKey,
                        inferenceMode: pItem.id == 'local_gguf' ? 'local' : 'cloud',
                      );
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 135,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? pItem.brandColor.withValues(alpha: 0.2)
                        : const Color(0xFF131722),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? pItem.brandColor : Colors.white.withValues(alpha: 0.08),
                      width: isSelected ? 1.2 : 0.7,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Icon(pItem.icon, size: 14, color: pItem.brandColor),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              pItem.name,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pItem.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 9, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // 3. Хранилище API-ключей (Multi-Key Vault)
        if (activePreset.requiresKey) ...[
          const SizedBox(height: 14),
          _buildSectionLabel('API КЛЮЧИ & ПРОВЕРКА (${activePreset.name.toUpperCase()})'),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF131722),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.providerId == 'custom') ...[
                  TextField(
                    controller: _customUrlCtrl,
                    style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white),
                    decoration: _compactInputDecoration('Base URL (например https://api.example.com/v1/chat/completions)'),
                    onChanged: (v) => ref.read(quantumAgentProvider.notifier).updateConfig(
                          providerId: state.providerId,
                          modelId: state.modelId,
                          apiKey: state.apiKey,
                          customBaseUrl: v.trim(),
                        ),
                  ),
                  const SizedBox(height: 6),
                ],
                Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _keyNameInputCtrl,
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.white),
                        decoration: _compactInputDecoration('Имя ключа'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _apiKeyInputCtrl,
                        obscureText: true,
                        style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white),
                        decoration: _compactInputDecoration(activePreset.keyHint),
                        onChanged: (v) => ref.read(quantumAgentProvider.notifier).updateConfig(
                              providerId: state.providerId,
                              modelId: state.modelId,
                              apiKey: v,
                            ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        ref.read(quantumAgentProvider.notifier).addVaultKey(
                              state.providerId,
                              _keyNameInputCtrl.text,
                              _apiKeyInputCtrl.text,
                            );
                        _keyNameInputCtrl.clear();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.purpleAccent.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.5)),
                        ),
                        child: const Icon(LucideIcons.plus, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                if (vaultKeys.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: vaultKeys.map((k) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: k.isActive
                              ? Colors.greenAccent.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: k.isActive ? Colors.greenAccent : Colors.white12,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () {
                                _apiKeyInputCtrl.text = k.key;
                                ref.read(quantumAgentProvider.notifier).activateVaultKey(state.providerId, k.name);
                              },
                              child: Text(
                                '${k.name} (${k.maskedKey})',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  color: k.isActive ? Colors.greenAccent : Colors.white70,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => ref.read(quantumAgentProvider.notifier).removeVaultKey(state.providerId, k.name),
                              child: const Icon(LucideIcons.x, size: 11, color: Colors.white38),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: state.isDiscoveringModels
                            ? null
                            : () => ref.read(quantumAgentProvider.notifier).discoverModelsForProvider(state.providerId),
                        icon: state.isDiscoveringModels
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.cyanAccent),
                              )
                            : const Icon(LucideIcons.refresh_cw, size: 12, color: Colors.cyanAccent),
                        label: Text(
                          'Загрузить модели & Проверить',
                          style: GoogleFonts.inter(fontSize: 10.5, color: Colors.cyanAccent),
                        ),
                      ),
                    ),
                  ],
                ),
                if (state.connectionStatusText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    state.connectionStatusText!,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: state.connectionVerified == true ? Colors.greenAccent : Colors.orangeAccent,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        // OpenRouter Routing (из Mobile-Harness)
        if (state.providerId == 'openrouter') ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF131722),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Бесплатные (:free) сверху', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
                    const Spacer(),
                    Switch(
                      value: state.freeModelsFirst,
                      onChanged: (v) => ref.read(quantumAgentProvider.notifier).updateConfig(
                            providerId: state.providerId,
                            modelId: state.modelId,
                            apiKey: state.apiKey,
                            freeModelsFirst: v,
                          ),
                    ),
                  ],
                ),
                TextField(
                  controller: _openRouterOrderCtrl,
                  style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white),
                  decoration: _compactInputDecoration('Порядок провайдеров OpenRouter (например deepinfra,together)'),
                  onChanged: (v) => ref.read(quantumAgentProvider.notifier).updateConfig(
                        providerId: state.providerId,
                        modelId: state.modelId,
                        apiKey: state.apiKey,
                        openRouterProviderOrder: v,
                      ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 14),
        // 4. Выбор модели с поиском
        _buildSectionLabel('ДОСТУПНЫЕ МОДЕЛИ (${filteredModels.length})'),
        TextField(
          style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white),
          decoration: _compactInputDecoration('Поиск модели по названию...'),
          onChanged: (v) => setState(() => _modelSearchQuery = v),
        ),
        const SizedBox(height: 8),
        ...filteredModels.take(60).map((mId) {
          final isSelected = mId == state.modelId;
          final isFree = mId.contains(':free');
          return Container(
            margin: const EdgeInsets.only(bottom: 5),
            decoration: BoxDecoration(
              color: isSelected
                  ? activePreset.brandColor.withValues(alpha: 0.18)
                  : const Color(0xFF131722),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? activePreset.brandColor : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              leading: Icon(
                isSelected ? LucideIcons.circle_check : LucideIcons.cpu,
                size: 14,
                color: isSelected ? Colors.greenAccent : Colors.white54,
              ),
              title: Text(
                mId,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              trailing: isFree
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'FREE',
                        style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w800, color: Colors.greenAccent),
                      ),
                    )
                  : null,
              onTap: () => ref.read(quantumAgentProvider.notifier).updateConfig(
                    providerId: state.providerId,
                    modelId: mId,
                    apiKey: state.apiKey,
                  ),
            ),
          );
        }),
      ],
    );
  }

  // ─── Каталог локальных моделей (из cross-platform-llm-client ModelView) ───

  Widget _buildLocalModelsCatalogView(QuantumAgentState state) {
    final filter = state.localModelFilter;
    final catalog = LocalAiModel.builtInCatalog.where((m) => m.category == filter).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 20),
      children: [
        // Фильтры категорий локальных моделей (Chat / Vision / Uncensored / Image SD)
        Row(
          children: [
            for (final item in [
              (id: 'general', label: '💬 Chat'),
              (id: 'vision', label: '👁️ Vision'),
              (id: 'uncensored', label: '🔓 Uncensored'),
              (id: 'image', label: '🎨 Image SD'),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: () => ref.read(quantumAgentProvider.notifier).setLocalModelFilter(item.id),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: filter == item.id
                            ? Colors.tealAccent.withValues(alpha: 0.2)
                            : const Color(0xFF131722),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: filter == item.id ? Colors.tealAccent : Colors.white12,
                        ),
                      ),
                      child: Text(
                        item.label,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: filter == item.id ? Colors.tealAccent : Colors.white60,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => ref.read(quantumAgentProvider.notifier).importLocalModelFromStorage(),
          icon: const Icon(LucideIcons.folder_open, size: 13, color: Colors.tealAccent),
          label: Text(
            'Импортировать .gguf / .litertlm / .safetensors с телефона',
            style: GoogleFonts.inter(fontSize: 10.5, color: Colors.tealAccent),
          ),
        ),
        const SizedBox(height: 8),
        ...catalog.map((m) {
          final isDownloaded = state.downloadedLocalModels.contains(m.filename);
          final isActive = state.activeLocalModel == m.filename && state.inferenceMode == 'local';
          final progress = state.downloadProgressByFile[m.filename];

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.tealAccent.withValues(alpha: 0.12)
                  : const Color(0xFF131722),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isActive ? Colors.tealAccent : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      m.isImageGen
                          ? LucideIcons.image
                          : m.isVision
                              ? LucideIcons.eye
                              : LucideIcons.cpu,
                      size: 14,
                      color: Colors.tealAccent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        m.name,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        m.size,
                        style: GoogleFonts.jetBrainsMono(fontSize: 9.5, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  m.description,
                  style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white60),
                ),
                const SizedBox(height: 8),
                if (progress != null) ...[
                  LinearProgressIndicator(
                    value: progress,
                    color: Colors.tealAccent,
                    backgroundColor: Colors.white12,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Скачивание: ${(progress * 100).toStringAsFixed(0)}%',
                        style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.tealAccent),
                      ),
                      InkWell(
                        onTap: () => ref.read(quantumAgentProvider.notifier).cancelLocalDownload(m.filename),
                        child: Text('Отмена', style: GoogleFonts.inter(fontSize: 10, color: Colors.redAccent)),
                      ),
                    ],
                  ),
                ] else
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.purpleAccent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          m.runtime.toUpperCase(),
                          style: GoogleFonts.jetBrainsMono(fontSize: 8.5, color: Colors.purpleAccent),
                        ),
                      ),
                      const Spacer(),
                      if (isDownloaded) ...[
                        InkWell(
                          onTap: () => ref.read(quantumAgentProvider.notifier).selectActiveLocalModel(m.filename),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isActive ? Colors.greenAccent : Colors.tealAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              isActive ? '✓ Активна' : 'Загрузить в чат',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isActive ? Colors.black : Colors.tealAccent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => ref.read(quantumAgentProvider.notifier).deleteLocalModel(m.filename),
                          child: const Icon(LucideIcons.trash_2, size: 13, color: Colors.redAccent),
                        ),
                      ] else
                        InkWell(
                          onTap: () => ref.read(quantumAgentProvider.notifier).downloadLocalModel(m),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.cyanAccent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.download, size: 11, color: Colors.cyanAccent),
                                const SizedBox(width: 4),
                                Text(
                                  'Скачать',
                                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.cyanAccent),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ВКЛАДКА 3: НАСТРОЙКИ ПАРАМЕТРОВ МОДЕЛИ + ЛОКАЛЬНЫЙ OPENAI СЕРВЕР
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSettingsAndServerTab(QuantumAgentState state) {
    final baseUrl = 'http://127.0.0.1:${state.localServerPort}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
      children: [
        // ── 1. ЛОКАЛЬНЫЙ OPENAI API СЕРВЕР (из cross-platform-llm-client ServerView) ──
        _buildSectionLabel('ЛОКАЛЬНЫЙ OPENAI API СЕРВЕР'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF131722),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: state.isLocalServerRunning
                  ? Colors.greenAccent.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: state.isLocalServerRunning ? Colors.greenAccent : Colors.white38,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.isLocalServerRunning
                          ? 'Сервер запущен на порту ${state.localServerPort}'
                          : 'Сервер остановлен',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => ref
                        .read(quantumAgentProvider.notifier)
                        .toggleLocalOpenAiServer(!state.isLocalServerRunning),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: state.isLocalServerRunning ? Colors.redAccent : Colors.greenAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                    ),
                    child: Text(
                      state.isLocalServerRunning ? 'Остановить' : 'Запустить',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: state.isLocalServerRunning ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Эндпоинт: $baseUrl/v1/chat/completions · Запросов: ${state.localServerRequestsCount}',
                style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.cyanAccent),
              ),
              const Divider(color: Colors.white12, height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Доступ из локальной сети (0.0.0.0)', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
                  Switch(
                    value: state.localServerAllowNetwork,
                    onChanged: (v) => ref.read(quantumAgentProvider.notifier).updateServerConfig(allowNetwork: v),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Требовать Bearer API-ключ', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
                  Switch(
                    value: state.localServerRequireKey,
                    onChanged: (v) => ref.read(quantumAgentProvider.notifier).updateServerConfig(requireKey: v),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      'Ключ: ${state.localServerApiKey}',
                      style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: Colors.white70),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.refresh_cw, size: 13, color: Colors.cyanAccent),
                    tooltip: 'Сгенерировать новый ключ',
                    onPressed: () => ref.read(quantumAgentProvider.notifier).generateNewServerKey(),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.copy, size: 13, color: Colors.white70),
                    tooltip: 'Скопировать curl-пример',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                        text: 'curl $baseUrl/v1/chat/completions -H "Content-Type: application/json" '
                            '-d \'{"model":"${state.modelId}","messages":[{"role":"user","content":"Hello"}]}\'',
                      ));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),
        // ── 2. ПАРАМЕТРЫ ГЕНЕРАЦИИ (из cross-platform-llm-client SettingsView) ──
        _buildSectionLabel('ПАРАМЕТРЫ МОДЕЛИ (TEMPERATURE / TOKENS / CONTEXT)'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF131722),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Temperature (креативность)', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
                  Text(
                    state.temperature.toStringAsFixed(2),
                    style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              Slider(
                value: state.temperature.clamp(0.0, 2.0),
                min: 0.0,
                max: 2.0,
                divisions: 40,
                activeColor: Colors.purpleAccent,
                onChanged: (v) => ref.read(quantumAgentProvider.notifier).updateGenerationParams(temperature: v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Max Tokens (длина ответа)', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
                  Text(
                    '${state.maxTokens}',
                    style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              Slider(
                value: state.maxTokens.toDouble().clamp(256, 8192),
                min: 256,
                max: 8192,
                divisions: 31,
                activeColor: Colors.cyanAccent,
                onChanged: (v) => ref.read(quantumAgentProvider.notifier).updateGenerationParams(maxTokens: v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Context Size (контекстное окно)', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
                  Text(
                    '${state.contextSize}',
                    style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              Slider(
                value: state.contextSize.toDouble().clamp(1024, 32768),
                min: 1024,
                max: 32768,
                divisions: 31,
                activeColor: Colors.tealAccent,
                onChanged: (v) => ref.read(quantumAgentProvider.notifier).updateGenerationParams(contextSize: v.round()),
              ),
              const SizedBox(height: 6),
              Text('Режим ускорения GGUF & LiteRT:', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final mode in [
                    (id: 'auto_fast', label: '⚡ Auto Fast'),
                    (id: 'gpu_fast', label: '🚀 GPU Fast'),
                    (id: 'cpu_safe', label: '🛡️ CPU Safe'),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: InkWell(
                          onTap: () => ref.read(quantumAgentProvider.notifier).updateGenerationParams(performanceMode: mode.id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: state.performanceMode == mode.id
                                  ? Colors.purpleAccent.withValues(alpha: 0.22)
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: state.performanceMode == mode.id ? Colors.purpleAccent : Colors.white12,
                              ),
                            ),
                            child: Text(
                              mode.label,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: state.performanceMode == mode.id ? Colors.white : Colors.white60,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text('Дополнительная системная инструкция (System Prompt):', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 4),
              TextField(
                controller: _customSysPromptCtrl,
                maxLines: 3,
                style: GoogleFonts.inter(fontSize: 11, color: Colors.white),
                decoration: _compactInputDecoration('Например: Всегда используй Riverpod и пиши комментарии на русском...'),
                onChanged: (v) => ref.read(quantumAgentProvider.notifier).updateGenerationParams(
                      systemPromptPreset: v.trim().isEmpty ? 'agent' : 'custom',
                      customSystemPrompt: v,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ВСПОМОГАТЕЛЬНЫЕ ВИДЖЕТЫ СООБЩЕНИЙ И КНОПОК
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMessageBubble(AgentChatMessage message, String? workspacePath) {
    final isUser = message.role == 'user';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isUser ? const Color(0xFF1E1B3A) : const Color(0xFF131722),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isUser
              ? Colors.purpleAccent.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.07),
          width: 0.7,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isUser ? LucideIcons.user : LucideIcons.bot,
                size: 13,
                color: isUser ? Colors.purpleAccent : Colors.cyanAccent,
              ),
              const SizedBox(width: 6),
              Text(
                isUser ? 'Вы' : 'Quantum Agent',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isUser ? Colors.purpleAccent : Colors.cyanAccent,
                ),
              ),
              const Spacer(),
              if (!isUser && message.content.isNotEmpty)
                InkWell(
                  onTap: () => Clipboard.setData(ClipboardData(text: message.content)),
                  child: const Icon(LucideIcons.copy, size: 12, color: Colors.white38),
                ),
            ],
          ),

          // Collapsible Thought Disclosure (<think> из cross-platform-llm-client)
          if (message.thinking != null && message.thinking!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: Colors.purpleAccent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.2), width: 0.5),
              ),
              child: ExpansionTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                tilePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                iconColor: Colors.purpleAccent,
                collapsedIconColor: Colors.purpleAccent,
                title: Row(
                  children: [
                    const Icon(LucideIcons.brain_circuit, size: 12, color: Colors.purpleAccent),
                    const SizedBox(width: 6),
                    Text(
                      message.thinkingDurationMs > 0
                          ? 'Мысли ИИ (${(message.thinkingDurationMs / 1000).toStringAsFixed(1)} сек)'
                          : 'Мысли ИИ (Reasoning)',
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.purpleAccent),
                    ),
                  ],
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: SelectableText(
                      message.thinking!,
                      style: GoogleFonts.inter(fontSize: 10.5, fontStyle: FontStyle.italic, color: Colors.white60),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Шаги инструментов
          if (message.toolCalls.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...message.toolCalls.map((tc) => _buildToolCallCard(tc)),
          ],

          // Основной текст ответа
          if (message.content.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              message.content,
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.42,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
          ],

          // Бейджи изменённых файлов
          if (message.modifiedFiles.isNotEmpty && workspacePath != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: message.modifiedFiles.take(8).map((relPath) {
                final fullPath = p.isAbsolute(relPath) ? relPath : p.join(workspacePath, relPath);
                return InkWell(
                  onTap: () {
                    ref.read(editorProvider.notifier).openFile(fullPath);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.35), width: 0.6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.file_code, size: 11, color: Colors.greenAccent),
                        const SizedBox(width: 4),
                        Text(
                          relPath,
                          style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.greenAccent),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolCallCard(AgentToolCall tc) {
    final Color statusColor = tc.isRunning
        ? Colors.amberAccent
        : (tc.isError ? Colors.redAccent : Colors.greenAccent);
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E15),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (tc.isRunning)
                const SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 1.6, color: Colors.amberAccent),
                )
              else
                Icon(
                  tc.isError ? LucideIcons.circle_alert : LucideIcons.circle_check,
                  size: 12,
                  color: statusColor,
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tc.title,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          if (tc.result != null && tc.result!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              tc.result!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.jetBrainsMono(fontSize: 9.5, color: Colors.white60),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHarnessCard(
    QuantumAgentState state,
    String id,
    String title,
    IconData icon,
    Color color,
  ) {
    final selected = state.selectedHarness == id;
    return InkWell(
      onTap: () => ref.read(quantumAgentProvider.notifier).updateConfig(
            providerId: state.providerId,
            modelId: state.modelId,
            apiKey: state.apiKey,
            selectedHarness: id,
          ),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.22) : const Color(0xFF131722),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeSegmentButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.purpleAccent.withValues(alpha: 0.22) : const Color(0xFF131722),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Colors.purpleAccent : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : Colors.white60,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 0.7),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildHeaderIconBtn({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return IconButton(
      icon: Icon(icon, size: 15, color: color),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
      onPressed: onTap,
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: Colors.white54,
        ),
      ),
    );
  }

  InputDecoration _compactInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 10.5, color: Colors.white38),
      filled: true,
      fillColor: const Color(0xFF0A0D14),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: Colors.white12),
      ),
    );
  }
}
