import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/models/chat_session.dart';

class JsonChatService {
  static const _fileName = 'chat_history.json';

  String _getFilePath(String workspacePath) {
    return p.join(workspacePath, '.quantum', _fileName);
  }

  Future<void> _ensureDir(String workspacePath) async {
    final dir = Directory(p.join(workspacePath, '.quantum'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  // ─── Load ────────────────────────────────────────

  Future<List<ChatSession>> loadSessions(String workspacePath) async {
    try {
      final file = File(_getFilePath(workspacePath));
      if (!await file.exists()) return [];

      final jsonStr = await file.readAsString();
      if (jsonStr.trim().isEmpty) return [];

      final List<dynamic> jsonList = jsonDecode(jsonStr);
      final sessions = jsonList
          .map((j) => ChatSession.fromJson(Map<String, dynamic>.from(j)))
          .toList();

      // Tag all sessions with workspacePath
      return sessions.map((s) => s.copyWith(workspacePath: workspacePath)).toList();
    } catch (e) {
      debugPrint('[JsonChat] Error loading sessions: $e');
      return [];
    }
  }

  // ─── Save ────────────────────────────────────────

  Future<void> saveSessions(String workspacePath, List<ChatSession> sessions) async {
    try {
      await _ensureDir(workspacePath);

      // Trim heavy fields before saving
      final trimmed = sessions.map((s) {
        final trimmedMessages = s.messages.map((m) {
          final json = m.toJson();
          json.remove('imageBase64');
          json.remove('fileBackups');
          if (json['executedActions'] != null) {
            final actions = (json['executedActions'] as List).map((a) {
              final action = Map<String, dynamic>.from(a);
              if (action['content'] != null && (action['content'] as String).length > 500) {
                action['content'] = '(truncated)';
              }
              return action;
            }).toList();
            json['executedActions'] = actions;
          }
          if (json['actionResults'] != null) {
            final results = Map<String, String>.from(json['actionResults']);
            final trimmedResults = <String, String>{};
            for (final entry in results.entries) {
              trimmedResults[entry.key] = entry.value.length > 500
                  ? '${entry.value.substring(0, 500)}...'
                  : entry.value;
            }
            json['actionResults'] = trimmedResults;
          }
          return json;
        }).toList();

        return {
          'id': s.id,
          'title': s.title,
          'messages': trimmedMessages,
          'createdAt': s.createdAt.toIso8601String(),
          if (s.workspacePath != null) 'workspacePath': s.workspacePath,
        };
      }).toList();

      final file = File(_getFilePath(workspacePath));
      await file.writeAsString(jsonEncode(trimmed));
      debugPrint('[JsonChat] Saved ${sessions.length} session(s) to ${file.path}');
    } catch (e) {
      debugPrint('[JsonChat] Error saving sessions: $e');
    }
  }

  // ─── Delete ──────────────────────────────────────

  Future<void> deleteSession(String workspacePath, String sessionId) async {
    final sessions = await loadSessions(workspacePath);
    sessions.removeWhere((s) => s.id == sessionId);
    await saveSessions(workspacePath, sessions);
  }
}

final jsonChatServiceProvider = Provider<JsonChatService>((ref) {
  return JsonChatService();
});
