import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class RemoteCursor {
  final String userId;
  final String userName;
  final int lineNumber;
  final int column;
  final String colorHex;

  RemoteCursor({
    required this.userId,
    required this.userName,
    required this.lineNumber,
    required this.column,
    required this.colorHex,
  });
}

class ChatMessage {
  final String id;
  final String userId;
  final String userName;
  final String text;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.userId,
    required this.userName,
    required this.text,
    required this.timestamp,
  });
}

class Collaborator {
  final String userId;
  final String userName;
  final String colorHex;
  final DateTime joinedAt;

  Collaborator({
    required this.userId,
    required this.userName,
    required this.colorHex,
    required this.joinedAt,
  });
}

class CollaborationState {
  final bool isInSession;
  final String? sessionId;
  final String? sessionCode;
  final String? userId;
  final String? userName;
  final List<Collaborator> collaborators;
  final List<RemoteCursor> remoteCursors;
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;

  CollaborationState({
    this.isInSession = false,
    this.sessionId,
    this.sessionCode,
    this.userId,
    this.userName,
    this.collaborators = const [],
    this.remoteCursors = const [],
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  CollaborationState copyWith({
    bool? isInSession,
    String? sessionId,
    String? sessionCode,
    String? userId,
    String? userName,
    List<Collaborator>? collaborators,
    List<RemoteCursor>? remoteCursors,
    List<ChatMessage>? messages,
    bool? isLoading,
    String? error,
  }) {
    return CollaborationState(
      isInSession: isInSession ?? this.isInSession,
      sessionId: sessionId ?? this.sessionId,
      sessionCode: sessionCode ?? this.sessionCode,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      collaborators: collaborators ?? this.collaborators,
      remoteCursors: remoteCursors ?? this.remoteCursors,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

const _colorPalette = [
  '#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4',
  '#FFEAA7', '#DDA0DD', '#98D8C8', '#F7DC6F',
];

class CollaborationNotifier extends StateNotifier<CollaborationState> {
  final _uuid = const Uuid();

  CollaborationNotifier() : super(CollaborationState());

  Future<void> createSession(String userName) async {
    state = state.copyWith(isLoading: true);
    try {
      final sessionId = _uuid.v4();
      final sessionCode = _uuid.v4().substring(0, 8).toUpperCase();
      final userId = _uuid.v4();
      const colorIndex = 0;

      state = state.copyWith(
        isLoading: false,
        isInSession: true,
        sessionId: sessionId,
        sessionCode: sessionCode,
        userId: userId,
        userName: userName,
        collaborators: [
          Collaborator(
            userId: userId,
            userName: userName,
            colorHex: _colorPalette[colorIndex],
            joinedAt: DateTime.now(),
          ),
        ],
        messages: [
          ChatMessage(
            id: _uuid.v4(),
            userId: userId,
            userName: userName,
            text: 'Session created',
            timestamp: DateTime.now(),
          ),
        ],
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> joinSession(String sessionCode, String userName) async {
    state = state.copyWith(isLoading: true);
    try {
      final userId = _uuid.v4();
      final colorIndex = (sessionCode.hashCode.abs()) % _colorPalette.length;

      final existingCollaborators = [
        Collaborator(
          userId: 'host',
          userName: 'Host',
          colorHex: _colorPalette[0],
          joinedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        Collaborator(
          userId: userId,
          userName: userName,
          colorHex: _colorPalette[colorIndex],
          joinedAt: DateTime.now(),
        ),
      ];

      state = state.copyWith(
        isLoading: false,
        isInSession: true,
        sessionId: sessionCode,
        sessionCode: sessionCode,
        userId: userId,
        userName: userName,
        collaborators: existingCollaborators,
        messages: [
          ChatMessage(
            id: _uuid.v4(),
            userId: userId,
            userName: userName,
            text: 'Joined session',
            timestamp: DateTime.now(),
          ),
        ],
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> leaveSession() async {
    state = CollaborationState();
  }

  void broadcastCursor(int lineNumber, int column) {
    if (!state.isInSession || state.userId == null) return;

    final cursor = RemoteCursor(
      userId: state.userId!,
      userName: state.userName ?? 'You',
      lineNumber: lineNumber,
      column: column,
      colorHex: state.collaborators
          .where((c) => c.userId == state.userId)
          .map((c) => c.colorHex)
          .firstOrNull ?? '#FFFFFF',
    );

    final updatedCursors = [
      ...state.remoteCursors.where((c) => c.userId != state.userId),
      cursor,
    ];

    state = state.copyWith(remoteCursors: updatedCursors);
  }

  void updateRemoteCursor(RemoteCursor cursor) {
    final updatedCursors = [
      ...state.remoteCursors.where((c) => c.userId != cursor.userId),
      cursor,
    ];
    state = state.copyWith(remoteCursors: updatedCursors);
  }

  void sendMessage(String text) {
    if (!state.isInSession || state.userId == null || text.isEmpty) return;

    final message = ChatMessage(
      id: _uuid.v4(),
      userId: state.userId!,
      userName: state.userName ?? 'You',
      text: text,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(messages: [...state.messages, message]);
  }

  void receiveMessage(ChatMessage message) {
    state = state.copyWith(messages: [...state.messages, message]);
  }
}

final collaborationProvider =
    StateNotifierProvider<CollaborationNotifier, CollaborationState>((ref) {
  return CollaborationNotifier();
});
