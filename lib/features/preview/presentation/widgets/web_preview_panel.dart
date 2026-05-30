import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

class SidebarWebPreviewPanel extends ConsumerStatefulWidget {
  const SidebarWebPreviewPanel({super.key});

  @override
  ConsumerState<SidebarWebPreviewPanel> createState() => _SidebarWebPreviewPanelState();
}

class _SidebarWebPreviewPanelState extends ConsumerState<SidebarWebPreviewPanel> {
  final TextEditingController _urlController = TextEditingController(text: "http://localhost:8080");
  InAppWebViewController? _webViewController;
  bool _serverIsRunning = false;

  @override
  void initState() {
    super.initState();
    // Sync initial state with provider
    _serverIsRunning = ref.read(serverRunningProvider);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _setServerRunning(bool val) {
    setState(() {
      _serverIsRunning = val;
    });
    ref.read(serverRunningProvider.notifier).state = val;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        // Address Bar & Browser Controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
          ),
          child: Row(
            children: [
              // Address Bar with Glass Look
              Expanded(
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.globe, size: 12, color: Colors.white38),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 11),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (_) {
                            if (_serverIsRunning) {
                              _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(_urlController.text)));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Reload Button
              if (_serverIsRunning)
                IconButton(
                  icon: const Icon(LucideIcons.rotate_cw, size: 14, color: Colors.greenAccent),
                  tooltip: l10n.refreshPreview,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _webViewController?.reload(),
                ),
              const SizedBox(width: 8),
              // Toggle Power (Start/Stop) Button
              IconButton(
                icon: Icon(
                  _serverIsRunning ? LucideIcons.power : LucideIcons.play,
                  size: 14,
                  color: _serverIsRunning ? Colors.redAccent : Colors.cyanAccent,
                ),
                tooltip: _serverIsRunning 
                    ? l10n.stopWebServer 
                    : l10n.startWebServer,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  _setServerRunning(!_serverIsRunning);
                },
              ),
              const SizedBox(width: 8),
              // Open in External Browser
              IconButton(
                icon: const Icon(LucideIcons.external_link, size: 14, color: Colors.blueAccent),
                tooltip: l10n.openInExternalBrowser,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () async {
                  final url = WebUri(_urlController.text);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),
        ),
        // WebView Frame
        Expanded(
          child: _serverIsRunning
              ? InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(_urlController.text)),
                  initialSettings: InAppWebViewSettings(
                    transparentBackground: true,
                    javaScriptEnabled: true,
                  ),
                  onWebViewCreated: (controller) => _webViewController = controller,
                  onReceivedError: (controller, request, error) {
                    Future.delayed(const Duration(seconds: 2), () {
                      _webViewController?.reload();
                    });
                  },
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.server_off, size: 36, color: Colors.white.withValues(alpha: 0.15)),
                      const SizedBox(height: 12),
                      Text(
                        l10n.webPreviewStopped,
                        style: GoogleFonts.inter(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.webPreviewStartInstructions,
                        style: GoogleFonts.inter(color: Colors.white24, fontSize: 10),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
