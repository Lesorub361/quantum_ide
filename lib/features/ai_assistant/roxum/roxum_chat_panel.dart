// Ported & adapted from roxum-ide (MIT License) - https://github.com/heckmon/roxum-ide

import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/token_counter_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/theme/conduit_palette.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_acp_bridge.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_ai_client.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_chat_notifier.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_modern_cards.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/terminal/conduit/conduit_appearance_sheet.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';

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
  final FocusNode _promptFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _pendingExpanded = false;
  int? _editingTurnIndex;
  final List<RoxumAttachment> _attachments = [];
  bool _isInputFocused = false;
  bool _hasPromptText = false;
  bool _showScrollToBottom = false;
  String? _dismissedActiveFilePath;

  @override
  void initState() {
    super.initState();
    _promptFocusNode.addListener(_handleFocusChange);
    _promptFocusNode.onKeyEvent = _handlePromptKeyEvent;
    _promptController.addListener(_handlePromptTextChange);
    _scrollController.addListener(_handleScrollChange);
  }

  @override
  void dispose() {
    _promptFocusNode.removeListener(_handleFocusChange);
    _promptFocusNode.dispose();
    _promptController.removeListener(_handlePromptTextChange);
    _promptController.dispose();
    _scrollController.removeListener(_handleScrollChange);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_isInputFocused != _promptFocusNode.hasFocus) {
      setState(() => _isInputFocused = _promptFocusNode.hasFocus);
    }
  }

  void _handlePromptTextChange() {
    final hasText = _promptController.text.trim().isNotEmpty;
    if (_hasPromptText != hasText) {
      setState(() => _hasPromptText = hasText);
    }
  }

  void _handleScrollChange() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final distFromBottom = pos.maxScrollExtent - pos.pixels;
    final shouldShow = pos.maxScrollExtent > 120 && distFromBottom > 120;
    if (_showScrollToBottom != shouldShow) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  KeyEventResult _handlePromptKeyEvent(FocusNode node, KeyEvent event) {
    final isDesktop =
        Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    if (!isDesktop) return KeyEventResult.ignored;
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      if (!isShift) {
        final isGenerating = ref.read(roxumChatProvider).isGenerating;
        if (!isGenerating) {
          _sendPrompt();
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
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

  Future<void> _copyFullChatToClipboard(
    RoxumChatSession session, {
    String? modelId,
  }) async {
    final buf = StringBuffer();
    buf.writeln('# QuantumIDE Roxum Chat Export');
    buf.writeln('- Session: ${session.title}');
    if (modelId != null && modelId.isNotEmpty) {
      buf.writeln('- Model: $modelId');
    }
    buf.writeln('- Turns: ${session.turns.length}');
    buf.writeln();

    for (var i = 0; i < session.turns.length; i++) {
      final t = session.turns[i];
      buf.writeln('---');
      buf.writeln('## Turn ${i + 1} (${t.timestamp.toIso8601String()})');
      buf.writeln('### User');
      buf.writeln(t.userRequest);
      if (t.attachmentNames.isNotEmpty) {
        buf.writeln('\nAttachments: ${t.attachmentNames.join(', ')}');
      }
      if (t.reasoningText.trim().isNotEmpty) {
        buf.writeln();
        buf.writeln('### Thinking (${t.thinkingDurationMs} ms)');
        buf.writeln(t.reasoningText.trim());
      }
      if (t.toolCalls.isNotEmpty) {
        buf.writeln();
        buf.writeln('### Tool Calls (${t.toolCalls.length})');
        for (final tc in t.toolCalls) {
          final status = tc.isRunning
              ? 'RUNNING'
              : (tc.success ? 'OK' : 'ERROR');
          buf.writeln('- `${tc.name}` [$status]');
          if (tc.arguments.isNotEmpty) {
            buf.writeln('  Args: `${jsonEncode(tc.arguments)}`');
          }
          if (tc.output.trim().isNotEmpty) {
            buf.writeln('  Output:');
            buf.writeln('  ```');
            buf.writeln(tc.output.trim());
            buf.writeln('  ```');
          }
        }
      }
      if (t.fileEdits.isNotEmpty) {
        buf.writeln();
        buf.writeln('### File Edits');
        for (final fe in t.fileEdits) {
          buf.writeln(
            '- `${fe.filePath}` (+${fe.addedLines} / -${fe.removedLines})',
          );
        }
      }
      if (t.aiResponse.trim().isNotEmpty) {
        buf.writeln();
        buf.writeln('### Assistant');
        buf.writeln(t.aiResponse.trim());
      }
      if (t.usage.totalTokens > 0) {
        buf.writeln();
        buf.writeln(
          '_Tokens: prompt=${t.usage.promptTokens}, completion=${t.usage.completionTokens}, total=${t.usage.totalTokens}_',
        );
      }
      buf.writeln();
    }

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Весь чат, размышления и логи инструментов скопированы'),
        duration: Duration(seconds: 2),
      ),
    );
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
    setState(() {
      _attachments.clear();
      _hasPromptText = false;
    });
    ref.read(roxumChatProvider.notifier).sendPrompt(
          text,
          truncateFromIndex: truncateIdx,
          attachments: attached,
        );
    _scrollToBottom();
  }

  void _clearCurrentChat(RoxumChatState chatState) {
    final notifier = ref.read(roxumChatProvider.notifier);
    if (chatState.currentSession.turns.isNotEmpty) {
      notifier.deleteSession(chatState.currentSessionId);
      if (ref.read(roxumChatProvider).currentSession.turns.isNotEmpty) {
        notifier.createNewSession();
      }
    } else {
      notifier.createNewSession();
    }
    setState(() {
      _editingTurnIndex = null;
      _attachments.clear();
    });
    _promptController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(roxumChatProvider);
    final settings = ref.watch(settingsProvider);
    final editorState = ref.watch(editorProvider);
    final models = ref.read(roxumChatProvider.notifier).availableModels(settings);
    final session = chatState.currentSession;

    final systemIsDark = Theme.of(context).brightness == Brightness.dark;
    final palette = settings.syncAppWithTerminalPalette
        ? resolveConduitPalette(settings.terminalTheme)
        : null;
    final bgColor = palette?.canvas ??
        (systemIsDark ? const Color(0xFF0D0F14) : const Color(0xFFF8FAFC));
    final isDark =
        ThemeData.estimateBrightnessForColor(bgColor) == Brightness.dark;
    final rawSurface = palette?.panel ??
        (isDark ? const Color(0xFF151924) : const Color(0xFFFFFFFF));
    final surfaceIsDark =
        ThemeData.estimateBrightnessForColor(rawSurface) == Brightness.dark;
    final surfaceColor = (surfaceIsDark == isDark)
        ? rawSurface
        : (isDark ? const Color(0xFF151924) : const Color(0xFFFFFFFF));
    final rawFg = palette?.foreground;
    final textColor = (rawFg != null &&
            (ThemeData.estimateBrightnessForColor(rawFg) == Brightness.dark) !=
                isDark)
        ? rawFg
        : (isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A));
    final mutedColor = textColor.withValues(alpha: 0.65);
    final accentColor = palette?.accent ??
        (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7));

    final selectedModelId = models.any((m) => m.id == chatState.selectedModelId)
        ? chatState.selectedModelId
        : (models.isNotEmpty ? models.first.id : null);

    final activeFilePath = editorState.activeFilePath;
    if (activeFilePath != _dismissedActiveFilePath &&
        _dismissedActiveFilePath != null &&
        activeFilePath != null) {
      // User switched to a different file; re-show chip cleanly on next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _dismissedActiveFilePath != null) {
          setState(() => _dismissedActiveFilePath = null);
        }
      });
    }
    final showActiveFileChip =
        activeFilePath != null && activeFilePath != _dismissedActiveFilePath;

    final enabledMcpCount = 0;
    final hasOpenRouterKey = settings.openrouterApiKey.trim().isNotEmpty;

    final panelTheme = Theme.of(context).copyWith(
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: Theme.of(context).colorScheme.copyWith(
            brightness: isDark ? Brightness.dark : Brightness.light,
            surface: surfaceColor,
            surfaceContainerHighest: isDark
                ? Color.lerp(surfaceColor, Colors.white, 0.08)!
                : Color.lerp(surfaceColor, Colors.black, 0.06)!,
            onSurface: textColor,
            primary: accentColor,
          ),
      textTheme: Theme.of(context).textTheme.apply(
            bodyColor: textColor,
            displayColor: textColor,
          ),
    );

    return Theme(
      data: panelTheme,
      child: Container(
        color: bgColor,
        child: SafeArea(
          top: true,
          bottom: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final panelWidth = constraints.maxWidth;
              final isNarrow = panelWidth < 400;

              Widget wrapExpanded(Widget child) {
                if (!widget.isExpanded) return child;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 780),
                    child: child,
                  ),
                );
              }

              return Column(
                children: [
                  // ── Compact Modern Header (1 row, 42px) ──
                  _buildCompactHeader(
                    context: context,
                    chatState: chatState,
                    session: session,
                    models: models,
                    enabledMcpCount: enabledMcpCount,
                    isNarrow: isNarrow,
                    textColor: textColor,
                    mutedColor: mutedColor,
                    accentColor: accentColor,
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: textColor.withValues(alpha: 0.08),
                  ),

                  // ── Pending Edits Banner (Keep All / Undo All) ──
                  if (chatState.pendingEdits.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                      child: wrapExpanded(
                        _buildPendingEditsBanner(
                          chatState,
                          surfaceColor,
                          textColor,
                          accentColor,
                        ),
                      ),
                    ),

                  // ── Messages List + Floating Scroll-to-Bottom Button ──
                  Expanded(
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: session.turns.isEmpty
                              ? wrapExpanded(
                                  _buildEmptyState(
                                    context: context,
                                    chatState: chatState,
                                    models: models,
                                    activeFilePath: activeFilePath,
                                    textColor: textColor,
                                    mutedColor: mutedColor,
                                    surfaceColor: surfaceColor,
                                    accentColor: accentColor,
                                  ),
                                )
                              : wrapExpanded(
                                  ListView.builder(
                                    controller: _scrollController,
                                    physics: const BouncingScrollPhysics(),
                                    padding: const EdgeInsets.only(
                                      top: 10,
                                      bottom: 18,
                                    ),
                                    itemCount: session.turns.length,
                                    itemBuilder: (context, index) {
                                      final turn = session.turns[index];
                                      final isLast =
                                          index == session.turns.length - 1;
                                      return _buildTurnItem(
                                        context: context,
                                        index: index,
                                        turn: turn,
                                        isGeneratingThis:
                                            isLast && chatState.isGenerating,
                                        panelWidth: widget.isExpanded
                                            ? panelWidth.clamp(0.0, 780.0)
                                            : panelWidth,
                                        textColor: textColor,
                                        surfaceColor: surfaceColor,
                                        accentColor: accentColor,
                                        isDark: isDark,
                                      );
                                    },
                                  ),
                                ),
                        ),
                        if (_showScrollToBottom && session.turns.isNotEmpty)
                          Positioned(
                            bottom: 10,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Material(
                                color: surfaceColor,
                                elevation: 3,
                                shadowColor:
                                    Colors.black.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(18),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: _scrollToBottom,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color:
                                            accentColor.withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          LucideIcons.arrow_down,
                                          size: 13,
                                          color: accentColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Вниз',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: textColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // ── Unified Modern Composer ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                    child: wrapExpanded(
                      _buildUnifiedComposer(
                        context: context,
                        chatState: chatState,
                        models: models,
                        selectedModelId: selectedModelId,
                        activeFilePath:
                            showActiveFileChip ? activeFilePath : null,
                        hasOpenRouterKey: hasOpenRouterKey,
                        surfaceColor: surfaceColor,
                        textColor: textColor,
                        mutedColor: mutedColor,
                        accentColor: accentColor,
                        isDark: isDark,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCompactHeader({
    required BuildContext context,
    required RoxumChatState chatState,
    required RoxumChatSession session,
    required List<RoxumModelOption> models,
    required int enabledMcpCount,
    required bool isNarrow,
    required Color textColor,
    required Color mutedColor,
    required Color accentColor,
  }) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Clickable session title -> opens chat history
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showHistoryDialog(context, chatState, accentColor),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.message_square,
                      size: 15,
                      color: accentColor,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          color: textColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      LucideIcons.chevron_down,
                      size: 14,
                      color: mutedColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // New chat
          IconButton(
            onPressed: () =>
                ref.read(roxumChatProvider.notifier).createNewSession(),
            icon: Icon(
              LucideIcons.square_pen,
              size: 17,
              color: mutedColor,
            ),
            tooltip: 'Новый чат',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: EdgeInsets.zero,
          ),
          // History
          IconButton(
            onPressed: () =>
                _showHistoryDialog(context, chatState, accentColor),
            icon: Icon(
              LucideIcons.history,
              size: 17,
              color: mutedColor,
            ),
            tooltip: 'История чатов',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: EdgeInsets.zero,
          ),
          if (isNarrow)
            PopupMenuButton<String>(
              tooltip: 'Ещё',
              padding: EdgeInsets.zero,
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    LucideIcons.ellipsis_vertical,
                    size: 18,
                    color: mutedColor,
                  ),
                  if (models.isEmpty || enabledMcpCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: models.isEmpty
                              ? Colors.orangeAccent
                              : const Color(0xFF22C55E),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              onSelected: (value) {
                switch (value) {
                  case 'copy_chat':
                    _copyFullChatToClipboard(
                      session,
                      modelId: chatState.selectedModelId,
                    );
                    break;
                  case 'tools':
                    _showToolPermissionsSheet(context, chatState);
                    break;
                  case 'mcp':
                    _showMcpServersDialog(context, accentColor);
                    break;
                  case 'providers':
                    _showProvidersDialog(context, accentColor);
                    break;
                  case 'clear':
                    _clearCurrentChat(chatState);
                    break;
                }
              },
              itemBuilder: (ctx) => [
                if (session.turns.isNotEmpty)
                  PopupMenuItem(
                    value: 'copy_chat',
                    child: Row(
                      children: [
                        Icon(LucideIcons.copy, size: 16, color: accentColor),
                        const SizedBox(width: 10),
                        const Text('Копировать весь чат и логи'),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'tools',
                  child: Row(
                    children: [
                      Icon(LucideIcons.wrench, size: 16, color: mutedColor),
                      const SizedBox(width: 10),
                      const Text('Инструменты агента'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'mcp',
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.blocks,
                        size: 16,
                        color: enabledMcpCount > 0
                            ? const Color(0xFF22C55E)
                            : mutedColor,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('MCP-серверы')),
                      if (enabledMcpCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF22C55E).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$enabledMcpCount',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF22C55E),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'providers',
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.plug,
                        size: 16,
                        color:
                            models.isEmpty ? Colors.orangeAccent : accentColor,
                      ),
                      const SizedBox(width: 10),
                      const Text('API провайдеры'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.trash_2,
                        size: 16,
                        color: Colors.redAccent,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Очистить чат',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else ...[
            IconButton(
              onPressed: () => _showToolPermissionsSheet(context, chatState),
              icon: Icon(
                LucideIcons.wrench,
                size: 17,
                color: mutedColor,
              ),
              tooltip: 'Инструменты агента',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              onPressed: () => _showMcpServersDialog(context, accentColor),
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    LucideIcons.blocks,
                    size: 17,
                    color: enabledMcpCount > 0
                        ? const Color(0xFF22C55E)
                        : mutedColor,
                  ),
                  if (enabledMcpCount > 0)
                    Positioned(
                      right: -5,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3.5,
                          vertical: 0.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$enabledMcpCount',
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              tooltip: 'MCP-серверы',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              onPressed: () => _showProvidersDialog(context, accentColor),
              icon: Icon(
                LucideIcons.plug,
                size: 17,
                color: models.isEmpty ? Colors.orangeAccent : accentColor,
              ),
              tooltip: 'API провайдеры',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
            ),
            if (session.turns.isNotEmpty) ...[
              IconButton(
                onPressed: () => _copyFullChatToClipboard(
                  session,
                  modelId: chatState.selectedModelId,
                ),
                icon: Icon(
                  LucideIcons.copy,
                  size: 16.5,
                  color: mutedColor,
                ),
                tooltip: 'Копировать весь чат и логи',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                onPressed: () => _clearCurrentChat(chatState),
                icon: Icon(
                  LucideIcons.trash_2,
                  size: 17,
                  color: mutedColor,
                ),
                tooltip: 'Очистить чат',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
              ),
            ],
          ],
          if (widget.onToggleExpand != null)
            IconButton(
              onPressed: widget.onToggleExpand,
              icon: Icon(
                widget.isExpanded
                    ? LucideIcons.minimize_2
                    : LucideIcons.maximize_2,
                size: 17,
                color: mutedColor,
              ),
              tooltip: widget.isExpanded ? 'Свернуть' : 'Развернуть',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
            ),
          if (widget.onClose != null)
            IconButton(
              onPressed: widget.onClose,
              icon: Icon(
                LucideIcons.x,
                size: 18,
                color: mutedColor,
              ),
              tooltip: 'Закрыть',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  Widget _buildUnifiedComposer({
    required BuildContext context,
    required RoxumChatState chatState,
    required List<RoxumModelOption> models,
    required String? selectedModelId,
    required String? activeFilePath,
    required bool hasOpenRouterKey,
    required Color surfaceColor,
    required Color textColor,
    required Color mutedColor,
    required Color accentColor,
    required bool isDark,
  }) {
    final canSend = _hasPromptText || _attachments.isNotEmpty;
    final hasTopChips = activeFilePath != null || _attachments.isNotEmpty;
    final showTelemetry =
        chatState.sessionUsage.totalTokens > 0 || hasOpenRouterKey;

    final selectedModel = models.isEmpty
        ? null
        : models.firstWhere(
            (m) => m.id == selectedModelId,
            orElse: () => models.first,
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Editing indicator banner directly above input
        if (_editingTurnIndex != null)
          Container(
            margin: const EdgeInsets.only(bottom: 5),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accentColor.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.pencil, size: 13, color: accentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Редактирование сообщения',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() => _editingTurnIndex = null);
                    _promptController.clear();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(LucideIcons.x, size: 15, color: mutedColor),
                  ),
                ),
              ],
            ),
          ),

        // Unified Composer Card
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isInputFocused
                  ? accentColor
                  : textColor.withValues(alpha: 0.13),
              width: _isInputFocused ? 1.4 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top context / attachments strip
              if (hasTopChips)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (activeFilePath != null)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3.5,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: accentColor.withValues(alpha: 0.32),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.file_code,
                                  size: 12,
                                  color: accentColor,
                                ),
                                const SizedBox(width: 5),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 160),
                                  child: Text(
                                    p.basename(activeFilePath),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: accentColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => setState(
                                    () => _dismissedActiveFilePath =
                                        activeFilePath,
                                  ),
                                  child: Tooltip(
                                    message: 'Скрыть файл из контекста',
                                    child: Icon(
                                      LucideIcons.x,
                                      size: 12,
                                      color: accentColor.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ..._attachments.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final att = entry.value;
                          return Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3.5,
                            ),
                            decoration: BoxDecoration(
                              color: textColor.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: textColor.withValues(alpha: 0.14),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  att.isImage
                                      ? LucideIcons.image
                                      : LucideIcons.paperclip,
                                  size: 12,
                                  color: accentColor,
                                ),
                                const SizedBox(width: 5),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 130),
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
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => setState(
                                    () => _attachments.removeAt(idx),
                                  ),
                                  child: Icon(
                                    LucideIcons.x,
                                    size: 12,
                                    color: mutedColor,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),

              // Center: Clean full-width TextField
              Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  hasTopChips ? 4 : 10,
                  12,
                  4,
                ),
                child: TextField(
                  controller: _promptController,
                  focusNode: _promptFocusNode,
                  cursorColor: accentColor,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: chatState.chatMode == RoxumChatMode.agent
                        ? 'Опишите задачу для агента...'
                        : 'Спросите о коде или проекте...',
                    hintStyle: TextStyle(
                      color: mutedColor.withValues(alpha: 0.7),
                      fontSize: 13.5,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),

              // Bottom action bar inside card (height 36px)
              Container(
                height: 36,
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                child: Row(
                  children: [
                    // Attach file
                    _composerIconBtn(
                      icon: LucideIcons.paperclip,
                      tooltip: 'Прикрепить файл',
                      color: mutedColor,
                      onTap: chatState.isGenerating
                          ? null
                          : () => _pickAttachment(imagesOnly: false),
                    ),
                    // Attach photo
                    _composerIconBtn(
                      icon: LucideIcons.image,
                      tooltip: 'Прикрепить фото',
                      color: mutedColor,
                      onTap: chatState.isGenerating
                          ? null
                          : () => _pickAttachment(imagesOnly: true),
                    ),
                    const SizedBox(width: 4),
                    // Compact Mode Pill (Ask / Agent)
                    _buildCompactModePill(
                      mode: chatState.chatMode,
                      textColor: textColor,
                      accentColor: accentColor,
                      isDark: isDark,
                    ),
                    if (chatState.chatMode == RoxumChatMode.agent) ...[
                      const SizedBox(width: 4),
                      _buildCompactEnginePill(
                        context: context,
                        chatState: chatState,
                        textColor: textColor,
                        accentColor: accentColor,
                        isDark: isDark,
                      ),
                    ],
                    const SizedBox(width: 5),
                    // Compact Model Pill
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _buildCompactModelPill(
                          context: context,
                          models: models,
                          selectedModel: selectedModel,
                          isRefreshing: chatState.isRefreshingModels,
                          textColor: textColor,
                          mutedColor: mutedColor,
                          accentColor: accentColor,
                          isDark: isDark,
                        ),
                      ),
                    ),
                    // Compact Telemetry Pill (opens detail sheet)
                    if (showTelemetry) ...[
                      const SizedBox(width: 4),
                      _buildTelemetryPill(
                        context: context,
                        chatState: chatState,
                        hasOpenRouterKey: hasOpenRouterKey,
                        textColor: textColor,
                        mutedColor: mutedColor,
                        accentColor: accentColor,
                      ),
                    ],
                    if (_hasPromptText && !chatState.isGenerating) ...[
                      const SizedBox(width: 6),
                      Text(
                        TokenCounterService.formatCompact(
                          TokenCounterService.countTokens(
                            _promptController.text,
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 10,
                          color: mutedColor.withValues(alpha: 0.78),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    // Round Send / Stop Button (32x32)
                    Tooltip(
                      message: chatState.isGenerating
                          ? 'Остановить генерацию'
                          : 'Отправить',
                      child: Material(
                        color: chatState.isGenerating
                            ? Colors.redAccent
                            : (canSend
                                ? accentColor
                                : textColor.withValues(alpha: 0.12)),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: chatState.isGenerating
                              ? () => ref
                                  .read(roxumChatProvider.notifier)
                                  .stopGeneration()
                              : (canSend ? _sendPrompt : null),
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: Icon(
                              chatState.isGenerating
                                  ? Icons.stop_rounded
                                  : LucideIcons.arrow_up,
                              size: 17,
                              color: chatState.isGenerating
                                  ? Colors.white
                                  : (canSend
                                      ? (ThemeData.estimateBrightnessForColor(
                                                  accentColor) ==
                                              Brightness.dark
                                          ? Colors.white
                                          : const Color(0xFF0F172A))
                                      : mutedColor.withValues(alpha: 0.5)),
                            ),
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
      ],
    );
  }

  Widget _composerIconBtn({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(
            icon,
            size: 16,
            color: onTap == null ? color.withValues(alpha: 0.35) : color,
          ),
        ),
      ),
    );
  }

  Widget _buildCompactModePill({
    required RoxumChatMode mode,
    required Color textColor,
    required Color accentColor,
    required bool isDark,
  }) {
    final isAgent = mode == RoxumChatMode.agent;
    return Tooltip(
      message: isAgent
          ? 'Режим Agent (правит файлы и запускает команды)'
          : 'Режим Ask (только ответы без правки файлов)',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          final next = isAgent ? RoxumChatMode.ask : RoxumChatMode.agent;
          ref.read(roxumChatProvider.notifier).setChatMode(next);
        },
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isAgent
                ? accentColor.withValues(alpha: 0.16)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isAgent
                  ? accentColor.withValues(alpha: 0.4)
                  : textColor.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAgent ? LucideIcons.bot : LucideIcons.message_circle,
                size: 12,
                color: isAgent ? accentColor : textColor.withValues(alpha: 0.75),
              ),
              const SizedBox(width: 4),
              Text(
                isAgent ? 'Agent' : 'Ask',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color:
                      isAgent ? accentColor : textColor.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactEnginePill({
    required BuildContext context,
    required RoxumChatState chatState,
    required Color textColor,
    required Color accentColor,
    required bool isDark,
  }) {
    final engine = chatState.agentEngine;
    final isAcp = engine != RoxumAgentEngine.builtIn;
    final pillColor = isAcp ? const Color(0xFF10B981) : accentColor;
    final isInstalling = chatState.installingEngine != null;

    return Tooltip(
      message: 'Движок агента: ${engine.displayName} (нажмите для выбора OpenCode / Gemini / Claude ACP)',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: chatState.isGenerating
            ? null
            : () => _showEnginePickerSheet(context, accentColor),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: isAcp
                ? pillColor.withValues(alpha: 0.16)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isAcp
                  ? pillColor.withValues(alpha: 0.5)
                  : textColor.withValues(alpha: 0.13),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isInstalling)
                SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: pillColor,
                  ),
                )
              else
                Icon(
                  isAcp ? LucideIcons.zap : LucideIcons.cpu,
                  size: 11.5,
                  color: isAcp ? pillColor : textColor.withValues(alpha: 0.78),
                ),
              const SizedBox(width: 4),
              Text(
                engine.shortLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isAcp ? pillColor : textColor.withValues(alpha: 0.88),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                LucideIcons.chevron_down,
                size: 11,
                color: isAcp
                    ? pillColor.withValues(alpha: 0.85)
                    : textColor.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEnginePickerSheet(
    BuildContext context,
    Color accentColor,
  ) async {
    ref.read(roxumChatProvider.notifier).refreshInstalledEngines();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Consumer(
          builder: (ctx, sheetRef, _) {
            final st = sheetRef.watch(roxumChatProvider);
            final theme = Theme.of(ctx);
            final isDark = theme.brightness == Brightness.dark;
            final bg = isDark ? const Color(0xFF141821) : Colors.white;
            final fg = theme.colorScheme.onSurface;
            final muted = fg.withValues(alpha: 0.65);

            return Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: fg.withValues(alpha: 0.12)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.zap, size: 18, color: accentColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Движок ИИ-агента (ACP + Built-in)',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: fg,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Проверить установленные CLI',
                          icon: Icon(
                            LucideIcons.refresh_cw,
                            size: 16,
                            color: muted,
                          ),
                          onPressed: () => sheetRef
                              .read(roxumChatProvider.notifier)
                              .refreshInstalledEngines(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Agent Client Protocol (acp_dart) позволяет запускать настоящий OpenCode, Gemini CLI или Claude Code прямо в интерфейсе QuantumIDE с вашими API-ключами.',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(height: 12),
                    for (final engine in RoxumAgentEngine.values) ...[
                      Builder(
                        builder: (_) {
                          final selected = st.agentEngine == engine;
                          final installed =
                              st.installedEngines[engine] ??
                              (engine == RoxumAgentEngine.builtIn);
                          final installingThis = st.installingEngine == engine;
                          final activeColor =
                              engine == RoxumAgentEngine.builtIn
                              ? accentColor
                              : const Color(0xFF10B981);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? activeColor.withValues(alpha: 0.12)
                                  : fg.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? activeColor.withValues(alpha: 0.55)
                                    : fg.withValues(alpha: 0.1),
                              ),
                            ),
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 2,
                              ),
                              leading: Icon(
                                engine == RoxumAgentEngine.builtIn
                                    ? LucideIcons.cpu
                                    : LucideIcons.zap,
                                size: 18,
                                color: selected ? activeColor : muted,
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      engine.displayName,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: fg,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: installed
                                          ? const Color(
                                              0xFF10B981,
                                            ).withValues(alpha: 0.16)
                                          : Colors.orange.withValues(
                                              alpha: 0.16,
                                            ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      installed
                                          ? 'Готов ✓'
                                          : 'Не установлен',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: installed
                                            ? const Color(0xFF10B981)
                                            : Colors.orangeAccent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  engine.subtitle,
                                  style: TextStyle(fontSize: 11.5, color: muted),
                                ),
                              ),
                              trailing: !installed
                                  ? (installingThis
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : TextButton(
                                            onPressed:
                                                st.installingEngine != null
                                                ? null
                                                : () async {
                                                    final res = await sheetRef
                                                        .read(
                                                          roxumChatProvider
                                                              .notifier,
                                                        )
                                                        .installAgentEngine(
                                                          engine,
                                                        );
                                                    if (!context.mounted) return;
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          res.success
                                                              ? '${engine.displayName} установлен и активирован!'
                                                              : 'Не удалось установить ${engine.shortLabel}: ${res.output.split('\n').last}',
                                                        ),
                                                        duration:
                                                            const Duration(
                                                              seconds: 4,
                                                            ),
                                                      ),
                                                    );
                                                  },
                                            child: const Text(
                                              'Установить',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ))
                                  : (selected
                                        ? Icon(
                                            LucideIcons.check,
                                            size: 16,
                                            color: activeColor,
                                          )
                                        : null),
                              onTap: () async {
                                await sheetRef
                                    .read(roxumChatProvider.notifier)
                                    .setAgentEngine(engine);
                                if (!sheetCtx.mounted) return;
                                Navigator.of(sheetCtx).pop();
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCompactModelPill({
    required BuildContext context,
    required List<RoxumModelOption> models,
    required RoxumModelOption? selectedModel,
    required bool isRefreshing,
    required Color textColor,
    required Color mutedColor,
    required Color accentColor,
    required bool isDark,
  }) {
    if (models.isEmpty || selectedModel == null) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showProvidersDialog(context, accentColor),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.45)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.plug, size: 12, color: Colors.orangeAccent),
              SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Подключить API',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.orangeAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () =>
          _showModelPickerDialog(context, models, selectedModel.id, accentColor),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: textColor.withValues(alpha: 0.11)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.sparkles, size: 11.5, color: accentColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                selectedModel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: textColor.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (isRefreshing) ...[
              const SizedBox(width: 4),
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            ] else ...[
              const SizedBox(width: 2),
              Icon(
                LucideIcons.chevron_down,
                size: 12,
                color: mutedColor,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryPill({
    required BuildContext context,
    required RoxumChatState chatState,
    required bool hasOpenRouterKey,
    required Color textColor,
    required Color mutedColor,
    required Color accentColor,
  }) {
    final total = chatState.sessionUsage.totalTokens;
    final compactLabel = total >= 1000
        ? '${(total / 1000).toStringAsFixed(1)}k'
        : (total > 0 ? '$total' : 'OR');

    return Tooltip(
      message: 'Использование токенов и лимиты',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showUsageTelemetrySheet(
          context: context,
          hasOpenRouterKey: hasOpenRouterKey,
          accentColor: accentColor,
        ),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: textColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: textColor.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.gauge, size: 12, color: accentColor),
              const SizedBox(width: 4),
              Text(
                compactLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: mutedColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showUsageTelemetrySheet({
    required BuildContext context,
    required bool hasOpenRouterKey,
    required Color accentColor,
  }) async {
    final isNarrow = MediaQuery.sizeOf(context).width < 600;

    Widget buildContent(BuildContext ctx) {
      return Consumer(
        builder: (context, modalRef, _) {
          final liveState = modalRef.watch(roxumChatProvider);
          final u = liveState.sessionUsage;
          final orLimits = liveState.openRouterLimits;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.gauge, size: 18, color: accentColor),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Телеметрия токенов и лимиты',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (hasOpenRouterKey)
                      IconButton(
                        onPressed: () => modalRef
                            .read(roxumChatProvider.notifier)
                            .refreshOpenRouterLimits(),
                        icon: const Icon(LucideIcons.refresh_cw, size: 16),
                        tooltip: 'Обновить лимиты OpenRouter',
                      ),
                  ],
                ),
                const Divider(height: 16),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(LucideIcons.arrow_down, size: 16, color: accentColor),
                  title: const Text('Входные токены (Prompt)'),
                  trailing: Text(
                    '${u.promptTokens}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(LucideIcons.arrow_up, size: 16, color: accentColor),
                  title: const Text('Выходные токены (Completion)'),
                  trailing: Text(
                    '${u.completionTokens}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(LucideIcons.sigma, size: 16),
                  title: const Text('Всего за сессию'),
                  trailing: Text(
                    '${u.totalTokens}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (u.costUsd > 0)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      LucideIcons.dollar_sign,
                      size: 16,
                      color: Color(0xFF22C55E),
                    ),
                    title: const Text('Стоимость сессии'),
                    trailing: Text(
                      '\$${u.costUsd.toStringAsFixed(4)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF22C55E),
                      ),
                    ),
                  ),
                if (orLimits != null) ...[
                  const Divider(height: 16),
                  Text(
                    'OpenRouter (${orLimits.label})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Потрачено всего: \$${orLimits.usageUsd.toStringAsFixed(4)} • Сегодня: \$${orLimits.usageDailyUsd.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (orLimits.limitRemainingUsd != null)
                    Text(
                      'Остаток лимита: \$${orLimits.limitRemainingUsd!.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFA78BFA),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (orLimits.freeDailyRemaining != null)
                    Text(
                      'Бесплатные запросы сегодня: ${orLimits.freeDailyRemaining} / ${orLimits.freeDailyLimit}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFA78BFA),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Закрыть'),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    if (isNarrow) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetCtx) => SafeArea(child: buildContent(sheetCtx)),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: buildContent(dialogCtx),
          ),
        ),
      );
    }
  }

  Future<void> _showModelPickerDialog(
    BuildContext context,
    List<RoxumModelOption> initialModels,
    String currentSelectedId,
    Color accentColor,
  ) async {
    String query = '';
    String filterTab = 'ALL'; // ALL, FREE, or provider name
    final isNarrow = MediaQuery.sizeOf(context).width < 600;

    Widget buildPickerBody(BuildContext modalCtx) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          return Consumer(
            builder: (context, modalRef, _) {
              final chatState = modalRef.watch(roxumChatProvider);
              final settings = modalRef.watch(settingsProvider);
              final models = modalRef
                  .read(roxumChatProvider.notifier)
                  .availableModels(settings);
              final providers = <String>{
                for (final m in models) m.provider,
              }.toList();

              final filtered = models.where((m) {
                if (filterTab == 'FREE' && !m.isFree) return false;
                if (filterTab != 'ALL' &&
                    filterTab != 'FREE' &&
                    m.provider != filterTab) {
                  return false;
                }
                if (query.isNotEmpty) {
                  final q = query.toLowerCase();
                  return m.name.toLowerCase().contains(q) ||
                      m.model.toLowerCase().contains(q) ||
                      m.provider.toLowerCase().contains(q);
                }
                return true;
              }).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                    child: Row(
                      children: [
                        Icon(LucideIcons.sparkles,
                            size: 18, color: accentColor),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Выбор модели',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: chatState.isRefreshingModels
                              ? null
                              : () => modalRef
                                  .read(roxumChatProvider.notifier)
                                  .refreshAllModels(),
                          icon: chatState.isRefreshingModels
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(LucideIcons.refresh_cw, size: 17),
                          tooltip: 'Обновить список моделей',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      autofocus: !isNarrow,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(LucideIcons.search, size: 17),
                        hintText: 'Поиск модели (qwen, gemini, free...)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setModalState(() => query = v.trim()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: Text('Все (${models.length})'),
                          selected: filterTab == 'ALL',
                          onSelected: (_) =>
                              setModalState(() => filterTab = 'ALL'),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text(
                            'Бесплатные (${models.where((m) => m.isFree).length})',
                          ),
                          selected: filterTab == 'FREE',
                          selectedColor:
                              const Color(0xFF22C55E).withValues(alpha: 0.25),
                          onSelected: (_) =>
                              setModalState(() => filterTab = 'FREE'),
                        ),
                        for (final prov in providers) ...[
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: Text(prov),
                            selected: filterTab == prov,
                            onSelected: (_) =>
                                setModalState(() => filterTab = prov),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('Модели не найдены'))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final m = filtered[i];
                              final isSel = m.id ==
                                  (chatState.selectedModelId ??
                                      currentSelectedId);
                              return ListTile(
                                dense: true,
                                selected: isSel,
                                leading: Icon(
                                  isSel
                                      ? Icons.check_circle
                                      : LucideIcons.cpu,
                                  size: 16,
                                  color: isSel ? accentColor : null,
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        m.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (m.isFree)
                                      Container(
                                        margin: const EdgeInsets.only(left: 6),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF22C55E)
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'FREE',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF22C55E),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  '${m.provider} • ${m.model}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onTap: () {
                                  modalRef
                                      .read(roxumChatProvider.notifier)
                                      .selectModel(m.id);
                                  Navigator.of(modalCtx).pop();
                                },
                              );
                            },
                          ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(modalCtx).pop();
                            _showProvidersDialog(context, accentColor);
                          },
                          child: const Text('Настроить API'),
                        ),
                        const SizedBox(width: 6),
                        TextButton(
                          onPressed: () => Navigator.of(modalCtx).pop(),
                          child: const Text('Закрыть'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    if (isNarrow) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetCtx) {
          final maxHeight = MediaQuery.sizeOf(sheetCtx).height * 0.85;
          return SizedBox(
            height: maxHeight,
            child: buildPickerBody(sheetCtx),
          );
        },
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 540),
            child: buildPickerBody(dialogCtx),
          ),
        ),
      );
    }
  }

  Widget _buildPendingEditsBanner(
    RoxumChatState chatState,
    Color surfaceColor,
    Color textColor,
    Color accentColor,
  ) {
    final edits = chatState.pendingEdits.values.toList();
    final totalAdded = edits.fold<int>(0, (s, e) => s + e.addedLines);
    final totalRemoved = edits.fold<int>(0, (s, e) => s + e.removedLines);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () =>
                    setState(() => _pendingExpanded = !_pendingExpanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
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
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () =>
                        ref.read(roxumChatProvider.notifier).undoAllEdits(),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 30),
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
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text(
                      'Принять',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF22C55E)),
                    ),
                  ),
                ],
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
                    const SizedBox(width: 6),
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

  Widget _buildEmptyState({
    required BuildContext context,
    required RoxumChatState chatState,
    required List<RoxumModelOption> models,
    required String? activeFilePath,
    required Color textColor,
    required Color mutedColor,
    required Color surfaceColor,
    required Color accentColor,
  }) {
    if (models.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.plug,
                    size: 28,
                    color: Colors.orangeAccent,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Подключите AI-провайдера',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Добавьте API-ключ OpenRouter, Gemini, OpenAI, Anthropic или локальный OpenAI-совместимый сервер, чтобы начать работу с Roxum AI.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: mutedColor,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => _showProvidersDialog(context, accentColor),
                  icon: const Icon(LucideIcons.plug, size: 16),
                  label: const Text('Настроить API / OpenRouter'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isAgent = chatState.chatMode == RoxumChatMode.agent;
    final activeFileName =
        activeFilePath != null ? p.basename(activeFilePath) : null;

    final List<({IconData icon, String title, String prompt})> quickCards;
    if (isAgent) {
      quickCards = [
        if (activeFileName != null)
          (
            icon: LucideIcons.bug,
            title: 'Найти и исправить ошибки в $activeFileName',
            prompt:
                'Проверь ошибки и предупреждения в активном файле $activeFileName и исправь их.',
          )
        else
          (
            icon: LucideIcons.wrench,
            title: 'Проверить диагностику и исправить проблемы',
            prompt:
                'Проверь диагностику проекта и исправь найденные ошибки компиляции или анализа.',
          ),
        (
          icon: LucideIcons.sparkles,
          title: activeFileName != null
              ? 'Отрефакторить и оптимизировать $activeFileName'
              : 'Найти TODO и узкие места производительности',
          prompt: activeFileName != null
              ? 'Улучши читаемость и производительность кода в $activeFileName.'
              : 'Найди TODO и возможные проблемы производительности в проекте.',
        ),
        (
          icon: LucideIcons.folder_tree,
          title: 'Разобрать архитектуру проекта',
          prompt: 'Изучи структуру проекта и кратко опиши основные модули.',
        ),
      ];
    } else {
      quickCards = [
        if (activeFileName != null)
          (
            icon: LucideIcons.file_search,
            title: 'Объяснить, как работает $activeFileName',
            prompt:
                'Объясни подробно логику и ключевые части файла $activeFileName.',
          )
        else
          (
            icon: LucideIcons.folder_tree,
            title: 'Объяснить структуру этого проекта',
            prompt: 'Объясни структуру и архитектуру этого проекта.',
          ),
        (
          icon: LucideIcons.shield_alert,
          title: activeFileName != null
              ? 'Найти потенциальные баги в $activeFileName'
              : 'Найти потенциальные баги и уязвимости',
          prompt: activeFileName != null
              ? 'Проверь $activeFileName на потенциальные баги, утечки и edge cases.'
              : 'Какие потенциальные ошибки и узкие места есть в текущем коде?',
        ),
        (
          icon: LucideIcons.lightbulb,
          title: 'Предложить улучшения и тесты',
          prompt:
              'Предложи план рефакторинга и ключевые unit-тесты для текущего модуля.',
        ),
      ];
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isAgent ? LucideIcons.bot : LucideIcons.message_circle,
                    size: 26,
                    color: accentColor,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isAgent ? 'Roxum AI Agent' : 'Roxum AI Ask',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isAgent
                    ? 'Читает файлы, правит код с diff-предпросмотром, проверяет диагностику и запускает команды.'
                    : 'Отвечает на вопросы по коду и архитектуре без изменения файлов.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: mutedColor,
                ),
              ),
              const SizedBox(height: 16),
              for (final card in quickCards)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(11),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: () {
                        _promptController.text = card.prompt;
                        _sendPrompt();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: textColor.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(card.icon, size: 16, color: accentColor),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                card.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: textColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              LucideIcons.arrow_up_right,
                              size: 14,
                              color: mutedColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTurnItem({
    required BuildContext context,
    required int index,
    required RoxumConversationTurn turn,
    required bool isGeneratingThis,
    required double panelWidth,
    required Color textColor,
    required Color surfaceColor,
    required Color accentColor,
    required bool isDark,
  }) {
    final bubbleMaxWidth = (panelWidth * 0.85).clamp(200.0, 560.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── User Bubble ──
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onLongPress: () => _showUserBubbleActions(index, turn),
              child: Container(
                constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.34),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (turn.attachmentNames.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: turn.attachmentNames
                                    .map(
                                      (name) => Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: textColor.withValues(
                                            alpha: 0.08,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              LucideIcons.paperclip,
                                              size: 11,
                                              color: accentColor,
                                            ),
                                            const SizedBox(width: 4),
                                            ConstrainedBox(
                                              constraints:
                                                  const BoxConstraints(
                                                maxWidth: 150,
                                              ),
                                              child: Text(
                                                name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  color: textColor.withValues(
                                                    alpha: 0.85,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          SelectableText(
                            turn.userRequest,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 2),
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: PopupMenuButton<String>(
                        tooltip: 'Действия',
                        padding: EdgeInsets.zero,
                        iconSize: 15,
                        icon: Icon(
                          LucideIcons.ellipsis_vertical,
                          size: 15,
                          color: textColor.withValues(alpha: 0.55),
                        ),
                        onSelected: (action) {
                          if (action == 'copy') {
                            Clipboard.setData(
                              ClipboardData(text: turn.userRequest),
                            );
                          } else if (action == 'edit') {
                            setState(() => _editingTurnIndex = index);
                            _promptController.text = turn.userRequest;
                            _promptFocusNode.requestFocus();
                          } else if (action == 'retry') {
                            ref.read(roxumChatProvider.notifier).sendPrompt(
                                  turn.userRequest,
                                  truncateFromIndex: index,
                                );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'copy',
                            child: Row(
                              children: [
                                Icon(LucideIcons.copy, size: 15),
                                SizedBox(width: 8),
                                Text('Копировать'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(LucideIcons.pencil, size: 15),
                                SizedBox(width: 8),
                                Text('Редактировать'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'retry',
                            child: Row(
                              children: [
                                Icon(LucideIcons.refresh_cw, size: 15),
                                SizedBox(width: 8),
                                Text('Повторить'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          if (turn.timeline.isNotEmpty) ...[
            ..._buildChronologicalTimeline(
              turn: turn,
              isGeneratingThis: isGeneratingThis,
              surfaceColor: surfaceColor,
              textColor: textColor,
              accentColor: accentColor,
            ),
            if (isGeneratingThis)
              _buildGeneratingIndicator(
                isToolRunning: turn.toolCalls.any((t) => t.isRunning),
                surfaceColor: surfaceColor,
                textColor: textColor,
              )
            else if (turn.aiResponse.isNotEmpty)
              _buildTurnFooter(index, turn, textColor),
          ] else ...[
            // ── Legacy / persisted turn rendering ──
            if (turn.reasoningText.isNotEmpty)
              RoxumThinkingCard(
                reasoningText: turn.reasoningText,
                durationMs: turn.thinkingDurationMs,
                isStreaming: isGeneratingThis && turn.aiResponse.isEmpty,
                surfaceColor: surfaceColor,
                textColor: textColor,
              ),
            if (turn.toolCalls.isNotEmpty)
              RoxumAgentTimeline(
                toolCalls: turn.toolCalls,
                surfaceColor: surfaceColor,
                textColor: textColor,
                onOpenFile: (fp) =>
                    ref.read(editorProvider.notifier).openFile(fp),
              ),
            if (turn.fileEdits.isNotEmpty)
              ...turn.fileEdits.map(
                (edit) => _buildDiffCard(edit, surfaceColor, textColor),
              ),
            if (isGeneratingThis && turn.aiResponse.isEmpty)
              _buildGeneratingIndicator(
                isToolRunning: turn.toolCalls.any((t) => t.isRunning),
                surfaceColor: surfaceColor,
                textColor: textColor,
              )
            else if (turn.aiResponse.isNotEmpty) ...[
              _buildAssistantTextCard(
                text: turn.aiResponse,
                isError: turn.isError,
                surfaceColor: surfaceColor,
                textColor: textColor,
                accentColor: accentColor,
              ),
              _buildTurnFooter(index, turn, textColor),
            ],
          ],
        ],
      ),
    );
  }

  List<Widget> _buildChronologicalTimeline({
    required RoxumConversationTurn turn,
    required bool isGeneratingThis,
    required Color surfaceColor,
    required Color textColor,
    required Color accentColor,
  }) {
    final widgets = <Widget>[];
    final items = turn.timeline;
    var i = 0;
    while (i < items.length) {
      final item = items[i];
      if (item.kind == RoxumTimelineKind.toolCall && item.toolCall != null) {
        final batch = <RoxumToolCallRecord>[];
        while (i < items.length &&
            items[i].kind == RoxumTimelineKind.toolCall &&
            items[i].toolCall != null) {
          batch.add(items[i].toolCall!);
          i++;
        }
        widgets.add(
          RoxumAgentTimeline(
            toolCalls: batch,
            surfaceColor: surfaceColor,
            textColor: textColor,
            onOpenFile: (fp) => ref.read(editorProvider.notifier).openFile(fp),
          ),
        );
        continue;
      }

      switch (item.kind) {
        case RoxumTimelineKind.reasoning:
          if (item.text.isNotEmpty) {
            widgets.add(
              RoxumThinkingCard(
                reasoningText: item.text,
                durationMs: item.durationMs > 0
                    ? item.durationMs
                    : turn.thinkingDurationMs,
                isStreaming: isGeneratingThis && i == items.length - 1,
                surfaceColor: surfaceColor,
                textColor: textColor,
              ),
            );
          }
          break;
        case RoxumTimelineKind.text:
          if (item.text.trim().isNotEmpty) {
            widgets.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildAssistantTextCard(
                  text: item.text,
                  isError: turn.isError && i == items.length - 1,
                  surfaceColor: surfaceColor,
                  textColor: textColor,
                  accentColor: accentColor,
                ),
              ),
            );
          }
          break;
        case RoxumTimelineKind.fileEdit:
          if (item.fileEdit != null) {
            widgets.add(_buildDiffCard(item.fileEdit!, surfaceColor, textColor));
          }
          break;
        case RoxumTimelineKind.toolCall:
          break;
      }
      i++;
    }
    return widgets;
  }

  Widget _buildDiffCard(
    RoxumPendingEdit edit,
    Color surfaceColor,
    Color textColor,
  ) {
    final pendingMap = ref.read(roxumChatProvider).pendingEdits;
    final isPending = pendingMap.containsKey(edit.filePath);
    return RoxumFileDiffCard(
      edit: edit,
      isPending: isPending,
      surfaceColor: surfaceColor,
      textColor: textColor,
      onOpenFile: () => ref.read(editorProvider.notifier).openFile(edit.filePath),
      onKeep: () => ref.read(roxumChatProvider.notifier).keepEdit(edit.filePath),
      onUndo: () => ref.read(roxumChatProvider.notifier).undoEdit(edit.filePath),
    );
  }

  Widget _buildGeneratingIndicator({
    required bool isToolRunning,
    required Color surfaceColor,
    required Color textColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Working',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: textColor.withValues(alpha: 0.72),
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .shimmer(duration: 1300.ms, color: textColor),
        ],
      ),
    );
  }

  Widget _buildAssistantTextCard({
    required String text,
    required bool isError,
    required Color surfaceColor,
    required Color textColor,
    required Color accentColor,
  }) {
    final isDark =
        ThemeData.estimateBrightnessForColor(surfaceColor) == Brightness.dark;
    final inlineAccent = accentColor;
    final markdown = GptMarkdown(
      text,
      style: TextStyle(
        color: isError ? Colors.redAccent : textColor,
        fontSize: 13.5,
        height: 1.5,
      ),
      styleSheet: GptMarkdownStyleSheet(
        heading: HeadingStyle(
          textStyle: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w700,
          ),
          dividerColor: textColor.withValues(alpha: 0.14),
        ),
        inlineCode: InlineCodeStyle(
          color: inlineAccent,
          backgroundColor: inlineAccent.withValues(alpha: 0.14),
          borderColor: inlineAccent.withValues(alpha: 0.28),
        ),
        table: TableStyle(
          headerBackground: isDark
              ? Colors.white.withValues(alpha: 0.09)
              : Colors.black.withValues(alpha: 0.06),
          headerTextStyle: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
          borderColor: textColor.withValues(alpha: 0.18),
          rowStripeColor: textColor.withValues(alpha: 0.03),
          overflow: TableOverflow.wrap,
        ),
        hr: HrStyle(
          color: textColor.withValues(alpha: 0.14),
          thickness: 1,
        ),
        link: LinkStyle(
          color: inlineAccent,
        ),
      ),
      codeBuilder: (ctx, name, code, closed) {
        final isShell = _isShellCommandBlock(name, code);
        final ed = ref.read(editorProvider);
        final activeFile = (ed.openFiles.isNotEmpty &&
                ed.activeTabIndex >= 0 &&
                ed.activeTabIndex < ed.openFiles.length)
            ? ed.openFiles[ed.activeTabIndex]
            : null;
        return RoxumCodeBlockCard(
          code: code,
          language: name,
          isTerminalCommand: isShell,
          surfaceColor: surfaceColor,
          textColor: textColor,
          onRunInTerminal: isShell
              ? () {
                  final cleaned = code
                      .split('\n')
                      .map((l) => l.trim())
                      .where((l) => l.isNotEmpty && !l.startsWith('#'))
                      .map((l) => l.startsWith(r'$ ') ? l.substring(2) : l)
                      .join(' && ');
                  if (cleaned.isEmpty) return;
                  final panel = ref.read(panelProvider.notifier);
                  panel.selectTab(PanelTab.terminal);
                  panel.openPanel();
                  ref
                      .read(terminalTabsProvider.notifier)
                      .sendCommand(cleaned);
                }
              : null,
          onInsertIntoEditor: (!isShell)
              ? () => _applyCodeBlockToTargetFile(code, activeFile)
              : null,
        );
      },
    );

    if (isError) {
      return Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.redAccent.withValues(alpha: 0.35),
          ),
        ),
        child: markdown,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: markdown,
    );
  }

  bool _isShellCommandBlock(String lang, String code) {
    final l = lang.trim().toLowerCase();
    if (const {
      'bash',
      'sh',
      'zsh',
      'shell',
      'console',
      'terminal',
      'cmd',
      'powershell',
    }.contains(l)) {
      return true;
    }
    if (l.isNotEmpty) return false;
    final firstLine = code
        .split('\n')
        .map((e) => e.trim())
        .firstWhere((e) => e.isNotEmpty, orElse: () => '');
    const prefixes = [
      r'$ ',
      'flutter ',
      'dart ',
      'git ',
      'npm ',
      'pnpm ',
      'yarn ',
      'cd ',
      'ls ',
      'mkdir ',
      'rm ',
      'python ',
      'pip ',
      'cargo ',
      'adb ',
    ];
    return prefixes.any(firstLine.startsWith);
  }

  Future<void> _applyCodeBlockToTargetFile(
    String code,
    EditorFile? activeFile,
  ) async {
    final workspace = ref.read(workspaceProvider).currentPath ?? '';
    final lines = code.split('\n');
    EditorFile? target = activeFile;
    var payload = code;

    if (lines.isNotEmpty && workspace.isNotEmpty) {
      final first = lines.first.trim();
      final match = RegExp(
        r'^(?://|#|--|/\*)\s*(?:file:\s*)?([^\s*]+?\.[a-zA-Z0-9]+)',
      ).firstMatch(first);
      if (match != null) {
        final rel = match.group(1)!;
        final candidatePath = p.isAbsolute(rel) ? rel : p.join(workspace, rel);
        if (File(candidatePath).existsSync()) {
          await ref.read(editorProvider.notifier).openFile(candidatePath);
          final ed = ref.read(editorProvider);
          final openedIdx =
              ed.openFiles.indexWhere((f) => f.path == candidatePath);
          if (openedIdx >= 0) {
            target = ed.openFiles[openedIdx];
            payload = lines.skip(1).join('\n').trimLeft();
          }
        }
      }
    }

    if (target == null) return;
    final ctrl = target.controller;
    final hasSelection = !ctrl.selection.isCollapsed;
    final looksLikeFullFile = !hasSelection &&
        lines.length >= 12 &&
        (payload.trimLeft().startsWith('import ') ||
            payload.trimLeft().startsWith('library ') ||
            payload.trimLeft().startsWith('<!DOCTYPE'));

    if (looksLikeFullFile) {
      ctrl.text = payload;
    } else {
      ctrl.replaceSelection(payload);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Применено в ${p.basename(target.path)}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildTurnFooter(
    int index,
    RoxumConversationTurn turn,
    Color textColor,
  ) {
    final hitStepLimit = turn.aiResponse.contains('Достигнут лимит шагов');
    final muted = textColor.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2, right: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hitStepLimit)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: FilledButton.tonalIcon(
                onPressed: () {
                  ref.read(roxumChatProvider.notifier).sendPrompt(
                        'Продолжи выполнение задачи с того места, где остановился, и доведи её до конца.',
                      );
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: const Text(
                  'Продолжить выполнение',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          Row(
            children: [
              if (turn.usage.totalTokens > 0)
                Expanded(
                  child: Text(
                    '↓${turn.usage.promptTokens} · ↑${turn.usage.completionTokens}${turn.usage.costUsd > 0 ? ' · \$${turn.usage.costUsd.toStringAsFixed(4)}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: textColor.withValues(alpha: 0.45),
                    ),
                  ),
                )
              else
                const Spacer(),
              Tooltip(
                message: 'Повторить ответ',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    ref.read(roxumChatProvider.notifier).sendPrompt(
                          turn.userRequest,
                          truncateFromIndex: index,
                        );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Icon(
                      LucideIcons.refresh_cw,
                      size: 14,
                      color: muted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Tooltip(
                message: 'Копировать ответ',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: turn.aiResponse));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ответ скопирован'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Icon(
                      LucideIcons.copy,
                      size: 14,
                      color: muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
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
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          builder: (_, scrollCtrl) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                return Consumer(
                  builder: (context, innerRef, _) {
                    final liveState = innerRef.watch(roxumChatProvider);
                    final runtime = innerRef.read(runtimeServiceProvider);
                    return Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(14),
                          child: Text(
                            'Инструменты и Ядро Roxum Agent',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        if (Platform.isAndroid) ...[
                          SwitchListTile(
                            value: runtime.useNativeRootMode,
                            onChanged: (val) async {
                              if (val) {
                                final ok = await runtime.checkRootAccess();
                                if (!ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Root-доступ (su) не обнаружен, но режим Своего ядра включён.',
                                      ),
                                    ),
                                  );
                                }
                              }
                              await runtime.setUseNativeRootMode(val);
                              if (!context.mounted) return;
                              setSheetState(() {});
                            },
                            secondary: const Icon(
                              Icons.bolt_rounded,
                              color: Color(0xFF22C55E),
                            ),
                            title: const Text(
                              'Своё ядро (Root — без скачивания Ubuntu)',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              runtime.useNativeRootMode
                                  ? 'Активно: команды и терминал работают напрямую на ядре устройства (Root/su)'
                                  : 'Выключено: используется песочница Ubuntu 24.04 (PRoot)',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            dense: true,
                          ),
                          const Divider(height: 1),
                        ],
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
      },
    );
  }

  Future<void> _showHistoryDialog(
    BuildContext context,
    RoxumChatState chatState,
    Color accentColor,
  ) async {
    final isNarrow = MediaQuery.sizeOf(context).width < 600;

    Widget buildBody(BuildContext modalCtx) {
      return Consumer(
        builder: (ctx, modalRef, _) {
          final liveState = modalRef.watch(roxumChatProvider);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
                child: Row(
                  children: [
                    Icon(LucideIcons.history, size: 18, color: accentColor),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'История чатов',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        modalRef
                            .read(roxumChatProvider.notifier)
                            .createNewSession();
                        Navigator.of(modalCtx).pop();
                      },
                      icon: const Icon(LucideIcons.square_pen, size: 17),
                      tooltip: 'Новый чат',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: liveState.sessions.length,
                  itemBuilder: (_, i) {
                    final s = liveState.sessions[i];
                    final isCurrent = s.id == liveState.currentSessionId;
                    return ListTile(
                      dense: true,
                      selected: isCurrent,
                      leading: Icon(
                        isCurrent
                            ? LucideIcons.message_square_dot
                            : LucideIcons.message_square,
                        size: 16,
                        color: isCurrent ? accentColor : null,
                      ),
                      title: Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${s.turns.length} сообщений',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: IconButton(
                        icon: const Icon(LucideIcons.trash_2, size: 16),
                        tooltip: 'Удалить чат',
                        onPressed: () {
                          modalRef
                              .read(roxumChatProvider.notifier)
                              .deleteSession(s.id);
                        },
                      ),
                      onTap: () {
                        modalRef
                            .read(roxumChatProvider.notifier)
                            .switchSession(s.id);
                        Navigator.of(modalCtx).pop();
                      },
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(modalCtx).pop(),
                    child: const Text('Закрыть'),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    if (isNarrow) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetCtx) {
          final maxHeight = MediaQuery.sizeOf(sheetCtx).height * 0.72;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SafeArea(child: buildBody(sheetCtx)),
          );
        },
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 460),
            child: buildBody(dialogCtx),
          ),
        ),
      );
    }
  }

  Future<void> _showProvidersDialog(
    BuildContext context,
    Color accentColor,
  ) async {
    final s = ref.read(settingsProvider);
    final openRouterCtrl = TextEditingController(text: s.openrouterApiKey);
    final customUrlCtrl = TextEditingController(text: s.customApiBaseUrl);
    final customKeyCtrl = TextEditingController(text: s.customApiKey);
    final geminiCtrl = TextEditingController(text: s.geminiApiKey);
    final deepseekCtrl = TextEditingController(text: s.deepseekApiKey);
    final openaiCtrl = TextEditingController(text: s.openaiApiKey);
    final anthropicCtrl = TextEditingController(text: s.anthropicApiKey);
    final groqCtrl = TextEditingController(text: s.groqApiKey);
    final xaiCtrl = TextEditingController(text: s.xaiApiKey);
    final mistralCtrl = TextEditingController(text: s.mistralApiKey);
    String discoveredPrimaryModel = s.customApiModel;

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
              title: Row(
                children: [
                  Icon(LucideIcons.plug, size: 18, color: accentColor),
                  const SizedBox(width: 8),
                  const Text('Провайдеры и API', style: TextStyle(fontSize: 16)),
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
                                      if (!ctx.mounted) return;
                                      setModalState(() {
                                        limitsPreview = res;
                                        checkingLimits = false;
                                      });
                                    } catch (e) {
                                      if (!ctx.mounted) return;
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
                            color: accentColor.withValues(alpha: 0.1),
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
                        'Локальный ИИ / Custom OpenAI',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: customUrlCtrl,
                        decoration: const InputDecoration(
                          labelText:
                              'URL сервера (напр. http://10.61.156.225:8080/v1)',
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
                                  if (!ctx.mounted) return;
                                  setModalState(() {
                                    fetchedModels = list;
                                    if (list.isNotEmpty) {
                                      discoveredPrimaryModel = list.first;
                                    }
                                    fetchingModels = false;
                                  });
                                } catch (e) {
                                  if (!ctx.mounted) return;
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
                            : const Icon(Icons.search, size: 14),
                        label: const Text('Найти модели автоматически'),
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
                              final isSelected = discoveredPrimaryModel == id;
                              return ChoiceChip(
                                label: Text(
                                  id,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                selected: isSelected,
                                onSelected: (_) => setModalState(
                                  () => discoveredPrimaryModel = id,
                                ),
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
                      const SizedBox(height: 6),
                      TextField(
                        controller: xaiCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'xAI (Grok) API Key',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: mistralCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Mistral API Key',
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
                    await notifier.setOpenrouterApiKey(
                      openRouterCtrl.text.trim(),
                    );
                    await notifier.setCustomApiBaseUrl(
                      customUrlCtrl.text.trim(),
                    );
                    await notifier.setCustomApiKey(customKeyCtrl.text.trim());
                    await notifier.setCustomApiModel(
                      discoveredPrimaryModel.trim(),
                    );
                    await notifier.setGeminiApiKey(geminiCtrl.text.trim());
                    await notifier.setDeepseekApiKey(deepseekCtrl.text.trim());
                    await notifier.setOpenaiApiKey(openaiCtrl.text.trim());
                    await notifier.setAnthropicApiKey(
                      anthropicCtrl.text.trim(),
                    );
                    await notifier.setGroqApiKey(groqCtrl.text.trim());
                    await notifier.setXaiApiKey(xaiCtrl.text.trim());
                    await notifier.setMistralApiKey(mistralCtrl.text.trim());
                    final chatNotifier = ref.read(roxumChatProvider.notifier);
                    chatNotifier.refreshAllModels();
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
    geminiCtrl.dispose();
    deepseekCtrl.dispose();
    openaiCtrl.dispose();
    anthropicCtrl.dispose();
    groqCtrl.dispose();
    xaiCtrl.dispose();
    mistralCtrl.dispose();
  }


  Future<void> _showMcpServersDialog(
    BuildContext context,
    Color accentColor,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('MCP servers are configured in Settings → MCP')),
    );
  }

  Future<void> _showAddCustomMcpDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('MCP servers are configured in Settings → MCP')),
    );
  }

}
