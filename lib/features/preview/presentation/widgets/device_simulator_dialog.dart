import 'dart:io';
import 'package:device_frame/device_frame.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

class DeviceOption {
  final String name;
  final String category;
  final DeviceInfo info;
  final String resolution;

  const DeviceOption({
    required this.name,
    required this.category,
    required this.info,
    required this.resolution,
  });
}

class DeviceSimulatorDialog extends StatefulWidget {
  final String? initialUrl;
  final String? initialHtmlContent;
  final String title;

  const DeviceSimulatorDialog({
    super.key,
    this.initialUrl,
    this.initialHtmlContent,
    this.title = 'Мульти-симулятор экранов',
  });

  static Future<void> show(
    BuildContext context, {
    String? url,
    String? htmlContent,
    String title = 'Мульти-симулятор экранов',
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => DeviceSimulatorDialog(
        initialUrl: url,
        initialHtmlContent: htmlContent,
        title: title,
      ),
    );
  }

  @override
  State<DeviceSimulatorDialog> createState() => _DeviceSimulatorDialogState();
}

class _DeviceSimulatorDialogState extends State<DeviceSimulatorDialog> {
  late final List<DeviceOption> _devices;
  late DeviceOption _selectedDevice;
  Orientation _orientation = Orientation.portrait;
  bool _showFrame = true;
  final bool _isDarkMode = true;
  double _zoomScale = 0.85;
  InAppWebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _devices = [
      // ─── Маленькие экраны (Компактные) ──────────────────────────
      DeviceOption(
        name: 'iPhone SE (3rd Gen)',
        category: 'Маленькие экраны',
        info: Devices.ios.iPhoneSE,
        resolution: '375 x 667',
      ),
      DeviceOption(
        name: 'iPhone 13 mini',
        category: 'Маленькие экраны',
        info: Devices.ios.iPhone13Mini,
        resolution: '375 x 812',
      ),
      DeviceOption(
        name: 'Android Compact (4.7")',
        category: 'Маленькие экраны',
        info: Devices.android.smallPhone,
        resolution: '360 x 640',
      ),

      // ─── Стандартные флагманы ──────────────────────────────────
      DeviceOption(
        name: 'iPhone 13 / 14 / 15',
        category: 'Стандартные смартфоны',
        info: Devices.ios.iPhone13,
        resolution: '390 x 844',
      ),
      DeviceOption(
        name: 'Samsung Galaxy S20',
        category: 'Стандартные смартфоны',
        info: Devices.android.samsungGalaxyS20,
        resolution: '360 x 800',
      ),
      DeviceOption(
        name: 'Android Standard (6.1")',
        category: 'Стандартные смартфоны',
        info: Devices.android.mediumPhone,
        resolution: '411 x 731',
      ),
      DeviceOption(
        name: 'OnePlus 8 Pro',
        category: 'Стандартные смартфоны',
        info: Devices.android.onePlus8Pro,
        resolution: '412 x 915',
      ),
      DeviceOption(
        name: 'Sony Xperia 1 II (21:9)',
        category: 'Стандартные смартфоны',
        info: Devices.android.sonyXperia1II,
        resolution: '384 x 854',
      ),

      // ─── Большие экраны (Max / Phablets) ──────────────────────
      DeviceOption(
        name: 'iPhone 13 Pro Max',
        category: 'Большие смартфоны / Max',
        info: Devices.ios.iPhone13ProMax,
        resolution: '428 x 926',
      ),
      DeviceOption(
        name: 'Galaxy Note 20 Ultra',
        category: 'Большие смартфоны / Max',
        info: Devices.android.samsungGalaxyNote20Ultra,
        resolution: '412 x 883',
      ),
      DeviceOption(
        name: 'Android Phablet (6.7")',
        category: 'Большие смартфоны / Max',
        info: Devices.android.bigPhone,
        resolution: '480 x 853',
      ),

      // ─── Планшеты и Foldables ─────────────────────────────────
      DeviceOption(
        name: 'iPad Pro 11"',
        category: 'Планшеты',
        info: Devices.ios.iPadPro11Inches,
        resolution: '834 x 1194',
      ),
      DeviceOption(
        name: 'iPad Air 4',
        category: 'Планшеты',
        info: Devices.ios.iPadAir4,
        resolution: '820 x 1180',
      ),
      DeviceOption(
        name: 'Android Tablet (10.5")',
        category: 'Планшеты',
        info: Devices.android.mediumTablet,
        resolution: '800 x 1280',
      ),
    ];

