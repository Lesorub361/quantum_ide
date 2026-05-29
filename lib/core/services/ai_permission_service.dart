import 'package:path/path.dart' as p;
import 'package:quantum_ide/models/chat_message.dart';

enum AiRiskLevel { low, medium, high }

class AiPermissionService {
  const AiPermissionService();

  /// Validates that a path is strictly inside the workspace root.
  /// Handles relative directory traversal attacks (e.g. using '..').
  bool isPathInScope(String path, String workspaceRoot) {
    try {
      final canonicalWorkspace = p.canonicalize(workspaceRoot);
      final canonicalPath = p.canonicalize(p.isAbsolute(path) ? path : p.join(workspaceRoot, path));
      
      // The path must start with the workspace root to be in scope
      return p.isWithin(canonicalWorkspace, canonicalPath) || canonicalWorkspace == canonicalPath;
    } catch (_) {
      return false;
    }
  }

  /// Extracts potential path candidates from a shell command string.
  List<String> extractPathCandidates(String command) {
    final candidates = <String>[];
    // Split by spaces, ignoring shell quotes if possible, but keeping simple splitting for robustness
    final tokens = command.split(RegExp(r'\s+'));
    for (final token in tokens) {
      if (token.isEmpty || token.startsWith('-')) {
        continue;
      }
      
      // Clean up common shell punctuation
      var cleanToken = token.replaceAll(RegExp(r'["\x27]'), ''); // Remove quotes
      if (cleanToken.endsWith(';') || cleanToken.endsWith('&') || cleanToken.endsWith('|')) {
        cleanToken = cleanToken.substring(0, cleanToken.length - 1);
      }

      if (cleanToken.isEmpty) continue;

      final isPathLike = cleanToken == '.' ||
          cleanToken == '..' ||
          cleanToken.startsWith('/') ||
          cleanToken.startsWith('./') ||
          cleanToken.startsWith('../') ||
          cleanToken.contains('/') ||
          cleanToken.contains(r'\');

      if (isPathLike) {
        candidates.add(cleanToken);
      }
    }
    return candidates;
  }

  /// Evaluates the risk level of an AIAction and determines if it is safe to auto-approve.
  AiRiskLevel evaluateActionRisk(AIAction action, String workspaceRoot) {
    // 1. Check path scope for file actions
    if (action.type == 'edit' || action.type == 'create' || action.type == 'delete') {
      if (action.path.isEmpty) {
        return AiRiskLevel.high;
      }
      if (!isPathInScope(action.path, workspaceRoot)) {
        // Any action outside the workspace is HIGH risk (and should be blocked)
        return AiRiskLevel.high;
      }
      
      if (action.type == 'delete') {
        return AiRiskLevel.high; // Deletion is always high risk
      }
      
      return AiRiskLevel.medium; // Edits and creation are medium risk
    }

    // 2. Command action evaluation
    if (action.type == 'command') {
      final cmd = action.content.trim();
      final cmdLower = cmd.toLowerCase();

      // Check path candidates within the command
      final paths = extractPathCandidates(cmd);
      for (final path in paths) {
        // If the path looks absolute or relative, but is outside the workspace, mark as HIGH risk
        // Ignore simple non-existent paths unless they resolve outside workspace
        final absPath = p.isAbsolute(path) ? path : p.join(workspaceRoot, path);
        if (!isPathInScope(absPath, workspaceRoot)) {
          // If it references something outside the workspace, block/high risk
          return AiRiskLevel.high;
        }
      }

      // Check against blocklist/high risk patterns
      final destructivePatterns = [
        'rm ',
        'mv ',
        'chmod ',
        'chown ',
        'kill ',
        'shutdown',
        'reboot',
        'dd ',
        'mkfs',
        '>', // Output redirect to files could overwrite system files if not scoped
        'sudo ',
        'apt ',
        'apt-get ',
        'npm install -g',
        'pip install',
      ];

      for (final pattern in destructivePatterns) {
        if (cmdLower.contains(pattern)) {
          return AiRiskLevel.high;
        }
      }

      // Check for low-risk read-only commands
      final lowRiskPrefixes = [
        'flutter analyze',
        'flutter test',
        'dart test',
        'git status',
        'git diff',
        'git log',
        'ls',
        'pwd',
        'find',
        'grep',
        'cat',
        'echo',
      ];

      for (final prefix in lowRiskPrefixes) {
        if (cmdLower == prefix || cmdLower.startsWith('$prefix ')) {
          return AiRiskLevel.low;
        }
      }

      // Default for other commands (e.g. running a build, flutter pub get, git commit) is medium risk
      return AiRiskLevel.medium;
    }

    // 3. Read-only operation types (Low risk)
    if (action.type == 'read_file' ||
        action.type == 'grep_search' ||
        action.type == 'list_dir' ||
        action.type == 'web_search' ||
        action.type == 'web_fetch') {
      // For read_file and list_dir, double-check scope for safety
      if (action.type == 'read_file' || action.type == 'list_dir') {
        final pathToCheck = action.path.isEmpty ? workspaceRoot : action.path;
        if (!isPathInScope(pathToCheck, workspaceRoot)) {
          return AiRiskLevel.high; // Reading outside workspace is high risk / blocked
        }
      }
      return AiRiskLevel.low;
    }

    // 4. MCP tool calls (Medium risk)
    if (action.type == 'mcp') {
      return AiRiskLevel.medium;
    }

    return AiRiskLevel.high;
  }
}
