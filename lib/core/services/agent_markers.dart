import 'dart:convert';

class AgentMarkers {
  static const thinkStart = '[[QUANTUM_THINK_START]]';
  static const thinkEnd = '[[QUANTUM_THINK_END]]';
  static const statusPrefix = '[[QUANTUM_STATUS:';
  static const editPrefix = '[[QUANTUM_EDIT:';
  static const terminalPrefix = '[[QUANTUM_TERMINAL:';
  static const toolStatusPrefix = '[[QUANTUM_TOOL_STATUS:';
  static const suffix = ']]';

  static String thinkBlock(String text) => '$thinkStart\n$text\n$thinkEnd';
  static String statusMarker(String status) => '$statusPrefix$status$suffix\n';
  static String editMarker(String filePath, int added, int removed) {
    final encoded = base64Encode(utf8.encode(filePath));
    return '$editPrefix$encoded|$added|$removed$suffix\n';
  }
  static String terminalMarker(String command, {String stdout = '', String stderr = '', String? exitCode}) {
    final payload = jsonEncode({
      'command': command,
      'stdout': stdout,
      'stderr': stderr,
      'exitCode': exitCode,
    });
    final encoded = base64Encode(utf8.encode(payload));
    return '$terminalPrefix$encoded$suffix\n';
  }

  static String parseStatus(String text) {
    if (!text.startsWith(statusPrefix)) return '';
    return text.substring(statusPrefix.length, text.length - suffix.length);
  }

  static Map<String, dynamic>? parseEditMarker(String text) {
    if (!text.startsWith(editPrefix)) return null;
    final inner = text.substring(editPrefix.length, text.length - suffix.length);
    final parts = inner.split('|');
    if (parts.length < 3) return null;
    try {
      return {
        'filePath': utf8.decode(base64Decode(parts[0])),
        'added': int.parse(parts[1]),
        'removed': int.parse(parts[2]),
      };
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? parseTerminalMarker(String text) {
    if (!text.startsWith(terminalPrefix)) return null;
    final encoded = text.substring(terminalPrefix.length, text.length - suffix.length);
    try {
      return jsonDecode(utf8.decode(base64Decode(encoded))) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

String statusForFunction(String functionName) {
  const analyzingTools = {
    'read_file', 'read_files_batch', 'list_directory', 'glob_search',
    'search_code', 'grep_in_files', 'search_web', 'fetch_url',
    'git_status', 'git_diff', 'git_log',
    'active_editor_file', 'currently_selected_text',
    'get_file_info', 'get_pending_edits',
  };
  const writingTools = {
    'write_file', 'create_file', 'delete_file', 'edit_file',
    'insert_at_line', 'replace_all_in_file', 'apply_diff',
  };
  if (analyzingTools.contains(functionName)) return 'Analyzing';
  if (writingTools.contains(functionName)) return 'Generating patch';
  return 'Processing';
}

int lineCount(String? text) {
  if (text == null || text.isEmpty) return 0;
  return text.split('\n').length;
}
