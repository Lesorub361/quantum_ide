import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/features/collaboration/presentation/notifiers/collaboration_notifier.dart';

class RemoteCursorOverlay extends StatelessWidget {
  final List<RemoteCursor> cursors;
  final double lineHeight;
  final double editorScrollOffset;

  const RemoteCursorOverlay({
    super.key,
    required this.cursors,
    this.lineHeight = 20.0,
    this.editorScrollOffset = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: cursors.map((cursor) {
          final color = Color(
              int.parse(cursor.colorHex.replaceFirst('#', '0xFF')));
          final top = (cursor.lineNumber - 1) * lineHeight - editorScrollOffset;

          return Positioned(
            top: top,
            left: cursor.column * 8.0 + 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 2,
                  height: lineHeight,
                  decoration: BoxDecoration(
                    color: color,
                    boxShadow: [
                      BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 4),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(4),
                      bottomRight: Radius.circular(4),
                      bottomLeft: Radius.circular(4),
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: color.withValues(alpha: 0.3), blurRadius: 4),
                    ],
                  ),
                  child: Text(
                    cursor.userName,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
