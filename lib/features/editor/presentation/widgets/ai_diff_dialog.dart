import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pretty_diff_text/pretty_diff_text.dart';

class AiDiffDialog extends StatelessWidget {
  final String filePath;
  final String oldContent;
  final String newContent;
  final VoidCallback onApply;

  const AiDiffDialog({
    super.key,
    required this.filePath,
    required this.oldContent,
    required this.newContent,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF131722),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.git_compare, color: Color(0xFFA78BFA), size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Сравнение изменений (Diff)',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Text(
                  filePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(color: Colors.white54, fontSize: 10.5),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 16, color: Colors.white54),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 440,
        child: Column(
          children: [
            // Legend
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0D14),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 4),
                  const Text('Удалено', style: TextStyle(color: Colors.white60, fontSize: 10)),
                  const SizedBox(width: 12),
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 4),
                  const Text('Добавлено', style: TextStyle(color: Colors.white60, fontSize: 10)),
                ],
              ),
            ),
            // Diff Content
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0D14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: PrettyDiffText(
                    oldText: oldContent,
                    newText: newContent,
                    defaultTextStyle: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 11),
                    addedTextStyle: GoogleFonts.jetBrainsMono(
                      color: Colors.greenAccent,
                      backgroundColor: Colors.green.withValues(alpha: 0.25),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    deletedTextStyle: GoogleFonts.jetBrainsMono(
                      color: Colors.redAccent,
                      backgroundColor: Colors.red.withValues(alpha: 0.25),
                      decoration: TextDecoration.lineThrough,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отклонить', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton.icon(
          icon: const Icon(LucideIcons.check, size: 14),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            Navigator.pop(context);
            onApply();
          },
          label: const Text('Применить изменения'),
        ),
      ],
    );
  }
}
