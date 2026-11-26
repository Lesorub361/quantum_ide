import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/models/ai_agent_models.dart';

/// File-backed persistence for [ChatSession] history under
/// `<workspace>/.quantum/chat_sessions` (or `$HOME/.quantum/chat_sessions`).
class ChatSessionStore {
  final void Function(String message)? onWarning;

  const ChatSessionStore({this.onWarning});

  /// Resolves and ensures the directory where session JSON files are stored.
  Directory getSessionsDirectory(String? workspacePath) {
    final String baseDir;
    if (workspacePath != null && workspacePath.isNotEmpty) {
      baseDir = p.join(workspacePath, '.quantum', 'chat_sessions');
    } else {
      baseDir = p.join(
        Platform.environment['HOME'] ?? '/root',
        '.quantum',
        'chat_sessions',
      );
    }
    final dir = Directory(baseDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Loads all saved sessions sorted by `updatedAt` descending, migrating
  /// legacy `.quantum/chat_history.json` entries if present.
  Future<List<ChatSession>> loadAll(String? workspacePath) async {
    final dir = getSessionsDirectory(workspacePath);
    final loaded = <ChatSession>[];

    if (await dir.exists()) {
      for (final entity in dir.listSync()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            if (content.trim().isNotEmpty) {
              final json = jsonDecode(content);
              if (json is Map<String, dynamic>) {
                loaded.add(ChatSession.fromJson(json));
              }
            }
          } catch (e) {
            onWarning?.call('Failed to load chat session ${entity.path}: $e');
          }
        }
      }
    }

    if (workspacePath != null && workspacePath.isNotEmpty) {
      final legacyFile =
          File(p.join(workspacePath, '.quantum', 'chat_history.json'));
      if (await legacyFile.exists()) {
        try {
          final content = await legacyFile.readAsString();
          final legacyList = jsonDecode(content);
          if (legacyList is List) {
            for (final item in legacyList) {
              if (item is Map<String, dynamic> && item['id'] != null) {
                final id = item['id'].toString();
                if (!loaded.any((s) => s.id == id)) {
                  final legacySession = ChatSession.fromJson(item);
                  if (legacySession.messages.isNotEmpty) {
                    loaded.add(legacySession);
                    final target = File(p.join(dir.path, '$id.json'));
                    await target
                        .writeAsString(jsonEncode(legacySession.toJson()));
                  }
                }
              }
            }
          }
        } catch (_) {}
      }
    }

    loaded.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return loaded;
  }

  /// Persists [session] to `<sessionsDir>/<session.id>.json`.
  Future<void> save(String? workspacePath, ChatSession session) async {
    final dir = getSessionsDirectory(workspacePath);
    final file = File(p.join(dir.path, '${session.id}.json'));
    await file.writeAsString(jsonEncode(session.toJson()));
  }

  /// Loads a single session by [sessionId], or returns `null` if missing/invalid.
  Future<ChatSession?> loadById(String? workspacePath, String sessionId) async {
    final dir = getSessionsDirectory(workspacePath);
    final file = File(p.join(dir.path, '$sessionId.json'));
    if (!await file.exists()) return null;
    final json =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return ChatSession.fromJson(json);
  }

  /// Deletes the persisted file for [sessionId] if it exists.
  Future<void> deleteById(String? workspacePath, String sessionId) async {
    final dir = getSessionsDirectory(workspacePath);
    final file = File(p.join(dir.path, '$sessionId.json'));
    if (await file.exists()) {
      await file.delete();
    }
  }
}
