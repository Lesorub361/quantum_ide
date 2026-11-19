import 'dart:io';
import 'package:conduit_vt/conduit_vt.dart' as xt;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';

enum QuantumLinkType {
  webUrl,
  localhost,
  gitUrl,
  filePath,
}

class QuantumTerminalLink {
  final QuantumLinkType type;
  final String rawText;
  final String target;
  final int? line;
  final int? column;
  final int startOffset;
  final int endOffset;

  const QuantumTerminalLink({
    required this.type,
    required this.rawText,
    required this.target,
    this.line,
    this.column,
    required this.startOffset,
    required this.endOffset,
  });

  String get displayLabel {
    switch (type) {
      case QuantumLinkType.webUrl:
        return target;
      case QuantumLinkType.localhost:
        return 'Local Server ($target)';
      case QuantumLinkType.gitUrl:
        return 'Git Repository ($target)';
      case QuantumLinkType.filePath:
        return line != null ? '$target:$line' : target;
    }
  }

  IconData get icon {
    switch (type) {
      case QuantumLinkType.webUrl:
        return LucideIcons.external_link;
      case QuantumLinkType.localhost:
        return LucideIcons.globe;
      case QuantumLinkType.gitUrl:
        return LucideIcons.git_branch;
      case QuantumLinkType.filePath:
        return LucideIcons.file_code;
    }
  }
}

class QuantumLinkDetector {
  static final RegExp _webUrlRegExp = RegExp(
    r'(https?:\/\/[^\s<>\"\x27`\)\]\x00-\x1f]+)',
    caseSensitive: false,
  );

  static final RegExp _localhostRegExp = RegExp(
    r'\b((?:localhost|127\.0\.0\.1|0\.0\.0\.0):(\d{2,5})(?:\/[^\s<>"]*)?)\b',
    caseSensitive: false,
  );

  static final RegExp _gitUrlRegExp = RegExp(
    r'\b(git@[a-zA-Z0-9_\.-]+:[a-zA-Z0-9_\.\/-]+\.git)\b',
    caseSensitive: false,
  );

  static final RegExp _filePathRegExp = RegExp(
    r'(?:^|[\s\("])((?:[a-zA-Z]:[\\/]|[\/~]|\.\/)?(?:[\w\-]+[\/\\])+[\w\-]+\.[a-zA-Z0-9]{1,8})(?::(\d+))?(?::(\d+))?',
    caseSensitive: false,
  );

  static String _trimUrlPunctuation(String raw) {
    var end = raw.length;
    while (end > 0) {
      final ch = raw.codeUnitAt(end - 1);
      if (ch == 0x2e || // .
          ch == 0x2c || // ,
          ch == 0x3b || // ;
          ch == 0x3a || // :
          ch == 0x29 || // )
          ch == 0x5d) {
        end--;
      } else {
        break;
      }
    }
    return raw.substring(0, end);
  }

