import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/collaboration_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:flutter/services.dart';

class LiveSharePanel extends ConsumerStatefulWidget {
  const LiveSharePanel({super.key});

  @override
  ConsumerState<LiveSharePanel> createState() => _LiveSharePanelState();
}

class _LiveSharePanelState extends ConsumerState<LiveSharePanel> {
  final TextEditingController _joinController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  final List<Color> _availableColors = [
    Colors.blueAccent,
    Colors.greenAccent,
    Colors.purpleAccent,
    Colors.orangeAccent,
    Colors.pinkAccent,
    Colors.tealAccent,
    Colors.amberAccent,
    Colors.redAccent,
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final collabState = ref.read(collaborationProvider);
      _nameController.text = collabState.localUserName;
    });
  }

  @override
  void dispose() {
    _joinController.dispose();
    _nameController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_chatScrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final collabState = ref.watch(collaborationProvider);
    final l10n = AppLocalizations.of(context)!;
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    // Auto scroll chat when new messages arrive
    ref.listen<CollaborationState>(collaborationProvider, (previous, next) {
      if (previous?.chatMessages.length != next.chatMessages.length) {
        _scrollToBottom();
      }
    });

    return Container(
      color: const Color(0xFF0F111A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sidebar header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.purpleAccent, Colors.pinkAccent],
                  ).createShader(bounds),
                  child: const Icon(LucideIcons.users, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.liveShare,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Section 1: User Profile Customization (Only when not connected)
                    if (!collabState.isConnected) ...[
                      _buildProfileCustomizer(context, collabState, l10n),
                      const SizedBox(height: 16),
                      _buildJoinHostControls(context, collabState, l10n),
                    ] else ...[
                      _buildSessionInfoCard(context, collabState, l10n, isRu),
                      const SizedBox(height: 16),
                      _buildParticipantsSection(context, collabState, l10n),
                      const SizedBox(height: 16),
                      _buildChatSection(context, collabState, l10n),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCustomizer(BuildContext context, CollaborationState state, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.userName,
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            onChanged: (val) => ref.read(collaborationProvider.notifier).setLocalName(val),
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              fillColor: Colors.white.withValues(alpha: 0.05),
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'ЦВЕТ КУРСОРА',
            style: GoogleFonts.inter(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 24,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _availableColors.length,
              itemBuilder: (context, index) {
                final color = _availableColors[index];
                final isSelected = state.localUserColor.value == color.value;
                return GestureDetector(
                  onTap: () => ref.read(collaborationProvider.notifier).setLocalColor(color),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected 
                        ? Border.all(color: Colors.white, width: 2) 
                        : Border.all(color: Colors.transparent),
                      boxShadow: isSelected 
                        ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 1)]
                        : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinHostControls(BuildContext context, CollaborationState state, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Host Button
        ElevatedButton.icon(
          onPressed: () => ref.read(collaborationProvider.notifier).startHosting(),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF3C3C), // Mandy Red
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(LucideIcons.radio, size: 16),
          label: Text(
            l10n.hostSession,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Divider(color: Colors.white10)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('ИЛИ', style: GoogleFonts.inter(fontSize: 10, color: Colors.white24, fontWeight: FontWeight.bold)),
            ),
            const Expanded(child: Divider(color: Colors.white10)),
          ],
        ),
        const SizedBox(height: 16),
        // Join Section
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.joinLink,
                style: GoogleFonts.inter(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _joinController,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                decoration: InputDecoration(
                  hintText: '192.168.1.15:9090',
                  hintStyle: const TextStyle(color: Colors.white24),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  filled: true,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  if (_joinController.text.isNotEmpty) {
                    ref.read(collaborationProvider.notifier).joinSession(_joinController.text);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(LucideIcons.arrow_right_to_line, size: 14),
                label: Text(
                  l10n.joinSession,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSessionInfoCard(BuildContext context, CollaborationState state, AppLocalizations l10n, bool isRu) {
    final title = state.isHosting ? l10n.hostingAt : l10n.connectedTo;
    
    // For Host, list local IPs. For Guest, show Host IP.
    String displayAddress = '';
    if (state.isHosting) {
      if (state.localIps.isNotEmpty) {
        displayAddress = state.localIps.map((ip) => '$ip:9090').join('\n');
      } else {
        displayAddress = '127.0.0.1:9090';
      }
    } else {
      displayAddress = state.hostAddress ?? '';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.15), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.sessionActive.toUpperCase(),
                style: GoogleFonts.inter(fontSize: 10, color: Colors.greenAccent, fontWeight: FontWeight.bold, letterSpacing: 0.8),
              ),
              const Spacer(),
              Text(
                state.isHosting ? 'HOST' : 'GUEST',
                style: GoogleFonts.jetBrainsMono(fontSize: 9, color: Colors.white38, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  displayAddress,
                  style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white, height: 1.4),
                ),
              ),
              const SizedBox(width: 8),
              if (state.isHosting && state.localIps.isNotEmpty)
                IconButton(
                  icon: const Icon(LucideIcons.copy, size: 14, color: Colors.white38),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '${state.localIps.first}:9090'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('IP скопирован в буфер обмена')),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () => ref.read(collaborationProvider.notifier).stopAll(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.2)),
              ),
              elevation: 0,
            ),
            icon: Icon(state.isHosting ? LucideIcons.square : LucideIcons.log_out, size: 14),
            label: Text(
              state.isHosting ? l10n.stopSession : l10n.disconnectSession,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsSection(BuildContext context, CollaborationState state, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.usersList,
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          const SizedBox(height: 10),
          // Local User
          _buildParticipantTile(
            state.localUserName,
            state.localUserColor,
            ref.read(editorProvider).activeFilePath != null
              ? p.basename(ref.read(editorProvider).activeFilePath!)
              : null,
            isMe: true,
          ),
          // Remote Users
          ...state.users.values.map((user) {
            return _buildParticipantTile(
              user.name,
              user.color,
              user.activeFile != null ? p.basename(user.activeFile!) : null,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildParticipantTile(String name, Color color, String? activeFile, {bool isMe = false}) {
    final initials = name.isNotEmpty ? name.substring(0, min(name.length, 2)).toUpperCase() : '??';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Вы', style: TextStyle(color: Colors.white54, fontSize: 8)),
                      ),
                    ],
                  ],
                ),
                if (activeFile != null)
                  Text(
                    'Редактирует: $activeFile',
                    style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.35)),
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  const Text(
                    'Просматривает проект',
                    style: TextStyle(fontSize: 10, color: Colors.white30),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatSection(BuildContext context, CollaborationState state, AppLocalizations l10n) {
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              l10n.chat,
              style: GoogleFonts.inter(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          // Chat messages lists
          Expanded(
            child: ListView.builder(
              controller: _chatScrollController,
              padding: const EdgeInsets.all(12),
              itemCount: state.chatMessages.length,
              itemBuilder: (context, index) {
                final msg = state.chatMessages[index];
                final isSystem = msg.senderId == 'system';
                
                if (isSystem) {
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      msg.text,
                      style: GoogleFonts.inter(color: Colors.grey, fontSize: 10, fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            msg.senderName,
                            style: TextStyle(
                              color: msg.senderColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Colors.white24, fontSize: 9),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        msg.text,
                        style: const TextStyle(color: Color(0xDDFFFFFF), fontSize: 12),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          // Input bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    onSubmitted: (val) => _sendChatMessage(),
                    style: const TextStyle(fontSize: 12.5, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: l10n.messagePlaceholder,
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      filled: true,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(LucideIcons.send, size: 15, color: Colors.purpleAccent),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _sendChatMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sendChatMessage() {
    if (_chatController.text.isNotEmpty) {
      ref.read(collaborationProvider.notifier).sendChatMessage(_chatController.text);
      _chatController.clear();
      _scrollToBottom();
    }
  }
}
