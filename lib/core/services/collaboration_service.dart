import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:re_editor/re_editor.dart';

// Vibrant user colors for Live Share cursor overlays
final List<Color> _userColors = [
  Colors.blueAccent,
  Colors.greenAccent,
  Colors.purpleAccent,
  Colors.orangeAccent,
  Colors.pinkAccent,
  Colors.tealAccent,
  Colors.amberAccent,
  Colors.redAccent,
];

class CollaborationUser {
  final String id;
  final String name;
  final Color color;
  final String? activeFile; // relative path
  final int cursorLine;
  final int cursorCol;
  final int selectionStartLine;
  final int selectionStartCol;
  final int selectionEndLine;
  final int selectionEndCol;

  CollaborationUser({
    required this.id,
    required this.name,
    required this.color,
    this.activeFile,
    this.cursorLine = 0,
    this.cursorCol = 0,
    this.selectionStartLine = -1,
    this.selectionStartCol = -1,
    this.selectionEndLine = -1,
    this.selectionEndCol = -1,
  });

  CollaborationUser copyWith({
    String? name,
    Color? color,
    String? activeFile,
    int? cursorLine,
    int? cursorCol,
    int? selectionStartLine,
    int? selectionStartCol,
    int? selectionEndLine,
    int? selectionEndCol,
  }) {
    return CollaborationUser(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      activeFile: activeFile ?? this.activeFile,
      cursorLine: cursorLine ?? this.cursorLine,
      cursorCol: cursorCol ?? this.cursorCol,
      selectionStartLine: selectionStartLine ?? this.selectionStartLine,
      selectionStartCol: selectionStartCol ?? this.selectionStartCol,
      selectionEndLine: selectionEndLine ?? this.selectionEndLine,
      selectionEndCol: selectionEndCol ?? this.selectionEndCol,
    );
  }
}

class CollabChatMessage {
  final String senderId;
  final String senderName;
  final Color senderColor;
  final String text;
  final DateTime timestamp;

  CollabChatMessage({
    required this.senderId,
    required this.senderName,
    required this.senderColor,
    required this.text,
    required this.timestamp,
  });
}

class CollaborationRepaintNotifier extends ChangeNotifier {
  void triggerRepaint() {
    notifyListeners();
  }
}

class CollaborationState {
  final bool isHosting;
  final bool isConnected;
  final String? hostAddress;
  final String localUserName;
  final Color localUserColor;
  final String? myId;
  final Map<String, CollaborationUser> users;
  final List<CollabChatMessage> chatMessages;
  final List<String> localIps;

  CollaborationState({
    this.isHosting = false,
    this.isConnected = false,
    this.hostAddress,
    required this.localUserName,
    required this.localUserColor,
    this.myId,
    this.users = const {},
    this.chatMessages = const [],
    this.localIps = const [],
  });

  CollaborationState copyWith({
    bool? isHosting,
    bool? isConnected,
    String? hostAddress,
    String? localUserName,
    Color? localUserColor,
    String? myId,
    Map<String, CollaborationUser>? users,
    List<CollabChatMessage>? chatMessages,
    List<String>? localIps,
  }) {
    return CollaborationState(
      isHosting: isHosting ?? this.isHosting,
      isConnected: isConnected ?? this.isConnected,
      hostAddress: hostAddress ?? this.hostAddress,
      localUserName: localUserName ?? this.localUserName,
      localUserColor: localUserColor ?? this.localUserColor,
      myId: myId ?? this.myId,
      users: users ?? this.users,
      chatMessages: chatMessages ?? this.chatMessages,
      localIps: localIps ?? this.localIps,
    );
  }
}

final collaborationProvider = StateNotifierProvider<CollaborationService, CollaborationState>((ref) {
  return CollaborationService(ref);
});

class CollaborationService extends StateNotifier<CollaborationState> {
  final Ref ref;
  final DiffMatchPatch _dmp = DiffMatchPatch();
  final Uuid _uuid = const Uuid();

  HttpServer? _server;
  final Map<String, WebSocket> _clientSockets = {}; // Host mode: clientId -> socket
  WebSocket? _socketToHost; // Client mode

  // Cursor and layout notification triggers
  final CollaborationRepaintNotifier cursorRepaintNotifier = CollaborationRepaintNotifier();

  // Internal flags to bypass local listener logic
  bool _isApplyingRemoteChange = false;
  bool get isApplyingRemoteChange => _isApplyingRemoteChange;

