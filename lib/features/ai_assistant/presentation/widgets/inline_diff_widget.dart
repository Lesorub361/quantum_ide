import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:diff_match_patch/diff_match_patch.dart';

class InlineDiffWidget extends StatelessWidget {
  final String oldText;
  final String newText;
  final String? filePath;

  const InlineDiffWidget({
    super.key,
    required this.oldText,
    required this.newText,
    this.filePath,
  });

  @override
  Widget build(BuildContext context) {
    final dmp = DiffMatchPatch();
    final diffs = dmp.diff(oldText, newText);
    dmp.diffCleanupSemantic(diffs);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (filePath != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.file_diff, size: 12, color: Colors.cyanAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      filePath!,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _buildDiffView(diffs),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffView(List<Diff> diffs) {
    final List<InlineSpan> spans = [];

    for (final diff in diffs) {
      final lines = diff.text.split('\n');
      for (int i = 0; i < lines.length; i++) {
        if (i > 0) {
          spans.add(TextSpan(text: '\n'));
        }
        
        Color bgColor;
        Color fgColor;
        String prefix;

        switch (diff.operation) {
          case DIFF_INSERT:
            bgColor = Colors.greenAccent.withValues(alpha: 0.15);
            fgColor = Colors.greenAccent;
            prefix = '+';
            break;
          case DIFF_DELETE:
            bgColor = Colors.redAccent.withValues(alpha: 0.15);
            fgColor = Colors.redAccent;
            prefix = '-';
            break;
          default:
            bgColor = Colors.transparent;
            fgColor = Colors.white70;
            prefix = ' ';
        }

        spans.add(WidgetSpan(
          child: Container(
            color: bgColor,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$prefix ',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: fgColor.withValues(alpha: 0.5),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                    text: lines[i],
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: fgColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
      }
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }
}