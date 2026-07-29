import 'package:quantum_ide/models/chat_message.dart';

/// Translates natural language responses from local models into actions.
/// Local models (LiteRT-LM / small GGUF) don't always output valid `<actions>` JSON,
/// so this service analyses their text and generates appropriate actions.
class LocalActionTranslator {
  /// Analyzes the model's response and extracts implicit actions.
  static List<AIAction> translateResponse(String response, String workspacePath) {
    final actions = <AIAction>[];
    final lower = response.toLowerCase();

    // ── File Creation intent ──────────────────────────────────────────────────
    if (_containsAny(lower, [
      'создам файл', 'создать файл', 'создаю файл', 'создаём файл',
      'новый файл', 'напишу файл', 'сохраню в файл', 'сохраню как',
      'create file', 'write file', 'new file', 'save as', 'saving to',
      'creating file', 'will create', 'let me create',
    ])) {
      final filename = _extractFilename(response);
      final content = _extractCodeBlock(response);
      if (filename != null && content != null && content.isNotEmpty) {
        actions.add(AIAction(
          type: 'create',
          path: _resolvePath(filename, workspacePath),
          content: content,
          description: 'Создание файла $filename',
        ));
        return actions;
      }
    }

    // ── File Edit intent ──────────────────────────────────────────────────────
    if (_containsAny(lower, [
      'отредактирую', 'изменю файл', 'обновлю файл', 'исправлю файл',
      'изменю код', 'обновлю код', 'добавлю в файл', 'редактирую',
      'edit file', 'modify file', 'update file', 'change file',
      'editing', 'modifying', 'updating', 'i will edit',
    ])) {
      final filename = _extractFilename(response);
      final content = _extractCodeBlock(response);
      if (filename != null && content != null && content.isNotEmpty) {
        actions.add(AIAction(
          type: 'edit',
          path: _resolvePath(filename, workspacePath),
          content: content,
          description: 'Редактирование файла $filename',
        ));
        return actions;
      }
    }

    // ── Command execution intent ──────────────────────────────────────────────
    if (_containsAny(lower, [
      'запущу', 'запускаю', 'выполню команду', 'выполняю', 'установлю',
      'устанавливаю', 'запустим', 'запустить', 'выполнить',
      'run command', 'execute', 'install', 'running', 'executing',
      'let me run', 'i will run', 'i\'ll run',
    ])) {
      final cmd = _extractCommand(response);
      if (cmd != null && cmd.isNotEmpty && cmd.length < 300) {
        actions.add(AIAction(
          type: 'command',
          path: '',
          content: cmd,
          description: 'Выполнение: $cmd',
        ));
        return actions;
      }
    }

    // ── File read intent ─────────────────────────────────────────────────────
    if (_containsAny(lower, [
      'прочитаю файл', 'посмотрю файл', 'открою файл', 'читаю файл',
      'посмотрю код', 'прочитаю код', 'проверю файл', 'загляну в файл',
      'read file', 'open file', 'look at file', 'check file',
      'let me read', 'reading', 'i\'ll read', 'viewing file',
    ])) {
      final filename = _extractFilename(response);
      if (filename != null) {
        actions.add(AIAction(
          type: 'read_file',
          path: _resolvePath(filename, workspacePath),
          content: '',
          description: 'Чтение файла $filename',
        ));
        return actions;
      }
    }

    // ── Directory listing intent ──────────────────────────────────────────────
    if (_containsAny(lower, [
      'покажи папку', 'покажи содержимое', 'список файлов', 'файлы проекта',
      'что в папке', 'смотрю папку', 'список папки',
      'list files', 'list directory', 'show files', 'ls ', 'dir ',
      'what files', 'project structure', 'project files',
    ])) {
      actions.add(AIAction(
        type: 'list_dir',
        path: workspacePath,
        content: '',
        description: 'Просмотр файлов проекта',
      ));
      return actions;
    }

    // ── Web search intent ─────────────────────────────────────────────────────
    if (_containsAny(lower, [
      'найди в интернете', 'поищи в интернете', 'погугли', 'поищу в сети',
      'ищу в интернете', 'найти в сети',
      'search web', 'google', 'search for', 'look up online',
    ])) {
      final query = _extractSearchQuery(response);
      if (query != null && query.isNotEmpty) {
        actions.add(AIAction(
          type: 'web_search',
          path: '',
          content: query,
          description: 'Поиск в интернете: $query',
        ));
        return actions;
      }
    }

    // ── Fallback: model wrote code without explicit intent keyword ────────────
    // If the model output a code block with a detectable filename, suggest creating it.
    final filename = _extractFilename(response);
    final content = _extractCodeBlock(response);
    if (filename != null && content != null && content.length > 20) {
      // Only auto-translate if message is short (model is trying to DO something, not explain)
      if (response.length < 1200) {
        actions.add(AIAction(
          type: 'create',
          path: _resolvePath(filename, workspacePath),
          content: content,
          description: 'Создание файла $filename (из кода модели)',
        ));
        return actions;
      }
    }

    return actions;
  }

