import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:quantum_ide/features/preview/presentation/widgets/mobile_companion_qr_dialog.dart';
import 'package:quantum_ide/features/preview/utils/preview_cache_helper.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/dedicated_terminal_notifier.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';

enum _PreviewDeviceMode { desktop, phone, tablet }

class FloatingWebPreviewOverlay extends ConsumerStatefulWidget {
  const FloatingWebPreviewOverlay({super.key});

  @override
  ConsumerState<FloatingWebPreviewOverlay> createState() =>
      _FloatingWebPreviewOverlayState();
}

class _FloatingWebPreviewOverlayState
    extends ConsumerState<FloatingWebPreviewOverlay> {
  final TextEditingController _urlController = TextEditingController();
  final List<String> _consoleErrors = [];

  InAppWebViewController? _webViewController;
  Offset? _windowOffset;
  Size? _windowSize;
  Offset? _bubbleOffset;

  bool _isMaximized = false;
  bool _showConsole = false;
  bool _isLandscape = false;
  bool _isLoading = false;
  double _loadProgress = 0;
  _PreviewDeviceMode _deviceMode = _PreviewDeviceMode.desktop;

  @override
  void initState() {
    super.initState();
    _urlController.text = PreviewCacheHelper.stripCacheBuster(
      ref.read(floatingPreviewUrlProvider),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _hardReload({String? url, bool clearCache = true}) async {
    final candidate = (url ?? _urlController.text).trim();
    final cleanUrl = PreviewCacheHelper.stripCacheBuster(
      candidate.isNotEmpty
          ? PreviewCacheHelper.normalizeUrl(candidate)
          : ref.read(floatingPreviewUrlProvider),
    );
    final target = cleanUrl.isNotEmpty ? cleanUrl : 'http://127.0.0.1:8080';
    await PreviewCacheHelper.hardLoad(
      _webViewController,
      target,
      clearCache: clearCache,
    );
  }

  void _navigateTo(String rawUrl) {
    final normalized = PreviewCacheHelper.normalizeUrl(rawUrl);
    if (normalized.isEmpty) return;
    final cleanUrl = PreviewCacheHelper.stripCacheBuster(normalized);
    _urlController.text = cleanUrl;
    ref.read(floatingPreviewUrlProvider.notifier).state = cleanUrl;
    ref.read(serverRunningProvider.notifier).state = true;
    _hardReload(url: cleanUrl, clearCache: true);
  }

  void _selectPort(int port) {
    _navigateTo('http://127.0.0.1:$port');
  }

  Future<void> _openExternalBrowser() async {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw.startsWith('http') ? raw : 'http://$raw');
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVisible = ref.watch(floatingPreviewVisibleProvider);
    if (!isVisible) return const SizedBox.shrink();

    final isMinimized = ref.watch(floatingPreviewMinimizedProvider);
    final currentUrl = ref.watch(floatingPreviewUrlProvider);
    final serverRunning = ref.watch(serverRunningProvider);
    final autoHotReload = ref.watch(flutterAutoHotReloadProvider);
    final runSession = ref.watch(
      dedicatedTerminalProvider.select((s) => s.sessions[DedicatedTerminalType.run]),
    );
    final isRunActive = runSession != null && !runSession.isExited;

    if (_urlController.text.isEmpty && currentUrl.isNotEmpty) {
      _urlController.text = PreviewCacheHelper.stripCacheBuster(currentUrl);
    }

    ref.listen<String>(floatingPreviewUrlProvider, (prev, next) {
      if (next.isNotEmpty && next != prev) {
        final clean = PreviewCacheHelper.stripCacheBuster(next);
        if (_urlController.text != clean) {
          _urlController.text = clean;
        }
        _hardReload(url: clean, clearCache: true);
      }
    });

    ref.listen<int>(floatingPreviewReloadTokenProvider, (prev, next) {
      if (next != prev) {
        _hardReload(clearCache: true);
      }
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        if (maxW <= 0 || maxH <= 0) return const SizedBox.shrink();

        if (isMinimized) {
          return _buildMinimizedBubble(maxW, maxH, serverRunning, currentUrl);
        }

        final isCompact = maxW < 600;
        final defaultW = isCompact ? math.max(280.0, maxW - 24) : 460.0;
        final defaultH = isCompact ? math.max(320.0, maxH * 0.68) : 600.0;

        final size = _isMaximized
            ? Size(math.max(280.0, maxW - 16), math.max(260.0, maxH - 16))
            : Size(
                (_windowSize?.width ?? defaultW).clamp(280.0, math.max(280.0, maxW - 12)),
                (_windowSize?.height ?? defaultH).clamp(260.0, math.max(260.0, maxH - 12)),
              );

        final maxLeft = math.max(8.0, maxW - size.width - 8);
        final maxTop = math.max(8.0, maxH - size.height - 8);

        final defaultOffset = Offset(
          ((maxW - size.width) / 2).clamp(8.0, maxLeft),
          ((maxH - size.height) / 2).clamp(8.0, maxTop),
        );

        final offset = _isMaximized
            ? const Offset(8, 8)
            : Offset(
                (_windowOffset?.dx ?? defaultOffset.dx).clamp(8.0, maxLeft),
                (_windowOffset?.dy ?? defaultOffset.dy).clamp(8.0, maxTop),
              );

        return Stack(
          children: [
            Positioned(
              left: offset.dx,
              top: offset.dy,
              width: size.width,
              height: size.height,
              child: Material(
                color: Colors.transparent,
                elevation: 24,
                shadowColor: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E121B).withValues(alpha: 0.97),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.cyanAccent.withValues(alpha: 0.25),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyanAccent.withValues(alpha: 0.08),
                        blurRadius: 24,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _buildTitleBar(maxLeft, maxTop, offset, serverRunning),
                      if (_isLoading)
                        LinearProgressIndicator(
                          value: _loadProgress > 0 && _loadProgress < 1 ? _loadProgress : null,
                          minHeight: 2,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                        ),
                      _buildAddressBar(),
                      _buildControlsStrip(autoHotReload, isRunActive),
                      Expanded(
                        child: _buildWebViewport(context, serverRunning),
                      ),
                      if (_showConsole) _buildConsoleDrawer(),
                      if (!_isMaximized) _buildBottomResizeBar(maxW, maxH, offset, size),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMinimizedBubble(
    double maxW,
    double maxH,
    bool serverRunning,
    String currentUrl,
  ) {
    final maxLeft = math.max(12.0, maxW - 190);
    final maxTop = math.max(12.0, maxH - 56);
    final pos = Offset(
      (_bubbleOffset?.dx ?? maxLeft - 8).clamp(12.0, maxLeft),
      (_bubbleOffset?.dy ?? maxTop - 72).clamp(12.0, maxTop),
    );

    final uri = Uri.tryParse(currentUrl);
    final portLabel = (uri != null && uri.hasPort) ? ':${uri.port}' : 'Web';

    return Stack(
      children: [
        Positioned(
          left: pos.dx,
          top: pos.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _bubbleOffset = Offset(
                  (pos.dx + details.delta.dx).clamp(12.0, maxLeft),
                  (pos.dy + details.delta.dy).clamp(12.0, maxTop),
                );
              });
            },
            onTap: () {
              ref.read(floatingPreviewMinimizedProvider.notifier).state = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _hardReload(clearCache: true);
              });
            },
            child: Material(
              color: Colors.transparent,
              elevation: 14,
              borderRadius: BorderRadius.circular(28),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF151C2C), Color(0xFF0F1420)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.cyanAccent.withValues(alpha: 0.45),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: serverRunning ? Colors.greenAccent : Colors.amberAccent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (serverRunning ? Colors.greenAccent : Colors.amberAccent)
                                .withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(LucideIcons.globe, size: 14, color: Colors.cyanAccent),
                    const SizedBox(width: 6),
                    Text(
                      'Browser $portLabel',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        ref.read(floatingPreviewVisibleProvider.notifier).state = false;
                        ref.read(floatingPreviewMinimizedProvider.notifier).state = false;
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(LucideIcons.x, size: 14, color: Colors.white54),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitleBar(
    double maxLeft,
    double maxTop,
    Offset offset,
    bool serverRunning,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: _isMaximized
          ? null
          : (details) {
              setState(() {
                final cur = _windowOffset ?? offset;
                _windowOffset = Offset(
                  (cur.dx + details.delta.dx).clamp(8.0, maxLeft),
                  (cur.dy + details.delta.dy).clamp(8.0, maxTop),
                );
              });
            },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF171E2E),
              const Color(0xFF111622),
            ],
          ),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
          ),
        ),
        child: Row(
          children: [
            _buildTrafficDot(
              color: const Color(0xFFFF5F56),
              tooltip: 'Закрыть',
              onTap: () {
                ref.read(floatingPreviewVisibleProvider.notifier).state = false;
              },
            ),
            const SizedBox(width: 6),
            _buildTrafficDot(
              color: const Color(0xFFFFBD2E),
              tooltip: 'Свернуть',
              onTap: () {
                ref.read(floatingPreviewMinimizedProvider.notifier).state = true;
              },
            ),
            const SizedBox(width: 6),
            _buildTrafficDot(
              color: const Color(0xFF27C93F),
              tooltip: _isMaximized ? 'Восстановить' : 'На весь экран',
              onTap: () {
                setState(() => _isMaximized = !_isMaximized);
              },
            ),
            const SizedBox(width: 10),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: serverRunning ? Colors.greenAccent : Colors.white24,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Quantum Browser',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (_consoleErrors.isNotEmpty)
              InkWell(
                onTap: () => setState(() => _showConsole = !_showConsole),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.45),
                      width: 0.6,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.circle_alert, size: 11, color: Colors.redAccent),
                      const SizedBox(width: 4),
                      Text(
                        '${_consoleErrors.length}',
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
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                LucideIcons.terminal,
                size: 13,
                color: _showConsole ? Colors.cyanAccent : Colors.white54,
              ),
              tooltip: 'Console',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              onPressed: () => setState(() => _showConsole = !_showConsole),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrafficDot({
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildAddressBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: const Color(0xFF0B0E16),
      child: Row(
        children: [
          _buildNavIcon(
            icon: LucideIcons.arrow_left,
            tooltip: 'Back',
            onTap: () => _webViewController?.goBack(),
          ),
          _buildNavIcon(
            icon: LucideIcons.arrow_right,
            tooltip: 'Forward',
            onTap: () => _webViewController?.goForward(),
          ),
          _buildNavIcon(
            icon: LucideIcons.rotate_cw,
            tooltip: 'Reload Page',
            color: Colors.cyanAccent,
            onTap: () => _hardReload(clearCache: true),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.lock, size: 11, color: Colors.white38),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      style: GoogleFonts.jetBrainsMono(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 11.5,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      textInputAction: TextInputAction.go,
                      onSubmitted: _navigateTo,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          _buildNavIcon(
            icon: LucideIcons.qr_code,
            tooltip: 'Mobile Live Preview (QR)',
            color: Colors.cyanAccent,
            onTap: () => MobileCompanionQrDialog.show(context, _urlController.text),
          ),
          _buildNavIcon(
            icon: LucideIcons.external_link,
            tooltip: 'Open in Browser',
            color: Colors.blueAccent,
            onTap: _openExternalBrowser,
          ),
        ],
      ),
    );
  }

  Widget _buildNavIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color color = Colors.white60,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }

  Widget _buildControlsStrip(bool autoHotReload, bool isRunActive) {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0E131E),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final port in const [8080, 3000, 5173, 5000]) ...[
              _buildChip(
                label: ':$port',
                isActive: _urlController.text.contains(':$port'),
                activeColor: Colors.cyanAccent,
                onTap: () => _selectPort(port),
              ),
              const SizedBox(width: 4),
            ],
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: Colors.white12,
            ),
            _buildDeviceChip(
              icon: LucideIcons.monitor,
              label: isRu ? 'Экран' : 'Full',
              mode: _PreviewDeviceMode.desktop,
            ),
            const SizedBox(width: 4),
            _buildDeviceChip(
              icon: LucideIcons.smartphone,
              label: isRu ? 'Телефон' : 'Phone',
              mode: _PreviewDeviceMode.phone,
            ),
            const SizedBox(width: 4),
            _buildDeviceChip(
              icon: LucideIcons.tablet,
              label: isRu ? 'Планшет' : 'Tablet',
              mode: _PreviewDeviceMode.tablet,
            ),
            if (_deviceMode != _PreviewDeviceMode.desktop) ...[
              const SizedBox(width: 4),
              _buildChip(
                icon: LucideIcons.rotate_cw,
                label: isRu ? 'Поворот' : 'Rotate',
                isActive: _isLandscape,
                activeColor: Colors.amberAccent,
                onTap: () => setState(() => _isLandscape = !_isLandscape),
              ),
            ],
            if (isRunActive) ...[
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: Colors.white12,
              ),
              _buildChip(
                icon: LucideIcons.zap,
                label: 'r',
                isActive: false,
                activeColor: Colors.yellow,
                onTap: () {
                  ref
                      .read(dedicatedTerminalProvider.notifier)
                      .sendRawChar(DedicatedTerminalType.run, 'r');
                },
              ),
              const SizedBox(width: 4),
              _buildChip(
                icon: LucideIcons.rotate_cw,
                label: 'R',
                isActive: false,
                activeColor: Colors.orangeAccent,
                onTap: () {
                  ref
                      .read(dedicatedTerminalProvider.notifier)
                      .sendRawChar(DedicatedTerminalType.run, 'R');
                  Future.delayed(const Duration(milliseconds: 1800), () {
                    if (mounted) {
                      _hardReload(clearCache: true);
                    }
                  });
                },
              ),
              const SizedBox(width: 4),
              _buildChip(
                icon: autoHotReload ? LucideIcons.sparkles : LucideIcons.circle_pause,
                label: isRu ? 'Авто' : 'Auto',
                isActive: autoHotReload,
                activeColor: Colors.greenAccent,
                onTap: () {
                  ref.read(flutterAutoHotReloadProvider.notifier).state =
                      !autoHotReload;
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceChip({
    required IconData icon,
    required String label,
    required _PreviewDeviceMode mode,
  }) {
    return _buildChip(
      icon: icon,
      label: label,
      isActive: _deviceMode == mode,
      activeColor: Colors.purpleAccent,
      onTap: () => setState(() => _deviceMode = mode),
    );
  }

  Widget _buildChip({
    IconData? icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive
                ? activeColor.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
            width: 0.6,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 11, color: isActive ? activeColor : Colors.white60),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                color: isActive ? activeColor : Colors.white70,
                fontSize: 10.5,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebViewport(BuildContext context, bool serverRunning) {
    final l10n = AppLocalizations.of(context)!;
    final webSupported = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

    final Widget content = webSupported
        ? InAppWebView(
            initialUrlRequest: PreviewCacheHelper.buildFreshRequest(
              _urlController.text.isEmpty
                  ? 'http://127.0.0.1:8080'
                  : _urlController.text,
            ),
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<VerticalDragGestureRecognizer>(
                  () => VerticalDragGestureRecognizer()),
              Factory<HorizontalDragGestureRecognizer>(
                  () => HorizontalDragGestureRecognizer()),
              Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
              Factory<PanGestureRecognizer>(() => PanGestureRecognizer()),
            },
            initialSettings: PreviewCacheHelper.freshWebViewSettings(),
            onWebViewCreated: (controller) => _webViewController = controller,
            onLoadStart: (controller, url) {
              if (!mounted) return;
              setState(() {
                _isLoading = true;
                if (url != null) {
                  _urlController.text =
                      PreviewCacheHelper.stripCacheBuster(url.toString());
                }
              });
            },
            onProgressChanged: (controller, progress) {
              if (!mounted) return;
              setState(() => _loadProgress = progress / 100.0);
            },
            onLoadStop: (controller, url) {
              if (!mounted) return;
              setState(() => _isLoading = false);
            },
            onReceivedError: (controller, request, error) {
              if (!mounted) return;
              final err =
                  '[Сеть] ${error.description} (${error.type}) URL: ${request.url}';
              setState(() {
                _isLoading = false;
                if (!_consoleErrors.contains(err)) {
                  _consoleErrors.add(err);
                }
              });
              if (serverRunning) {
                Future.delayed(const Duration(seconds: 3), () {
                  if (mounted) {
                    _hardReload(clearCache: false);
                  }
                });
              }
            },
            onReceivedHttpError: (controller, request, errorResponse) {
              if (!mounted) return;
              final err =
                  '[HTTP ${errorResponse.statusCode}] ${errorResponse.reasonPhrase ?? 'Ошибка'} (${request.url})';
              if (!_consoleErrors.contains(err)) {
                setState(() => _consoleErrors.add(err));
              }
            },
            onConsoleMessage: (controller, consoleMessage) {
              if (!mounted) return;
              final msg = consoleMessage.message;
              final isError =
                  consoleMessage.messageLevel == ConsoleMessageLevel.ERROR ||
                      msg.contains('EXCEPTION CAUGHT') ||
                      msg.contains('Error:') ||
                      msg.contains('Uncaught') ||
                      msg.contains('TypeError:');
              if (isError && !_consoleErrors.contains(msg)) {
                setState(() => _consoleErrors.add(msg));
              }
            },
          )
        : Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.globe,
                    size: 40,
                    color: Colors.cyanAccent.withValues(alpha: 0.75),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.webPreviewNotSupported,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _openExternalBrowser,
                        icon: const Icon(LucideIcons.external_link, size: 14),
                        label: Text(l10n.openInExternalBrowser),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            MobileCompanionQrDialog.show(context, _urlController.text),
                        icon: const Icon(LucideIcons.qr_code, size: 14),
                        label: const Text('QR Preview'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );

    if (_deviceMode == _PreviewDeviceMode.desktop) {
      return Container(color: const Color(0xFF0A0D14), child: content);
    }

    final baseSize = _deviceMode == _PreviewDeviceMode.phone
        ? const Size(390, 844)
        : const Size(768, 1024);
    final logicalSize =
        _isLandscape ? Size(baseSize.height, baseSize.width) : baseSize;

    return Container(
      color: const Color(0xFF07090E),
      padding: const EdgeInsets.all(10),
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: Container(
            width: logicalSize.width + 20,
            height: logicalSize.height + 24,
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F2E),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black87, blurRadius: 20, spreadRadius: 2),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: logicalSize.width,
                height: logicalSize.height,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConsoleDrawer() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFF140D12),
        border: Border(
          top: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              children: [
                const Icon(LucideIcons.terminal, size: 12, color: Colors.redAccent),
                const SizedBox(width: 6),
                Text(
                  'Console (${_consoleErrors.length})',
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _consoleErrors.clear()),
                  child: Text(
                    'Clear',
                    style: GoogleFonts.inter(color: Colors.white54, fontSize: 10.5),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _consoleErrors.isEmpty
                ? Center(
                    child: Text(
                      'No console errors',
                      style: GoogleFonts.inter(color: Colors.white30, fontSize: 11),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    itemCount: _consoleErrors.length,
                    itemBuilder: (ctx, i) {
                      final err = _consoleErrors[i];
                      return InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: err));
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(
                            err,
                            style: GoogleFonts.jetBrainsMono(
                              color: Colors.redAccent.shade100,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomResizeBar(
    double maxW,
    double maxH,
    Offset offset,
    Size size,
  ) {
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E16),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          Text(
            '${size.width.round()}×${size.height.round()}',
            style: GoogleFonts.jetBrainsMono(color: Colors.white24, fontSize: 9.5),
          ),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) {
              setState(() {
                final curSize = _windowSize ?? size;
                final maxAllowedW = math.max(280.0, maxW - offset.dx - 8);
                final maxAllowedH = math.max(260.0, maxH - offset.dy - 8);
                _windowSize = Size(
                  (curSize.width + details.delta.dx).clamp(280.0, maxAllowedW),
                  (curSize.height + details.delta.dy).clamp(260.0, maxAllowedH),
                );
              });
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(
                LucideIcons.move_diagonal_2,
                size: 12,
                color: Colors.white38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
