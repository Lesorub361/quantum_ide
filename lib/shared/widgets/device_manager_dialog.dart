import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/adb_device_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/utils/adaptive_dialog_helper.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/models/adb_device.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';

class DeviceManagerDialog extends ConsumerStatefulWidget {
  const DeviceManagerDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await AdaptiveDialogHelper.showAdaptiveSheet(
      context: context,
      desktopMaxWidth: 680,
      desktopMaxHeight: 640,
      backgroundColor: const Color(0xFF13151D),
      builder: (context) => const DeviceManagerDialog(),
    );
  }

  @override
  ConsumerState<DeviceManagerDialog> createState() => _DeviceManagerDialogState();
}

class _DeviceManagerDialogState extends ConsumerState<DeviceManagerDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _wifiConnectController = TextEditingController();
  final TextEditingController _wifiPairHostController = TextEditingController();
  final TextEditingController _wifiPairCodeController = TextEditingController();
  String? _statusBannerText;
  bool _isActionRunning = false;
  String? _lastScreenshotPath;
  String? _lastLogcatSnippet;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(adbDeviceServiceProvider.notifier).refreshDevices();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _wifiConnectController.dispose();
    _wifiPairHostController.dispose();
    _wifiPairCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adbState = ref.watch(adbDeviceServiceProvider);
    final adbService = ref.read(adbDeviceServiceProvider.notifier);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF06B6D4)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(LucideIcons.smartphone, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Менеджер устройств & Тестирование',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Подключение второго телефона по USB (OTG) / Wi-Fi',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: adbState.isChecking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                      )
                    : const Icon(LucideIcons.refresh_cw, size: 18, color: Colors.white70),
                tooltip: 'Обновить устройства',
                onPressed: adbState.isChecking ? null : () => adbService.refreshDevices(),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 18, color: Colors.white38),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Tabs
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(8),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(
                  iconMargin: EdgeInsets.zero,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.cable, size: 15),
                      SizedBox(width: 6),
                      Text('USB (OTG) & Список'),
                    ],
                  ),
                ),
                Tab(
                  iconMargin: EdgeInsets.zero,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.wifi, size: 15),
                      SizedBox(width: 6),
                      Text('Wi-Fi ADB'),
                    ],
                  ),
                ),
                Tab(
                  iconMargin: EdgeInsets.zero,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.bot, size: 15),
                      SizedBox(width: 6),
                      Text('ИИ Тест-лаборатория'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Status message if action executed
          if (_statusBannerText != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _statusBannerText!.contains('✅')
                    ? Colors.greenAccent.withValues(alpha: 0.15)
                    : (_statusBannerText!.toLowerCase().contains('ошибк') ||
                            _statusBannerText!.contains('protocol fault') ||
                            _statusBannerText!.contains('Сбой'))
                        ? Colors.redAccent.withValues(alpha: 0.15)
                        : Colors.blueAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _statusBannerText!.contains('✅')
                      ? Colors.greenAccent.withValues(alpha: 0.3)
                      : (_statusBannerText!.toLowerCase().contains('ошибк') ||
                              _statusBannerText!.contains('protocol fault') ||
                              _statusBannerText!.contains('Сбой'))
                          ? Colors.redAccent.withValues(alpha: 0.35)
                          : Colors.blueAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _statusBannerText!.contains('✅')
                        ? LucideIcons.circle_check
                        : (_statusBannerText!.toLowerCase().contains('ошибк') ||
                                _statusBannerText!.contains('protocol fault') ||
                                _statusBannerText!.contains('Сбой'))
                            ? LucideIcons.circle_alert
                            : LucideIcons.info,
                    size: 16,
                    color: _statusBannerText!.contains('✅')
                        ? Colors.greenAccent
                        : (_statusBannerText!.toLowerCase().contains('ошибк') ||
                                _statusBannerText!.contains('protocol fault') ||
                                _statusBannerText!.contains('Сбой'))
                            ? Colors.redAccent
                            : Colors.cyanAccent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          _statusBannerText!,
                          style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white, height: 1.35),
                        ),
                        if (_statusBannerText!.contains('protocol fault') ||
                            _statusBannerText!.contains('Сбой') ||
                            _statusBannerText!.contains('VPN')) ...[
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () async {
                              setState(() => _statusBannerText = 'Перезапуск ADB сервера...');
                              final res = await adbService.restartServer();
                              setState(() => _statusBannerText = res);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.amberAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(LucideIcons.refresh_cw, size: 12, color: Colors.amberAccent),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Перезапустить ADB сервер сейчас',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.amberAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 14, color: Colors.white54),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() => _statusBannerText = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Tab content
          Flexible(
            child: SizedBox(
              height: 380,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDevicesTab(adbState, adbService),
                  _buildWifiTab(adbService),
                  _buildAiTestingTab(adbState),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── TAB 1: Devices list & OTG Status ──────────────────────────────────────

  Widget _buildDevicesTab(AdbDeviceState adbState, AdbDeviceService adbService) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        // USB Host OTG Support Banner
        _buildOtgSupportBanner(adbState),
        const SizedBox(height: 12),

        // Connected ADB devices
        Text(
          'Обнаруженные телефоны (${adbState.devices.length}):',
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70),
        ),
        const SizedBox(height: 8),

        if (adbState.devices.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              children: [
                const Icon(LucideIcons.smartphone, size: 36, color: Colors.white24),
                const SizedBox(height: 10),
                Text(
                  'Устройства не обнаружены',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  '1. Соедините телефоны кабелем Type-C ↔ Type-C.\n'
                  '2. На втором телефоне включите «Отладку по USB» в Настройках разработчика.\n'
                  '3. Подтвердите диалог «Разрешить отладку с этого устройства».\n'
                  '4. Для Oppo / Realme / OnePlus: включите «Подключение OTG» в настройках.',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white60, height: 1.4),
                ),
              ],
            ),
          ),
        ] else ...[
          ...adbState.devices.map((device) => _buildDeviceCard(device, adbState, adbService)),
        ],

        const SizedBox(height: 16),
        // Screenshot preview if taken
        if (_lastScreenshotPath != null && File(_lastScreenshotPath!).existsSync()) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.camera, size: 15, color: Colors.cyanAccent),
                    const SizedBox(width: 8),
                    Text(
                      'Скриншот с целевого устройства:',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 14, color: Colors.white38),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _lastScreenshotPath = null),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_lastScreenshotPath!),
                    height: 160,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Logcat snippet if retrieved
        if (_lastLogcatSnippet != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1117),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.triangle_alert, size: 15, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Text(
                      'Последние ошибки (Logcat *:E):',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.redAccent),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 14, color: Colors.white38),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _lastLogcatSnippet = null),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  _lastLogcatSnippet!,
                  style: GoogleFonts.firaCode(fontSize: 10, color: Colors.white70),
                  maxLines: 8,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Bottom utility actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: const Icon(LucideIcons.power, size: 15),
                label: Text('Перезапуск ADB', style: GoogleFonts.inter(fontSize: 12)),
                onPressed: () async {
                  setState(() => _statusBannerText = 'Перезапуск ADB сервера...');
                  final res = await adbService.restartServer();
                  setState(() => _statusBannerText = res);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: const Icon(LucideIcons.cable, size: 15),
                label: Text('Подключить USB OTG', style: GoogleFonts.inter(fontSize: 12)),
                onPressed: () async {
                  setState(() => _statusBannerText = 'Запрос USB-OTG и запуск моста ADB...');
                  final res = await adbService.connectUsbOtg();
                  setState(() => _statusBannerText = res);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildCompiledApksSection(adbState, adbService),
      ],
    );
  }

  Widget _buildCompiledApksSection(AdbDeviceState adbState, AdbDeviceService adbService) {
    final currentWs = ref.watch(workspaceProvider).currentPath;
    return FutureBuilder<List<String>>(
      future: adbService.findCompiledApks(workspacePath: currentWs),
      builder: (context, snapshot) {
        final apks = snapshot.data ?? const [];
        if (apks.isEmpty) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.package, size: 15, color: Colors.cyanAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Скомпилированные APK в проектах (${apks.length}):',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...apks.take(5).map((apkPath) {
                final shortPath = apkPath.replaceFirst('/root/projects/', '');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          shortPath,
                          style: GoogleFonts.firaCode(fontSize: 10, color: Colors.white70),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (adbState.selectedDevice != null)
                        _buildSmallActionButton(
                          icon: LucideIcons.smartphone,
                          label: 'На OTG/ADB',
                          color: Colors.greenAccent,
                          onTap: () async {
                            setState(() {
                              _isActionRunning = true;
                              _statusBannerText = 'Установка $shortPath на ${adbState.selectedDevice!.displayName}...';
                            });
                            final res = await adbService.installAndRun(
                              apkPath: apkPath,
                              deviceId: adbState.selectedDevice!.id,
                            );
                            setState(() {
                              _isActionRunning = false;
                              _statusBannerText = res;
                            });
                          },
                        ),
                      const SizedBox(width: 6),
                      _buildSmallActionButton(
                        icon: LucideIcons.download,
                        label: 'На этот телефон',
                        color: Colors.cyanAccent,
                        onTap: () async {
                          final res = await adbService.installApkOnHostPhone(apkPath);
                          setState(() => _statusBannerText = res);
                        },
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOtgSupportBanner(AdbDeviceState adbState) {
    final isSupported = adbState.isUsbHostSupported;
    final hasUsbDevices = adbState.rawUsbDevices.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSupported
            ? Colors.greenAccent.withValues(alpha: 0.08)
            : Colors.amberAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSupported
              ? Colors.greenAccent.withValues(alpha: 0.25)
              : Colors.amberAccent.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isSupported ? LucideIcons.circle_check_big : LucideIcons.circle_alert,
                size: 18,
                color: isSupported ? Colors.greenAccent : Colors.amberAccent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSupported
                          ? 'USB Host (OTG) поддерживается'
                          : 'USB Host (OTG) не обнаружен',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSupported ? Colors.greenAccent : Colors.amberAccent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isSupported
                          ? (hasUsbDevices
                              ? 'Физически подключено по Type-C: ${adbState.rawUsbDevices.length} устр.'
                              : 'Подключите второй телефон кабелем Type-C ↔ Type-C и включите «Отладку по USB».')
                          : 'Используйте вкладку «Wi-Fi ADB» для беспроводного подключения второго телефона.',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasUsbDevices) ...[
            const SizedBox(height: 8),
            ...adbState.rawUsbDevices.map((usb) {
              final mfg = (usb['manufacturer'] ?? '').toString().trim();
              final prod = (usb['product'] ?? '').toString().trim();
              final title = '$mfg $prod'.trim().isNotEmpty
                  ? '$mfg $prod'.trim()
                  : 'USB ${usb['vendorHex'] ?? usb['vendorId']}:${usb['productHex'] ?? usb['productId']}';
              final modeDesc = (usb['modeDescription'] ?? '').toString();
              final hasAdb = usb['hasAdbInterface'] == true;
              return Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                       LucideIcons.usb,
                      size: 14,
                      color: hasAdb ? Colors.cyanAccent : Colors.amberAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$title — $modeDesc',
                        style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceCard(AdbDevice device, AdbDeviceState adbState, AdbDeviceService adbService) {
    final isSelected = adbState.selectedDevice?.id == device.id;
    final statusColor = device.isOnline ? Colors.greenAccent : Colors.amberAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF2563EB).withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF3B82F6).withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (device.isUsb ? Colors.cyanAccent : Colors.purpleAccent).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  device.isUsb ? LucideIcons.cable : LucideIcons.wifi,
                  size: 18,
                  color: device.isUsb ? Colors.cyanAccent : Colors.purpleAccent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            device.displayName,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            device.status.labelRu,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: ${device.id} • ${device.connectionType.labelRu}${device.androidVersion != null ? " • ${device.androidVersion}" : ""}',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Активно',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                )
              else
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  onPressed: () => adbService.selectDevice(device),
                  child: Text('Выбрать', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Actions row for this device
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildSmallActionButton(
                icon: LucideIcons.play,
                label: 'Запустить проект',
                color: Colors.greenAccent,
                onTap: () => _installAndRunProject(device),
              ),
              _buildSmallActionButton(
                icon: LucideIcons.camera,
                label: 'Скриншот',
                color: Colors.cyanAccent,
                onTap: () => _takeScreenshot(device),
              ),
              _buildSmallActionButton(
                icon: LucideIcons.file_text,
                label: 'Ошибки (Logcat)',
                color: Colors.amberAccent,
                onTap: () => _fetchLogcat(device),
              ),
              if (device.isWifi)
                _buildSmallActionButton(
                  icon: LucideIcons.power_off,
                  label: 'Отключить',
                  color: Colors.redAccent,
                  onTap: () async {
                    final res = await adbService.disconnectWifi(device.id);
                    setState(() => _statusBannerText = res);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _isActionRunning ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: color),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TAB 2: Wi-Fi ADB (Wireless Debugging) ──────────────────────────────────

  Widget _buildWifiTab(AdbDeviceService adbService) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.purpleAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.wifi, size: 18, color: Colors.purpleAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Беспроводное подключение позволяет отлаживать и тестировать приложения без кабеля. Оба телефона должны быть в одной Wi-Fi сети (или первый телефон раздает точку доступа второму).',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.white70, height: 1.3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.shield_alert, size: 15, color: Colors.amberAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Внимание: если на телефоне включён VPN, он блокирует локальную сеть (LAN). Отключите VPN или включите в его настройках «Обход локальной сети» (Bypass LAN).',
                        style: GoogleFonts.inter(fontSize: 10.5, color: Colors.amberAccent, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Connect section
        Text(
          '1. Быстрое подключение по IP:порт',
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _wifiConnectController,
                style: GoogleFonts.firaCode(fontSize: 13, color: Colors.white),
                decoration: InputDecoration(
                  hintText: '192.168.1.15:5555',
                  hintStyle: GoogleFonts.firaCode(fontSize: 12, color: Colors.white38),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              ),
              icon: const Icon(LucideIcons.plug, size: 15),
              label: Text('Подключить', style: GoogleFonts.inter(fontSize: 12)),
              onPressed: () async {
                final res = await adbService.connectWifi(_wifiConnectController.text);
                setState(() => _statusBannerText = res);
              },
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Pairing section (Android 11+)
        Text(
          '2. Сопряжение по коду (Android 11+)',
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 4),
        Text(
          'На втором телефоне: Настройки ➔ Для разработчиков ➔ Беспроводная отладка ➔ «Подключить устройство с помощью кода сопряжения».',
          style: GoogleFonts.inter(fontSize: 11, color: Colors.white60),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _wifiPairHostController,
                style: GoogleFonts.firaCode(fontSize: 12, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'IP:порт (e.g. 192.168.1.15:37891)',
                  hintStyle: GoogleFonts.firaCode(fontSize: 11, color: Colors.white38),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _wifiPairCodeController,
                style: GoogleFonts.firaCode(fontSize: 12, color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Код (6 цифр)',
                  hintStyle: GoogleFonts.firaCode(fontSize: 11, color: Colors.white38),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              ),
              onPressed: () async {
                final res = await adbService.pairWifi(
                  _wifiPairHostController.text,
                  _wifiPairCodeController.text,
                );
                setState(() => _statusBannerText = res);
              },
              child: Text('Сопряжение', style: GoogleFonts.inter(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  // ─── TAB 3: AI Testing Lab ─────────────────────────────────────────────────

  Widget _buildAiTestingTab(AdbDeviceState adbState) {
    final hasDevice = adbState.selectedDevice != null;
    final deviceName = adbState.selectedDevice?.displayName ?? 'Телефон не выбран';

    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF3B82F6).withValues(alpha: 0.15),
                const Color(0xFF8B5CF6).withValues(alpha: 0.15),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.bot, size: 22, color: Colors.cyanAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Автономное ИИ-тестирование',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Цель: $deviceName (${hasDevice ? "Готов к тестам" : "Подключите телефон"})',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: hasDevice ? Colors.greenAccent : Colors.amberAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        _buildAiScenarioCard(
          icon: LucideIcons.layout_dashboard,
          title: 'Тест интерфейса и верстки (UI Audit)',
          description: 'ИИ снимет скриншот с экрана второго телефона, изучит дерево элементов, проверит кнопки и отсутствие переполнений (RenderFlex overflow).',
          buttonLabel: 'Запустить аудит UI',
          onTap: () => _launchAiScenario(
            'Подключись ко второму телефону, сними скриншот экрана (device_screenshot), проинспектируй элементы UI (device_inspect_ui) и проверь, нет ли визуальных дефектов.',
          ),
        ),
        const SizedBox(height: 10),

        _buildAiScenarioCard(
          icon: LucideIcons.bug,
          title: 'Поиск крашей и ошибок (Crash & Logcat)',
          description: 'ИИ запустит приложение на втором телефоне, прочитает системные логи крашей через logcat и автоматически исправит найденные ошибки в коде.',
          buttonLabel: 'Искать краши с ИИ',
          onTap: () => _launchAiScenario(
            'Собери APK проекта, установи на подключенный телефон, запусти и проверь logcat на наличие крашей и ошибок (device_get_logs). Если найдешь ошибку, исправь её в коде проекта.',
          ),
        ),
        const SizedBox(height: 10),

        _buildAiScenarioCard(
          icon: LucideIcons.hand,
          title: 'Сквозное тестирование сценариев (E2E Test)',
          description: 'ИИ будет нажимать кнопки, вводить тестовые данные в текстовые поля и проверять переходы между экранами.',
          buttonLabel: 'Запустить E2E сценарий',
          onTap: () => _launchAiScenario(
            'Проведи E2E тестирование приложения на подключенном смартфоне: протестируй основные экраны, понажимай кнопки навигации и проверь реакцию интерфейса.',
          ),
        ),
      ],
    );
  }

  Widget _buildAiScenarioCard({
    required IconData icon,
    required String title,
    required String description,
    required String buttonLabel,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.cyanAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white60, height: 1.3),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(LucideIcons.sparkles, size: 14),
              label: Text(buttonLabel, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: onTap,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Actions ───────────────────────────────────────────────────────────────

  void _launchAiScenario(String prompt) {
    Navigator.pop(context);
    // Send message to AI assistant
    ref.read(aiProvider.notifier).askAI(prompt);
    // Open right chat panel
    ref.read(rightChatPanelOpenProvider.notifier).state = true;
  }

  Future<void> _installAndRunProject(AdbDevice device) async {
    setState(() {
      _isActionRunning = true;
      _statusBannerText = 'Поиск / сборка APK и установка на ${device.displayName}...';
    });

    final currentWs = ref.read(workspaceProvider).currentPath;
    if (currentWs == null || currentWs.isEmpty) {
      setState(() {
        _isActionRunning = false;
        _statusBannerText = 'Рабочий проект не открыт';
      });
      return;
    }

    final candidates = [
      '$currentWs/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk',
      '$currentWs/build/app/outputs/flutter-apk/app-release.apk',
      '$currentWs/build/app/outputs/flutter-apk/app-debug.apk',
    ];

    String? targetApk;
    for (final c in candidates) {
      if (File(c).existsSync()) {
        targetApk = c;
        break;
      }
    }

    if (targetApk == null && File('$currentWs/pubspec.yaml').existsSync()) {
      setState(() {
        _statusBannerText = 'Сборка APK текущего проекта ($currentWs)...';
      });
      try {
        final runtime = ref.read(runtimeServiceProvider);
        await runtime.runCommand('cd "$currentWs" && flutter build apk --debug');
        for (final c in candidates) {
          if (File(c).existsSync()) {
            targetApk = c;
            break;
          }
        }
      } catch (e) {
        setState(() {
          _isActionRunning = false;
          _statusBannerText = 'Ошибка сборки APK: $e';
        });
        return;
      }
    }

    if (targetApk == null || !File(targetApk).existsSync()) {
      setState(() {
        _isActionRunning = false;
        _statusBannerText = 'APK файл не найден в $currentWs/build/. Скомпилируйте проект.';
      });
      return;
    }

    final pkg = await ref.read(adbDeviceServiceProvider.notifier).detectPackageNameForApk(targetApk);
    final res = await ref.read(adbDeviceServiceProvider.notifier).installAndRun(
          apkPath: targetApk,
          packageName: pkg,
          deviceId: device.id,
        );

    setState(() {
      _isActionRunning = false;
      _statusBannerText = 'Результат: $res';
    });
  }

  Future<void> _takeScreenshot(AdbDevice device) async {
    setState(() {
      _isActionRunning = true;
      _statusBannerText = 'Снятие скриншота с ${device.displayName}...';
    });

    try {
      final path = await ref.read(adbDeviceServiceProvider.notifier).takeScreenshot(deviceId: device.id);
      setState(() {
        _isActionRunning = false;
        _lastScreenshotPath = path;
        _statusBannerText = 'Скриншот успешно сохранен!';
      });
    } catch (e) {
      setState(() {
        _isActionRunning = false;
        _statusBannerText = 'Ошибка скриншота: $e';
      });
    }
  }

  Future<void> _fetchLogcat(AdbDevice device) async {
    setState(() {
      _isActionRunning = true;
      _statusBannerText = 'Загрузка логов с ${device.displayName}...';
    });

    final logs = await ref.read(adbDeviceServiceProvider.notifier).getLogcatErrors(deviceId: device.id);
    setState(() {
      _isActionRunning = false;
      _lastLogcatSnippet = logs.isNotEmpty ? logs : 'Ошибок в logcat не обнаружено!';
      _statusBannerText = 'Логи получены';
    });
  }
}
