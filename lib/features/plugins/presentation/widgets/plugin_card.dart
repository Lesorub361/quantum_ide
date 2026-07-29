import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/features/plugins/presentation/notifiers/plugin_manager_notifier.dart';

class PluginCard extends StatelessWidget {
  final Plugin plugin;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;
  final VoidCallback onEnable;
  final VoidCallback onDisable;

  const PluginCard({
    super.key,
    required this.plugin,
    required this.onInstall,
    required this.onUninstall,
    required this.onEnable,
    required this.onDisable,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _statusColor.withValues(alpha: 0.2)),
                  ),
                  child: Icon(_statusIcon, color: _statusColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              plugin.name,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          _buildStatusBadge(),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${plugin.author} · v${plugin.version}',
                        style: GoogleFonts.inter(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              plugin.description,
              style: GoogleFonts.inter(
                color: Colors.white60,
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (plugin.rating > 0) ...[
                  const Icon(LucideIcons.star, size: 11, color: Colors.amberAccent),
                  const SizedBox(width: 3),
                  Text(
                    plugin.rating.toString(),
                    style: GoogleFonts.inter(
                        color: Colors.amberAccent, fontSize: 10),
                  ),
                  const SizedBox(width: 12),
                ],
                if (plugin.downloads > 0) ...[
                  const Icon(LucideIcons.download, size: 11, color: Colors.white38),
                  const SizedBox(width: 3),
                  Text(
                    _formatDownloads(plugin.downloads),
                    style: GoogleFonts.inter(
                        color: Colors.white38, fontSize: 10),
                  ),
                  const SizedBox(width: 12),
                ],
                ...plugin.tags.map((tag) => Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tag,
                        style: GoogleFonts.inter(
                            color: Colors.white38, fontSize: 8.5),
                      ),
                    )),
                const Spacer(),
                _buildActionButtons(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    final Color badgeColor;
    final String label;

    switch (plugin.status) {
      case PluginStatus.available:
        badgeColor = Colors.white38;
        label = 'Available';
        break;
      case PluginStatus.installed:
        badgeColor = Colors.greenAccent;
        label = 'Installed';
        break;
      case PluginStatus.enabled:
        badgeColor = Colors.cyanAccent;
        label = 'Enabled';
        break;
      case PluginStatus.disabled:
        badgeColor = Colors.orangeAccent;
        label = 'Disabled';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: badgeColor.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
            color: badgeColor, fontSize: 8.5, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildActionButtons() {
    switch (plugin.status) {
      case PluginStatus.available:
        return _buildButton(
          label: 'Install',
          icon: LucideIcons.download,
          color: Colors.purpleAccent,
          onTap: onInstall,
        );
      case PluginStatus.installed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildButton(
              label: 'Enable',
              icon: LucideIcons.play,
              color: Colors.greenAccent,
              onTap: onEnable,
            ),
            const SizedBox(width: 6),
            _buildButton(
              label: 'Uninstall',
              icon: LucideIcons.trash_2,
              color: Colors.redAccent,
              onTap: onUninstall,
            ),
          ],
        );
      case PluginStatus.enabled:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildButton(
              label: 'Disable',
              icon: LucideIcons.pause,
              color: Colors.orangeAccent,
              onTap: onDisable,
            ),
            const SizedBox(width: 6),
            _buildButton(
              label: 'Uninstall',
              icon: LucideIcons.trash_2,
              color: Colors.redAccent,
              onTap: onUninstall,
            ),
          ],
        );
      case PluginStatus.disabled:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildButton(
              label: 'Enable',
              icon: LucideIcons.play,
              color: Colors.greenAccent,
              onTap: onEnable,
            ),
            const SizedBox(width: 6),
            _buildButton(
              label: 'Uninstall',
              icon: LucideIcons.trash_2,
              color: Colors.redAccent,
              onTap: onUninstall,
            ),
          ],
        );
    }
  }

  Widget _buildButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 10, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                    color: color, fontSize: 9, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDownloads(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return '$count';
  }

  IconData get _statusIcon {
    switch (plugin.status) {
      case PluginStatus.available:
        return LucideIcons.puzzle;
      case PluginStatus.installed:
        return LucideIcons.circle_check;
      case PluginStatus.enabled:
        return LucideIcons.zap;
      case PluginStatus.disabled:
        return LucideIcons.circle_x;
    }
  }

  Color get _statusColor {
    switch (plugin.status) {
      case PluginStatus.available:
        return Colors.purpleAccent;
      case PluginStatus.installed:
        return Colors.greenAccent;
      case PluginStatus.enabled:
        return Colors.cyanAccent;
      case PluginStatus.disabled:
        return Colors.orangeAccent;
    }
  }
}
