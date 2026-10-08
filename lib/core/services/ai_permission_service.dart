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
    if (action.type == 'edit' || action.type == 'create' || action.type == 'delete' || action.type == 'rewrite_whole_file') {
      if (action.path.isEmpty) {
        return AiRiskLevel.high;
      }
      if (!isPathInScope(action.path, workspaceRoot)) {
        // Any action outside the workspace is blocked/high risk
        return AiRiskLevel.high;
      }
      
      if (action.type == 'delete') {
        return AiRiskLevel.high; // Deletion requires caution
      }
      
      // Inside workspace: creating and editing files is safe for autonomous agent
      return AiRiskLevel.low;
    }

    // 2. Command action evaluation
    if (action.type == 'command') {
      final cmd = action.content.trim();
      final cmdLower = cmd.toLowerCase();

      // Check against destructive system patterns
      final destructivePatterns = [
        'rm -rf /',
        'rm -rf ~',
        'rm -rf ..',
        'mv /',
        'chmod -R 777 /',
        'shutdown',
        'reboot',
        'mkfs',
        ':(){ :|:& };:',
      ];

      for (final pattern in destructivePatterns) {
        if (cmdLower.contains(pattern)) {
          return AiRiskLevel.high;
        }
      }

      // Standard development tools and commands run inside PRoot container safely
      return AiRiskLevel.low;
    }

    // 3. Read-only and exploration operation types (Low risk)
    if (action.type == 'read_file' ||
        action.type == 'grep_search' ||
        action.type == 'list_dir' ||
        action.type == 'find_symbols' ||
        action.type == 'web_search' ||
        action.type == 'web_fetch') {
      return AiRiskLevel.low;
    }

    // 4. MCP tool calls (Low risk)
    if (action.type == 'mcp') {
      return AiRiskLevel.low;
    }

    return AiRiskLevel.medium;
  }
}

