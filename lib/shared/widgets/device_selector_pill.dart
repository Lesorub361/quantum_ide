import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/adb_device_service.dart';
import 'package:quantum_ide/shared/widgets/device_manager_dialog.dart';

class DeviceSelectorPill extends ConsumerWidget {
  final bool compact;

  const DeviceSelectorPill({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adbState = ref.watch(adbDeviceServiceProvider);
    final selected = adbState.selectedDevice;

    Color badgeColor;
    IconData icon;
    String label;

    if (selected != null) {
      icon = selected.isUsb ? LucideIcons.smartphone : LucideIcons.wifi;
      label = selected.displayName;
      badgeColor = selected.isOnline ? Colors.greenAccent : Colors.amberAccent;
    } else if (adbState.devices.isNotEmpty) {
      icon = LucideIcons.smartphone;
      label = 'Устройств: ${adbState.devices.length}';
      badgeColor = Colors.cyanAccent;
    } else {
      icon = LucideIcons.smartphone;
      label = compact ? 'Устройство' : 'Подключить телефон';
      badgeColor = Colors.white38;
    }

    return InkWell(
      onTap: () => DeviceManagerDialog.show(context),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: badgeColor),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compact ? 70 : 120),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
