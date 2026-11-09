import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher_string.dart';

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

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // High contrast adaptive GitHub-like styling
    final backgroundColor = isDark ? const Color(0xFF0D1117) : theme.colorScheme.surface;
    final headerColor = isDark ? const Color(0xFF161B22) : theme.colorScheme.surfaceContainer;
    final textColor = isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328);
    final textMutedColor = isDark ? const Color(0xFF8B949E) : const Color(0xFF656D76);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.1) : theme.colorScheme.outlineVariant;
    final codeBlockBg = isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA);
    final inlineCodeBg = isDark ? const Color(0xFF21262D) : const Color(0xFFEFF1F3);
    final linkColor = isDark ? const Color(0xFF58A6FF) : const Color(0xFF0969DA);
    final accentColor = isDark ? Colors.cyanAccent : theme.colorScheme.primary;

    return Container(
      color: backgroundColor,
      child: Column(
        children: [
          // ── Top Header Bar ───────────────────────────────────────────
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: headerColor,
              border: Border(
                bottom: BorderSide(
                  color: borderColor,
                  width: 0.8,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.file_text, size: 14, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          fileName,
                          style: GoogleFonts.inter(
                            color: textColor,
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
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.3),
                            width: 0.6,
                          ),
                        ),
                        child: Text(
                          'Предпросмотр',
                          style: GoogleFonts.inter(
                            color: accentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$lineCount стр. • $wordCount слов',
                        style: GoogleFonts.inter(
                          color: textMutedColor,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                // Copy Raw Content Button
                IconButton(
                  icon: Icon(LucideIcons.copy, size: 14, color: textMutedColor),
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
                    backgroundColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: BorderSide(
                        color: borderColor,
                        width: 0.6,
                      ),
                    ),
                  ),
                  icon: Icon(LucideIcons.code, size: 13, color: accentColor),
                  label: Text(
                    'Редактировать',
                    style: GoogleFonts.inter(
                      color: textColor,
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
                        Icon(LucideIcons.file_text, size: 42, color: textMutedColor.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text(
                          'Файл пуст. Переключитесь в режим редактирования, чтобы добавить текст.',
                          style: GoogleFonts.inter(color: textMutedColor, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: onClose,
                          icon: const Icon(LucideIcons.pencil, size: 14),
                          label: const Text('Открыть редактор'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor.withValues(alpha: 0.15),
                            foregroundColor: accentColor,
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: Theme(
                        data: theme.copyWith(
                          brightness: isDark ? Brightness.dark : Brightness.light,
                          scaffoldBackgroundColor: backgroundColor,
                          colorScheme: theme.colorScheme.copyWith(
                            surface: backgroundColor,
                            onSurface: textColor,
                            onSurfaceVariant: textMutedColor,
                            primary: linkColor,
                            outline: borderColor,
                          ),
                          textTheme: theme.textTheme.apply(
                            bodyColor: textColor,
                            displayColor: textColor,
                          ),
                        ),
                        child: GptMarkdownTheme(
                          gptThemeData: GptMarkdownThemeData(
                            brightness: isDark ? Brightness.dark : Brightness.light,
                            highlightColor: inlineCodeBg,
                            h1: GoogleFonts.inter(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                            h2: GoogleFonts.inter(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                            h3: GoogleFonts.inter(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 17,
                            ),
                            h4: GoogleFonts.inter(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            h5: GoogleFonts.inter(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            h6: GoogleFonts.inter(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            hrLineColor: borderColor,
                            linkColor: linkColor,
                            inlineCode: InlineCodeStyle(
                              color: textColor,
                              backgroundColor: inlineCodeBg,
                              borderColor: borderColor,
                              borderWidth: 0.8,
                              fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
                              fontSizeFactor: 0.9,
                            ),
                            styleSheet: GptMarkdownStyleSheet(
                              codeBlock: CodeBlockStyle(
                                backgroundColor: codeBlockBg,
                                borderColor: borderColor,
                                borderWidth: 0.8,
                                textColor: textColor,
                                showCopyButton: true,
                                fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
                                fontSize: 12.5,
                              ),
                              table: TableStyle(
                                borderColor: borderColor,
                                headerBackground: headerColor,
                                rowStripeColor: isDark ? const Color(0xFF131720) : const Color(0xFFF9FAFB),
                              ),
                            ),
                          ),
                          child: GptMarkdown(
                            content,
                            style: GoogleFonts.inter(
                              color: textColor,
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
                  ),
          ),
        ],
      ),
    );
  }
}
