import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:photo_view/photo_view.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:path/path.dart' as p;

class FilePreviewPage extends StatelessWidget {
  final String filePath;

  const FilePreviewPage({
    super.key,
    required this.filePath,
  });

  bool _isImage(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.png' ||
        ext == '.jpg' ||
        ext == '.jpeg' ||
        ext == '.gif' ||
        ext == '.webp' ||
        ext == '.bmp';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fileName = p.basename(filePath);
    final isImg = _isImage(filePath);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090B0F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fileName,
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              filePath,
              style: GoogleFonts.inter(fontSize: 9.5, color: Colors.white38),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Chip(
              backgroundColor: const Color(0xFFFF3C3C).withValues(alpha: 0.15),
              side: const BorderSide(color: Color(0x3FFF3C3C)),
              label: Text(
                isImg ? l10n.image : l10n.document,
                style: const TextStyle(color: Color(0xFFFF3C3C), fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0D0F14),
              const Color(0xFF0A0B0E),
            ],
          ),
        ),
        child: isImg 
            ? _buildImagePreview(l10n) 
            : _buildMarkdownPreview(l10n),
      ),
    );
  }

  Widget _buildImagePreview(AppLocalizations l10n) {
    return Center(
      child: ClipRRect(
        child: PhotoView(
          imageProvider: FileImage(File(filePath)),
          backgroundDecoration: const BoxDecoration(color: Colors.transparent),
          minScale: PhotoViewComputedScale.contained * 0.8,
          maxScale: PhotoViewComputedScale.covered * 2.5,
          loadingBuilder: (context, event) => const Center(
            child: CircularProgressIndicator(color: Colors.redAccent),
          ),
          errorBuilder: (context, error, stackTrace) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.image_off, size: 48, color: Colors.redAccent),
                const SizedBox(height: 12),
                Text(l10n.failedToLoadImage, style: GoogleFonts.inter(color: Colors.white38, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMarkdownPreview(AppLocalizations l10n) {
    return FutureBuilder<String>(
      future: File(filePath).readAsString(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(l10n.failedToReadFile(snapshot.error.toString()), style: const TextStyle(color: Colors.white30)),
          );
        }

        final data = snapshot.data ?? '';

        return Markdown(
          data: data,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            h1: GoogleFonts.outfit(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            h2: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            h3: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            p: GoogleFonts.inter(color: Colors.white70, fontSize: 13, height: 1.5),
            code: GoogleFonts.firaCode(
              color: const Color(0xFFFF3C3C),
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              fontSize: 11.5,
            ),
            codeblockPadding: const EdgeInsets.all(12),
            codeblockDecoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 0.8),
            ),
            blockquote: GoogleFonts.inter(color: Colors.white54, fontSize: 12.5),
            blockquoteDecoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Color(0xFFFF3C3C), width: 3.5)),
            ),
            blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            horizontalRuleDecoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.8)),
            ),
            listBullet: GoogleFonts.inter(color: const Color(0xFFFF3C3C)),
            tableHead: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            tableBody: GoogleFonts.inter(color: Colors.white70, fontSize: 11.5),
            tableBorder: TableBorder.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
            tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
        );
      },
    );
  }
}
