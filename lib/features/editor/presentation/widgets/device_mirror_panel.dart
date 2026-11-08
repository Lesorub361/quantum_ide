import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/adb_device_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/models/adb_device.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';

enum _DevicePanelSubTab {
  screen,
  logcat,
}

class DeviceMirrorPanel extends ConsumerStatefulWidget {
  final bool isActive;
  const DeviceMirrorPanel({super.key, this.isActive = false});

  @override
  ConsumerState<DeviceMirrorPanel> createState() => _DeviceMirrorPanelState();
}

class _DeviceMirrorPanelState extends ConsumerState<DeviceMirrorPanel> {
  _DevicePanelSubTab _currentSubTab = _DevicePanelSubTab.screen;

  // Screen mirroring state
  bool _isStreaming = false;
  Uint8List? _currentFrame;
  Size _deviceDisplaySize = const Size(1080, 2400);
  bool _isLoadingFrame = false;
  Timer? _streamTimer;
  int _fpsIntervalMs = 500; // default 2 FPS for stability over local bridge

  // Pan gesture tracking for swipe
  Offset? _panStartPosition;
  Offset? _panCurrentPosition;

  // Logcat state
  final TextEditingController _logSearchController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();
  String _selectedLogLevel = 'ALL';
  List<String> _logLines = [];
  bool _isStreamingLogcat = false;
  bool _autoScroll = true;
  Timer? _logcatTimer;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initDevice();
        ref.read(adbDeviceServiceProvider.notifier).startPolling(interval: const Duration(seconds: 15));
      });
    }
  }

  @override
  void didUpdateWidget(DeviceMirrorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _initDevice();
      ref.read(adbDeviceServiceProvider.notifier).startPolling(interval: const Duration(seconds: 15));
    } else if (!widget.isActive && oldWidget.isActive) {
      try {
        ref.read(adbDeviceServiceProvider.notifier).stopPolling();
      } catch (_) {}
      _streamTimer?.cancel();
      _logcatTimer?.cancel();
    }
  }

  @override
  void dispose() {
    try {
      ref.read(adbDeviceServiceProvider.notifier).stopPolling();
    } catch (_) {}
    _streamTimer?.cancel();
    _logcatTimer?.cancel();
    _logSearchController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  Future<void> _initDevice() async {
    final adbService = ref.read(adbDeviceServiceProvider.notifier);
    await adbService.checkUsbHostSupport();
    await adbService.refreshDevices();

    final selected = ref.read(adbDeviceServiceProvider).selectedDevice;
    if (selected != null && selected.isOnline) {
      _updateDisplaySize(selected.id);
      _startStream();
    }
  }

  Future<void> _updateDisplaySize(String deviceId) async {
    final size = await ref.read(adbDeviceServiceProvider.notifier).getDeviceDisplaySize(deviceId: deviceId);
    if (mounted) {
      setState(() {
        _deviceDisplaySize = size;
      });
    }
  }

  void _startStream() {
    if (_isStreaming) return;
    setState(() {
      _isStreaming = true;
    });
    _fetchNextFrame();
    _streamTimer?.cancel();
    _streamTimer = Timer.periodic(Duration(milliseconds: _fpsIntervalMs), (_) {
      if (_isStreaming && mounted && _currentSubTab == _DevicePanelSubTab.screen) {
        _fetchNextFrame();
      }
    });
  }

  void _stopStream() {
    _streamTimer?.cancel();
    _streamTimer = null;
    if (mounted) {
      setState(() {
        _isStreaming = false;
      });
    }
  }

  Future<void> _fetchNextFrame() async {
    if (_isLoadingFrame) return;
    final selected = ref.read(adbDeviceServiceProvider).selectedDevice;
    if (selected == null || !selected.isOnline) return;

    _isLoadingFrame = true;
    try {
      final frame = await ref.read(adbDeviceServiceProvider.notifier).captureScreenFrame(deviceId: selected.id);
      if (mounted && frame != null && frame.isNotEmpty) {
        setState(() {
          _currentFrame = frame;
        });
      }
    } catch (_) {
    } finally {
      _isLoadingFrame = false;
    }
  }

  void _triggerImmediateRefresh() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted && _isStreaming) {
        _fetchNextFrame();
      }
    });
  }

  // Forward Touch Events
  void _handleTap(TapUpDetails details, BoxConstraints constraints) {
    final selected = ref.read(adbDeviceServiceProvider).selectedDevice;
    if (selected == null || !selected.isOnline || _currentFrame == null) return;

    final touchPoint = _mapScreenOffsetToDeviceCoordinates(details.localPosition, constraints);
    if (touchPoint != null) {
      ref.read(adbDeviceServiceProvider.notifier).sendTap(touchPoint.dx.toInt(), touchPoint.dy.toInt(), deviceId: selected.id);
      _triggerImmediateRefresh();
    }
  }

  void _handlePanStart(DragStartDetails details) {
    _panStartPosition = details.localPosition;
    _panCurrentPosition = details.localPosition;
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    _panCurrentPosition = details.localPosition;
  }

  void _handlePanEnd(DragEndDetails details, BoxConstraints constraints) {
    if (_panStartPosition == null || _panCurrentPosition == null) return;
    final selected = ref.read(adbDeviceServiceProvider).selectedDevice;
    if (selected == null || !selected.isOnline) return;

    final startPoint = _mapScreenOffsetToDeviceCoordinates(_panStartPosition!, constraints);
    final endPoint = _mapScreenOffsetToDeviceCoordinates(_panCurrentPosition!, constraints);

    if (startPoint != null && endPoint != null) {
      final dx = (endPoint.dx - startPoint.dx).abs();
      final dy = (endPoint.dy - startPoint.dy).abs();

      if (dx > 10 || dy > 10) {
        ref.read(adbDeviceServiceProvider.notifier).sendSwipe(
          startPoint.dx.toInt(),
          startPoint.dy.toInt(),
          endPoint.dx.toInt(),
          endPoint.dy.toInt(),
          durationMs: 250,
          deviceId: selected.id,
        );
        _triggerImmediateRefresh();
      }
    }

    _panStartPosition = null;
    _panCurrentPosition = null;
  }

  Offset? _mapScreenOffsetToDeviceCoordinates(Offset localOffset, BoxConstraints constraints) {
    final containerW = constraints.maxWidth;
    final containerH = constraints.maxHeight;
    final deviceAspect = _deviceDisplaySize.width / _deviceDisplaySize.height;
    final containerAspect = containerW / containerH;

    double renderedW;
    double renderedH;
    double offsetX;
    double offsetY;

    if (containerAspect > deviceAspect) {
      // Height is constrained, black bars on left/right
      renderedH = containerH;
      renderedW = containerH * deviceAspect;
      offsetX = (containerW - renderedW) / 2;
      offsetY = 0;
    } else {
      // Width is constrained, black bars on top/bottom
      renderedW = containerW;
      renderedH = containerW / deviceAspect;
      offsetX = 0;
      offsetY = (containerH - renderedH) / 2;
    }

    final relX = localOffset.dx - offsetX;
    final relY = localOffset.dy - offsetY;

    if (relX < 0 || relX > renderedW || relY < 0 || relY > renderedH) {
      return null;
    }

    final realX = (relX / renderedW) * _deviceDisplaySize.width;
    final realY = (relY / renderedH) * _deviceDisplaySize.height;

    return Offset(realX.clamp(0, _deviceDisplaySize.width), realY.clamp(0, _deviceDisplaySize.height));
  }

  // Key navigation
  void _sendKey(int keyCode) {
    final selected = ref.read(adbDeviceServiceProvider).selectedDevice;
    if (selected != null) {
      ref.read(adbDeviceServiceProvider.notifier).sendKeyEvent(keyCode, deviceId: selected.id);
      _triggerImmediateRefresh();
    }
  }

  // Text input dialog
  void _showTextInputDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        title: Row(
          children: [
            const Icon(LucideIcons.keyboard, color: Colors.cyanAccent, size: 20),
            const SizedBox(width: 8),
            Text('Ввод текста на телефон', style: GoogleFonts.firaCode(fontSize: 16, color: Colors.white)),
          ],
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: GoogleFonts.firaCode(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Введите текст для отправки...',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onSubmitted: (val) {
            Navigator.pop(ctx);
            if (val.isNotEmpty) {
              final selected = ref.read(adbDeviceServiceProvider).selectedDevice;
              if (selected != null) {
                ref.read(adbDeviceServiceProvider.notifier).sendText(val, deviceId: selected.id);
                _triggerImmediateRefresh();
              }
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
            onPressed: () {
              Navigator.pop(ctx);
              final val = textController.text;
              if (val.isNotEmpty) {
                final selected = ref.read(adbDeviceServiceProvider).selectedDevice;
                if (selected != null) {
                  ref.read(adbDeviceServiceProvider.notifier).sendText(val, deviceId: selected.id);
                  _triggerImmediateRefresh();
                }
              }
            },
            child: const Text('Отправить', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Install APK picker bottom sheet
  Future<void> _showInstallApkDialog() async {
    final workspaceState = ref.read(workspaceProvider);
    final apks = await ref.read(adbDeviceServiceProvider.notifier).findCompiledApks(workspacePath: workspaceState.currentPath);

    if (!mounted) return;

    if (apks.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1E2230),
          content: Text(
            'Скомпилированные APK файлы не найдены.\nСначала соберите проект через кнопку «Собрать APK» в терминале.',
            style: GoogleFonts.firaCode(color: Colors.orangeAccent),
          ),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141720),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.package, color: Colors.greenAccent, size: 20),
                const SizedBox(width: 8),
                Text('Установить APK на телефон', style: GoogleFonts.firaCode(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 12),
            Text('Выберите файл для установки через USB/ADB:', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: apks.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                itemBuilder: (c, idx) {
                  final apk = apks[idx];
                  final name = apk.split('/').last;
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    leading: const Icon(LucideIcons.file_box, color: Colors.cyanAccent, size: 20),
                    title: Text(name, style: GoogleFonts.firaCode(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(apk, style: const TextStyle(color: Colors.white38, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(LucideIcons.arrow_up_right, color: Colors.greenAccent, size: 18),
                    onTap: () async {
                      Navigator.pop(ctx);
                      _installApk(apk);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _installApk(String apkPath) async {
    final selected = ref.read(adbDeviceServiceProvider).selectedDevice;
    if (selected == null) return;

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        backgroundColor: const Color(0xFF1E2230),
        content: Row(
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent)),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Установка ${apkPath.split('/').last} на ${selected.displayTitle}...', style: GoogleFonts.firaCode(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
      ),
    );

    final res = await ref.read(adbDeviceServiceProvider.notifier).installAndRun(apkPath: apkPath, deviceId: selected.id);

    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          backgroundColor: res.contains('Success') ? const Color(0xFF14301E) : const Color(0xFF381616),
          content: Text(res, style: GoogleFonts.firaCode(color: res.contains('Success') ? Colors.greenAccent : Colors.redAccent, fontSize: 12)),
        ),
      );
      _triggerImmediateRefresh();
    }
  }

  // Logcat stream management
  void _startLogcatStream() {
    _logcatTimer?.cancel();
    setState(() {
      _isStreamingLogcat = true;
    });
    _fetchLogcat();
    _logcatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isStreamingLogcat && mounted && _currentSubTab == _DevicePanelSubTab.logcat) {
        _fetchLogcat();
      }
    });
  }

  void _stopLogcatStream() {
    _logcatTimer?.cancel();
    _logcatTimer = null;
    if (mounted) {
      setState(() {
        _isStreamingLogcat = false;
      });
    }
  }

  Future<void> _fetchLogcat() async {
    final selected = ref.read(adbDeviceServiceProvider).selectedDevice;
    if (selected == null || !selected.isOnline) return;

    final runtime = ref.read(runtimeServiceProvider);
    try {
      final levelFilter = _selectedLogLevel == 'ALL' ? '' : '*:$_selectedLogLevel';
      final cmd = 'adb -s ${selected.id} logcat -d -t 120 $levelFilter 2>/dev/null || true';
      final output = await runtime.runCommand(cmd);
      if (mounted && output.isNotEmpty) {
        final lines = output.split('\n');
        setState(() {
          _logLines = lines;
        });
        if (_autoScroll && _logScrollController.hasClients) {
          _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
        }
      }
    } catch (_) {}
  }

  void _clearLogcat() async {
    final selected = ref.read(adbDeviceServiceProvider).selectedDevice;
    if (selected != null) {
      await ref.read(runtimeServiceProvider).runCommand('adb -s ${selected.id} logcat -c 2>/dev/null || true');
      setState(() {
        _logLines = [];
      });
    }
  }

  // Wi-Fi dialog
  void _showWifiConnectDialog() {
    final ipController = TextEditingController(text: '192.168.1.');
    final portController = TextEditingController(text: '5555');
    final codeController = TextEditingController();
    bool isPairingMode = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF161922),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
          title: Row(
            children: [
              const Icon(LucideIcons.wifi, color: Colors.cyanAccent, size: 20),
              const SizedBox(width: 8),
              Text('Wi-Fi подключение ADB', style: GoogleFonts.firaCode(fontSize: 16, color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Прямое подключение'),
                    selected: !isPairingMode,
                    onSelected: (v) => setDlgState(() => isPairingMode = !v),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Сопряжение (Android 11+)'),
                    selected: isPairingMode,
                    onSelected: (v) => setDlgState(() => isPairingMode = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: ipController,
                      style: GoogleFonts.firaCode(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(labelText: 'IP адрес', hintText: '192.168.1.105'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: portController,
                      style: GoogleFonts.firaCode(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(labelText: 'Порт', hintText: '5555'),
                    ),
                  ),
                ],
              ),
              if (isPairingMode) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: codeController,
                  style: GoogleFonts.firaCode(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(labelText: 'Код сопряжения (6 цифр)', hintText: '123456'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
              onPressed: () async {
                Navigator.pop(ctx);
                final target = '${ipController.text.trim()}:${portController.text.trim()}';
                final adb = ref.read(adbDeviceServiceProvider.notifier);
                String result;
                if (isPairingMode) {
                  result = await adb.pairWifi(target, codeController.text.trim());
                } else {
                  result = await adb.connectWifi(target);
                }
                if (mounted && context.mounted) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(backgroundColor: const Color(0xFF1E2230), content: Text(result, style: GoogleFonts.firaCode())),
                  );
                }
              },
              child: Text(isPairingMode ? 'Сопрячь' : 'Подключить', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AdbDeviceState>(adbDeviceServiceProvider, (prev, next) {
      final prevOnline = prev?.selectedDevice?.isOnline ?? false;
      final nextOnline = next.selectedDevice?.isOnline ?? false;
      if (!prevOnline && nextOnline && next.selectedDevice != null) {
        _updateDisplaySize(next.selectedDevice!.id);
        if (_currentSubTab == _DevicePanelSubTab.screen && !_isStreaming) {
          _startStream();
        }
      }
    });

    final adbState = ref.watch(adbDeviceServiceProvider);
    final selectedDevice = adbState.selectedDevice;

    return Container(
      color: const Color(0xFF090B12),
      child: Column(
        children: [
          // Subtabs and quick actions bar
          _buildTopBar(adbState, selectedDevice),

          // Main view: Screen or Logcat
          Expanded(
            child: selectedDevice == null
                ? _buildNoDeviceView(adbState)
                : (_currentSubTab == _DevicePanelSubTab.screen
                    ? _buildMirroringView(selectedDevice)
                    : _buildLogcatView(selectedDevice)),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(AdbDeviceState adbState, AdbDevice? selectedDevice) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F121C),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          // Subtab toggle: Screen / Logcat
          Container(
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSubTabButton(
                  title: 'Экран',
                  icon: LucideIcons.smartphone,
                  isSelected: _currentSubTab == _DevicePanelSubTab.screen,
                  onTap: () {
                    setState(() => _currentSubTab = _DevicePanelSubTab.screen);
                    if (!_isStreaming && selectedDevice != null && selectedDevice.isOnline) {
                      _startStream();
                    }
                  },
                ),
                _buildSubTabButton(
                  title: 'Logcat',
                  icon: LucideIcons.terminal,
                  isSelected: _currentSubTab == _DevicePanelSubTab.logcat,
                  onTap: () {
                    setState(() => _currentSubTab = _DevicePanelSubTab.logcat);
                    if (!_isStreamingLogcat && selectedDevice != null && selectedDevice.isOnline) {
                      _startLogcatStream();
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Device Selector Dropdown
          Expanded(
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<AdbDevice>(
                  isDense: true,
                  value: selectedDevice,
                  hint: Row(
                    children: [
                      Icon(LucideIcons.smartphone, size: 14, color: Colors.white.withValues(alpha: 0.4)),
                      const SizedBox(width: 6),
                      Text(
                        adbState.devices.isEmpty ? 'Нет подключенных устройств' : 'Выберите устройство',
                        style: GoogleFonts.firaCode(fontSize: 11, color: Colors.white60),
                      ),
                    ],
                  ),
                  dropdownColor: const Color(0xFF161924),
                  icon: const Icon(LucideIcons.chevron_down, size: 14, color: Colors.white54),
                  items: adbState.devices.map((device) {
                    return DropdownMenuItem<AdbDevice>(
                      value: device,
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: device.isOnline
                                  ? Colors.greenAccent
                                  : (device.isUnauthorized ? Colors.orangeAccent : Colors.redAccent),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            device.displayTitle,
                            style: GoogleFonts.firaCode(fontSize: 11, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (device.isUsbBridged) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.cyanAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text('USB', style: TextStyle(fontSize: 8, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (newDev) {
                    if (newDev != null) {
                      ref.read(adbDeviceServiceProvider.notifier).selectDevice(newDev);
                      _updateDisplaySize(newDev.id);
                      _triggerImmediateRefresh();
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Action buttons
          _buildActionButton(
            tooltip: 'Подключить USB (OTG кабель)',
            icon: LucideIcons.cable,
            color: Colors.greenAccent,
            onTap: () async {
              final msg = await ref.read(adbDeviceServiceProvider.notifier).connectUsbOtg();
              if (mounted) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(backgroundColor: const Color(0xFF1E2230), content: Text(msg, style: GoogleFonts.firaCode())),
                );
              }
            },
          ),
          _buildActionButton(
            tooltip: 'Подключить по Wi-Fi',
            icon: LucideIcons.wifi,
            color: Colors.cyanAccent,
            onTap: _showWifiConnectDialog,
          ),
          _buildActionButton(
            tooltip: 'Установить собранный APK на телефон',
            icon: LucideIcons.arrow_down_to_line,
            color: Colors.amberAccent,
            onTap: _showInstallApkDialog,
          ),
          _buildActionButton(
            tooltip: 'Починить и проверить ADB (Fix ADB)',
            icon: LucideIcons.wrench,
            color: Colors.purpleAccent,
            onTap: () async {
              final res = await ref.read(adbDeviceServiceProvider.notifier).fixAdbEnvironment();
              if (mounted) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(backgroundColor: const Color(0xFF1E2230), content: Text(res, style: GoogleFonts.firaCode())),
                );
              }
            },
          ),
          _buildActionButton(
            tooltip: 'Обновить список устройств',
            icon: LucideIcons.refresh_cw,
            color: Colors.white70,
            onTap: () => ref.read(adbDeviceServiceProvider.notifier).refreshDevices(),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.cyanAccent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isSelected ? Colors.cyanAccent : Colors.white60),
            const SizedBox(width: 4),
            Text(
              title,
              style: GoogleFonts.firaCode(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.cyanAccent : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 28,
      height: 28,
      margin: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
              ),
              child: Icon(icon, size: 14, color: color),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoDeviceView(AdbDeviceState adbState) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF121520),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.smartphone, color: Colors.cyanAccent, size: 28),
              ),
              const SizedBox(height: 14),
              Text(
                'Подключите телефон по проводу или Wi-Fi',
                textAlign: TextAlign.center,
                style: GoogleFonts.firaCode(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(
                'Для показа экрана (Mirroring), кликов и установки APK на второй телефон:\n\n'
                '1. Соедините телефоны кабелем Type-C (OTG).\n'
                '2. Подтвердите системное окно Android «Разрешить доступ к USB-устройству».\n'
                '3. На подключаемом телефоне включите «Отладку по USB» в настройках разработчика.\n'
                '4. Либо подключитесь по Wi-Fi к одной сети.',
                style: TextStyle(fontSize: 12, height: 1.45, color: Colors.white.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: const Icon(LucideIcons.cable, size: 16),
                    label: const Text('Подключить по USB (OTG)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: () async {
                      final msg = await ref.read(adbDeviceServiceProvider.notifier).connectUsbOtg();
                      if (mounted) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(backgroundColor: const Color(0xFF1E2230), content: Text(msg, style: GoogleFonts.firaCode())),
                        );
                      }
                    },
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent.withValues(alpha: 0.15),
                      foregroundColor: Colors.cyanAccent,
                      side: const BorderSide(color: Colors.cyanAccent),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: const Icon(LucideIcons.wifi, size: 16),
                    label: const Text('По Wi-Fi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: _showWifiConnectDialog,
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    icon: const Icon(LucideIcons.refresh_cw, size: 14),
                    label: const Text('Обновить', style: TextStyle(fontSize: 12)),
                    onPressed: () => ref.read(adbDeviceServiceProvider.notifier).refreshDevices(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMirroringView(AdbDevice device) {
    return Column(
      children: [
        // Screen viewport
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Captured frame or loading placeholder
                  if (_currentFrame != null)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) => _handleTap(details, constraints),
                      onPanStart: _handlePanStart,
                      onPanUpdate: _handlePanUpdate,
                      onPanEnd: (details) => _handlePanEnd(details, constraints),
                      child: Container(
                        color: Colors.black,
                        child: Center(
                          child: Image.memory(
                            _currentFrame!,
                            gaplessPlayback: true,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    )
                  else if (device.isUnauthorized)
                    Container(
                      color: Colors.black,
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.shield_alert, color: Colors.orangeAccent, size: 48),
                            const SizedBox(height: 14),
                            Text(
                              'Требуется подтверждение RSA-ключа',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.firaCode(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Разблокируйте экран второго телефона.\nВ появившемся диалоге Android отметьте «Всегда разрешать с этого компьютера» и нажмите ОК.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, height: 1.45, color: Colors.white.withValues(alpha: 0.7)),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orangeAccent,
                                foregroundColor: Colors.black,
                              ),
                              icon: const Icon(LucideIcons.refresh_cw, size: 14),
                              label: const Text('Проверить статус', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              onPressed: () => ref.read(adbDeviceServiceProvider.notifier).refreshDevices(),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (device.isOffline)
                    Container(
                      color: Colors.black,
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.circle_alert, color: Colors.redAccent, size: 48),
                            const SizedBox(height: 14),
                            Text(
                              'Телефон в статусе Оффлайн (${device.id})',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.firaCode(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Переподключите кабель Type-C или нажмите кнопку повторного подключения USB.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, height: 1.45, color: Colors.white.withValues(alpha: 0.7)),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.greenAccent,
                                foregroundColor: Colors.black,
                              ),
                              icon: const Icon(LucideIcons.cable, size: 14),
                              label: const Text('Переподключить USB', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              onPressed: () async {
                                final msg = await ref.read(adbDeviceServiceProvider.notifier).reconnectDevice(device.id);
                                if (mounted && context.mounted) {
                                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                    SnackBar(backgroundColor: const Color(0xFF1E2230), content: Text(msg, style: GoogleFonts.firaCode())),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Container(
                      color: Colors.black,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.cyanAccent, strokeWidth: 2)),
                            const SizedBox(height: 12),
                            Text(
                              'Захват экрана ${device.displayTitle}...',
                              style: GoogleFonts.firaCode(color: Colors.white60, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Overlay controls: Stream toggle & FPS selector
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            iconSize: 16,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(_isStreaming ? LucideIcons.pause : LucideIcons.play, color: _isStreaming ? Colors.greenAccent : Colors.white60),
                            tooltip: _isStreaming ? 'Пауза трансляции' : 'Возобновить трансляцию',
                            onPressed: () {
                              if (_isStreaming) {
                                _stopStream();
                              } else {
                                _startStream();
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            iconSize: 16,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(LucideIcons.camera, color: Colors.cyanAccent),
                            tooltip: 'Сделать скриншот в проект',
                            onPressed: () async {
                              try {
                                final path = await ref.read(adbDeviceServiceProvider.notifier).takeScreenshot(deviceId: device.id);
                                if (mounted && context.mounted) {
                                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                    SnackBar(backgroundColor: const Color(0xFF1E2230), content: Text('Скриншот сохранён:\n$path', style: GoogleFonts.firaCode())),
                                  );
                                }
                              } catch (e) {
                                if (mounted && context.mounted) {
                                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Ошибка скриншота: $e')));
                                }
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          PopupMenuButton<int>(
                            tooltip: 'Частота обновления',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            color: const Color(0xFF1A1D28),
                            child: Row(
                              children: [
                                Text('${(1000 / _fpsIntervalMs).round()} FPS', style: GoogleFonts.firaCode(fontSize: 10, color: Colors.white70)),
                                const Icon(LucideIcons.chevron_down, size: 12, color: Colors.white54),
                              ],
                            ),
                            itemBuilder: (c) => [
                              const PopupMenuItem(value: 200, child: Text('5 FPS (быстро)')),
                              const PopupMenuItem(value: 500, child: Text('2 FPS (стандарт)')),
                              const PopupMenuItem(value: 1000, child: Text('1 FPS (эконом)')),
                            ],
                            onSelected: (val) {
                              setState(() {
                                _fpsIntervalMs = val;
                              });
                              if (_isStreaming) {
                                _stopStream();
                                _startStream();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        // Virtual Navigation Bar
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF0C0E16),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavButton(
                tooltip: 'Назад (Back)',
                icon: LucideIcons.arrow_left,
                onTap: () => _sendKey(4),
              ),
              _buildNavButton(
                tooltip: 'Домой (Home)',
                icon: LucideIcons.circle,
                onTap: () => _sendKey(3),
              ),
              _buildNavButton(
                tooltip: 'Недавние приложения (Recents)',
                icon: LucideIcons.square,
                onTap: () => _sendKey(187),
              ),
              const VerticalDivider(width: 16, indent: 8, endIndent: 8, color: Colors.white12),
              _buildNavButton(
                tooltip: 'Ввод текста',
                icon: LucideIcons.keyboard,
                color: Colors.cyanAccent,
                onTap: _showTextInputDialog,
              ),
              _buildNavButton(
                tooltip: 'Громкость -',
                icon: LucideIcons.volume_1,
                onTap: () => _sendKey(25),
              ),
              _buildNavButton(
                tooltip: 'Громкость +',
                icon: LucideIcons.volume_2,
                onTap: () => _sendKey(24),
              ),
              _buildNavButton(
                tooltip: 'Питание (Вкл/Выкл экран)',
                icon: LucideIcons.power,
                color: Colors.redAccent,
                onTap: () => _sendKey(26),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavButton({
    required String tooltip,
    required IconData icon,
    Color color = Colors.white70,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Widget _buildLogcatView(AdbDevice device) {
    final search = _logSearchController.text.toLowerCase().trim();
    final filteredLines = _logLines.where((l) {
      if (search.isNotEmpty && !l.toLowerCase().contains(search)) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Logcat control toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0F121C),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
          ),
          child: Row(
            children: [
              // Search input
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller: _logSearchController,
                    style: GoogleFonts.firaCode(fontSize: 11, color: Colors.white),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      prefixIcon: const Icon(LucideIcons.search, size: 13, color: Colors.white38),
                      hintText: 'Фильтр по тексту, тегу или PID...',
                      hintStyle: const TextStyle(fontSize: 11, color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Level dropdown
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isDense: true,
                    value: _selectedLogLevel,
                    dropdownColor: const Color(0xFF161924),
                    style: GoogleFonts.firaCode(fontSize: 11, color: Colors.white),
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('Все уровни')),
                      DropdownMenuItem(value: 'E', child: Text('Ошибки (E)')),
                      DropdownMenuItem(value: 'W', child: Text('Предупреждения (W)')),
                      DropdownMenuItem(value: 'I', child: Text('Инфо (I)')),
                      DropdownMenuItem(value: 'D', child: Text('Debug (D)')),
                    ],
                    onChanged: (lvl) {
                      if (lvl != null) {
                        setState(() {
                          _selectedLogLevel = lvl;
                        });
                        _fetchLogcat();
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Play / Pause stream
              _buildActionButton(
                tooltip: _isStreamingLogcat ? 'Остановить live-поток' : 'Запустить live-поток',
                icon: _isStreamingLogcat ? LucideIcons.pause : LucideIcons.play,
                color: _isStreamingLogcat ? Colors.greenAccent : Colors.white60,
                onTap: () {
                  if (_isStreamingLogcat) {
                    _stopLogcatStream();
                  } else {
                    _startLogcatStream();
                  }
                },
              ),
              _buildActionButton(
                tooltip: 'Очистить логи устройства (adb logcat -c)',
                icon: LucideIcons.trash_2,
                color: Colors.redAccent,
                onTap: _clearLogcat,
              ),
              _buildActionButton(
                tooltip: 'Скопировать все логи',
                icon: LucideIcons.copy,
                color: Colors.cyanAccent,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: filteredLines.join('\n')));
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('Логи скопированы в буфер обмена')),
                  );
                },
              ),
            ],
          ),
        ),

        // Log content
        Expanded(
          child: filteredLines.isEmpty
              ? Center(
                  child: Text(
                    _isStreamingLogcat ? 'Ожидание новых логов...' : 'Логи пусты. Нажмите Play для старта.',
                    style: GoogleFonts.firaCode(color: Colors.white38, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  controller: _logScrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  itemCount: filteredLines.length,
                  itemBuilder: (ctx, idx) {
                    final line = filteredLines[idx];
                    Color lineColor = Colors.white70;
                    if (line.contains(' E ') || line.contains(' E/') || line.contains('FATAL') || line.contains('Exception')) {
                      lineColor = Colors.redAccent;
                    } else if (line.contains(' W ') || line.contains(' W/')) {
                      lineColor = Colors.amberAccent;
                    } else if (line.contains(' I ') || line.contains(' I/')) {
                      lineColor = Colors.cyanAccent;
                    }

                    return SelectableText(
                      line,
                      style: GoogleFonts.firaCode(fontSize: 10.5, color: lineColor, height: 1.3),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
