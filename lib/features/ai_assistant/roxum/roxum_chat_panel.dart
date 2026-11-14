// Ported & adapted from roxum-ide (MIT License) - https://github.com/heckmon/roxum-ide

import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_ai_client.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_chat_notifier.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_tool_catalog.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';

class RoxumChatPanel extends ConsumerStatefulWidget {
  final VoidCallback? onClose;
  final VoidCallback? onToggleExpand;
  final bool isExpanded;

  const RoxumChatPanel({
    super.key,
    this.onClose,
    this.onToggleExpand,
    this.isExpanded = false,
  });

  @override
  ConsumerState<RoxumChatPanel> createState() => _RoxumChatPanelState();
}

class _RoxumChatPanelState extends ConsumerState<RoxumChatPanel> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _pendingExpanded = false;
  int? _editingTurnIndex;
  final List<RoxumAttachment> _attachments = [];

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickAttachment({required bool imagesOnly}) async {
    try {
      final files = await FilePicker.pickFiles(
        type: imagesOnly ? FileType.image : FileType.any,
      );
      if (files.isEmpty || !mounted) return;

      final added = <RoxumAttachment>[];
      for (final file in files) {
        final filePath = file.path;
        if (filePath == null) continue;
        final bytes = await File(filePath).readAsBytes();
        final ext = p.extension(file.name).toLowerCase();
        final isImg = imagesOnly ||
            const ['.png', '.jpg', '.jpeg', '.webp', '.gif'].contains(ext);
        if (isImg) {
          final mime = switch (ext) {
            '.png' => 'image/png',
            '.webp' => 'image/webp',
            '.gif' => 'image/gif',
            _ => 'image/jpeg',
          };
          added.add(
            RoxumAttachment(
              name: file.name,
              mimeType: mime,
              base64Data: base64Encode(bytes),
              sizeBytes: bytes.length,
            ),
          );
        } else {
          String? textContent;
          if (bytes.length <= 120 * 1024) {
            try {
              textContent = utf8.decode(bytes);
            } catch (_) {}
          }
          added.add(
            RoxumAttachment(
              name: file.name,
              mimeType: 'text/plain',
              textContent: textContent,
              sizeBytes: bytes.length,
            ),
          );
        }
      }
      if (!mounted) return;
      if (added.isNotEmpty) {
        setState(() => _attachments.addAll(added));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось прикрепить файл: $e')),
      );
    }
  }

  void _sendPrompt() {
    final text = _promptController.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    final truncateIdx = _editingTurnIndex;
    final attached = List<RoxumAttachment>.from(_attachments);
    _editingTurnIndex = null;
    _promptController.clear();
    setState(() => _attachments.clear());
    ref.read(roxumChatProvider.notifier).sendPrompt(
          text,
          truncateFromIndex: truncateIdx,
          attachments: attached,
        );
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(roxumChatProvider);
    final settings = ref.watch(settingsProvider);
    final editorState = ref.watch(editorProvider);
    final models = ref.read(roxumChatProvider.notifier).availableModels(settings);
    final session = chatState.currentSession;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D0F14) : const Color(0xFFF8FAFC);
    final surfaceColor =
        isDark ? const Color(0xFF151924) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
    final mutedColor = textColor.withValues(alpha: 0.6);

    final selectedModelId = models.any((m) => m.id == chatState.selectedModelId)
        ? chatState.selectedModelId
        : (models.isNotEmpty ? models.first.id : null);

    return Container(
      color: bgColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            children: [
              // ── Top Bar (Roxum style: Model selector + Mode + History + New) ──
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildModelSelector(
                            models: models,
                            selectedModelId: selectedModelId,
                            textColor: textColor,
                            isDark: isDark,
                          ),
                        ),
                        if (widget.onToggleExpand != null) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: widget.onToggleExpand,
                            icon: Icon(
                              widget.isExpanded
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
                              size: 18,
                              color: mutedColor,
                            ),
                            visualDensity: VisualDensity.compact,
                            tooltip: widget.isExpanded ? 'Свернуть' : 'Развернуть',
                          ),
                        ],
                        if (widget.onClose != null)
                          IconButton(
                            onPressed: widget.onClose,
                            icon: Icon(
                              LucideIcons.x,
                              size: 18,
                              color: mutedColor,
                            ),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Закрыть',
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _buildModeSelector(
                            chatState.chatMode,
                            textColor,
                            isDark,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () => _showProvidersDialog(context),
                          icon: Icon(
                            LucideIcons.plug,
                            size: 17,
                            color: models.isEmpty
                                ? Colors.orangeAccent
                                : const Color(0xFF38BDF8),
                          ),
                          tooltip: 'Подключить провайдера / API',
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: () =>
                              _showToolPermissionsSheet(context, chatState),
                          icon: Icon(
                            LucideIcons.wrench,
                            size: 18,
                            color: mutedColor,
                          ),
                          tooltip: 'Инструменты агента',
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: () =>
                              _showHistoryDialog(context, chatState),
                          icon: Icon(
                            Icons.history,
                            size: 20,
                            color: mutedColor,
                          ),
                          tooltip: 'История чатов',
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: () => ref
                              .read(roxumChatProvider.notifier)
                              .createNewSession(),
                          icon: Icon(
                            Icons.add_comment_outlined,
                            size: 20,
                            color: mutedColor,
                          ),
                          tooltip: 'Новый чат',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                              color: mutedColor,
                            ),
                          ),
                        ),
                        if (_editingTurnIndex != null)
                          TextButton(
                            onPressed: () {
                              setState(() => _editingTurnIndex = null);
                              _promptController.clear();
                            },
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text(
                              'Отменить правку',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Pending Edits Banner (Keep All / Undo All) ──
              if (chatState.pendingEdits.isNotEmpty)
                _buildPendingEditsBanner(chatState, surfaceColor, textColor),

              // ── Messages List ──
              Expanded(
                child: session.turns.isEmpty
                    ? _buildEmptyState(textColor, mutedColor, surfaceColor)
                    : ListView.builder(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: session.turns.length,
                        itemBuilder: (context, index) {
                          final turn = session.turns[index];
                          final isLast = index == session.turns.length - 1;
                          return _buildTurnItem(
                            context: context,
                            index: index,
                            turn: turn,
                            isGeneratingThis: isLast && chatState.isGenerating,
                            textColor: textColor,
                            surfaceColor: surfaceColor,
                            isDark: isDark,
                          );
                        },
                      ),
              ),

              // ── Token Counter + OpenRouter Limits Bar ──
              if (chatState.sessionUsage.totalTokens > 0 ||
                  settings.openrouterApiKey.trim().isNotEmpty)
                _buildUsageTelemetryBar(
                  chatState: chatState,
                  hasOpenRouterKey: settings.openrouterApiKey.trim().isNotEmpty,
                  surfaceColor: surfaceColor,
                  textColor: textColor,
                ),

              // ── Active File Chip + Attachments + Roxum Input Box ──
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_attachments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _attachments.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final att = entry.value;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: surfaceColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF38BDF8)
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    att.isImage
                                        ? Icons.image_outlined
                                        : Icons.insert_drive_file_outlined,
                                    size: 13,
                                    color: const Color(0xFF38BDF8),
                                  ),
                                  const SizedBox(width: 5),
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 140),
                                    child: Text(
                                      att.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  InkWell(
                                    onTap: () => setState(
                                      () => _attachments.removeAt(idx),
                                    ),
                                    child: Icon(
                                      Icons.close,
                                      size: 13,
                                      color: mutedColor,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    if (editorState.activeFilePath != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0178B9).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF0178B9).withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.description_outlined,
                                size: 12,
                                color: Color(0xFF38BDF8),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  p.basename(editorState.activeFilePath!),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF38BDF8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    TextField(
                      controller: _promptController,
                      cursorColor: textColor,
                      style: TextStyle(color: textColor, fontSize: 13.5),
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        labelText: 'Ask AI',
                        labelStyle: TextStyle(color: mutedColor, fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF0178B9),
                            width: 1.5,
                          ),
                        ),
                        prefixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: chatState.isGenerating
                                  ? null
                                  : () => _pickAttachment(imagesOnly: true),
                              icon: Icon(
                                Icons.image_outlined,
                                size: 18,
                                color: mutedColor,
                              ),
                              tooltip: 'Прикрепить фото',
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              onPressed: chatState.isGenerating
                                  ? null
                                  : () => _pickAttachment(imagesOnly: false),
                              icon: Icon(
                                Icons.attach_file,
                                size: 18,
                                color: mutedColor,
                              ),
                              tooltip: 'Прикрепить файл',
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        suffixIcon: IconButton(
                          onPressed: chatState.isGenerating
                              ? () => ref
                                  .read(roxumChatProvider.notifier)
                                  .stopGeneration()
                              : _sendPrompt,
                          icon: Icon(
                            chatState.isGenerating
                                ? Icons.stop_circle_outlined
                                : Icons.send_rounded,
                            color: chatState.isGenerating
                                ? Colors.redAccent
                                : const Color(0xFF38BDF8),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelSelector({
    required List<RoxumModelOption> models,
    required String? selectedModelId,
    required Color textColor,
    required bool isDark,
  }) {
    if (models.isEmpty) {
      return InkWell(
        onTap: () => _showProvidersDialog(context),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
          ),
          alignment: Alignment.centerLeft,
          child: const Row(
            children: [
              Icon(LucideIcons.plug, size: 13, color: Colors.orangeAccent),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Подключить провайдера / API',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orangeAccent,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedModelId,
          isExpanded: true,
          isDense: true,
          dropdownColor: isDark ? const Color(0xFF1E2230) : Colors.white,
          icon: Icon(
            Icons.arrow_drop_down,
            color: textColor.withValues(alpha: 0.6),
            size: 18,
          ),
          style: TextStyle(color: textColor, fontSize: 12.5),
          items: models.map((m) {
            return DropdownMenuItem<String>(
              value: m.id,
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.sparkles,
                    size: 13,
                    color: Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${m.provider}: ${m.name}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: textColor, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (id) {
            if (id != null) {
              ref.read(roxumChatProvider.notifier).selectModel(id);
            }
          },
        ),
      ),
    );
  }

  Widget _buildModeSelector(
    RoxumChatMode mode,
    Color textColor,
    bool isDark,
  ) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<RoxumChatMode>(
          value: mode,
          isDense: true,
          dropdownColor: isDark ? const Color(0xFF1E2230) : Colors.white,
          icon: Icon(
            Icons.arrow_drop_down,
            color: textColor.withValues(alpha: 0.6),
            size: 18,
          ),
          style: TextStyle(color: textColor, fontSize: 13),
          items: [
            DropdownMenuItem(
              value: RoxumChatMode.ask,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 14,
                    color: textColor.withValues(alpha: 0.75),
                  ),
                  const SizedBox(width: 6),
                  Text('Ask', style: TextStyle(color: textColor, fontSize: 13)),
                ],
              ),
            ),
            DropdownMenuItem(
              value: RoxumChatMode.agent,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.smart_toy_outlined,
                    size: 14,
                    color: textColor.withValues(alpha: 0.75),
                  ),
                  const SizedBox(width: 6),
                  Text('Agent', style: TextStyle(color: textColor, fontSize: 13)),
                ],
              ),
            ),
          ],
          onChanged: (next) {
            if (next != null) {
              ref.read(roxumChatProvider.notifier).setChatMode(next);
            }
          },
        ),
      ),
    );
  }

  Widget _buildPendingEditsBanner(
    RoxumChatState chatState,
    Color surfaceColor,
    Color textColor,
  ) {
    final edits = chatState.pendingEdits.values.toList();
    final totalAdded = edits.fold<int>(0, (s, e) => s + e.addedLines);
    final totalRemoved = edits.fold<int>(0, (s, e) => s + e.removedLines);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF0178B9).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              InkWell(
                onTap: () =>
                    setState(() => _pendingExpanded = !_pendingExpanded),
                child: Row(
                  children: [
                    Icon(
                      _pendingExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                      color: textColor.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${edits.length} файл(ов)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '+$totalAdded',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF22C55E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '-$totalRemoved',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    ref.read(roxumChatProvider.notifier).undoAllEdits(),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text(
                  'Отменить',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFFEF4444)),
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(roxumChatProvider.notifier).keepAllEdits(),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text(
                  'Принять',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF22C55E)),
                ),
              ),
            ],
          ),
          if (_pendingExpanded)
            ...edits.map((e) {
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.basename(e.filePath),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: textColor.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                    Text(
                      '+${e.addedLines} -${e.removedLines}',
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.55),
                      ),
                    ),
                    IconButton(
                      onPressed: () => ref
                          .read(roxumChatProvider.notifier)
                          .undoEdit(e.filePath),
                      icon: const Icon(
                        Icons.undo,
                        size: 15,
                        color: Color(0xFFEF4444),
                      ),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Отменить файл',
                    ),
                    IconButton(
                      onPressed: () => ref
                          .read(roxumChatProvider.notifier)
                          .keepEdit(e.filePath),
                      icon: const Icon(
                        Icons.check,
                        size: 15,
                        color: Color(0xFF22C55E),
                      ),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Принять файл',
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    Color textColor,
    Color mutedColor,
    Color surfaceColor,
  ) {
    final quickPrompts = [
      'Проверь ошибки в активном файле',
      'Объясни структуру этого проекта',
      'Найди TODO или проблемы производительности',
    ];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0178B9).withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.smart_toy_outlined,
                size: 28,
                color: Color(0xFF38BDF8),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Roxum AI Agent',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Читает файлы, правит код с diff-предпросмотром, проверяет диагностику и запускает команды.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: mutedColor),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: quickPrompts.map((q) {
                return ActionChip(
                  backgroundColor: surfaceColor,
                  side: BorderSide(color: textColor.withValues(alpha: 0.12)),
                  label: Text(
                    q,
                    style: TextStyle(fontSize: 11.5, color: textColor),
                  ),
                  onPressed: () {
                    _promptController.text = q;
                    _sendPrompt();
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTurnItem({
    required BuildContext context,
    required int index,
    required RoxumConversationTurn turn,
    required bool isGeneratingThis,
    required Color textColor,
    required Color surfaceColor,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── User Bubble ──
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onLongPress: () => _showUserBubbleActions(index, turn),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0178B9).withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF0178B9).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  turn.userRequest,
                  style: TextStyle(color: textColor, fontSize: 13),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Tool Call Cards ──
          if (turn.toolCalls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                children: turn.toolCalls
                    .map((tc) => _buildToolCallTile(tc, surfaceColor, textColor))
                    .toList(),
              ),
            ),

          // ── Assistant Response ──
          if (isGeneratingThis && turn.aiResponse.isEmpty)
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF38BDF8),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Думаю...',
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor.withValues(alpha: 0.65),
                  ),
                ),
              ],
            )
          else if (turn.aiResponse.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: turn.isError
                    ? Colors.redAccent.withValues(alpha: 0.1)
                    : surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: turn.isError
                      ? Colors.redAccent.withValues(alpha: 0.35)
                      : textColor.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GptMarkdown(
                    turn.aiResponse,
                    style: TextStyle(
                      color: turn.isError ? Colors.redAccent : textColor,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (turn.usage.totalTokens > 0)
                        Text(
                          '↓${turn.usage.promptTokens} · ↑${turn.usage.completionTokens}${turn.usage.costUsd > 0 ? ' · \$${turn.usage.costUsd.toStringAsFixed(4)}' : ''}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: textColor.withValues(alpha: 0.45),
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: turn.aiResponse),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Ответ скопирован'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Icon(
                          Icons.copy_outlined,
                          size: 14,
                          color: textColor.withValues(alpha: 0.5),
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

  Widget _buildToolCallTile(
    RoxumToolCallRecord tc,
    Color surfaceColor,
    Color textColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withValues(alpha: 0.08)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: tc.isRunning
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF38BDF8),
                ),
              )
            : Icon(
                tc.success ? Icons.check_circle_outline : Icons.error_outline,
                size: 15,
                color: tc.success ? const Color(0xFF22C55E) : Colors.redAccent,
              ),
        title: Text(
          tc.name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Args: ${jsonEncode(tc.arguments)}',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: textColor.withValues(alpha: 0.7),
              ),
            ),
          ),
          if (tc.output.isNotEmpty) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tc.output.length > 600
                    ? '${tc.output.substring(0, 600)}...'
                    : tc.output,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: textColor.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showUserBubbleActions(
    int index,
    RoxumConversationTurn turn,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Копировать'),
                onTap: () => Navigator.of(sheetContext).pop('copy'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Редактировать и отправить'),
                onTap: () => Navigator.of(sheetContext).pop('edit'),
              ),
              ListTile(
                leading: const Icon(Icons.refresh_outlined),
                title: const Text('Повторить запрос'),
                onTap: () => Navigator.of(sheetContext).pop('retry'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == 'copy') {
      Clipboard.setData(ClipboardData(text: turn.userRequest));
    } else if (action == 'edit') {
      setState(() => _editingTurnIndex = index);
      _promptController.text = turn.userRequest;
    } else if (action == 'retry') {
      ref
          .read(roxumChatProvider.notifier)
          .sendPrompt(turn.userRequest, truncateFromIndex: index);
    }
  }

  Future<void> _showToolPermissionsSheet(
    BuildContext context,
    RoxumChatState chatState,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          builder: (_, scrollCtrl) {
            return Consumer(
              builder: (context, innerRef, _) {
                final liveState = innerRef.watch(roxumChatProvider);
                return Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Инструменты Roxum Agent',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollCtrl,
                        itemCount: agenticToolSpecs.length,
                        itemBuilder: (_, i) {
                          final spec = agenticToolSpecs[i];
                          final enabled =
                              liveState.toolSelections[spec.name] ?? true;
                          return SwitchListTile(
                            value: enabled,
                            onChanged: (v) => innerRef
                                .read(roxumChatProvider.notifier)
                                .toggleTool(spec.name, v),
                            title: Text(
                              spec.label,
                              style: const TextStyle(fontSize: 13.5),
                            ),
                            subtitle: Text(
                              spec.description,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            dense: true,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showHistoryDialog(
    BuildContext context,
    RoxumChatState chatState,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('История чатов'),
          content: SizedBox(
            width: 340,
            height: 320,
            child: ListView.builder(
              itemCount: chatState.sessions.length,
              itemBuilder: (_, i) {
                final s = chatState.sessions[i];
                final isCurrent = s.id == chatState.currentSessionId;
                return ListTile(
                  selected: isCurrent,
                  title: Text(
                    s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${s.turns.length} сообщений'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () {
                      ref.read(roxumChatProvider.notifier).deleteSession(s.id);
                      Navigator.of(dialogCtx).pop();
                    },
                  ),
                  onTap: () {
                    ref.read(roxumChatProvider.notifier).switchSession(s.id);
                    Navigator.of(dialogCtx).pop();
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUsageTelemetryBar({
    required RoxumChatState chatState,
    required bool hasOpenRouterKey,
    required Color surfaceColor,
    required Color textColor,
  }) {
    final u = chatState.sessionUsage;
    final orLimits = chatState.openRouterLimits;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.gauge,
            size: 13,
            color: Color(0xFF38BDF8),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                Text(
                  '↓ ${u.promptTokens}',
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor.withValues(alpha: 0.75),
                  ),
                ),
                Text(
                  '↑ ${u.completionTokens}',
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor.withValues(alpha: 0.75),
                  ),
                ),
                Text(
                  'Σ ${u.totalTokens}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                if (u.costUsd > 0)
                  Text(
                    '\$${u.costUsd.toStringAsFixed(4)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF22C55E),
                    ),
                  ),
                if (orLimits != null)
                  Text(
                    orLimits.limitRemainingUsd != null
                        ? 'OR ост: \$${orLimits.limitRemainingUsd!.toStringAsFixed(2)}'
                        : (orLimits.freeDailyRemaining != null
                            ? 'OR Free: ${orLimits.freeDailyRemaining}/${orLimits.freeDailyLimit}'
                            : 'OR: \$${orLimits.usageUsd.toStringAsFixed(3)}'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFA78BFA),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          if (hasOpenRouterKey)
            InkWell(
              onTap: () => ref
                  .read(roxumChatProvider.notifier)
                  .refreshOpenRouterLimits(),
              child: Tooltip(
                message: 'Обновить лимиты OpenRouter',
                child: Icon(
                  Icons.refresh,
                  size: 14,
                  color: textColor.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showProvidersDialog(BuildContext context) async {
    final s = ref.read(settingsProvider);
    final openRouterCtrl = TextEditingController(text: s.openrouterApiKey);
    final customUrlCtrl = TextEditingController(text: s.customApiBaseUrl);
    final customKeyCtrl = TextEditingController(text: s.customApiKey);
    final customModelCtrl = TextEditingController(text: s.customApiModel);
    final geminiCtrl = TextEditingController(text: s.geminiApiKey);
    final deepseekCtrl = TextEditingController(text: s.deepseekApiKey);
    final openaiCtrl = TextEditingController(text: s.openaiApiKey);
    final anthropicCtrl = TextEditingController(text: s.anthropicApiKey);
    final groqCtrl = TextEditingController(text: s.groqApiKey);

    OpenRouterKeyLimits? limitsPreview;
    String? limitsError;
    bool checkingLimits = false;

    List<String> fetchedModels = const [];
    String? modelsError;
    bool fetchingModels = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(LucideIcons.plug, size: 18, color: Color(0xFF38BDF8)),
                  SizedBox(width: 8),
                  Text('Провайдеры и API', style: TextStyle(fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'OpenRouter',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: openRouterCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'OpenRouter API Key (sk-or-v1-...)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: checkingLimits
                                ? null
                                : () async {
                                    final key = openRouterCtrl.text.trim();
                                    if (key.isEmpty) return;
                                    setModalState(() {
                                      checkingLimits = true;
                                      limitsError = null;
                                    });
                                    try {
                                      final res = await RoxumAiClient
                                          .fetchOpenRouterKeyLimits(key);
                                      setModalState(() {
                                        limitsPreview = res;
                                        checkingLimits = false;
                                      });
                                    } catch (e) {
                                      setModalState(() {
                                        limitsError = e.toString();
                                        checkingLimits = false;
                                      });
                                    }
                                  },
                            icon: checkingLimits
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.speed, size: 14),
                            label: const Text('Проверить лимиты'),
                          ),
                        ],
                      ),
                      if (limitsError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            limitsError!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      if (limitsPreview != null)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0178B9).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ключ: ${limitsPreview!.label}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Потрачено всего: \$${limitsPreview!.usageUsd.toStringAsFixed(4)} • Сегодня: \$${limitsPreview!.usageDailyUsd.toStringAsFixed(4)}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              if (limitsPreview!.limitRemainingUsd != null)
                                Text(
                                  'Остаток лимита: \$${limitsPreview!.limitRemainingUsd!.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              if (limitsPreview!.freeDailyRemaining != null)
                                Text(
                                  'Бесплатные запросы сегодня: ${limitsPreview!.freeDailyRemaining} / ${limitsPreview!.freeDailyLimit}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                      const Divider(height: 20),
                      const Text(
                        'Локальный ИИ / Custom OpenAI (/v1)',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: customUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Base URL (например http://10.61.156.225:8080/v1)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: customKeyCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Bearer Token / API Key (если нужен)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: customModelCtrl,
                        decoration: const InputDecoration(
                          labelText: 'ID модели',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: fetchingModels
                            ? null
                            : () async {
                                setModalState(() {
                                  fetchingModels = true;
                                  modelsError = null;
                                });
                                try {
                                  final list =
                                      await RoxumAiClient.fetchRemoteModels(
                                    baseUrl: customUrlCtrl.text.trim(),
                                    apiKey: customKeyCtrl.text.trim(),
                                  );
                                  setModalState(() {
                                    fetchedModels = list;
                                    if (list.isNotEmpty &&
                                        customModelCtrl.text.trim().isEmpty) {
                                      customModelCtrl.text = list.first;
                                    }
                                    fetchingModels = false;
                                  });
                                } catch (e) {
                                  setModalState(() {
                                    modelsError = e.toString();
                                    fetchingModels = false;
                                  });
                                }
                              },
                        icon: fetchingModels
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_download_outlined, size: 14),
                        label: const Text('Загрузить модели (/v1/models)'),
                      ),
                      if (modelsError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            modelsError!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      if (fetchedModels.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: fetchedModels.map((id) {
                              return ActionChip(
                                label: Text(id, style: const TextStyle(fontSize: 11)),
                                onPressed: () =>
                                    setModalState(() => customModelCtrl.text = id),
                              );
                            }).toList(),
                          ),
                        ),
                      const Divider(height: 20),
                      const Text(
                        'Другие облачные провайдеры',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: geminiCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Google Gemini API Key',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: deepseekCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'DeepSeek API Key',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: openaiCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'OpenAI API Key',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: anthropicCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Anthropic Claude API Key',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: groqCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Groq API Key',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () async {
                    final notifier = ref.read(settingsProvider.notifier);
                    await notifier.setOpenrouterApiKey(openRouterCtrl.text.trim());
                    await notifier.setCustomApiBaseUrl(customUrlCtrl.text.trim());
                    await notifier.setCustomApiKey(customKeyCtrl.text.trim());
                    await notifier.setCustomApiModel(customModelCtrl.text.trim());
                    await notifier.setGeminiApiKey(geminiCtrl.text.trim());
                    await notifier.setDeepseekApiKey(deepseekCtrl.text.trim());
                    await notifier.setOpenaiApiKey(openaiCtrl.text.trim());
                    await notifier.setAnthropicApiKey(anthropicCtrl.text.trim());
                    await notifier.setGroqApiKey(groqCtrl.text.trim());
                    final chatNotifier = ref.read(roxumChatProvider.notifier);
                    if (customUrlCtrl.text.trim().isNotEmpty) {
                      chatNotifier.refreshCustomModels();
                    }
                    if (openRouterCtrl.text.trim().isNotEmpty) {
                      chatNotifier.refreshOpenRouterLimits();
                    }
                    if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                  },
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );
    openRouterCtrl.dispose();
    customUrlCtrl.dispose();
    customKeyCtrl.dispose();
    customModelCtrl.dispose();
    geminiCtrl.dispose();
    deepseekCtrl.dispose();
    openaiCtrl.dispose();
    anthropicCtrl.dispose();
    groqCtrl.dispose();
  }
}
