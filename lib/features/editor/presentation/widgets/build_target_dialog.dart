import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/build_resource_optimizer.dart';

class BuildTargetDialog extends StatefulWidget {
  final Function(String command, String displayCmd, BuildTargetType target)
      onStartBuild;
  final String? initialProjectName;

  const BuildTargetDialog({
    super.key,
    required this.onStartBuild,
    this.initialProjectName,
  });

  @override
  State<BuildTargetDialog> createState() => _BuildTargetDialogState();
}

class _BuildTargetDialogState extends State<BuildTargetDialog> {
  late SystemHardwareProfile _hardware;
  BuildTargetType _selectedTarget = BuildTargetType.arm64;
  BuildPerformanceMode _selectedMode = BuildPerformanceMode.balanced;
  late int _workers;

  @override
  void initState() {
    super.initState();
    _hardware = BuildResourceOptimizer.detectHardware();
    final config = BuildResourceOptimizer.computeResourceConfig(
      hardware: _hardware,
      mode: _selectedMode,
    );
    _workers = config.workers;
  }

  void _onModeChanged(BuildPerformanceMode mode) {
    setState(() {
      _selectedMode = mode;
      final config = BuildResourceOptimizer.computeResourceConfig(
        hardware: _hardware,
        mode: mode,
      );
      _workers = config.workers;
    });
  }

  void _triggerBuild() {
    final cmd = BuildResourceOptimizer.generateBuildCommand(
      target: _selectedTarget,
      mode: _selectedMode,
      customWorkers: _workers,
    );
    final displayCmd = BuildResourceOptimizer.getDisplayCommand(_selectedTarget);

    Navigator.of(context).pop();
    widget.onStartBuild(cmd, displayCmd, _selectedTarget);
  }

