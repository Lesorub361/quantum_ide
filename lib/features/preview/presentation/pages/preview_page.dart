import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

class PreviewPage extends ConsumerStatefulWidget {
  const PreviewPage({super.key});

  @override
  ConsumerState<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends ConsumerState<PreviewPage> {
  InAppWebViewController? webViewController;

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);
    final openFiles = editorState.openFiles;
    
    if (openFiles.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Preview')),
        body: const Center(child: Text('No files open to preview')),
      );
    }

    final activeFile = openFiles[editorState.activeTabIndex];
    final content = activeFile.controller.text;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Preview'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.rotate_cw),
            onPressed: () {
              webViewController?.reload();
            },
          ),
        ],
      ),
      body: (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)
          ? InAppWebView(
              initialData: InAppWebViewInitialData(
                data: content,
                mimeType: 'text/html',
                encoding: 'utf-8',
              ),
              onWebViewCreated: (controller) {
                webViewController = controller;
              },
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                useWideViewPort: true,
                loadWithOverviewMode: true,
                supportZoom: true,
              ),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.globe, size: 48, color: Colors.blueAccent),
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)!.webPreviewNotSupported,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context)!.webPreviewNotSupportedDesc,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