    _selectedDevice = _devices[0]; // Start with small screen by default to inspect compactness!
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      backgroundColor: const Color(0xFF0F111A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height * 0.95,
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: Container(
                  color: const Color(0xFF0A0C14),
                  child: InteractiveViewer(
                    minScale: 0.3,
                    maxScale: 2.5,
                    child: Center(
                      child: Transform.scale(
                        scale: _zoomScale,
                        child: DeviceFrame(
                          device: _selectedDevice.info,
                          orientation: _orientation,
                          isFrameVisible: _showFrame,
                          screen: Container(
                            color: _isDarkMode ? Colors.black : Colors.white,
                            child: _buildWebViewContent(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _buildBottomInfoBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141724),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.smartphone, color: Colors.cyanAccent, size: 18),
          ),
          const SizedBox(width: 10),
          // Device selector dropdown
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<DeviceOption>(
                value: _selectedDevice,
                isExpanded: true,
                dropdownColor: const Color(0xFF171B2B),
                borderRadius: BorderRadius.circular(12),
                icon: const Icon(LucideIcons.chevron_down, color: Colors.cyanAccent, size: 16),
                selectedItemBuilder: (ctx) {
                  return _devices.map((d) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${d.name} (${d.resolution})',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList();
                },
                items: _devices.map((d) {
                  final isCompact = d.category == 'Маленькие экраны';
                  return DropdownMenuItem<DeviceOption>(
                    value: d,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isCompact ? LucideIcons.smartphone_nfc : LucideIcons.smartphone,
                              color: isCompact ? Colors.amberAccent : Colors.cyanAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(d.name, style: const TextStyle(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(d.resolution, style: GoogleFonts.jetBrainsMono(color: Colors.white60, fontSize: 11)),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (newDevice) {
                  if (newDevice != null) {
                    setState(() {
                      _selectedDevice = newDevice;
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Orientation toggle
          IconButton(
            tooltip: _orientation == Orientation.portrait ? 'Повернуть в альбомный' : 'Повернуть в портретный',
            icon: Icon(
              _orientation == Orientation.portrait ? LucideIcons.screen_share : LucideIcons.rotate_ccw,
              color: Colors.white70,
              size: 18,
            ),
            onPressed: () {
              setState(() {
                _orientation = _orientation == Orientation.portrait
                    ? Orientation.landscape
                    : Orientation.portrait;
              });
            },
          ),
          // Frame toggle
          IconButton(
            tooltip: _showFrame ? 'Скрыть рамку корпуса' : 'Показать корпус устройства',
            icon: Icon(
              _showFrame ? LucideIcons.frame : LucideIcons.minimize,
              color: _showFrame ? Colors.cyanAccent : Colors.white38,
              size: 18,
            ),
            onPressed: () {
              setState(() {
                _showFrame = !_showFrame;
              });
            },
          ),
          // Close button
          IconButton(
            icon: const Icon(LucideIcons.x, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomInfoBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF141724),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                '${_selectedDevice.category} • ${_selectedDevice.resolution}',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
          // Zoom scale controls
          Row(
            children: [
              IconButton(
                icon: const Icon(LucideIcons.zoom_out, size: 14, color: Colors.white60),
                onPressed: () {
                  setState(() {
                    _zoomScale = (_zoomScale - 0.1).clamp(0.4, 1.5);
                  });
                },
              ),
              Text(
                '${(_zoomScale * 100).toInt()}%',
                style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(LucideIcons.zoom_in, size: 14, color: Colors.white60),
                onPressed: () {
                  setState(() {
                    _zoomScale = (_zoomScale + 0.1).clamp(0.4, 1.5);
                  });
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Обновить страницу',
                icon: const Icon(LucideIcons.rotate_cw, size: 14, color: Colors.white70),
                onPressed: () {
                  _webViewController?.reload();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebViewContent() {
    final url = widget.initialUrl ?? 'http://localhost:8080';
    final html = widget.initialHtmlContent;

    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      return InAppWebView(
        initialUrlRequest: html == null ? URLRequest(url: WebUri(url)) : null,
        initialData: html != null
            ? InAppWebViewInitialData(data: html, mimeType: 'text/html', encoding: 'utf-8')
            : null,
        onWebViewCreated: (c) => _webViewController = c,
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<VerticalDragGestureRecognizer>(() => VerticalDragGestureRecognizer()),
          Factory<HorizontalDragGestureRecognizer>(() => HorizontalDragGestureRecognizer()),
          Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
          Factory<PanGestureRecognizer>(() => PanGestureRecognizer()),
        },
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          useWideViewPort: true,
          loadWithOverviewMode: true,
          supportZoom: true,
          transparentBackground: true,
        ),
      );
    }

    return Center(
      child: Text(
        'Симуляция HTML/Веб\n$url',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70),
      ),
    );
  }
}
