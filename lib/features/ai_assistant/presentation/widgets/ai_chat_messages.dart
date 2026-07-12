import 'dart:io';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:diff_match_patch/diff_match_patch.dart';

import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/git_service.dart';
import 'package:quantum_ide/core/services/ai_permission_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_diff_page.dart';
import 'package:quantum_ide/models/chat_message.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';

class CollapsibleConsole extends StatefulWidget {
  final String content;
  const CollapsibleConsole({super.key, required this.content});

  @override
  State<CollapsibleConsole> createState() => _CollapsibleConsoleState();
}

class _CollapsibleConsoleState extends State<CollapsibleConsole> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  const Icon(LucideIcons.terminal, size: 12, color: Colors.white54),
                  const SizedBox(width: 6),
                  Text(
                    'Console Log',
                    style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Icon(_isExpanded ? LucideIcons.chevron_up : LucideIcons.chevron_down, size: 12, color: Colors.white54),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.black26,
              child: SelectableText(
                widget.content.trim(),
                style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 10.5, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

class AIChatMessages extends ConsumerStatefulWidget {
  final AIState aiState;
  const AIChatMessages({super.key, required this.aiState});

  @override
  ConsumerState<AIChatMessages> createState() => AIChatMessagesState();
}

class AIChatMessagesState extends ConsumerState<AIChatMessages> {
  final ScrollController _scroll = ScrollController();
  int? _editingMessageIndex;
  TextEditingController? _editingController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void didUpdateWidget(AIChatMessages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aiState.messages.length != widget.aiState.messages.length ||
        oldWidget.aiState.isLoading != widget.aiState.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  void _scrollToBottom() {
    if (_scroll.hasClients) {
      final maxExtent = _scroll.position.maxScrollExtent;
      if (maxExtent > 0) {
        _scroll.jumpTo(maxExtent);
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _editingController?.dispose();
    super.dispose();
  }

  bool _isNotificationMessage(String content) {
    // Check if the message is a system notification (e.g. context reset or warning)
    final text = content.trim();
    return text.startsWith('🔄') || 
           text.startsWith('⚠️') || 
           text.contains('Контекст сброшен') ||
           text.contains('Context overflow');
  }

  Widget _buildSystemNotificationCard(String content) {
    final isWarning = content.contains('⚠️') || content.contains('error') || content.contains('failed');
    final gradientColors = isWarning
        ? [Colors.redAccent.withValues(alpha: 0.15), Colors.orangeAccent.withValues(alpha: 0.05)]
        : [Colors.cyanAccent.withValues(alpha: 0.12), Colors.purpleAccent.withValues(alpha: 0.04)];
    final borderColor = isWarning ? Colors.redAccent.withValues(alpha: 0.4) : Colors.cyanAccent.withValues(alpha: 0.3);
    final iconData = isWarning ? LucideIcons.triangle_alert : LucideIcons.refresh_cw;
    final iconColor = isWarning ? Colors.redAccent : Colors.cyanAccent;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, size: 16, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: MarkdownBody(
              data: content,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.9), fontSize: 11.5, height: 1.45),
                strong: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                code: GoogleFonts.jetBrainsMono(
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  color: Colors.orangeAccent.shade100,
                  fontSize: 10.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildStepSummary(ChatMessage message) {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    final executed = message.executedActions ?? [];

    final readTypes = ['read_file', 'list_dir', 'grep_search', 'find_symbols', 'web_search', 'web_fetch'];
    final writeTypes = ['create', 'edit', 'delete'];

    final readingActions = executed.where((a) => readTypes.contains(a.type)).toList();
    final writingActions = executed.where((a) => writeTypes.contains(a.type)).toList();
    final commandActions = executed.where((a) => a.type == 'command').toList();
    final mcpActions = executed.where((a) => a.type == 'mcp').toList();

    final int editCount = writingActions.length;
    int additions = 0;
    int deletions = 0;
    for (final action in writingActions) {
      additions += action.additions ?? 0;
      deletions += action.deletions ?? 0;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF131520).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // HEADER
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.greenAccent,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.greenAccent,
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'AGENCY RUN STATUS',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Colors.greenAccent,
                      ),
                    ),
                    const Spacer(),
                    if (message.stepNumber != null)
                      Text(
                        'Step ${message.stepNumber}/${message.totalSteps ?? 12}',
                        style: GoogleFonts.inter(
                          color: Colors.white38,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),

              // PIPELINE CONTENT
              Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      message.taskName != null && message.taskName!.isNotEmpty
                          ? message.taskName!
                          : AppLocalizations.of(context)!.taskExecution,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // SECTION 1: READ / SCAN OPERATIONS
                    if (readingActions.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(LucideIcons.file_search, size: 12, color: Colors.cyanAccent),
                          const SizedBox(width: 6),
                          Text(
                            'ИЗУЧЕНИЕ ПРОЕКТА (Чтение файлов)',
                            style: GoogleFonts.inter(
                              color: Colors.cyanAccent,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: readingActions.map((action) {
                          final fileName = action.path.split('/').last;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: action.path.isNotEmpty
                                  ? () => ref.read(editorProvider.notifier).openFile(action.path)
                                  : null,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.cyanAccent.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.15)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(LucideIcons.file_text, size: 10, color: Colors.cyanAccent),
                                    const SizedBox(width: 4),
                                    Text(
                                      fileName.isNotEmpty ? fileName : (action.description ?? 'Explored'),
                                      style: GoogleFonts.inter(
                                        color: Colors.white70,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // SECTION 2: WRITE / EDIT OPERATIONS
                    if (writingActions.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(LucideIcons.pencil_line, size: 12, color: Colors.blueAccent),
                          const SizedBox(width: 6),
                          Text(
                            'МОДИФИКАЦИЯ ФАЙЛОВ (Запись кода)',
                            style: GoogleFonts.inter(
                              color: Colors.blueAccent,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: writingActions.length,
                        itemBuilder: (context, idx) {
                          final action = writingActions[idx];
                          final fileName = action.path.split('/').last;
                          final displayPath = workspacePath != null && action.path.startsWith(workspacePath)
                              ? p.relative(action.path, from: workspacePath)
                              : action.path;
                          final dirPath = displayPath.contains('/')
                              ? displayPath.substring(0, displayPath.lastIndexOf('/'))
                              : '';

                          final Color fileIconColor = action.type == 'create'
                              ? Colors.greenAccent
                              : (action.type == 'delete' ? Colors.redAccent : Colors.blueAccent);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.02),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  action.type == 'create'
                                      ? LucideIcons.file_plus
                                      : (action.type == 'delete' ? LucideIcons.file_x : LucideIcons.file_code),
                                  size: 13,
                                  color: fileIconColor,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => ref.read(editorProvider.notifier).openFile(action.path),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          fileName,
                                          style: GoogleFonts.inter(
                                            color: Colors.white.withValues(alpha: 0.85),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                        if (dirPath.isNotEmpty)
                                          Text(
                                            dirPath,
                                            style: GoogleFonts.inter(color: Colors.white30, fontSize: 9),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                if ((action.additions ?? 0) > 0) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: Colors.greenAccent.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '+${action.additions}',
                                      style: GoogleFonts.jetBrainsMono(color: Colors.greenAccent, fontSize: 8.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                if ((action.deletions ?? 0) > 0) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '-${action.deletions}',
                                      style: GoogleFonts.jetBrainsMono(color: Colors.redAccent, fontSize: 8.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                InkWell(
                                  onTap: () => ref.read(editorProvider.notifier).openFile(action.path, isDiffView: true),
                                  child: const Icon(LucideIcons.diff, size: 12, color: Colors.white38),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () async {
                                    final l10n = AppLocalizations.of(context)!;
                                    final messenger = ScaffoldMessenger.of(context);
                                    final gitSvc = ref.read(gitServiceProvider);
                                    final relPath = workspacePath != null && action.path.startsWith(workspacePath)
                                        ? p.relative(action.path, from: workspacePath)
                                        : action.path;
                                    await gitSvc.discardChanges(relPath);

                                    final isOpen = ref.read(editorProvider).openFiles.any((f) => f.path == action.path);
                                    if (isOpen) {
                                      await ref.read(editorProvider.notifier).openFile(action.path);
                                    }

                                    if (mounted) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(l10n.discardedFileChanges(fileName)),
                                        ),
                                      );
                                    }
                                  },
                                  child: const Icon(LucideIcons.undo, size: 12, color: Colors.redAccent),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                    ],

                    // SECTION 3: COMMAND LOGS
                    if (commandActions.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(LucideIcons.terminal, size: 12, color: Colors.amberAccent),
                          const SizedBox(width: 6),
                          Text(
                            'ЗАПУСК В ТЕРМИНАЛЕ (Шелл команды)',
                            style: GoogleFonts.inter(
                              color: Colors.amberAccent,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...commandActions.map((action) {
                        final output = message.actionResults?[action.path.isNotEmpty ? action.path : action.content] ?? '';
                        return _CollapsibleCommandConsole(
                          command: action.content,
                          output: output,
                        );
                      }),
                      const SizedBox(height: 10),
                    ],

                    // SECTION 4: MCP TOOL CALLS
                    if (mcpActions.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(LucideIcons.plug, size: 12, color: Colors.purpleAccent),
                          const SizedBox(width: 6),
                          Text(
                            'MCP ИНСТРУМЕНТЫ (Подключенные серверы)',
                            style: GoogleFonts.inter(
                              color: Colors.purpleAccent,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...mcpActions.map((action) {
                        final output = message.actionResults?[action.path.isNotEmpty ? action.path : action.content] ?? '';
                        return _CollapsibleMcpConsole(
                          server: action.server ?? 'unknown',
                          tool: action.tool ?? 'unknown',
                          arguments: action.arguments ?? {},
                          output: output,
                        );
                      }),
                      const SizedBox(height: 10),
                    ],

                    // STATS & CONTROL ROW
                    Row(
                      children: [
                        Text(
                          editCount > 0
                              ? AppLocalizations.of(context)!.filesChangedCount(editCount, additions, deletions)
                              : (commandActions.isNotEmpty 
                                  ? AppLocalizations.of(context)!.commandsExecutedCount(commandActions.length)
                                  : 'Выполнено MCP операций: ${mcpActions.length}'),
                          style: GoogleFonts.inter(color: Colors.white38, fontSize: 9.5, fontWeight: FontWeight.w500),
                        ),
                        const Spacer(),
                        if (editCount > 0) ...[
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(AppLocalizations.of(context)!.changesAccepted),
                                    backgroundColor: const Color(0xFF1E2230),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.25)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(LucideIcons.check, size: 10, color: Colors.greenAccent),
                                    const SizedBox(width: 4),
                                    Text(
                                      AppLocalizations.of(context)!.keep,
                                      style: GoogleFonts.inter(
                                        color: Colors.greenAccent,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final gitSvc = ref.read(gitServiceProvider);
                                final editor = ref.read(editorProvider.notifier);
                                int undone = 0;
                                for (final action in writingActions) {
                                  final relPath = workspacePath != null && action.path.startsWith(workspacePath)
                                      ? p.relative(action.path, from: workspacePath)
                                      : action.path;
                                  await gitSvc.discardChanges(relPath);

                                  final isOpen = ref.read(editorProvider).openFiles.any((f) => f.path == action.path);
                                  if (isOpen) {
                                    await editor.openFile(action.path);
                                  }
                                  undone++;
                                }
                                if (mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(AppLocalizations.of(context)!.undoneChanges(undone)),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(LucideIcons.undo, size: 10, color: Colors.redAccent),
                                    const SizedBox(width: 4),
                                    Text(
                                      AppLocalizations.of(context)!.undo,
                                      style: GoogleFonts.inter(
                                        color: Colors.redAccent,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
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

  Widget _buildActionStep(ChatMessage message) {
    final type = message.actionStepType ?? 'unknown';
    final path = message.actionStepPath ?? '';
    final result = message.actionStepResult;
    
    Color chipColor;
    IconData chipIcon;
    switch (type) {
      case 'read_file':
      case 'list_dir':
      case 'grep_search':
      case 'find_symbols':
        chipColor = Colors.cyanAccent;
        chipIcon = LucideIcons.eye;
        break;
      case 'create':
        chipColor = Colors.greenAccent;
        chipIcon = LucideIcons.plus;
        break;
      case 'edit':
        chipColor = Colors.amberAccent;
        chipIcon = LucideIcons.pencil;
        break;
      case 'delete':
        chipColor = Colors.redAccent;
        chipIcon = LucideIcons.trash_2;
        break;
      case 'command':
        chipColor = Colors.orangeAccent;
        chipIcon = LucideIcons.terminal;
        break;
      case 'web_search':
      case 'web_fetch':
        chipColor = Colors.blueAccent;
        chipIcon = LucideIcons.globe;
        break;
      case 'mcp':
        chipColor = Colors.purpleAccent;
        chipIcon = LucideIcons.plug;
        break;
      default:
        chipColor = Colors.white54;
        chipIcon = LucideIcons.settings;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 2,
            height: 20,
            margin: const EdgeInsets.only(top: 8, right: 8),
            decoration: BoxDecoration(
              color: chipColor.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Icon(chipIcon, size: 11, color: chipColor.withValues(alpha: 0.7)),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.content,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: chipColor.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (result != null && result.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      result.length > 200 ? '${result.substring(0, 200)}...' : result,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        color: Colors.white38,
                        height: 1.3,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (widget.aiState.messages.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final hasEnoughSpace = constraints.maxHeight > 90;
          return ClipRect(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hasEnoughSpace) ...[
                    Icon(LucideIcons.sparkles, size: 36, color: Colors.purpleAccent.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                  ],
                  if (constraints.maxHeight > 40)
                    Text(
                      l10n.askAboutCode,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
                    ),
                ],
              ),
            ),
          );
        },
      );
    }

    final itemCount = widget.aiState.messages.length + (widget.aiState.isLoading ? 1 : 0);

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: itemCount,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        if (index == widget.aiState.messages.length) {
          final role = widget.aiState.activeAgentRole ?? 'Agent';
          final status = widget.aiState.currentStatusMessage ?? 
              AppLocalizations.of(context)!.thinking;
          
          Color roleColor;
          switch (role.toLowerCase()) {
            case 'planner':
              roleColor = Colors.cyanAccent;
              break;
            case 'coder':
              roleColor = Colors.purpleAccent;
              break;
            case 'validator':
              roleColor = Colors.orangeAccent;
              break;
            default:
              roleColor = Colors.blueAccent;
          }

          return _GlowingAgentLoader(
            color: roleColor,
            status: status,
            role: role,
          );
        }

        final message = widget.aiState.messages[index];
        final isUser = message.role == MessageRole.user;
        final isSystem = message.role == MessageRole.system;
        final isLastMessage = index == widget.aiState.messages.length - 1;

        return GestureDetector(
          onLongPress: () {
            _showCompactMessageMenu(context, ref, message, index);
          },
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: isUser 
                  ? CrossAxisAlignment.end 
                  : (isSystem ? CrossAxisAlignment.stretch : CrossAxisAlignment.start),
              children: [
                if (isSystem)
                  message.isActionStep
                      ? _buildActionStep(message)
                      : (message.isStepSummary
                          ? _buildStepSummary(message)
                          : (_isNotificationMessage(message.content)
                              ? _buildSystemNotificationCard(message.content)
                              : () {
                                  final mcpActions = message.executedActions?.where((a) => a.type == 'mcp').toList() ?? [];
                                  if (mcpActions.isNotEmpty) {
                                    final action = mcpActions.first;
                                    return _CollapsibleMcpConsole(
                                      server: action.server ?? 'unknown',
                                      tool: action.tool ?? 'unknown',
                                      arguments: action.arguments ?? {},
                                      output: message.content,
                                    );
                                  }
                                  final commandActions = message.executedActions?.where((a) => a.type == 'command').toList() ?? [];
                                  if (commandActions.isNotEmpty) {
                                    final action = commandActions.first;
                                    return _CollapsibleCommandConsole(
                                      command: action.content,
                                      output: message.content,
                                    );
                                  }
                                  return CollapsibleConsole(content: message.content);
                                }()))
                else if (isUser)
                  GlassContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    blur: 8,
                    opacity: 0.2,
                    color: const Color(0xFFa078ff), // Stitch primary violet color
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(2),
                    ),
                    border: Border.all(
                      color: const Color(0xFFd0bcff).withValues(alpha: 0.5),
                      width: 0.8,
                    ),
                    child: _editingMessageIndex == index
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _editingController,
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                                maxLines: null,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _editingMessageIndex = null;
                                        _editingController?.dispose();
                                        _editingController = null;
                                      });
                                    },
                                    child: Text(
                                      AppLocalizations.of(context)!.cancel,
                                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.cyanAccent.withValues(alpha: 0.1),
                                      foregroundColor: Colors.cyanAccent,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        side: const BorderSide(color: Colors.cyanAccent, width: 0.4),
                                      ),
                                    ),
                                    onPressed: () {
                                      final newText = _editingController?.text.trim() ?? '';
                                      if (newText.isNotEmpty && newText != message.content) {
                                        ref.read(aiProvider.notifier).editUserRequest(index, newText);
                                      }
                                      setState(() {
                                        _editingMessageIndex = null;
                                        _editingController?.dispose();
                                        _editingController = null;
                                      });
                                    },
                                    child: Text(
                                      AppLocalizations.of(context)!.resubmit,
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : SelectableText(
                            message.content,
                            style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, height: 1.4),
                          ),
                  )
                else
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: Color(0xFFd0bcff), // Stitch violet left line
                          width: 3,
                        ),
                      ),
                    ),
                    child: GlassContainer(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      blur: 20,
                      opacity: 0.15,
                      color: const Color(0xFF282A30), // Stitch dark bg
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 0.8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _renderMarkdown(message.content, context),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: Row(
                    mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: [
                      Text(
                        isUser 
                            ? l10n.you 
                            : (isSystem 
                                ? AppLocalizations.of(context)!.system 
                                : (ref.read(aiServiceProvider).settings.currentProvider.id == 'local_edge'
                                    ? l10n.localAiDisplayName
                                    : ref.read(aiServiceProvider).settings.currentProvider.displayName)),
                        style: GoogleFonts.inter(color: Colors.white12, fontSize: 9),
                      ),
                    ],
                  ),
                ),
                if (message.actions != null && message.actions!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildMessageActionsCard(message.actions!, isLastMessage),
                ] else if (!isUser && !isSystem && isLastMessage && widget.aiState.proposedActions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildMessageActionsCard(widget.aiState.proposedActions, isLastMessage),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageActionsCard(List<AIAction> actions, bool isLastMessage) {
    final l10n = AppLocalizations.of(context)!;
    
    final pendingActions = actions.where((a) => widget.aiState.proposedActions.any((pa) => pa.path == a.path && pa.content == a.content)).toList();
    final isPending = pendingActions.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161923),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: actions.length,
            itemBuilder: (context, index) {
              final action = actions[index];
              final isActionPending = widget.aiState.proposedActions.any((pa) => pa.path == action.path && pa.content == action.content);
              return AIActionFileItem(
                action: action,
                isPending: isActionPending,
                onShowDiff: () => _showDiffDialog(action),
                onRemove: () => ref.read(aiProvider.notifier).removeAction(action),
              );
            },
          ),
          if (isPending) ...[
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${l10n.filesCount(pendingActions.length)} ${l10n.withChanges}',
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () {
                          for (final action in List<AIAction>.from(pendingActions)) {
                            ref.read(aiProvider.notifier).removeAction(action);
                          }
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          l10n.rejectAll,
                          style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          await ref.read(aiProvider.notifier).executeActionsManually(pendingActions);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E60FF),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: Text(
                          l10n.acceptAll,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(LucideIcons.circle_check, size: 12, color: Colors.greenAccent),
                  const SizedBox(width: 6),
                  Text(
                    l10n.changesApplied,
                    style: GoogleFonts.inter(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
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
        title: Text(AppLocalizations.of(context)!.changesInFile(action.path.split('/').last), style: const TextStyle(color: Colors.white, fontSize: 16)),
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
              ref.read(aiProvider.notifier).executeActionManually(action);
              Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context)!.apply),
          ),
        ],
      ),
    );
  }

  List<Widget> _renderMarkdown(String text, BuildContext context) {
    final List<Widget> widgets = [];
    
    // First, extract and handle <think>...</think> blocks
    final thinkingRegex = RegExp(r'<think>([\s\S]*?)</think>', caseSensitive: false);
    final thinkingMatches = thinkingRegex.allMatches(text).toList();
    
    String processedText = text;
    int thinkingIndex = 0;
    
    for (final match in thinkingMatches) {
      final thinkingContent = match.group(1)?.trim() ?? '';
      if (thinkingContent.isNotEmpty) {
        widgets.add(_buildThinkingBlock(thinkingContent, context, thinkingIndex));
        thinkingIndex++;
      }
      processedText = processedText.replaceFirst(match.group(0)!, '');
    }
    
    // Now process remaining text for code blocks
    final regex = RegExp(r'```([a-zA-Z0-9_\-+]*)\n([\s\S]*?)```');
    
    int lastIndex = 0;
    
    for (final match in regex.allMatches(processedText)) {
      if (match.start > lastIndex) {
        final prevText = processedText.substring(lastIndex, match.start).trim();
        if (prevText.isNotEmpty) {
          widgets.add(_buildTextSection(prevText, context));
        }
      }
      
      final language = match.group(1)?.trim() ?? '';
      final code = match.group(2) ?? '';
      widgets.add(_buildCodeBlock(code, language, context));
      
      lastIndex = match.end;
    }
    
    if (lastIndex < processedText.length) {
      final remainingText = processedText.substring(lastIndex).trim();
      if (remainingText.isNotEmpty) {
        widgets.add(_buildTextSection(remainingText, context));
      }
    }
    
    return widgets;
  }

  Widget _buildThinkingBlock(String content, BuildContext context, int index) {
    return _CollapsibleThinking(content: content, index: index);
  }

  Widget _buildTextSection(String text, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: MarkdownBody(
        data: text,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.95), fontSize: 13.5, height: 1.5),
          strong: GoogleFonts.inter(color: Colors.cyanAccent.withValues(alpha: 0.9), fontWeight: FontWeight.bold, fontSize: 13.5),
          em: GoogleFonts.inter(color: Colors.white70, fontStyle: FontStyle.italic, fontSize: 13.5),
          h1: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          h2: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          h3: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          listBullet: GoogleFonts.inter(color: Colors.cyanAccent, fontSize: 13.5),
          code: GoogleFonts.jetBrainsMono(
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            color: Colors.orangeAccent.shade100,
            fontSize: 12.0,
          ),
          tableBody: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
          tableHead: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          tableBorder: TableBorder.all(color: Colors.white24, width: 0.5),
          tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          blockSpacing: 10,
        ),
      ),
    );
  }

  Widget _buildCodeBlock(String code, String language, BuildContext context) {
    final editor = ref.watch(editorProvider);
    final hasActiveFile = editor.activeFilePath != null;
    final currentFileName = editor.activeFilePath?.split('/').last ?? '';

    return CollapsibleCodeBlock(
      code: code,
      language: language,
      currentFileName: currentFileName,
      hasActiveFile: hasActiveFile,
      activeFilePath: editor.activeFilePath ?? '',
      ref: ref,
    );
  }

  void _showCompactMessageMenu(BuildContext context, WidgetRef ref, ChatMessage message, int index) {
    final isUser = message.role == MessageRole.user;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131520),
      barrierColor: Colors.black.withValues(alpha: 0.5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(LucideIcons.copy, size: 16, color: Colors.white70),
                  title: const Text('Скопировать текст', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  dense: true,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.content));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context)!.codeCopied),
                        duration: const Duration(seconds: 1),
                        backgroundColor: const Color(0xFF1E2230),
                      ),
                    );
                  },
                ),
                if (isUser && !widget.aiState.isLoading)
                  ListTile(
                    leading: const Icon(LucideIcons.pencil, size: 16, color: Colors.cyanAccent),
                    title: const Text('Редактировать запрос', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    dense: true,
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _editingMessageIndex = index;
                        _editingController = TextEditingController(text: message.content);
                      });
                    },
                  ),
                if (!widget.aiState.isLoading && index < widget.aiState.messages.length - 1)
                  ListTile(
                    leading: const Icon(LucideIcons.rotate_ccw, size: 16, color: Colors.redAccent),
                    title: const Text('Откатить историю к этому шагу', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    dense: true,
                    onTap: () async {
                      Navigator.pop(context);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xFF1E2230),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          title: Text(
                            AppLocalizations.of(context)!.confirmRollback,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          content: Text(
                            AppLocalizations.of(context)!.rollbackConfirmationText,
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(
                                AppLocalizations.of(context)!.cancel,
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(
                                AppLocalizations.of(context)!.yesRollback,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await ref.read(aiProvider.notifier).rollbackToMessage(index);
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class CollapsibleCodeBlock extends StatefulWidget {
  final String code;
  final String language;
  final String currentFileName;
  final bool hasActiveFile;
  final String activeFilePath;
  final WidgetRef ref;

  const CollapsibleCodeBlock({
    super.key,
    required this.code,
    required this.language,
    required this.currentFileName,
    required this.hasActiveFile,
    required this.activeFilePath,
    required this.ref,
  });

  @override
  State<CollapsibleCodeBlock> createState() => _CollapsibleCodeBlockState();
}

class _CollapsibleCodeBlockState extends State<CollapsibleCodeBlock> {
  bool _isExpanded = false;
  late final CodeLineEditingController _controller;

  static final CodeHighlightTheme _highlightTheme = CodeHighlightTheme(
    languages: {
      'dart': CodeHighlightThemeMode(mode: langDart),
      'json': CodeHighlightThemeMode(mode: langJson),
      'html': CodeHighlightThemeMode(mode: langXml),
      'xml': CodeHighlightThemeMode(mode: langXml),
      'js': CodeHighlightThemeMode(mode: langJavascript),
      'javascript': CodeHighlightThemeMode(mode: langJavascript),
      'yaml': CodeHighlightThemeMode(mode: langYaml),
      'markdown': CodeHighlightThemeMode(mode: langMarkdown),
      'py': CodeHighlightThemeMode(mode: langPython),
      'python': CodeHighlightThemeMode(mode: langPython),
      'cpp': CodeHighlightThemeMode(mode: langCpp),
      'java': CodeHighlightThemeMode(mode: langJava),
      'php': CodeHighlightThemeMode(mode: langPhp),
    },
    theme: atomOneDarkTheme,
  );

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController(
      codeLines: CodeLines.fromText(widget.code.trim()),
    );
  }

  @override
  void didUpdateWidget(CollapsibleCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) {
      _controller.codeLines = CodeLines.fromText(widget.code.trim());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.code.trim().split('\n');
    final isLongCode = lines.length > 10;
    


    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0F111A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.code, size: 12, color: Colors.cyanAccent),
                      const SizedBox(width: 6),
                      Text(
                        widget.language.isEmpty ? 'CODE' : widget.language.toUpperCase(),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (widget.hasActiveFile) ...[
                        Tooltip(
                          message: 'Replace code in ${widget.currentFileName}',
                          child: InkWell(
                            onTap: () {
                              widget.ref.read(editorProvider.notifier).updateFileContentFromAI(
                                widget.activeFilePath,
                                widget.code.trim(),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('File ${widget.currentFileName} updated!'),
                                  backgroundColor: const Color(0xFF1E2230),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(LucideIcons.pencil, size: 11, color: Colors.cyanAccent),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Apply to ${widget.currentFileName}',
                                    style: GoogleFonts.inter(fontSize: 10, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: widget.code));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(AppLocalizations.of(context)!.codeCopied),
                              duration: const Duration(seconds: 1),
                              backgroundColor: const Color(0xFF1E2230),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.copy, size: 11, color: Colors.white38),
                              const SizedBox(width: 4),
                              Text(
                                AppLocalizations.of(context)!.copy,
                                style: GoogleFonts.inter(fontSize: 10, color: Colors.white38),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 0.5,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: (_isExpanded || !isLongCode) ? 450.0 : 160.0,
              ),
              child: CodeEditor(
                controller: _controller,
                readOnly: true,
                wordWrap: true,
                style: CodeEditorStyle(
                  fontSize: 11.5,
                  fontFamily: 'jetBrainsMono',
                  backgroundColor: const Color(0xFF0F111A),
                  codeTheme: _highlightTheme,
                ),
              ),
            ),
          ),
          if (isLongCode) ...[
            Container(
              height: 0.5,
              color: Colors.white.withValues(alpha: 0.06),
            ),
            InkWell(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                color: Colors.white.withValues(alpha: 0.01),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isExpanded ? LucideIcons.chevron_up : LucideIcons.chevron_down,
                      size: 11,
                      color: Colors.cyanAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isExpanded ? 'Свернуть код' : 'Развернуть код (${lines.length} строк)',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AIActionFileItem extends ConsumerStatefulWidget {
  final AIAction action;
  final VoidCallback onShowDiff;
  final VoidCallback onRemove;
  final bool isPending;

  const AIActionFileItem({
    super.key,
    required this.action,
    required this.onShowDiff,
    required this.onRemove,
    this.isPending = true,
  });

  @override
  ConsumerState<AIActionFileItem> createState() => _AIActionFileItemState();
}

class _AIActionFileItemState extends ConsumerState<AIActionFileItem> {
  int _additions = 0;
  int _deletions = 0;
  bool _calculated = false;

  @override
  void initState() {
    super.initState();
    _calculateDiffStats();
  }

  @override
  void didUpdateWidget(AIActionFileItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.action.content != widget.action.content || oldWidget.action.path != widget.action.path) {
      _calculateDiffStats();
    }
  }

  Future<void> _calculateDiffStats() async {
    if (widget.action.type == 'command') return;
    
    try {
      final file = File(widget.action.path);
      String originalContent = '';
      if (widget.action.type == 'edit' && await file.exists()) {
        originalContent = await file.readAsString();
      }
      final modifiedContent = widget.action.content;

      final dmp = DiffMatchPatch();
      final diffs = dmp.diff(originalContent, modifiedContent);
      dmp.diffCleanupSemantic(diffs);

      int additions = 0;
      int deletions = 0;

      for (final d in diffs) {
        final lineCount = '\n'.allMatches(d.text).length + (d.text.isNotEmpty ? 1 : 0);
        if (d.operation == DIFF_INSERT) {
          additions += lineCount;
        } else if (d.operation == DIFF_DELETE) {
          deletions += lineCount;
        }
      }

      if (mounted) {
        setState(() {
          _additions = additions;
          _deletions = deletions;
          _calculated = true;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    final displayPath = (workspacePath != null && widget.action.path.startsWith(workspacePath))
        ? p.relative(widget.action.path, from: workspacePath)
        : widget.action.path;

    final fileName = displayPath.split('/').last;
    final dirPath = displayPath.contains('/') 
        ? displayPath.substring(0, displayPath.lastIndexOf('/')) 
        : '';

    Color typeColor;
    IconData typeIcon;
    switch (widget.action.type) {
      case 'edit':
        typeColor = Colors.blueAccent;
        typeIcon = LucideIcons.pencil;
        break;
      case 'create':
        typeColor = Colors.greenAccent;
        typeIcon = LucideIcons.file_plus;
        break;
      case 'delete':
        typeColor = Colors.redAccent;
        typeIcon = LucideIcons.file_x;
        break;
      case 'command':
        typeColor = Colors.amberAccent;
        typeIcon = LucideIcons.terminal;
        break;
      default:
        typeColor = Colors.white38;
        typeIcon = LucideIcons.sparkles;
    }

    const permissionService = AiPermissionService();
    final inScope = widget.action.type == 'command' || permissionService.isPathInScope(widget.action.path, workspacePath ?? '');
    final risk = permissionService.evaluateActionRisk(widget.action, workspacePath ?? '');
    
    Color riskColor;
    String riskLabel;
    
    if (!inScope) {
      riskColor = Colors.redAccent;
      riskLabel = AppLocalizations.of(context)!.outOfScope;
    } else {
      switch (risk) {
        case AiRiskLevel.low:
          riskColor = Colors.greenAccent;
          riskLabel = AppLocalizations.of(context)!.low;
          break;
        case AiRiskLevel.medium:
          riskColor = Colors.purpleAccent;
          riskLabel = AppLocalizations.of(context)!.medium;
          break;
        case AiRiskLevel.high:
          riskColor = Colors.orangeAccent;
          riskLabel = AppLocalizations.of(context)!.high;
          break;
      }
    }

    return InkWell(
      onTap: () {
        if (widget.action.type == 'edit' || widget.action.type == 'create') {
          ref.read(editorProvider.notifier).openFile(widget.action.path, isDiffView: true);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(typeIcon, size: 13, color: typeColor),
                const SizedBox(width: 7),
                Expanded(
                  child: widget.action.type == 'command'
                      ? Text(
                          widget.action.content,
                          style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : Row(
                          children: [
                            Flexible(
                              child: Text(
                                  fileName,
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (dirPath.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  dirPath,
                                  style: GoogleFonts.inter(color: Colors.white30, fontSize: 10.5),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
                if (widget.action.type != 'command' && _calculated) ...[
                  if (_additions > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '+$_additions',
                      style: GoogleFonts.jetBrainsMono(color: const Color(0xFF4EC994), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                  if (_deletions > 0) ...[
                    const SizedBox(width: 2),
                    Text(
                      '-$_deletions',
                      style: GoogleFonts.jetBrainsMono(color: const Color(0xFFFF6B6B), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: riskColor.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    riskLabel,
                    style: GoogleFonts.inter(color: riskColor, fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                if (widget.isPending) ...[
                  if (widget.action.type == 'edit' || widget.action.type == 'create') ...[
                    InkWell(
                      onTap: () => ref.read(editorProvider.notifier).openFile(widget.action.path, isDiffView: true),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.diff, size: 10, color: Colors.white38),
                            const SizedBox(width: 3),
                            Text('Diff', style: GoogleFonts.inter(fontSize: 10, color: Colors.white38)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  InkWell(
                    onTap: () => ref.read(aiProvider.notifier).executeActionManually(widget.action),
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F5132).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFF4EC994).withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.keep,
                        style: GoogleFonts.inter(color: const Color(0xFF4EC994), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: widget.onRemove,
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5C1818).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.reject,
                        style: GoogleFonts.inter(color: const Color(0xFFFF6B6B), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ] else ...[
                  if (widget.action.type == 'edit' || widget.action.type == 'create') ...[
                    InkWell(
                      onTap: () => ref.read(editorProvider.notifier).openFile(widget.action.path, isDiffView: true),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.eye, size: 10, color: Colors.white38),
                            const SizedBox(width: 3),
                            Text(AppLocalizations.of(context)!.viewAction, style: GoogleFonts.inter(fontSize: 10, color: Colors.white38)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.circle_check, size: 10, color: Color(0xFF4EC994)),
                      const SizedBox(width: 3),
                      Text(
                        AppLocalizations.of(context)!.applied,
                        style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF4EC994), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── CUSTOM GLOWING AI AGENT LOADERS & WIDGETS ────────────────────────

class _GlowingAgentLoader extends StatefulWidget {
  final Color color;
  final String status;
  final String role;

  const _GlowingAgentLoader({
    required this.color,
    required this.status,
    required this.role,
  });

  @override
  State<_GlowingAgentLoader> createState() => _GlowingAgentLoaderState();
}

class _GlowingAgentLoaderState extends State<_GlowingAgentLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 12, left: 4, right: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F111A).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.color.withValues(alpha: 0.35),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.15),
            blurRadius: 16,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    RotationTransition(
                      turns: _controller,
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation<Color>(widget.color.withValues(alpha: 0.5)),
                        ),
                      ),
                    ),
                    _PulsingDot(color: widget.color),
                    Icon(
                      widget.role.toLowerCase() == 'planner'
                          ? LucideIcons.compass
                          : (widget.role.toLowerCase() == 'coder'
                              ? LucideIcons.code
                              : (widget.role.toLowerCase() == 'validator'
                                  ? LucideIcons.shield_check
                                  : LucideIcons.bot)),
                      size: 16,
                      color: widget.color,
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.color,
                              boxShadow: [
                                BoxShadow(
                                  color: widget.color.withValues(alpha: 0.8),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.role.toUpperCase(),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: widget.color,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '• ACTIVE RUN',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Colors.white24,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        widget.status,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.9),
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
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 26 + (6 * _controller.value),
          height: 26 + (6 * _controller.value),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.08 * (1.0 - _controller.value)),
            border: Border.all(
              color: widget.color.withValues(alpha: 0.25 * (1.0 - _controller.value)),
              width: 1.0,
            ),
          ),
        );
      },
    );
  }
}

class _CollapsibleThinking extends StatefulWidget {
  final String content;
  final int index;

  const _CollapsibleThinking({
    required this.content,
    required this.index,
  });

  @override
  State<_CollapsibleThinking> createState() => _CollapsibleThinkingState();
}

class _CollapsibleThinkingState extends State<_CollapsibleThinking> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.purpleAccent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(LucideIcons.brain, size: 12, color: Colors.purpleAccent.shade100),
                  const SizedBox(width: 6),
                  Text(
                    'Thinking...',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: Colors.purpleAccent.shade100,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _isExpanded ? LucideIcons.chevron_up : LucideIcons.chevron_down,
                    size: 12,
                    color: Colors.white30,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.black26,
              child: SelectableText(
                widget.content,
                style: GoogleFonts.jetBrainsMono(
                  color: Colors.white54,
                  fontSize: 10.5,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CollapsibleCommandConsole extends StatefulWidget {
  final String command;
  final String output;

  const _CollapsibleCommandConsole({
    required this.command,
    required this.output,
  });

  @override
  State<_CollapsibleCommandConsole> createState() => _CollapsibleCommandConsoleState();
}

class _CollapsibleCommandConsoleState extends State<_CollapsibleCommandConsole> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final cleanOutput = widget.output.trim();
    final hasOutput = cleanOutput.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F111A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: hasOutput ? () => setState(() => _isExpanded = !_isExpanded) : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(LucideIcons.terminal, size: 13, color: Colors.amberAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '\$ ${widget.command}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasOutput) ...[
                    const SizedBox(width: 8),
                    Icon(
                      _isExpanded ? LucideIcons.chevron_up : LucideIcons.chevron_down,
                      size: 13,
                      color: Colors.white30,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_isExpanded && hasOutput)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: SelectableText(
                    cleanOutput,
                    style: GoogleFonts.jetBrainsMono(
                      color: Colors.white70,
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CollapsibleMcpConsole extends StatefulWidget {
  final String server;
  final String tool;
  final Map<String, dynamic> arguments;
  final String output;

  const _CollapsibleMcpConsole({
    required this.server,
    required this.tool,
    required this.arguments,
    required this.output,
  });

  @override
  State<_CollapsibleMcpConsole> createState() => _CollapsibleMcpConsoleState();
}

class _CollapsibleMcpConsoleState extends State<_CollapsibleMcpConsole> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isError = widget.output.toLowerCase().contains('error') || 
                    widget.output.toLowerCase().contains('failed');
                    
    final statusColor = isError ? Colors.redAccent : Colors.greenAccent;
    final statusIcon = isError ? LucideIcons.circle_x : LucideIcons.circle_check;

    String displayOutput = widget.output;
    try {
      final parsed = jsonDecode(widget.output);
      if (parsed is Map && parsed.containsKey('content') && parsed['content'] is List) {
        final list = parsed['content'] as List;
        final textParts = list.map((item) {
          if (item is Map && item.containsKey('text')) {
            return item['text'].toString();
          }
          return item.toString();
        }).toList();
        displayOutput = textParts.join('\n');
      } else if (parsed is Map) {
        displayOutput = const JsonEncoder.withIndent('  ').convert(parsed);
      }
    } catch (_) {
      // Keep original output if not valid JSON
    }

    final cleanOutput = displayOutput.trim();
    final hasOutput = cleanOutput.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF131520),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: hasOutput ? () => setState(() => _isExpanded = !_isExpanded) : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(LucideIcons.plug, size: 14, color: Colors.purpleAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.server,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text('→', style: TextStyle(color: Colors.purpleAccent, fontSize: 10)),
                            const SizedBox(width: 4),
                            Text(
                              widget.tool,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                color: Colors.purpleAccent.shade100,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (widget.arguments.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Args: ${jsonEncode(widget.arguments)}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              color: Colors.white38,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(statusIcon, size: 13, color: statusColor),
                  if (hasOutput) ...[
                    const SizedBox(width: 8),
                    Icon(
                      _isExpanded ? LucideIcons.chevron_up : LucideIcons.chevron_down,
                      size: 13,
                      color: Colors.white30,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_isExpanded && hasOutput) ...[
            const Divider(color: Colors.white10, height: 1),
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.black26,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.arguments.isNotEmpty) ...[
                    Text(
                      'INPUT ARGUMENTS:',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.white30,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert(widget.arguments),
                        style: GoogleFonts.jetBrainsMono(
                          color: Colors.cyanAccent.shade100,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    'RESPONSE:',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.white30,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      cleanOutput,
                      style: GoogleFonts.jetBrainsMono(
                        color: isError ? Colors.redAccent.shade100 : Colors.white70,
                        fontSize: 9.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
