import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/utils/file_type_detector.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class FilePreviewWidget extends StatefulWidget {
  final String filePath;

  const FilePreviewWidget({super.key, required this.filePath});

  @override
  State<FilePreviewWidget> createState() => _FilePreviewWidgetState();
}

class _FilePreviewWidgetState extends State<FilePreviewWidget> {
  bool? _exists;
  String? _svgContent;
  int? _fileSize;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FilePreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.filePath.isEmpty) return;
    final file = File(widget.filePath);
    final exists = await file.exists();
    if (!mounted) return;
    setState(() => _exists = exists);
    if (!exists) return;

    if (FileTypeDetector.isSvg(widget.filePath)) {
      final content = await file.readAsString();
      if (!mounted) return;
      setState(() => _svgContent = content);
    } else {
      final size = await file.length();
      if (!mounted) return;
      setState(() => _fileSize = size);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.filePath.isEmpty) {
      return const Center(child: Text('No file selected'));
    }

    if (_exists == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_exists!) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text('File not found: ${widget.filePath}'),
          ],
        ),
      );
    }

    if (FileTypeDetector.isImage(widget.filePath)) {
      return _buildImagePreview(context);
    }

    if (FileTypeDetector.isSvg(widget.filePath)) {
      return _buildSvgPreview(context);
    }

    if (FileTypeDetector.isPdf(widget.filePath)) {
      return _buildPdfPreview(context);
    }

    return _buildGenericPreview(context);
  }

  Widget _buildImagePreview(BuildContext context) {
    final file = File(widget.filePath);
    return InteractiveViewer(
      minScale: 0.1,
      maxScale: 5.0,
      child: Center(
        child: Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image, size: 64),
                const SizedBox(height: 16),
                Text('Cannot display image: ${p.basename(widget.filePath)}'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSvgPreview(BuildContext context) {
    final content = _svgContent;
    if (content == null) return const Center(child: CircularProgressIndicator());
    final encoded = Uri.dataFromString(
      content,
      mimeType: 'image/svg+xml',
      encoding: utf8,
    ).toString();

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(encoded)),
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        supportZoom: true,
      ),
    );
  }

  Widget _buildPdfPreview(BuildContext context) {
    final file = File(widget.filePath);
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('file://${file.absolute.path}')),
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        supportZoom: true,
      ),
    );
  }

  Widget _buildGenericPreview(BuildContext context) {
    final ext = p.extension(widget.filePath).replaceFirst('.', '').toUpperCase();
    final size = _fileSize ?? 0;
    final sizeStr = size > 1048576
        ? '${(size / 1048576).toStringAsFixed(1)} MB'
        : size > 1024
            ? '${(size / 1024).toStringAsFixed(1)} KB'
            : '$size B';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.file,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            p.basename(widget.filePath),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '$ext \u2022 $sizeStr',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