  // Cache to track previously synchronized files
  final Map<String, String> _lastSyncedText = {};

  CollaborationService(this.ref)
      : super(CollaborationState(
          localUserName: 'Developer',
          localUserColor: _userColors[0],
        )) {
    _loadPreferences();
    _fetchLocalIps();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('collab_username');
      final colorHex = prefs.getString('collab_usercolor');
      
      String name = savedName ?? 'Dev_${Random().nextInt(900) + 100}';
      Color color = _userColors[Random().nextInt(_userColors.length)];
      
      if (colorHex != null) {
        try {
          color = Color(int.parse(colorHex));
        } catch (_) {}
      }

      state = state.copyWith(
        localUserName: name,
        localUserColor: color,
      );
    } catch (e) {
      debugPrint('Error loading preferences: $e');
    }
  }

  Future<void> setLocalName(String name) async {
    if (name.trim().isEmpty) return;
    state = state.copyWith(localUserName: name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('collab_username', name);

    // Broadcast user settings update
    _sendBroadcast({
      'type': 'user_update',
      'userId': state.myId ?? 'host',
      'name': name,
      'color': state.localUserColor.value.toString(),
    });
  }

  Future<void> setLocalColor(Color color) async {
    state = state.copyWith(localUserColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('collab_usercolor', color.value.toString());

    // Broadcast user settings update
    _sendBroadcast({
      'type': 'user_update',
      'userId': state.myId ?? 'host',
      'name': state.localUserName,
      'color': color.value.toString(),
    });
  }

  Future<void> _fetchLocalIps() async {
    List<String> ips = [];
    try {
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            ips.add(addr.address);
          }
        }
      }
    } catch (e) {
      debugPrint('Error listing network interfaces: $e');
    }
    state = state.copyWith(localIps: ips);
  }

  // --- Hosting Mode ---

  Future<void> startHosting({int port = 9090}) async {
    await stopAll();
    _fetchLocalIps();
    
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      state = state.copyWith(
        isHosting: true,
        isConnected: true,
        myId: 'host',
        hostAddress: 'ws://127.0.0.1:$port',
      );

      _server!.listen((HttpRequest request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then((socket) {
            _handleHostIncomingClient(socket);
          });
        }
      });
      
      _addSystemChat('Сессия создана на порту $port.');
    } catch (e) {
      debugPrint('Error starting HTTP server: $e');
      _addSystemChat('Ошибка при создании сессии: $e');
      await stopAll();
    }
  }

  void _handleHostIncomingClient(WebSocket socket) {
    final clientId = _uuid.v4();
    _clientSockets[clientId] = socket;

    socket.listen(
      (data) {
        try {
          final message = jsonDecode(data as String) as Map<String, dynamic>;
          _processMessageAsHost(clientId, message);
        } catch (e) {
          debugPrint('Host failed parsing client message: $e');
        }
      },
      onDone: () => _handleHostClientDisconnect(clientId),
      onError: (e) => _handleHostClientDisconnect(clientId),
    );
  }

  void _handleHostClientDisconnect(String clientId) {
    final user = state.users[clientId];
    _clientSockets.remove(clientId);
    
    final updatedUsers = Map<String, CollaborationUser>.from(state.users);
    updatedUsers.remove(clientId);
    state = state.copyWith(users: updatedUsers);
    
    if (user != null) {
      _addSystemChat('Пользователь ${user.name} отключился.');
      _sendBroadcast({
        'type': 'user_left',
        'userId': clientId,
      });
    }
    
    cursorRepaintNotifier.triggerRepaint();
  }

  // --- Client Mode ---

  Future<void> joinSession(String address) async {
    await stopAll();
    
    // Address cleanup
    String wsUrl = address.trim();
    if (!wsUrl.startsWith('ws://') && !wsUrl.startsWith('wss://')) {
      wsUrl = 'ws://$wsUrl';
    }
    if (!wsUrl.contains(':')) {
      wsUrl = '$wsUrl:9090';
    }

    try {
      _socketToHost = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 8));
      state = state.copyWith(
        isHosting: false,
        isConnected: true,
        hostAddress: wsUrl,
      );

      _socketToHost!.listen(
        (data) {
          try {
            final message = jsonDecode(data as String) as Map<String, dynamic>;
            _processMessageAsClient(message);
          } catch (e) {
            debugPrint('Client failed parsing host message: $e');
          }
        },
        onDone: () => _handleClientDisconnected(),
        onError: (e) => _handleClientDisconnected(),
      );

      // Send initial handshake
      _socketToHost!.add(jsonEncode({
        'type': 'join',
        'name': state.localUserName,
        'color': state.localUserColor.value.toString(),
      }));

    } catch (e) {
      debugPrint('Error joining session: $e');
      _addSystemChat('Ошибка при подключении к $wsUrl: $e');
      await stopAll();
    }
  }

  void _handleClientDisconnected() {
    _addSystemChat('Подключение к сессии потеряно.');
    stopAll();
  }

  // --- Tear Down ---

  Future<void> stopAll() async {
    _server?.close(force: true);
    _server = null;

    for (final socket in _clientSockets.values) {
      socket.close();
    }
    _clientSockets.clear();

    _socketToHost?.close();
    _socketToHost = null;

    _lastSyncedText.clear();

    state = CollaborationState(
      isHosting: false,
      isConnected: false,
      localUserName: state.localUserName,
      localUserColor: state.localUserColor,
      localIps: state.localIps,
      users: {},
      chatMessages: [],
    );

    cursorRepaintNotifier.triggerRepaint();
  }

  // --- Core Sync Logic ---

  void initializeFileSync(String absolutePath, String content) {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;
    final relativePath = p.relative(absolutePath, from: workspacePath);

    _lastSyncedText[relativePath] = content;

    // In client mode, request initial sync content from host if we just opened it
    if (state.isConnected && !state.isHosting) {
      _socketToHost?.add(jsonEncode({
        'type': 'request_file_sync',
        'filePath': relativePath,
      }));
    }
  }

  void handleLocalChange(String absolutePath, String currentText) {
    if (!state.isConnected) return;
    if (_isApplyingRemoteChange) return;

    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;
    final relativePath = p.relative(absolutePath, from: workspacePath);

    final lastText = _lastSyncedText[relativePath] ?? '';
    if (lastText == currentText) return;

    final patches = _dmp.patch(lastText, currentText);
    final patchText = patchToText(patches);

    _lastSyncedText[relativePath] = currentText;

    _sendBroadcast({
      'type': 'edit',
      'userId': state.myId ?? 'host',
      'filePath': relativePath,
      'patch': patchText,
    });
  }

  void handleLocalCursorMove(
    String absolutePath,
    int cursorLine,
    int cursorCol,
    int selStartLine,
    int selStartCol,
    int selEndLine,
    int selEndCol,
  ) {
    if (!state.isConnected) return;

    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;
    final relativePath = p.relative(absolutePath, from: workspacePath);

    _sendBroadcast({
      'type': 'cursor',
      'userId': state.myId ?? 'host',
      'filePath': relativePath,
      'cursorLine': cursorLine,
      'cursorCol': cursorCol,
      'selectionStartLine': selStartLine,
      'selectionStartCol': selStartCol,
      'selectionEndLine': selEndLine,
      'selectionEndCol': selEndCol,
    });
  }

  void sendChatMessage(String text) {
    if (text.trim().isEmpty) return;
    
    final payload = {
      'type': 'chat',
      'userId': state.myId ?? 'host',
      'senderName': state.localUserName,
      'senderColor': state.localUserColor.value.toString(),
      'text': text,
    };

    _sendBroadcast(payload);

    // Append to local chat
    final newMsg = CollabChatMessage(
      senderId: state.myId ?? 'host',
      senderName: state.localUserName,
      senderColor: state.localUserColor,
      text: text,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(chatMessages: [...state.chatMessages, newMsg]);
  }

  // --- Network Routing ---

  void _sendBroadcast(Map<String, dynamic> payload) {
    final encoded = jsonEncode(payload);
    if (state.isHosting) {
      for (final clientSocket in _clientSockets.values) {
        clientSocket.add(encoded);
      }
    } else {
      _socketToHost?.add(encoded);
    }
  }

  void _processMessageAsHost(String clientId, Map<String, dynamic> msg) {
    final type = msg['type'] as String;

    switch (type) {
      case 'join':
        final name = msg['name'] as String;
        final colorVal = int.tryParse(msg['color'] as String? ?? '') ?? Colors.cyanAccent.value;
        
        final newUser = CollaborationUser(
          id: clientId,
          name: name,
          color: Color(colorVal),
        );

        final updatedUsers = Map<String, CollaborationUser>.from(state.users);
        updatedUsers[clientId] = newUser;
        state = state.copyWith(users: updatedUsers);

        // 1. Welcome client with their ID, current clients list, and sync text cache
        final currentUsersJson = state.users.values
            .map((u) => {
                  'id': u.id,
                  'name': u.name,
                  'color': u.color.value.toString(),
                  'activeFile': u.activeFile,
                  'cursorLine': u.cursorLine,
                  'cursorCol': u.cursorCol,
                  'selectionStartLine': u.selectionStartLine,
                  'selectionStartCol': u.selectionStartCol,
                  'selectionEndLine': u.selectionEndLine,
                  'selectionEndCol': u.selectionEndCol,
                })
            .toList();

        // Also add host to the list sent to the client
        currentUsersJson.add({
          'id': 'host',
          'name': state.localUserName,
          'color': state.localUserColor.value.toString(),
          'activeFile': ref.read(editorProvider).activeFilePath != null
              ? p.relative(ref.read(editorProvider).activeFilePath!, from: ref.read(workspaceProvider).currentPath!)
              : null,
          'cursorLine': 0,
          'cursorCol': 0,
          'selectionStartLine': -1,
          'selectionStartCol': -1,
          'selectionEndLine': -1,
          'selectionEndCol': -1,
        });

        _clientSockets[clientId]?.add(jsonEncode({
          'type': 'welcome',
          'assignedId': clientId,
          'users': currentUsersJson,
        }));

        // 2. Broadcast user_joined to other clients
        _sendBroadcast({
          'type': 'user_joined',
          'user': {
            'id': clientId,
            'name': name,
            'color': colorVal.toString(),
          }
        });

        _addSystemChat('Пользователь $name присоединился.');
        break;

      case 'request_file_sync':
        final filePath = msg['filePath'] as String;
        _sendHostFileSync(clientId, filePath);
        break;

      case 'edit':
        final filePath = msg['filePath'] as String;
        final patchText = msg['patch'] as String;

        _applyTextPatch(filePath, patchText);

        // Forward to all clients except sender
        _forwardBroadcastExcept(clientId, msg);
        break;

      case 'cursor':
        final filePath = msg['filePath'] as String?;
        final line = msg['cursorLine'] as int;
        final col = msg['cursorCol'] as int;
        final selStartL = msg['selectionStartLine'] as int;
        final selStartC = msg['selectionStartCol'] as int;
        final selEndL = msg['selectionEndLine'] as int;
        final selEndC = msg['selectionEndCol'] as int;

        final user = state.users[clientId];
        if (user != null) {
          final updated = user.copyWith(
            activeFile: filePath,
            cursorLine: line,
            cursorCol: col,
            selectionStartLine: selStartL,
            selectionStartCol: selStartC,
            selectionEndLine: selEndL,
            selectionEndCol: selEndC,
          );
          final updatedUsers = Map<String, CollaborationUser>.from(state.users);
          updatedUsers[clientId] = updated;
          state = state.copyWith(users: updatedUsers);
          cursorRepaintNotifier.triggerRepaint();
        }

        // Forward cursor update
        _forwardBroadcastExcept(clientId, msg);
        break;

      case 'chat':
        final text = msg['text'] as String;
        final senderName = msg['senderName'] as String;
        final colorVal = int.tryParse(msg['senderColor'] as String? ?? '') ?? Colors.cyanAccent.value;

        // Append locally
        final newMsg = CollabChatMessage(
          senderId: clientId,
          senderName: senderName,
          senderColor: Color(colorVal),
          text: text,
          timestamp: DateTime.now(),
        );
        state = state.copyWith(chatMessages: [...state.chatMessages, newMsg]);

        // Forward chat
        _forwardBroadcastExcept(clientId, msg);
        break;

      case 'user_update':
        final name = msg['name'] as String;
        final colorVal = int.tryParse(msg['color'] as String? ?? '') ?? Colors.cyanAccent.value;
        
        final user = state.users[clientId];
        if (user != null) {
          final updated = user.copyWith(name: name, color: Color(colorVal));
          final updatedUsers = Map<String, CollaborationUser>.from(state.users);
          updatedUsers[clientId] = updated;
          state = state.copyWith(users: updatedUsers);
          cursorRepaintNotifier.triggerRepaint();
        }
        
        _forwardBroadcastExcept(clientId, msg);
        break;
    }
  }

  void _processMessageAsClient(Map<String, dynamic> msg) {
    final type = msg['type'] as String;

    switch (type) {
      case 'welcome':
        final assignedId = msg['assignedId'] as String;
        final usersList = msg['users'] as List;

        final Map<String, CollaborationUser> joinedUsers = {};
        for (final item in usersList) {
          final uMap = item as Map<String, dynamic>;
          final id = uMap['id'] as String;
          if (id == assignedId) continue; // skip myself

          final name = uMap['name'] as String;
          final colorVal = int.tryParse(uMap['color'] as String? ?? '') ?? Colors.cyanAccent.value;
          final activeFile = uMap['activeFile'] as String?;
          final line = uMap['cursorLine'] as int? ?? 0;
          final col = uMap['cursorCol'] as int? ?? 0;

          joinedUsers[id] = CollaborationUser(
            id: id,
            name: name,
            color: Color(colorVal),
            activeFile: activeFile,
            cursorLine: line,
            cursorCol: col,
            selectionStartLine: uMap['selectionStartLine'] as int? ?? -1,
            selectionStartCol: uMap['selectionStartCol'] as int? ?? -1,
            selectionEndLine: uMap['selectionEndLine'] as int? ?? -1,
            selectionEndCol: uMap['selectionEndCol'] as int? ?? -1,
          );
        }

        state = state.copyWith(
          myId: assignedId,
          users: joinedUsers,
        );
        _addSystemChat('Вы подключились к сессии в качестве гостя.');
        cursorRepaintNotifier.triggerRepaint();
        break;

      case 'user_joined':
        final uData = msg['user'] as Map<String, dynamic>;
        final id = uData['id'] as String;
        final name = uData['name'] as String;
        final colorVal = int.tryParse(uData['color'] as String? ?? '') ?? Colors.cyanAccent.value;

        if (id == state.myId) return;

        final newUser = CollaborationUser(
          id: id,
          name: name,
          color: Color(colorVal),
        );

        final updatedUsers = Map<String, CollaborationUser>.from(state.users);
        updatedUsers[id] = newUser;
        state = state.copyWith(users: updatedUsers);
        
        _addSystemChat('Пользователь $name присоединился.');
        cursorRepaintNotifier.triggerRepaint();
        break;

      case 'user_left':
        final userId = msg['userId'] as String;
        final user = state.users[userId];
        
        final updatedUsers = Map<String, CollaborationUser>.from(state.users);
        updatedUsers.remove(userId);
        state = state.copyWith(users: updatedUsers);
        
        if (user != null) {
          _addSystemChat('Пользователь ${user.name} покинул сессию.');
        }
        cursorRepaintNotifier.triggerRepaint();
        break;

      case 'file_sync':
        final filePath = msg['filePath'] as String;
        final content = msg['content'] as String;
        _applyFullFileSync(filePath, content);
        break;

      case 'edit':
        final filePath = msg['filePath'] as String;
        final patchText = msg['patch'] as String;
        _applyTextPatch(filePath, patchText);
        break;

      case 'cursor':
        final userId = msg['userId'] as String;
        final filePath = msg['filePath'] as String?;
        final line = msg['cursorLine'] as int;
        final col = msg['cursorCol'] as int;
        final selStartL = msg['selectionStartLine'] as int;
        final selStartC = msg['selectionStartCol'] as int;
        final selEndL = msg['selectionEndLine'] as int;
        final selEndC = msg['selectionEndCol'] as int;

        final user = state.users[userId];
        if (user != null) {
          final updated = user.copyWith(
            activeFile: filePath,
            cursorLine: line,
            cursorCol: col,
            selectionStartLine: selStartL,
            selectionStartCol: selStartC,
            selectionEndLine: selEndL,
            selectionEndCol: selEndC,
          );
          final updatedUsers = Map<String, CollaborationUser>.from(state.users);
          updatedUsers[userId] = updated;
          state = state.copyWith(users: updatedUsers);
          cursorRepaintNotifier.triggerRepaint();
        }
        break;

      case 'chat':
        final text = msg['text'] as String;
        final senderId = msg['userId'] as String;
        final senderName = msg['senderName'] as String;
        final colorVal = int.tryParse(msg['senderColor'] as String? ?? '') ?? Colors.cyanAccent.value;

        final newMsg = CollabChatMessage(
          senderId: senderId,
          senderName: senderName,
          senderColor: Color(colorVal),
          text: text,
          timestamp: DateTime.now(),
        );
        state = state.copyWith(chatMessages: [...state.chatMessages, newMsg]);
        break;

      case 'user_update':
        final userId = msg['userId'] as String;
        final name = msg['name'] as String;
        final colorVal = int.tryParse(msg['color'] as String? ?? '') ?? Colors.cyanAccent.value;
        
        final user = state.users[userId];
        if (user != null) {
          final updated = user.copyWith(name: name, color: Color(colorVal));
          final updatedUsers = Map<String, CollaborationUser>.from(state.users);
          updatedUsers[userId] = updated;
          state = state.copyWith(users: updatedUsers);
          cursorRepaintNotifier.triggerRepaint();
        }
        break;
    }
  }

  void _forwardBroadcastExcept(String senderClientId, Map<String, dynamic> msg) {
    final encoded = jsonEncode(msg);
    _clientSockets.forEach((clientId, socket) {
      if (clientId != senderClientId) {
        socket.add(encoded);
      }
    });
  }

  // --- Document Application & Sync Actions ---

  Future<void> _sendHostFileSync(String clientId, String relativePath) async {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;
    final absolutePath = p.join(workspacePath, relativePath);

    String content = '';
    // Check if open in host editor
    final editorState = ref.read(editorProvider);
    final idx = editorState.openFiles.indexWhere((f) => f.path == absolutePath);
    if (idx != -1) {
      content = editorState.openFiles[idx].controller.text;
    } else {
      final file = File(absolutePath);
      if (await file.exists()) {
        content = await file.readAsString();
      }
    }

    _clientSockets[clientId]?.add(jsonEncode({
      'type': 'file_sync',
      'filePath': relativePath,
      'content': content,
    }));
  }

  void _applyFullFileSync(String relativePath, String content) {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;
    final absolutePath = p.join(workspacePath, relativePath);

    _isApplyingRemoteChange = true;
    _lastSyncedText[relativePath] = content;

    try {
      final editorState = ref.read(editorProvider);
      final idx = editorState.openFiles.indexWhere((f) => f.path == absolutePath);

      if (idx != -1) {
        final controller = editorState.openFiles[idx].controller;
        if (controller.text != content) {
          controller.text = content;
        }
      } else {
        final file = File(absolutePath);
        if (file.existsSync()) {
          final localContent = file.readAsStringSync();
          if (localContent != content) {
            file.writeAsStringSync(content);
            ref.read(projectServiceProvider.notifier).mirrorEntity(absolutePath);
          }
        }
      }
    } catch (e) {
      debugPrint('Error applying file sync for $relativePath: $e');
    } finally {
      _isApplyingRemoteChange = false;
    }
  }

  void _applyTextPatch(String relativePath, String patchText) {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;
    final absolutePath = p.join(workspacePath, relativePath);

    _isApplyingRemoteChange = true;
    
    try {
      final lastText = _lastSyncedText[relativePath] ?? '';
      final patches = patchFromText(patchText);
      final result = patchApply(patches, lastText);
      final newText = result[0] as String;
      
      _lastSyncedText[relativePath] = newText;

      final editorState = ref.read(editorProvider);
      final idx = editorState.openFiles.indexWhere((f) => f.path == absolutePath);

      if (idx != -1) {
        final controller = editorState.openFiles[idx].controller;
        final selection = controller.selection;

        if (controller.text != newText) {
          controller.text = newText;
          // Restore and clamp selection
          try {
            controller.selection = CodeLineSelection(
              baseIndex: selection.baseIndex.clamp(0, controller.codeLines.length - 1),
              baseOffset: selection.baseOffset,
              extentIndex: selection.extentIndex.clamp(0, controller.codeLines.length - 1),
              extentOffset: selection.extentOffset,
            );
          } catch (_) {}
        }
      } else {
        final file = File(absolutePath);
        if (file.existsSync()) {
          file.writeAsStringSync(newText);
          ref.read(projectServiceProvider.notifier).mirrorEntity(absolutePath);
        }
      }
    } catch (e) {
      debugPrint('Error applying patch for $relativePath: $e');
    } finally {
      _isApplyingRemoteChange = false;
    }
  }

  // Helper system chat logger
  void _addSystemChat(String text) {
    final systemMsg = CollabChatMessage(
      senderId: 'system',
      senderName: 'System',
      senderColor: Colors.grey,
      text: text,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(chatMessages: [...state.chatMessages, systemMsg]);
  }
}
