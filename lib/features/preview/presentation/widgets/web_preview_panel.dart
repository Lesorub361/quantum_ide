import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'mobile_companion_qr_dialog.dart';

class SidebarWebPreviewPanel extends ConsumerStatefulWidget {
  const SidebarWebPreviewPanel({super.key});

  @override
  ConsumerState<SidebarWebPreviewPanel> createState() => _SidebarWebPreviewPanelState();
}

class _SidebarWebPreviewPanelState extends ConsumerState<SidebarWebPreviewPanel> {
  final TextEditingController _urlController = TextEditingController(text: 'http://localhost:8080');
  InAppWebViewController? _webViewController;
  bool _serverIsRunning = false;
  final List<String> _serverErrors = [];
  bool _showErrorsPanel = false;

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
              // Error Indicator Badge (if errors detected)
              if (_serverErrors.isNotEmpty) ...[
                InkWell(
                  onTap: () => setState(() => _showErrorsPanel = !_showErrorsPanel),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.circle_alert, size: 12, color: Colors.redAccent),
                        const SizedBox(width: 4),
                        Text(
                          '${_serverErrors.length}',
                          style: GoogleFonts.jetBrainsMono(
                            color: Colors.redAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
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
              // Mobile Companion (QR Code) Button
              if (_serverIsRunning)
                IconButton(
                  icon: const Icon(LucideIcons.qr_code, size: 14, color: Colors.cyanAccent),
                  tooltip: 'Mobile Live Preview (QR)',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => MobileCompanionQrDialog.show(context, _urlController.text),
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
              ? ((Platform.isAndroid || Platform.isIOS || Platform.isMacOS)
                  ? InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(_urlController.text)),
                      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                        Factory<VerticalDragGestureRecognizer>(() => VerticalDragGestureRecognizer()),
                        Factory<HorizontalDragGestureRecognizer>(() => HorizontalDragGestureRecognizer()),
                        Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
                        Factory<PanGestureRecognizer>(() => PanGestureRecognizer()),
                      },
                      initialSettings: InAppWebViewSettings(
                        transparentBackground: true,
                        javaScriptEnabled: true,
                        supportZoom: true,
                        useWideViewPort: true,
                        verticalScrollBarEnabled: true,
                        horizontalScrollBarEnabled: true,
                        disableVerticalScroll: false,
                        disableHorizontalScroll: false,
                        overScrollMode: OverScrollMode.ALWAYS,
                      ),
                      onWebViewCreated: (controller) => _webViewController = controller,
                      onReceivedError: (controller, request, error) {
                        final err = '[Сеть] ${error.description} (${error.type}) URL: ${request.url}';
                        if (!_serverErrors.contains(err)) {
                          setState(() => _serverErrors.add(err));
                        }
                        Future.delayed(const Duration(seconds: 3), () {
                          _webViewController?.reload();
                        });
                      },
                      onReceivedHttpError: (controller, request, errorResponse) {
                        final err = '[HTTP ${errorResponse.statusCode}] ${errorResponse.reasonPhrase ?? 'Ошибка'} (URL: ${request.url})';
                        if (!_serverErrors.contains(err)) {
                          setState(() => _serverErrors.add(err));
                        }
                      },
                      onConsoleMessage: (controller, consoleMessage) {
                        final msg = consoleMessage.message;
                        final isError = consoleMessage.messageLevel == ConsoleMessageLevel.ERROR ||
                            msg.contains('EXCEPTION CAUGHT') ||
                            msg.contains('Error:') ||
                            msg.contains('Uncaught') ||
                            msg.contains('TypeError:');
                        if (isError && !_serverErrors.contains(msg)) {
                          setState(() => _serverErrors.add(msg));
                        }
                      },
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.globe, size: 36, color: Colors.cyanAccent.withValues(alpha: 0.7)),
                            const SizedBox(height: 12),
                            Text(
                              l10n.webPreviewNotSupported,
                              style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.webPreviewNotSupportedDesc,
                              style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    final url = WebUri(_urlController.text);
                                    if (await canLaunchUrl(url)) {
                                      await launchUrl(url, mode: LaunchMode.externalApplication);
                                    }
                                  },
                                  icon: const Icon(LucideIcons.external_link, size: 14),
                                  label: Text(l10n.openInExternalBrowser, style: GoogleFonts.inter(fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent.withValues(alpha: 0.2),
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.blueAccent, width: 0.5),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => MobileCompanionQrDialog.show(context, _urlController.text),
                                  icon: const Icon(LucideIcons.qr_code, size: 14),
                                  label: Text('Open on Mobile', style: GoogleFonts.inter(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.cyanAccent,
                                    side: const BorderSide(color: Colors.cyanAccent, width: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ))
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
        // Error Inspector Panel
        if (_serverErrors.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1B0B0E),
              border: Border(
                top: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3), width: 1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => setState(() => _showErrorsPanel = !_showErrorsPanel),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.triangle_alert, size: 14, color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Text(
                          'Ошибки сервера/рантайма (${_serverErrors.length})',
                          style: GoogleFonts.inter(
                            color: Colors.redAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => setState(() => _serverErrors.clear()),
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(LucideIcons.trash_2, size: 13, color: Colors.white38),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          _showErrorsPanel ? LucideIcons.chevron_down : LucideIcons.chevron_up,
                          size: 14,
                          color: Colors.white60,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showErrorsPanel) ...[
                  Container(
                    height: 120,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: SelectableText(
                        _serverErrors.join('\n\n---\n\n'),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          color: const Color(0xFFFF8A80),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(LucideIcons.copy, size: 12, color: Colors.white70),
                            label: Text('Копировать', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: _serverErrors.join('\n\n')));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Ошибки скопированы в буфер'),
                                    duration: Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(LucideIcons.sparkles, size: 12, color: Colors.white),
                            label: Text('Исправить с ИИ', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purpleAccent.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            onPressed: () {
                              final errorLog = _serverErrors.join('\n\n');
                              ref.read(rightChatPanelOpenProvider.notifier).state = true;
                              ref.read(aiProvider.notifier).askAI(
                                'Пожалуйста, проанализируй эту ошибку в веб-приложении/сервере и предложи исправление кода:\n\n```\n$errorLog\n```',
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
