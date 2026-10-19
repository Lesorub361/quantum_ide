import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:diff_match_patch/diff_match_patch.dart';

class InlineDiffWidget extends StatefulWidget {
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
  State<InlineDiffWidget> createState() => _InlineDiffWidgetState();
}

class _InlineDiffWidgetState extends State<InlineDiffWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final dmp = DiffMatchPatch();
    final diffs = dmp.diff(widget.oldText, widget.newText);
    dmp.diffCleanupSemantic(diffs);

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottomInset > 20;
    final double maxH = _isExpanded
        ? 520.0
        : (isKeyboardOpen ? 180.0 : 300.0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                    widget.filePath ?? 'Изменения кода',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _isExpanded = !_isExpanded),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      _isExpanded ? LucideIcons.minimize_2 : LucideIcons.maximize_2,
                      size: 13,
                      color: Colors.cyanAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            constraints: BoxConstraints(maxHeight: maxH),
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
          spans.add(const TextSpan(text: '\n'));
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