import 'dart:io';
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

  Widget _buildMessageActionDetails(AIAction action) {
    return SelectionArea(
      child: Builder(builder: (context) {
        final workspacePath = ref.read(workspaceProvider).currentPath;
        IconData iconData;
        Color iconColor;
        String text;
        
        if (action.type == 'command') {
          iconData = LucideIcons.terminal;
          iconColor = Colors.white54;
          text = AppLocalizations.of(context)!.ranAction(action.content);
        } else {
          final fileName = action.path.split('/').last;
          iconColor = action.type == 'create' 
              ? Colors.greenAccent 
              : (action.type == 'delete' ? Colors.redAccent : Colors.blueAccent);
          
          iconData = action.type == 'create' 
              ? LucideIcons.file_plus 
              : (action.type == 'delete' ? LucideIcons.file_x : LucideIcons.pencil);
          
          final relDir = workspacePath != null && action.path.startsWith(workspacePath)
              ? p.dirname(p.relative(action.path, from: workspacePath))
              : '';
          
          final dirSuffix = relDir.isNotEmpty && relDir != '.' ? ' ${AppLocalizations.of(context)!.inFolder(relDir)}' : '';
          final typeStr = action.type == 'create' 
              ? AppLocalizations.of(context)!.created 
              : (action.type == 'delete' ? AppLocalizations.of(context)!.deleted : AppLocalizations.of(context)!.edited);
          text = '$typeStr $fileName$dirSuffix';
        }
        
        return Row(
          children: [
            Icon(iconData, size: 11, color: iconColor),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 11, color: Colors.white70))),
          ],
        );
      }),
    );
  }

  Widget _buildStepSummary(ChatMessage message) {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    final executed = message.executedActions ?? [];
    
    int editCount = 0;
    int additions = 0;
    int deletions = 0;
    int commandCount = 0;
    
    for (final action in executed) {
      if (action.type == 'command') {
        commandCount++;
      } else {
        editCount++;
        additions += action.additions ?? 0;
        deletions += action.deletions ?? 0;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (executed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(executed.length, (index) {
                final action = executed[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: _buildMessageActionDetails(action),
                );
              }),
            ),
          ),
        
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2230),
            borderRadius: BorderRadius.circular(12),
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
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(LucideIcons.circle_check, size: 12, color: Colors.greenAccent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.taskName != null && message.taskName!.isNotEmpty
                                ? (message.taskName!.length > 40 ? '${message.taskName!.substring(0, 40)}...' : message.taskName!)
                                : AppLocalizations.of(context)!.taskExecution,
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                          if (message.stepNumber != null)
                            Text(
                              AppLocalizations.of(context)!.stepNumber(message.stepNumber!, message.totalSteps ?? 12),
                              style: GoogleFonts.inter(color: Colors.white38, fontSize: 9.5),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      editCount > 0 
                          ? AppLocalizations.of(context)!.filesChangedCount(editCount, additions, deletions)
                          : AppLocalizations.of(context)!.commandsExecutedCount(commandCount),
                      style: GoogleFonts.inter(color: Colors.white60, fontSize: 10),
                    ),
                    if (editCount > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(LucideIcons.check, size: 10, color: Colors.greenAccent),
                            label: Text(
                              AppLocalizations.of(context)!.keep,
                              style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(AppLocalizations.of(context)!.changesAccepted),
                                  backgroundColor: const Color(0xFF1E2230),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(LucideIcons.undo_2, size: 10, color: Colors.redAccent),
                            label: Text(
                              AppLocalizations.of(context)!.undo,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final gitSvc = ref.read(gitServiceProvider);
                              final editor = ref.read(editorProvider.notifier);
                              int undone = 0;
                              for (final action in executed) {
                                  if (action.type == 'edit' || action.type == 'create') {
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
                              }
                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(AppLocalizations.of(context)!.undoneChanges(undone)),
                                    backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              if (editCount > 0) ...[
                const Divider(color: Colors.white10, height: 1),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: executed.where((a) => a.type != 'command').length,
                  itemBuilder: (context, idx) {
                    final editActions = executed.where((a) => a.type != 'command').toList();
                    final action = editActions[idx];
                    final fileName = action.path.split('/').last;
                    final displayPath = workspacePath != null && action.path.startsWith(workspacePath)
                        ? p.relative(action.path, from: workspacePath)
                        : action.path;
                    final dirPath = displayPath.contains('/')
                        ? displayPath.substring(0, displayPath.lastIndexOf('/'))
                        : '';

                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      leading: const Icon(LucideIcons.file_code, size: 13, color: Colors.white54),
                      title: Row(
                        children: [
                          Text(fileName, style: GoogleFonts.inter(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                          if (dirPath.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Expanded(child: Text('in $dirPath', style: GoogleFonts.inter(color: Colors.white30, fontSize: 9), overflow: TextOverflow.ellipsis)),
                          ],
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if ((action.additions ?? 0) > 0)
                            Text(
                              '+${action.additions}',
                              style: GoogleFonts.jetBrainsMono(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          if ((action.additions ?? 0) > 0 && (action.deletions ?? 0) > 0) const SizedBox(width: 4),
                          if ((action.deletions ?? 0) > 0)
                            Text(
                              '-${action.deletions}',
                              style: GoogleFonts.jetBrainsMono(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(LucideIcons.undo_2, size: 10, color: Colors.white38),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () async {
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
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
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
          String roleText;
          IconData roleIcon;
          
          switch (role.toLowerCase()) {
            case 'planner':
              roleColor = Colors.cyanAccent;
              roleText = AppLocalizations.of(context)!.planner;
              roleIcon = LucideIcons.compass;
              break;
            case 'coder':
              roleColor = Colors.purpleAccent;
              roleText = AppLocalizations.of(context)!.coder;
              roleIcon = LucideIcons.code;
              break;
            case 'validator':
              roleColor = Colors.orangeAccent;
              roleText = AppLocalizations.of(context)!.validator;
              roleIcon = LucideIcons.shield_check;
              break;
            default:
              roleColor = Colors.blueAccent;
              roleText = AppLocalizations.of(context)!.aiAgentRole;
              roleIcon = LucideIcons.bot;
          }

          return Container(
            margin: const EdgeInsets.only(top: 4, bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2230).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: roleColor.withValues(alpha: 0.25),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ]
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(roleColor),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(roleIcon, size: 11, color: roleColor),
                          const SizedBox(width: 4),
                          Text(
                            roleText,
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: roleColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        status,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final message = widget.aiState.messages[index];
        final isUser = message.role == MessageRole.user;
        final isSystem = message.role == MessageRole.system;
        final isLastMessage = index == widget.aiState.messages.length - 1;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: isUser 
                ? CrossAxisAlignment.end 
                : (isSystem ? CrossAxisAlignment.stretch : CrossAxisAlignment.start),
            children: [
              if (isSystem)
                message.isStepSummary
                    ? _buildStepSummary(message)
                    : CollapsibleConsole(content: message.content)
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: isUser
                        ? LinearGradient(
                            colors: [
                              Colors.purpleAccent.withValues(alpha: 0.18),
                              const Color(0xFF512DA8).withValues(alpha: 0.32),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isUser ? null : Colors.white.withValues(alpha: 0.03),
                    borderRadius: isUser
                        ? const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(2),
                          )
                        : const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                            bottomLeft: Radius.circular(2),
                            bottomRight: Radius.circular(16),
                          ),
                    border: Border.all(
                      color: isUser
                          ? Colors.purpleAccent.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.08),
                      width: isUser ? 0.9 : 0.6,
                    ),
                    boxShadow: isUser
                        ? [
                            BoxShadow(
                              color: Colors.purpleAccent.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: isUser
                      ? (_editingMessageIndex == index
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _editingController,
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5),
                                  maxLines: null,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                ),
                                const SizedBox(height: 8),
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
                                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.cyanAccent.withValues(alpha: 0.15),
                                        foregroundColor: Colors.cyanAccent,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        minimumSize: Size.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(6),
                                          side: const BorderSide(color: Colors.cyanAccent, width: 0.5),
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
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : SelectableText(
                              message.content,
                              style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5, height: 1.45),
                            ))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _renderMarkdown(message.content, context),
                        ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
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
                      style: GoogleFonts.inter(color: Colors.white24, fontSize: 10),
                    ),
                    if (isUser && !widget.aiState.isLoading && _editingMessageIndex == null) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _editingMessageIndex = index;
                            _editingController = TextEditingController(text: message.content);
                          });
                        },
                        child: const Icon(LucideIcons.pencil, size: 10, color: Colors.cyanAccent),
                      ),
                    ],
                    if (!widget.aiState.isLoading && index < widget.aiState.messages.length - 1) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: AppLocalizations.of(context)!.rollbackHistoryToStep,
                        child: InkWell(
                          onTap: () async {
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
                          child: const Icon(LucideIcons.rotate_ccw, size: 10, color: Colors.redAccent),
                        ),
                      ),
                    ],
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
    final regex = RegExp(r'```([a-zA-Z0-9_\-+]*)\n([\s\S]*?)```');
    
    int lastIndex = 0;
    
    for (final match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        final prevText = text.substring(lastIndex, match.start).trim();
        if (prevText.isNotEmpty) {
          widgets.add(_buildTextSection(prevText, context));
        }
      }
      
      final language = match.group(1)?.trim() ?? '';
      final code = match.group(2) ?? '';
      widgets.add(_buildCodeBlock(code, language, context));
      
      lastIndex = match.end;
    }
    
    if (lastIndex < text.length) {
      final remainingText = text.substring(lastIndex).trim();
      if (remainingText.isNotEmpty) {
        widgets.add(_buildTextSection(remainingText, context));
      }
    }
    
    return widgets;
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

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
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
                        language.isEmpty ? 'CODE' : language.toUpperCase(),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (hasActiveFile) ...[
                        Tooltip(
                           message: 'Replace code in $currentFileName',
                          child: InkWell(
                            onTap: () {
                              ref.read(editorProvider.notifier).updateFileContentFromAI(
                                editor.activeFilePath!,
                                code.trim(),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                   content: Text('File $currentFileName updated!'),
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
                                    'Apply to $currentFileName',
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
                          Clipboard.setData(ClipboardData(text: code));
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
            padding: const EdgeInsets.all(12.0),
            child: SelectableText(
              code.trim(),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12.5,
                color: Colors.white.withValues(alpha: 0.95),
                height: 1.45,
              ),
            ),
          ),
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
          ref.read(editorProvider.notifier).openFile(widget.action.path);
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
                      onTap: widget.onShowDiff,
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
                      onTap: widget.onShowDiff,
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
