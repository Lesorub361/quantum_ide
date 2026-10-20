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
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: badgeColor),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compact ? 80 : 120),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