  @override
  Widget build(BuildContext context) {
    final config = BuildResourceOptimizer.computeResourceConfig(
      hardware: _hardware,
      mode: _selectedMode,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  LucideIcons.hammer,
                  size: 20,
                  color: Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Выбор сборки и ресурсов',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.initialProjectName != null
                          ? 'Проект: ${widget.initialProjectName}'
                          : 'Настройка целевой архитектуры и оптимизация ядер',
                      style: GoogleFonts.inter(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 18, color: Colors.white60),
                onPressed: () => Navigator.of(context).pop(),
                splashRadius: 18,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Hardware & Auto-Tuning Summary Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF1E2230),
                  Color(0xFF181B26),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.cyanAccent.withValues(alpha: 0.22),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      LucideIcons.cpu,
                      size: 16,
                      color: Colors.cyanAccent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Аппаратные ресурсы устройства',
                      style: GoogleFonts.inter(
                        color: Colors.cyanAccent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${_hardware.cpuCores} ядер CPU',
                        style: GoogleFonts.jetBrainsMono(
                          color: Colors.cyanAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(
                        LucideIcons.memory_stick,
                        'Память',
                        '${_hardware.availableRamMb} MB свободно / ${_hardware.totalRamMb} MB',
                      ),
                    ),
                    Expanded(
                      child: _buildStatItem(
                        LucideIcons.zap,
                        'Воркеров Gradle',
                        '$_workers из ${_hardware.cpuCores} ядер (JVM ${config.jvmHeapMb}M)',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Performance Mode Selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Профиль производительности:',
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _workers == 4 ? 'Сборка в 4x быстрее' : '$_workers воркеров',
                style: GoogleFonts.inter(
                  color: const Color(0xFFF59E0B),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildModeChip(
                  mode: BuildPerformanceMode.turbo,
                  title: 'Турбо (Макс)',
                  icon: LucideIcons.flame,
                  color: Colors.deepOrangeAccent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildModeChip(
                  mode: BuildPerformanceMode.balanced,
                  title: 'Авто (Баланс)',
                  icon: LucideIcons.check_check,
                  color: const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildModeChip(
                  mode: BuildPerformanceMode.safe,
                  title: 'Эко (2 ядра)',
                  icon: LucideIcons.shield,
                  color: Colors.blueAccent,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Target Selection Label
          Text(
            'Целевая архитектура и формат:',
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),

          // Target list
          _buildTargetCard(
            target: BuildTargetType.arm64,
            title: 'APK ARM64 (64-бит)',
            subtitle:
                'Самый быстрый (в 4-5 раз быстрее). Рекомендуется для вашего планшета и 99% современных Android.',
            badge: '⚡ Рекомендуется · 4 мин',
            badgeColor: Colors.amber,
            icon: LucideIcons.zap,
          ),
          const SizedBox(height: 8),
          _buildTargetCard(
            target: BuildTargetType.arm32,
            title: 'APK ARMv7 (32-бит)',
            subtitle:
                'Для старых смартфонов и устройств с 32-битной архитектурой.',
            badge: '32-bit ARM',
            badgeColor: Colors.blueAccent,
            icon: LucideIcons.smartphone,
          ),
          const SizedBox(height: 8),
          _buildTargetCard(
            target: BuildTargetType.x86_64,
            title: 'APK x86_64',
            subtitle:
                'Для эмуляторов Android Studio, Genymotion и x86 планшетов/ПК.',
            badge: 'Эмуляторы',
            badgeColor: Colors.cyanAccent,
            icon: LucideIcons.monitor,
          ),
          const SizedBox(height: 8),
          _buildTargetCard(
            target: BuildTargetType.split,
            title: 'Split APKs (все архитектуры)',
            subtitle:
                'Генерирует 3 раздельных APK (arm64, armv7, x86_64) в корне проекта.',
            badge: '3 файла APK',
            badgeColor: Colors.orangeAccent,
            icon: LucideIcons.boxes,
          ),
          const SizedBox(height: 8),
          _buildTargetCard(
            target: BuildTargetType.aab,
            title: 'AppBundle (AAB)',
            subtitle:
                'Бандл для публикации в Google Play Store. Содержит библиотеки всех платформ.',
            badge: 'Google Play',
            badgeColor: Colors.purpleAccent,
            icon: LucideIcons.rocket,
          ),
          const SizedBox(height: 8),
          _buildTargetCard(
            target: BuildTargetType.debug,
            title: 'Debug APK (ARM64)',
            subtitle:
                'Отладочная сборка для быстрой проверки с горячей перезагрузкой.',
            badge: 'Отладка',
            badgeColor: Colors.yellow,
            icon: LucideIcons.bug,
          ),

          const SizedBox(height: 16),

          // Command Preview
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.terminal, size: 14, color: Colors.white54),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    BuildResourceOptimizer.getDisplayCommand(_selectedTarget),
                    style: GoogleFonts.jetBrainsMono(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(
                      ClipboardData(
                        text: BuildResourceOptimizer.generateBuildCommand(
                          target: _selectedTarget,
                          mode: _selectedMode,
                          customWorkers: _workers,
                        ),
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Команда скопирована в буфер'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(LucideIcons.copy, size: 14, color: Colors.white60),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Отмена',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _triggerBuild,
                  icon: const Icon(LucideIcons.play, size: 16),
                  label: Text(
                    'Запустить сборку',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: Colors.white54),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 10.5),
              ),
              Text(
                value,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeChip({
    required BuildPerformanceMode mode,
    required String title,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedMode == mode;
    return InkWell(
      onTap: () => _onModeChanged(mode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? color
                : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: isSelected ? color : Colors.white60),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  color: isSelected ? color : Colors.white70,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetCard({
    required BuildTargetType target,
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
    required IconData icon,
  }) {
    final isSelected = _selectedTarget == target;

    return InkWell(
      onTap: () => setState(() => _selectedTarget = target),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
              : const Color(0xFF141720),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF59E0B).withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.06),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 16,
                color: isSelected ? const Color(0xFFF59E0B) : Colors.white70,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: badgeColor.withValues(alpha: 0.3),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          badge,
                          style: GoogleFonts.inter(
                            color: badgeColor,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected
                  ? LucideIcons.circle_dot
                  : LucideIcons.circle,
              size: 16,
              color: isSelected ? const Color(0xFFF59E0B) : Colors.white24,
            ),
          ],
        ),
      ),
    );
  }
}