  /// Find all links and file paths within [text]
  static List<QuantumTerminalLink> detectAll(String text) {
    final List<QuantumTerminalLink> results = [];

    // 1. Web URLs (https://, http://)
    for (final m in _webUrlRegExp.allMatches(text)) {
      final rawMatch = m.group(1);
      if (rawMatch != null) {
        final raw = _trimUrlPunctuation(rawMatch);
        if (raw.isNotEmpty) {
          results.add(QuantumTerminalLink(
            type: QuantumLinkType.webUrl,
            rawText: raw,
            target: raw,
            startOffset: m.start,
            endOffset: m.start + raw.length,
          ));
        }
      }
    }

    // 2. Localhost server patterns (e.g. localhost:3000, 127.0.0.1:8080)
    for (final m in _localhostRegExp.allMatches(text)) {
      final raw = m.group(1);
      if (raw != null) {
        final fullUrl = raw.startsWith('http') ? raw : 'http://$raw';
        results.add(QuantumTerminalLink(
          type: QuantumLinkType.localhost,
          rawText: raw,
          target: fullUrl,
          startOffset: m.start,
          endOffset: m.end,
        ));
      }
    }

    // 3. Git URLs
    for (final m in _gitUrlRegExp.allMatches(text)) {
      final raw = m.group(1);
      if (raw != null) {
        results.add(QuantumTerminalLink(
          type: QuantumLinkType.gitUrl,
          rawText: raw,
          target: raw,
          startOffset: m.start,
          endOffset: m.end,
        ));
      }
    }

    // 4. File paths with optional line:col (e.g. lib/main.dart:42:15)
    for (final m in _filePathRegExp.allMatches(text)) {
      final filePath = m.group(1);
      if (filePath != null && !filePath.startsWith('http://') && !filePath.startsWith('https://')) {
        int? line;
        int? col;
        if (m.group(2) != null) {
          line = int.tryParse(m.group(2)!);
        }
        if (m.group(3) != null) {
          col = int.tryParse(m.group(3)!);
        }

        results.add(QuantumTerminalLink(
          type: QuantumLinkType.filePath,
          rawText: m.group(0)!.trim(),
          target: filePath,
          line: line,
          column: col,
          startOffset: m.start,
          endOffset: m.end,
        ));
      }
    }

    return results;
  }

  /// Locate link directly under cursor or tap at [col] within [line]
  static QuantumTerminalLink? findLinkAt(String line, int col) {
    final links = detectAll(line);
    for (final link in links) {
      if (col >= link.startOffset && col <= link.endOffset) {
        return link;
      }
    }
    return null;
  }

  /// Locate link (including multi-line wrapped URLs) in [buffer] at ([lineIndex], [colIndex]).
  static QuantumTerminalLink? findLinkInBuffer(
    xt.Buffer buffer,
    int lineIndex,
    int colIndex,
  ) {
    if (lineIndex < 0 || lineIndex >= buffer.lines.length) {
      return null;
    }

    final lineStr = buffer.lines[lineIndex].toString();
    return findLinkAt(lineStr, colIndex);
  }

  /// Interactive handler to open link, local server or jump to file in code editor
  static Future<void> handleLinkTap(
    BuildContext context,
    WidgetRef ref,
    QuantumTerminalLink link,
  ) async {
    HapticFeedback.lightImpact();

    switch (link.type) {
      case QuantumLinkType.webUrl:
      case QuantumLinkType.localhost:
        await Clipboard.setData(ClipboardData(text: link.target));
        final uri = Uri.tryParse(link.target);
        if (uri != null) {
          var ok = false;
          try {
            ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {
            ok = false;
          }
          if (!ok) {
            try {
              ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
            } catch (_) {
              ok = false;
            }
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  ok
                      ? 'Ссылка открыта и скопирована в буфер обмена'
                      : 'Ссылка скопирована в буфер: ${link.target}',
                ),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
        break;

      case QuantumLinkType.gitUrl:
        await Clipboard.setData(ClipboardData(text: link.target));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Git URL скопирован: ${link.target}'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        break;

      case QuantumLinkType.filePath:
        final workspace = ref.read(workspaceProvider).currentPath;
        String resolvedPath = link.target;

        if (workspace != null && !p.isAbsolute(resolvedPath)) {
          resolvedPath = p.normalize(p.join(workspace, resolvedPath));
        }

        if (File(resolvedPath).existsSync()) {
          await ref.read(editorProvider.notifier).openFile(
            resolvedPath,
            line: link.line != null ? link.line! - 1 : null,
            column: link.column != null ? link.column! - 1 : null,
          );

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(LucideIcons.file_code, size: 16, color: Colors.cyanAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Открыт файл ${p.basename(resolvedPath)}${link.line != null ? " : строка ${link.line}" : ""}',
                        style: GoogleFonts.inter(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          // If file not found locally, offer copy or notification
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Файл не найден: ${link.target}'),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'Копировать',
                  onPressed: () => Clipboard.setData(ClipboardData(text: link.target)),
                ),
              ),
            );
          }
        }
        break;
    }
  }
}
