import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/adb_device_service.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/models/adb_device.dart';
import 'package:quantum_ide/models/project_model.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';
import 'package:quantum_ide/shared/widgets/device_manager_dialog.dart';

/// Running Devices / Device Mirroring Panel (Android Studio style)
///
/// Features:
/// - Real-time connected smartphone screen streaming (Mirroring)
/// - Interactive touch events (Tap, Swipe, Navigation keys) translated to ADB
/// - Hot Reload (⚡ r) and Hot Restart (⟳ R) controls
/// - One-click Build, Install & Launch APK directly on target device
/// - Live Logcat & Crash analysis
class RunningDevicesPanel extends ConsumerStatefulWidget {
  const RunningDevicesPanel({super.key});

  @override
  ConsumerState<RunningDevicesPanel> createState() => _RunningDevicesPanelState();
}

class _RunningDevicesPanelState extends ConsumerState<RunningDevicesPanel> {
  String? _screenshotPath;
  bool _isCapturing = false;
  bool _isActionRunning = false;
  String? _statusBanner;
  Offset? _lastTouchRipple;
  Timer? _rippleTimer;
  Size _deviceResolution = const Size(1080, 2400);
  bool _autoRefresh = false;
  Timer? _autoRefreshTimer;
  String? _logcatErrors;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchResolutionAndInitialScreen();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _rippleTimer?.cancel();
    super.dispose();
  }

  void _fetchResolutionAndInitialScreen() async {
    final adbState = ref.read(adbDeviceServiceProvider);
    final target = adbState.selectedDevice;
    if (target != null && target.isOnline) {
      await _detectDeviceResolution(target.id);
      _captureScreen(silent: true);
    }
  }

  Future<void> _detectDeviceResolution(String deviceId) async {
    try {
      final runtime = ref.read(runtimeServiceProvider);
      final output = await runtime.runCommand('adb -s $deviceId shell wm size 2>/dev/null || true');
      final match = RegExp(r'(\d+)x(\d+)').firstMatch(output);
      if (match != null) {
        final w = double.tryParse(match.group(1)!) ?? 1080;
        final h = double.tryParse(match.group(2)!) ?? 2400;
        if (mounted) {
          setState(() {
            _deviceResolution = Size(w, h);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _captureScreen({bool silent = false}) async {
    final adbState = ref.read(adbDeviceServiceProvider);
    final target = adbState.selectedDevice;
    if (target == null || !target.isOnline) return;

    if (!silent) {
      setState(() => _isCapturing = true);
    }

    try {
      final path = await ref.read(adbDeviceServiceProvider.notifier).takeScreenshot(deviceId: target.id);
      if (mounted) {
        setState(() {
          _screenshotPath = path;
          _isCapturing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          if (!silent) _statusBanner = 'Ошибка захвата: $e';
        });
      }
    }
  }

  void _handleTap(TapUpDetails details, BoxConstraints constraints, double renderWidth, double renderHeight) async {
    final adbState = ref.read(adbDeviceServiceProvider);
    final target = adbState.selectedDevice;
    if (target == null || !target.isOnline) return;

    final localX = details.localPosition.dx.clamp(0.0, renderWidth);
    final localY = details.localPosition.dy.clamp(0.0, renderHeight);

    // Map local tap to physical device coordinate
    final nativeX = ((localX / renderWidth) * _deviceResolution.width).round();
    final nativeY = ((localY / renderHeight) * _deviceResolution.height).round();

    // Trigger visual touch ripple indicator
    setState(() {
      _lastTouchRipple = Offset(localX, localY);
    });
    _rippleTimer?.cancel();
    _rippleTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _lastTouchRipple = null);
    });

    HapticFeedback.selectionClick();
    try {
      await ref.read(adbDeviceServiceProvider.notifier).sendTap(nativeX, nativeY, deviceId: target.id);
      // Wait slightly for Android frame buffer to render before pulling screen
      Future.delayed(const Duration(milliseconds: 380), () {
        if (mounted) _captureScreen(silent: true);
      });
    } catch (_) {}
  }

  void _sendKey(int keyCode, String keyName) async {
    final adbState = ref.read(adbDeviceServiceProvider);
    final target = adbState.selectedDevice;
    if (target == null || !target.isOnline) return;

    HapticFeedback.lightImpact();
    try {
      await ref.read(adbDeviceServiceProvider.notifier).sendKeyEvent(keyCode, deviceId: target.id);
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _captureScreen(silent: true);
      });
    } catch (e) {
      if (mounted) setState(() => _statusBanner = 'Ошибка $keyName: $e');
    }
  }

  void _showTextInputDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF13151D),
        title: Row(
          children: [
            const Icon(LucideIcons.keyboard, size: 18, color: Colors.cyanAccent),
            const SizedBox(width: 8),
            Text('Ввести текст на телефоне', style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.inter(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Введите текст или команду...',
            hintStyle: GoogleFonts.inter(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
          onSubmitted: (text) {
            Navigator.pop(ctx);
            if (text.isNotEmpty) {
              ref.read(adbDeviceServiceProvider.notifier).sendText(text).then((_) {
                Future.delayed(const Duration(milliseconds: 350), () => _captureScreen(silent: true));
              });
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.white60))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () {
              final text = controller.text;
              Navigator.pop(ctx);
              if (text.isNotEmpty) {
                ref.read(adbDeviceServiceProvider.notifier).sendText(text).then((_) {
                  Future.delayed(const Duration(milliseconds: 350), () => _captureScreen(silent: true));
                });
              }
            },
            child: const Text('Отправить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _sendHotReload() {
    ref.read(terminalTabsProvider.notifier).sendCommand('r');
    HapticFeedback.mediumImpact();
    setState(() => _statusBanner = '⚡ Hot Reload отправлен в рантайм');
    Future.delayed(const Duration(milliseconds: 800), () => _captureScreen(silent: true));
  }

  void _sendHotRestart() {
    ref.read(terminalTabsProvider.notifier).sendCommand('R');
    HapticFeedback.heavyImpact();
    setState(() => _statusBanner = '⟳ Hot Restart отправлен');
    Future.delayed(const Duration(milliseconds: 1500), () => _captureScreen(silent: true));
  }

  void _runOrInstallOnDevice() async {
    final adbState = ref.read(adbDeviceServiceProvider);
    final target = adbState.selectedDevice;
    if (target == null || !target.isOnline) {
      DeviceManagerDialog.show(context);
      return;
    }

    final workspace = ref.read(workspaceProvider);
    final projects = ref.read(projectServiceProvider);
    final currentProject = projects.firstWhere(
      (p) => p.path == workspace.currentPath,
      orElse: () => Project(
        id: '',
        name: 'App',
        path: workspace.currentPath ?? '',
        type: ProjectType.flutter,
        lastOpened: DateTime.now(),
      ),
    );

    setState(() {
      _isActionRunning = true;
      _statusBanner = '🚀 Запуск проекта на устройстве ${target.displayName}...';
    });

    try {
      // Send flutter run targeting the selected device in terminal
      ref.read(projectServiceProvider.notifier).runProject(currentProject, targetDevice: target.id);
      setState(() {
        _isActionRunning = false;
        _statusBanner = '▶ Проект запущен на ${target.displayName}! Экран обновится через 3 сек.';
      });
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) _captureScreen(silent: true);
      });
    } catch (e) {
      setState(() {
        _isActionRunning = false;
        _statusBanner = 'Ошибка запуска: $e';
      });
    }
  }

  void _showLogcat() async {
    final target = ref.read(adbDeviceServiceProvider).selectedDevice;
    if (target == null) return;

    setState(() => _isActionRunning = true);
    final logs = await ref.read(adbDeviceServiceProvider.notifier).getLogcatErrors(lines: 100, deviceId: target.id);
    if (!mounted) return;

    setState(() {
      _isActionRunning = false;
      _logcatErrors = logs;
    });

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF11131A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.bug, size: 18, color: Colors.redAccent),
                const SizedBox(width: 8),
                Text('Logcat (Ошибки и Краши)', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                const Spacer(),
                IconButton(icon: const Icon(LucideIcons.refresh_cw, size: 16, color: Colors.white70), onPressed: () => _showLogcat()),
                IconButton(icon: const Icon(LucideIcons.x, size: 18, color: Colors.white38), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                child: SelectableText(
                  logs.isEmpty ? 'Ошибок в logcat не обнаружено 👍' : logs,
                  style: GoogleFonts.jetBrainsMono(fontSize: 11, color: logs.isEmpty ? Colors.greenAccent : const Color(0xFFFF8B8B)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adbState = ref.watch(adbDeviceServiceProvider);
    final target = adbState.selectedDevice;

    return Container(
      color: const Color(0xFF0F1117),
      child: Column(
        children: [
          // ─── Верхняя панель управления (Android Studio Running Devices Toolbar) ───
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF151822),
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
            ),
            child: Row(
              children: [
                // Device badge
                InkWell(
                  onTap: () => DeviceManagerDialog.show(context),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: target != null && target.isOnline
                          ? const Color(0xFF10B981).withValues(alpha: 0.18)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: target != null && target.isOnline
                            ? const Color(0xFF10B981).withValues(alpha: 0.4)
                            : Colors.white.withValues(alpha: 0.1),
                        width: 0.6,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          target != null && target.isUsb ? LucideIcons.smartphone : LucideIcons.wifi,
                          size: 13,
                          color: target != null && target.isOnline ? const Color(0xFF34D399) : Colors.white60,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          target?.displayName ?? 'Подключить телефон',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: target != null && target.isOnline ? Colors.white : Colors.white60,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(LucideIcons.chevron_down, size: 11, color: Colors.white38),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Controls
                if (target != null && target.isOnline) ...[
                  _toolBtn(
                    icon: LucideIcons.play,
                    color: Colors.greenAccent,
                    tooltip: 'Запустить проект на телефоне',
                    onTap: _runOrInstallOnDevice,
                  ),
                  const SizedBox(width: 3),
                  _toolBtn(
                    icon: LucideIcons.zap,
                    color: Colors.yellowAccent,
                    tooltip: 'Hot Reload (r)',
                    onTap: _sendHotReload,
                  ),
                  const SizedBox(width: 3),
                  _toolBtn(
                    icon: LucideIcons.rotate_cw,
                    color: Colors.cyanAccent,
                    tooltip: 'Hot Restart (R)',
                    onTap: _sendHotRestart,
                  ),
                  const SizedBox(width: 3),
                  _toolBtn(
                    icon: LucideIcons.camera,
                    color: Colors.white70,
                    tooltip: 'Обновить экран (Скриншот)',
                    isLoading: _isCapturing,
                    onTap: () => _captureScreen(),
                  ),
                  const SizedBox(width: 3),
                  _toolBtn(
                    icon: LucideIcons.bug,
                    color: Colors.redAccent,
                    tooltip: 'Ошибки Logcat',
                    onTap: _showLogcat,
                  ),
                ],

                const Spacer(),

                // Device Manager shortcut
                Tooltip(
                  message: 'Менеджер устройств & Wi-Fi сопряжение',
                  child: InkWell(
                    onTap: () => DeviceManagerDialog.show(context),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(LucideIcons.settings_2, size: 15, color: Colors.white.withValues(alpha: 0.6)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Status banner
          if (_statusBanner != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: Colors.cyanAccent.withValues(alpha: 0.1),
              width: double.infinity,
              child: Row(
                children: [
                  const Icon(LucideIcons.info, size: 12, color: Colors.cyanAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _statusBanner!,
                      style: GoogleFonts.inter(fontSize: 10.5, color: Colors.cyanAccent),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _statusBanner = null),
                    child: const Icon(LucideIcons.x, size: 12, color: Colors.white54),
                  ),
                ],
              ),
            ),

          // ─── Тело экрана (Зеркалирование или Empty State) ───
          Expanded(
            child: target == null || !target.isOnline
                ? _buildDisconnectedState()
                : _buildMirroringScreen(target),
          ),
        ],
      ),
    );
  }

  Widget _toolBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: isLoading
                ? SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.5, color: color))
                : Icon(icon, size: 13, color: color),
          ),
        ),
      ),
    );
  }

  Widget _buildDisconnectedState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF06B6D4)],
                ),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.25), blurRadius: 16),
                ],
              ),
              child: const Icon(LucideIcons.smartphone, size: 32, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              'Running Devices (Зеркалирование)',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                'Подключите телефон по Wi-Fi (Wireless Debugging) или USB (OTG), чтобы запускать APK в один клик и тестировать интерфейс прямо в Quantum IDE.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white60, height: 1.4),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(LucideIcons.wifi, size: 15, color: Colors.white),
                  label: const Text('Подключить телефон (Wi-Fi / OTG)', style: TextStyle(fontSize: 12, color: Colors.white)),
                  onPressed: () => DeviceManagerDialog.show(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMirroringScreen(AdbDevice device) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate proportional scale inside container
        final availW = constraints.maxWidth - 32;
        final availH = constraints.maxHeight - 56; // Leave space for navigation keys
        final aspect = _deviceResolution.width / _deviceResolution.height;

        double targetW = availH * aspect;
        double targetH = availH;
        if (targetW > availW) {
          targetW = availW;
          targetH = availW / aspect;
        }

        targetW = targetW.clamp(160.0, 420.0);
        targetH = (targetW / aspect).clamp(240.0, constraints.maxHeight - 50);

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ─── Smartphone Bezel Frame ───
                Container(
                  width: targetW + 16,
                  height: targetH + 20,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E222D),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Camera Notch / Speaker
                      Container(
                        width: 32,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),

                      // Screen canvas
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            color: Colors.black,
                            child: LayoutBuilder(
                              builder: (ctx, screenConstraints) {
                                final sW = screenConstraints.maxWidth;
                                final sH = screenConstraints.maxHeight;

                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (details) => _handleTap(details, screenConstraints, sW, sH),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (_screenshotPath != null && File(_screenshotPath!).existsSync())
                                        Image.file(
                                          File(_screenshotPath!),
                                          fit: BoxFit.fill,
                                          filterQuality: FilterQuality.medium,
                                          errorBuilder: (_, __, ___) => _buildScreenPlaceholder(),
                                        )
                                      else
                                        _buildScreenPlaceholder(),

                                      // Touch ripple indicator
                                      if (_lastTouchRipple != null)
                                        Positioned(
                                          left: _lastTouchRipple!.dx - 18,
                                          top: _lastTouchRipple!.dy - 18,
                                          child: IgnorePointer(
                                            child: Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.cyanAccent.withValues(alpha: 0.4),
                                                border: Border.all(color: Colors.white, width: 2),
                                              ),
                                            ),
                                          ),
                                        ),

                                      // Spinner if capturing
                                      if (_isCapturing)
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                            child: const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // ─── Android Navigation Keys (Back, Home, Recents, Volume, Text) ───
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151822),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _navBtn(icon: LucideIcons.arrow_left, label: 'Назад', tooltip: 'Кнопка Назад (Key 4)', onTap: () => _sendKey(4, 'Назад')),
                      const SizedBox(width: 8),
                      _navBtn(icon: LucideIcons.circle, label: 'Домой', tooltip: 'Кнопка Домой (Key 3)', onTap: () => _sendKey(3, 'Домой')),
                      const SizedBox(width: 8),
                      _navBtn(icon: LucideIcons.square, label: 'Недавние', tooltip: 'Недавние приложения (Key 187)', onTap: () => _sendKey(187, 'Недавние')),
                      const SizedBox(width: 8),
                      Container(width: 1, height: 16, color: Colors.white24),
                      const SizedBox(width: 8),
                      _navBtn(icon: LucideIcons.volume_2, label: 'Vol+', tooltip: 'Громкость +', onTap: () => _sendKey(24, 'Громкость +')),
                      const SizedBox(width: 6),
                      _navBtn(icon: LucideIcons.volume_1, label: 'Vol-', tooltip: 'Громкость -', onTap: () => _sendKey(25, 'Громкость -')),
                      const SizedBox(width: 8),
                      Container(width: 1, height: 16, color: Colors.white24),
                      const SizedBox(width: 8),
                      _navBtn(icon: LucideIcons.keyboard, label: 'Текст', tooltip: 'Ввести текст с клавиатуры', onTap: _showTextInputDialog),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScreenPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.smartphone, size: 28, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 8),
          Text(
            'Нажмите «Обновить экран» или «Запустить»\nдля отображения интерфейса телефона',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white38),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            icon: const Icon(LucideIcons.camera, size: 12, color: Colors.cyanAccent),
            label: const Text('Захватить экран', style: TextStyle(fontSize: 11, color: Colors.cyanAccent)),
            onPressed: () => _captureScreen(),
          ),
        ],
      ),
    );
  }

  Widget _navBtn({
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: Colors.white70),
              const SizedBox(width: 3),
              Text(label, style: GoogleFonts.inter(fontSize: 10, color: Colors.white60)),
            ],
          ),
        ),
      ),
    );
  }
}
