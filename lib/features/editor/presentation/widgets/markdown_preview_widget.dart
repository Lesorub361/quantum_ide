import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';

class MarkdownPreviewWidget extends ConsumerWidget {
  final String content;
  final String filePath;
  final VoidCallback onClose;

  const MarkdownPreviewWidget({
    super.key,
    required this.content,
    required this.filePath,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileName = filePath.split('/').where((s) => s.isNotEmpty).lastOrNull ?? 'Markdown';
    final lineCount = content.isEmpty ? 0 : content.split('\n').length;
    final wordCount = content.isEmpty ? 0 : RegExp(r'\S+').allMatches(content).length;

    return Container(
      color: const Color(0xFF0D1117),
      child: Column(
        children: [
          // ── Top Header Bar ───────────────────────────────────────────
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.8,
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.file_text, size: 14, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          fileName,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.cyanAccent.withValues(alpha: 0.3),
                            width: 0.6,
                          ),
                        ),
                        child: Text(
                          'Предпросмотр',
                          style: GoogleFonts.inter(
                            color: Colors.cyanAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$lineCount стр. • $wordCount слов',
                        style: GoogleFonts.inter(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                // Copy Raw Content Button
                IconButton(
                  icon: const Icon(LucideIcons.copy, size: 14, color: Colors.white70),
                  tooltip: 'Копировать Markdown',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Markdown скопирован в буфер обмена'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                // Switch to Edit Mode Button
                TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 0.6,
                      ),
                    ),
                  ),
                  icon: const Icon(LucideIcons.code, size: 13, color: Colors.cyanAccent),
                  label: Text(
                    'Редактировать',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onPressed: onClose,
                ),
              ],
            ),
          ),

          // ── Scrollable Rendered Markdown Content ───────────────────────
          Expanded(
            child: content.trim().isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.file_text, size: 42, color: Colors.white.withValues(alpha: 0.15)),
                        const SizedBox(height: 12),
                        Text(
                          'Файл пуст. Переключитесь в режим редактирования, чтобы добавить текст.',
                          style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: onClose,
                          icon: const Icon(LucideIcons.pencil, size: 14),
                          label: const Text('Открыть редактор'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent.withValues(alpha: 0.2),
                            foregroundColor: Colors.cyanAccent,
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: GptMarkdown(
                        content,
                        style: GoogleFonts.inter(
                          color: const Color(0xFFE6EDF3),
                          fontSize: 14,
                          height: 1.6,
                        ),
                        onLinkTap: (url, title) async {
                          if (await canLaunchUrlString(url)) {
                            await launchUrlString(url, mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
