import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/features/collaboration/presentation/notifiers/collaboration_notifier.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';

class CollaborationPage extends ConsumerStatefulWidget {
  const CollaborationPage({super.key});

  @override
  ConsumerState<CollaborationPage> createState() => _CollaborationPageState();
}

class _CollaborationPageState extends ConsumerState<CollaborationPage> {
  final TextEditingController _sessionCodeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  @override
  void dispose() {
    _sessionCodeController.dispose();
    _nameController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collabState = ref.watch(collaborationProvider);
    final collabNotifier = ref.read(collaborationProvider.notifier);

    if (collabState.isInSession) {
      return _buildActiveSession(collabState, collabNotifier);
    }

    return _buildJoinOrCreateView(collabState, collabNotifier);
  }

  Widget _buildJoinOrCreateView(
      CollaborationState state, CollaborationNotifier notifier) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A10),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.cyanAccent.withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color:
                                      Colors.cyanAccent.withValues(alpha: 0.15)),
                            ),
                            child: const Icon(LucideIcons.users,
                                color: Colors.cyanAccent, size: 40),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Live Share',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Collaborate in real-time with other developers',
                            style: GoogleFonts.inter(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          _buildNameInput(),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: state.isLoading || _nameController.text.isEmpty
                                  ? null
                                  : () => notifier.createSession(
                                      _nameController.text),
                              icon: const Icon(LucideIcons.plus, size: 14),
                              label: Text(
                                state.isLoading
                                    ? 'Creating...'
                                    : 'Create Session',
                                style: const TextStyle(fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.cyanAccent.withValues(alpha: 0.15),
                                foregroundColor: Colors.cyanAccent,
                                elevation: 0,
                                side: BorderSide(
                                    color: Colors.cyanAccent
                                        .withValues(alpha: 0.3)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                  child: Divider(
                                      color: Colors.white.withValues(alpha: 0.1))),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('OR',
                                    style: GoogleFonts.inter(
                                        color: Colors.white24, fontSize: 10)),
                              ),
                              Expanded(
                                  child: Divider(
                                      color: Colors.white.withValues(alpha: 0.1))),
                            ],
                          ),
                          const SizedBox(height: 24),
                          _buildSessionCodeInput(),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: state.isLoading || _sessionCodeController.text.isEmpty
                                  ? null
                                  : () => notifier.joinSession(
                                      _sessionCodeController.text,
                                      _nameController.text.isEmpty
                                          ? 'Guest'
                                          : _nameController.text),
                              icon: const Icon(LucideIcons.log_in, size: 14),
                              label: Text(
                                state.isLoading ? 'Joining...' : 'Join Session',
                                style: const TextStyle(fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.greenAccent.withValues(alpha: 0.15),
                                foregroundColor: Colors.greenAccent,
                                elevation: 0,
                                side: BorderSide(
                                    color: Colors.greenAccent
                                        .withValues(alpha: 0.3)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          if (state.error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              state.error!,
                              style: GoogleFonts.inter(
                                  color: Colors.redAccent, fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameInput() {
    return TextField(
      controller: _nameController,
      decoration: InputDecoration(
        hintText: 'Your display name',
        hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.cyanAccent, width: 0.8),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        prefixIcon: const Icon(LucideIcons.user, size: 15, color: Colors.white38),
      ),
      style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
    );
  }

  Widget _buildSessionCodeInput() {
    return TextField(
      controller: _sessionCodeController,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        hintText: 'Enter session code',
        hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.greenAccent, width: 0.8),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        prefixIcon:
            const Icon(LucideIcons.key_round, size: 15, color: Colors.white38),
      ),
      style: GoogleFonts.jetBrainsMono(
          color: Colors.white, fontSize: 13, letterSpacing: 2),
    );
  }

  Widget _buildActiveSession(
      CollaborationState state, CollaborationNotifier notifier) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A10),
      body: SafeArea(
        child: Column(
          children: [
            _buildActiveHeader(state, notifier),
            Expanded(
              child: Row(
                children: [
                  Expanded(flex: 2, child: _buildCollaboratorsList(state)),
                  Container(
                      width: 1,
                      color: Colors.white.withValues(alpha: 0.06)),
                  Expanded(flex: 3, child: _buildChatPanel(state, notifier)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveHeader(
      CollaborationState state, CollaborationNotifier notifier) {
    return GlassContainer(
      blur: 20,
      opacity: 0.05,
      borderRadius: BorderRadius.zero,
      border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(LucideIcons.arrow_left, color: Colors.white70),
              onPressed: () => notifier.leaveSession(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Live Session',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Code: ${state.sessionCode}',
                        style: GoogleFonts.jetBrainsMono(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              '${state.collaborators.length} connected',
              style: GoogleFonts.inter(
                color: Colors.cyanAccent,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(LucideIcons.copy, size: 14, color: Colors.white38),
              onPressed: () {
                if (state.sessionCode != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Session code copied: ${state.sessionCode}'),
                      backgroundColor: const Color(0xFF0F172A),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollaboratorsList(CollaborationState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'COLLABORATORS',
            style: GoogleFonts.inter(
              fontSize: 9.5,
              color: Colors.white24,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: state.collaborators.length,
            itemBuilder: (context, index) {
              final collaborator = state.collaborators[index];
              final isYou = collaborator.userId == state.userId;
              final color =
                  Color(int.parse(collaborator.colorHex.replaceFirst('#', '0xFF')));

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: Center(
                        child: Text(
                          collaborator.userName[0].toUpperCase(),
                          style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            collaborator.userName,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isYou)
                            Text(
                              'You',
                              style: GoogleFonts.inter(
                                color: Colors.white38,
                                fontSize: 9,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
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

  Widget _buildChatPanel(
      CollaborationState state, CollaborationNotifier notifier) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'CHAT',
            style: GoogleFonts.inter(
              fontSize: 9.5,
              color: Colors.white24,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(
          child: state.messages.isEmpty
              ? Center(
                  child: Text(
                    'No messages yet',
                    style: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: state.messages.length,
                  itemBuilder: (context, index) {
                    final msg = state.messages[index];
                    final color = state.collaborators
                        .where((c) => c.userId == msg.userId)
                        .map((c) => c.colorHex)
                        .firstOrNull;

                    final authorColor = color != null
                        ? Color(int.parse(color.replaceFirst('#', '0xFF')))
                        : Colors.white54;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                msg.userName,
                                style: GoogleFonts.inter(
                                  color: authorColor,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                                style: GoogleFonts.inter(
                                    color: Colors.white24, fontSize: 8.5),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            msg.text,
                            style: GoogleFonts.inter(
                              color: Colors.white70,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle:
                        GoogleFonts.inter(color: Colors.white24, fontSize: 11),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Colors.cyanAccent, width: 0.8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 11),
                  onSubmitted: (text) {
                    if (text.isNotEmpty) {
                      notifier.sendMessage(text);
                      _chatController.clear();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(LucideIcons.send, size: 16),
                color: Colors.cyanAccent,
                onPressed: () {
                  if (_chatController.text.isNotEmpty) {
                    notifier.sendMessage(_chatController.text);
                    _chatController.clear();
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return GlassContainer(
      blur: 20,
      opacity: 0.05,
      borderRadius: BorderRadius.zero,
      border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(LucideIcons.arrow_left, color: Colors.white70),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            const Icon(LucideIcons.users, size: 16, color: Colors.cyanAccent),
            const SizedBox(width: 8),
            Text(
              'Live Share',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