  static bool _containsAny(String text, List<String> patterns) {
    for (final pattern in patterns) {
      if (text.contains(pattern)) return true;
    }
    return false;
  }

  static String? _extractFilename(String text) {
    // Look for common file extensions
    final extensions = [
      'dart', 'py', 'js', 'ts', 'tsx', 'jsx',
      'html', 'css', 'json', 'yaml', 'yml', 'md', 'txt',
      'xml', 'kt', 'java', 'cpp', 'c', 'h', 'sh', 'gradle',
    ];
    for (final ext in extensions) {
      // Find words ending with .ext — supports path separators
      final regex = RegExp('([\\w./_-]+\\.$ext)');
      final match = regex.firstMatch(text);
      if (match != null) {
        final candidate = match.group(1)!;
        // Skip very short matches that look like noise
        if (candidate.length >= 4) return candidate;
      }
    }
    return null;
  }

  static String? _extractCodeBlock(String text) {
    // Try fenced code block first (```lang ... ```)
    final fenced = RegExp(r'```(?:\w+)?\s*\n([\s\S]*?)```');
    final fencedMatch = fenced.firstMatch(text);
    if (fencedMatch != null) {
      return fencedMatch.group(1)?.trim();
    }
    // Try indented block (4 spaces)
    final lines = text.split('\n');
    final indented = lines.where((l) => l.startsWith('    ')).toList();
    if (indented.length >= 3) {
      return indented.map((l) => l.substring(4)).join('\n').trim();
    }
    return null;
  }

  static String? _extractCommand(String text) {
    // Look for shell-like patterns in backticks first
    final backtick = RegExp(r'`([^`\n]{3,150})`');
    final backtickMatch = backtick.firstMatch(text);
    if (backtickMatch != null) {
      final cmd = backtickMatch.group(1)?.trim() ?? '';
      // Validate it looks like a command (starts with a known tool)
      final cmdLower = cmd.toLowerCase();
      if (_looksLikeCommand(cmdLower)) return cmd;
    }

    final lower = text.toLowerCase();
    final keywords = [
      'запущу', 'запускаю', 'выполню', 'выполняю', 'установлю', 'устанавливаю',
      'run', 'execute', 'install', 'i\'ll run',
    ];
    for (final kw in keywords) {
      final idx = lower.indexOf(kw);
      if (idx >= 0) {
        final after = text.substring(idx + kw.length).trim();
        // Remove leading punctuation/quotes
        String cmd = after;
        while (cmd.isNotEmpty && (cmd.startsWith(',') || cmd.startsWith('.') ||
               cmd.startsWith(':') || cmd.startsWith('"') || cmd.startsWith("'"))) {
          cmd = cmd.substring(1).trim();
        }
        // Take until end of line or next sentence
        final endIdx = cmd.indexOf('\n');
        if (endIdx > 0) cmd = cmd.substring(0, endIdx).trim();
        if (cmd.length > 300) cmd = cmd.substring(0, 300);
        if (cmd.isNotEmpty && _looksLikeCommand(cmd.toLowerCase())) return cmd;
      }
    }
    return null;
  }

  static bool _looksLikeCommand(String cmd) {
    const knownTools = [
      'flutter', 'dart', 'python', 'python3', 'pip', 'pip3',
      'npm', 'npx', 'node', 'git', 'ls', 'cd', 'mkdir',
      'cat', 'echo', 'touch', 'cp', 'mv', 'gradle', 'adb',
    ];
    for (final tool in knownTools) {
      if (cmd.startsWith(tool)) return true;
    }
    return false;
  }

  static String? _extractSearchQuery(String text) {
    final lower = text.toLowerCase();
    
    final keywords = [
      'найди в интернете', 'поищи в интернете', 'погугли',
      'ищу в интернете', 'найти в сети',
      'search web', 'google', 'search for', 'look up online',
    ];
    for (final kw in keywords) {
      final idx = lower.indexOf(kw);
      if (idx >= 0) {
        final after = text.substring(idx + kw.length).trim();
        String query = after;
        // Remove leading punctuation
        while (query.isNotEmpty && (query.startsWith(',') || query.startsWith(':') ||
               query.startsWith('"') || query.startsWith("'"))) {
          query = query.substring(1).trim();
        }
        // Take until end of line or punctuation
        final endIdx = query.indexOf('\n');
        if (endIdx > 0) query = query.substring(0, endIdx).trim();
        // Remove trailing punctuation
        while (query.isNotEmpty && (query.endsWith('.') || query.endsWith('?') || query.endsWith('!'))) {
          query = query.substring(0, query.length - 1).trim();
        }
        if (query.isNotEmpty && query.length < 200) return query;
      }
    }
    return null;
  }

  static String _resolvePath(String filename, String workspacePath) {
    if (filename.startsWith('/')) return filename;
    // If filename already has a directory separator, use as-is relative to workspace
    return '$workspacePath/$filename';
  }
}
