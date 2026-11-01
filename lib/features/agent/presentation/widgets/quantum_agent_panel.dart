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

class QuantumAgentPanel extends ConsumerStatefulWidget {
  const QuantumAgentPanel({super.key});

  @override
  ConsumerState<QuantumAgentPanel> createState() => _QuantumAgentPanelState();
}

class _QuantumAgentPanelState extends ConsumerState<QuantumAgentPanel> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
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
    ref.read(quantumAgentProvider.notifier).sendUserMessage(text);
    _scrollToBottom();
  }

  Future<void> _showSettingsDialog(BuildContext context) async {
    final agentState = ref.read(quantumAgentProvider);
    final notifier = ref.read(quantumAgentProvider.notifier);

    String selectedProviderId = agentState.providerId;
    QuantumAgentProviderPreset currentPreset = QuantumAgentProviderPreset.byId(selectedProviderId);
    String selectedModelId = currentPreset.models.contains(agentState.modelId)
        ? agentState.modelId
        : currentPreset.models.first;
    final keyController = TextEditingController(text: agentState.apiKey);

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final preset = QuantumAgentProviderPreset.byId(selectedProviderId);
            return AlertDialog(
              backgroundColor: const Color(0xFF141824),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.25)),
              ),
              title: Row(
                children: [
                  const Icon(LucideIcons.bot, color: Colors.cyanAccent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Настройки Quantum Agent',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Провайдер ИИ:',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedProviderId,
                      dropdownColor: const Color(0xFF1B2030),
                      isExpanded: true,
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0D1017),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: QuantumAgentProviderPreset.presets
                          .map((p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.name, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (val) async {
                        if (val == null) return;
                        final savedKey = await notifier.getSavedKeyForProvider(val);
                        final newPreset = QuantumAgentProviderPreset.byId(val);
                        setModalState(() {
                          selectedProviderId = val;
                          selectedModelId = newPreset.models.first;
                          keyController.text = savedKey;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Модель:',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: preset.models.contains(selectedModelId) ? selectedModelId : preset.models.first,
                      dropdownColor: const Color(0xFF1B2030),
                      isExpanded: true,
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0D1017),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: preset.models
                          .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(m, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => selectedModelId = val);
                        }
                      },
                    ),
                    if (preset.requiresKey) ...[
                      const SizedBox(height: 12),
                      Text(
                        'API Ключ:',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: keyController,
                        obscureText: true,
                        style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: preset.keyHint,
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF0D1017),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          'Работает без API-ключа: автоматически синхронизирует файлы с /storage/emulated/0/QuantumIDE, восстанавливает пустые файлы, проверяет синтаксис Dart, лечит конфиги сборки и передаёт задачи в мост Antigravity.',
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.white70, height: 1.35),
                        ),
                      ),
                    ],
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
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    await notifier.updateConfig(
                      providerId: selectedProviderId,
                      modelId: selectedModelId,
                      apiKey: keyController.text,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Сохранить', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final agentState = ref.watch(quantumAgentProvider);
    final ws = ref.watch(workspaceProvider).currentPath;

    return Container(
      color: const Color(0xFF0B0E14),
      child: Column(
        children: [
          // ─── Верхняя панель (Header) ───────────────────────────────────────
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF10141D),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07), width: 0.6),
              ),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.sparkles, size: 15, color: Color(0xFF4CD7F6)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'QUANTUM AGENT',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: Colors.white,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _showSettingsDialog(context),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CD7F6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF4CD7F6).withValues(alpha: 0.3), width: 0.6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          agentState.modelId.split('/').last,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            color: const Color(0xFF4CD7F6),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(LucideIcons.settings, size: 11, color: Color(0xFF4CD7F6)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(LucideIcons.trash_2, size: 13.5, color: Colors.white54),
                  tooltip: 'Очистить чат',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () => ref.read(quantumAgentProvider.notifier).clearHistory(),
                ),
              ],
            ),
          ),

          // ─── Быстрые кнопки-действия (Quick Actions) ──────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0E121A),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.5),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _QuickActionChip(
                    icon: LucideIcons.wrench,
                    label: 'Исправить ошибки',
                    color: Colors.amberAccent,
                    onTap: () => _sendPrompt('Проверить проект, синхронизировать файлы и исправить ошибки сборки'),
                  ),
                  const SizedBox(width: 6),
                  _QuickActionChip(
                    icon: LucideIcons.refresh_cw,
                    label: 'Синхронизация',
                    color: Colors.cyanAccent,
                    onTap: () async {
                      await ref.read(editorProvider.notifier).syncExternalNow(reloadAllTabs: true);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✓ Файлы синхронизированы с /storage/emulated/0/QuantumIDE'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  _QuickActionChip(
                    icon: LucideIcons.rocket,
                    label: 'Собрать APK',
                    color: Colors.greenAccent,
                    onTap: () => _sendPrompt('Собрать APK'),
                  ),
                ],
              ),
            ),
          ),

          // ─── Список сообщений и карточек инструментов ─────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(10),
              itemCount: agentState.messages.length,
              itemBuilder: (context, index) {
                final msg = agentState.messages[index];
                return _MessageBubble(
                  message: msg,
                  workspacePath: ws,
                );
              },
            ),
          ),

          // ─── Индикатор текущего шага агента ────────────────────────────────
          if (agentState.isWorking)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: const Color(0xFF141B29),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.8, color: Color(0xFF4CD7F6)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      agentState.statusText.isEmpty ? 'Quantum Agent работает...' : agentState.statusText,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF4CD7F6)),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => ref.read(quantumAgentProvider.notifier).stopGeneration(),
                    icon: const Icon(LucideIcons.square, size: 10, color: Colors.redAccent),
                    label: const Text('Стоп', style: TextStyle(fontSize: 10.5, color: Colors.redAccent)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),

          // ─── Поле ввода задачи ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            decoration: BoxDecoration(
              color: const Color(0xFF10141D),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.6),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 4,
                    style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white),
                    onSubmitted: (_) => _sendPrompt(),
                    decoration: InputDecoration(
                      hintText: 'Напишите задачу (исправить код, создать файл, собрать APK)...',
                      hintStyle: GoogleFonts.inter(fontSize: 11.5, color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF090C12),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF4CD7F6), width: 1),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Material(
                  color: const Color(0xFF4CD7F6),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: agentState.isWorking ? null : () => _sendPrompt(),
                    borderRadius: BorderRadius.circular(10),
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(LucideIcons.send, size: 15, color: Colors.black),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends ConsumerWidget {
  final AgentChatMessage message;
  final String? workspacePath;

  const _MessageBubble({
    required this.message,
    required this.workspacePath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.role == 'user';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isUser ? const Color(0xFF172234) : const Color(0xFF121722),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isUser
              ? const Color(0xFF4CD7F6).withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.07),
          width: 0.7,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                isUser ? LucideIcons.user : LucideIcons.sparkles,
                size: 12,
                color: isUser ? Colors.cyanAccent : const Color(0xFF4CD7F6),
              ),
              const SizedBox(width: 6),
              Text(
                isUser ? 'Вы' : 'Quantum Agent',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isUser ? Colors.cyanAccent : Colors.white,
                ),
              ),
              const Spacer(),
              if (!isUser && message.content.isNotEmpty)
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ответ скопирован'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: const Icon(LucideIcons.copy, size: 12, color: Colors.white38),
                ),
            ],
          ),

          // Карточки вызванных инструментов (в стиле Antigravity / Cline)
          if (message.toolCalls.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...message.toolCalls.map((tc) => _ToolCallCard(toolCall: tc)),
          ],

          // Текст ответа
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

          // Бейджи изменённых файлов (по клику сразу открывают файл в редакторе)
          if (message.modifiedFiles.isNotEmpty && workspacePath != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: message.modifiedFiles.take(8).map((relPath) {
                final fullPath = p.isAbsolute(relPath) ? relPath : p.join(workspacePath!, relPath);
                return InkWell(
                  onTap: () {
                    ref.read(editorProvider.notifier).openFile(fullPath, fileName: p.basename(fullPath));
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
                        const Icon(LucideIcons.file_check, size: 11, color: Colors.greenAccent),
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
}

class _ToolCallCard extends StatefulWidget {
  final AgentToolCall toolCall;
  const _ToolCallCard({required this.toolCall});

  @override
  State<_ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<_ToolCallCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tc = widget.toolCall;
    final color = tc.isError
        ? Colors.redAccent
        : (tc.isRunning ? Colors.cyanAccent : Colors.greenAccent);

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0D14),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(7),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  if (tc.isRunning)
                    const SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.cyanAccent),
                    )
                  else
                    Icon(
                      tc.isError ? LucideIcons.circle_alert : LucideIcons.circle_check,
                      size: 12,
                      color: color,
                    ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tc.title,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? LucideIcons.chevron_up : LucideIcons.chevron_down,
                    size: 12,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded && tc.result != null && tc.result!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5)),
              ),
              child: SelectableText(
                tc.result!,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: Colors.white70,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
