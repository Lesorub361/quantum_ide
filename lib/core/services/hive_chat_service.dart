import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:quantum_ide/models/chat_session.dart';
import 'package:quantum_ide/models/chat_message.dart';

const String _boxSessions = 'quantum_chat_sessions';
const String _boxMessages = 'quantum_chat_messages';
const String _boxSettings = 'quantum_settings';

class HiveChatService {
  late Box _sessionsBox;
  late Box _messagesBox;
  late Box _settingsBox;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _sessionsBox = await Hive.openBox(_boxSessions);
    _messagesBox = await Hive.openBox(_boxMessages);
    _settingsBox = await Hive.openBox(_boxSettings);
    _initialized = true;
    debugPrint('[HiveChat] Initialized: ${_sessionsBox.length} sessions, ${_messagesBox.length} messages');
  }

  // ─── Sessions ────────────────────────────────────

  List<ChatSession> getAllSessions() {
    final sessions = <ChatSession>[];
    for (final key in _sessionsBox.keys) {
      try {
        final data = _sessionsBox.get(key);
        if (data is Map) {
          sessions.add(ChatSession.fromJson(Map<String, dynamic>.from(data)));
        }
      } catch (e) {
        debugPrint('[HiveChat] Error loading session $key: $e');
      }
    }
    sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sessions;
  }

  Future<void> saveSession(ChatSession session) async {
    await _sessionsBox.put(session.id, session.toJson());
  }

  Future<void> deleteSession(String id) async {
    await _sessionsBox.delete(id);
    // Delete all messages for this session
    final keysToDelete = <dynamic>[];
    for (final key in _messagesBox.keys) {
      final data = _messagesBox.get(key);
      if (data is Map && data['sessionId'] == id) {
        keysToDelete.add(key);
      }
    }
    await _messagesBox.deleteAll(keysToDelete);
  }

  // ─── Messages ────────────────────────────────────

  List<ChatMessage> getMessagesForSession(String sessionId) {
    final messages = <ChatMessage>[];
    for (final key in _messagesBox.keys) {
      try {
        final data = _messagesBox.get(key);
        if (data is Map && data['sessionId'] == sessionId) {
          messages.add(ChatMessage.fromJson(Map<String, dynamic>.from(data)));
        }
      } catch (e) {
        debugPrint('[HiveChat] Error loading message $key: $e');
      }
    }
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return messages;
  }

  Future<void> saveMessage(ChatMessage message) async {
    final json = message.toJson();
    json['sessionId'] = message.sessionId ?? '';
    // Remove heavy fields for storage
    json.remove('imageBase64');
    json.remove('fileBackups');
    await _messagesBox.put(message.timestamp.millisecondsSinceEpoch.toString(), json);
  }

  // ─── Settings ────────────────────────────────────

  T? getSetting<T>(String key, {T? defaultValue}) {
    return _settingsBox.get(key, defaultValue: defaultValue) as T?;
  }

  Future<void> setSetting(String key, dynamic value) async {
    await _settingsBox.put(key, value);
  }

  // ─── Migration from JSON ─────────────────────────

  Future<void> migrateFromJson(String workspacePath) async {
    try {
      final file = File(p.join(workspacePath, '.quantum', 'chat_history.json'));
      if (!await file.exists()) return;

      final jsonStr = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonStr);

      int sessionsImported = 0;
      int messagesImported = 0;

      for (final sessionJson in jsonList) {
        try {
          final session = ChatSession.fromJson(Map<String, dynamic>.from(sessionJson));
          if (!_sessionsBox.containsKey(session.id)) {
            await _sessionsBox.put(session.id, session.toJson());
            sessionsImported++;

            for (final msg in session.messages) {
              final msgJson = msg.toJson();
              msgJson['sessionId'] = session.id;
              msgJson.remove('imageBase64');
              msgJson.remove('fileBackups');
              await _messagesBox.put(
                '${session.id}_${msg.timestamp.millisecondsSinceEpoch}',
                msgJson,
              );
              messagesImported++;
            }
          }
        } catch (e) {
          debugPrint('[HiveChat] Error migrating session: $e');
        }
      }

      debugPrint('[HiveChat] Migrated $sessionsImported sessions, $messagesImported messages from JSON');

      // Rename old JSON file as backup
      final backupFile = File('${file.path}.backup');
      if (!await backupFile.exists()) {
        await file.rename(backupFile.path);
      }
    } catch (e) {
      debugPrint('[HiveChat] Migration error: $e');
    }
  }

  // ─── Fallback: load from JSON if Hive is empty ───

  Future<List<ChatSession>> loadFromJsonFallback(String workspacePath) async {
    try {
      final file = File(p.join(workspacePath, '.quantum', 'chat_history.json'));
      if (!await file.exists()) return [];

      final jsonStr = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList.map((j) => ChatSession.fromJson(Map<String, dynamic>.from(j))).toList();
    } catch (e) {
      debugPrint('[HiveChat] JSON fallback error: $e');
      return [];
    }
  }
}

final hiveChatServiceProvider = Provider<HiveChatService>((ref) {
  return HiveChatService();
});
