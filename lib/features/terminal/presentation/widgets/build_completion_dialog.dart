import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:quantum_ide/core/services/android_app_installer_service.dart';
import 'package:quantum_ide/core/services/talker_service.dart';

class ApkFileEntry {
  final String path;
  final int size;

  const ApkFileEntry({required this.path, required this.size});
}

class ApkSizeBreakdown {
  final int totalBytes;
  final int nativeBytes;
  final int dexBytes;
  final int assetBytes;
  final int resBytes;
  final int otherBytes;
  final List<ApkFileEntry> topFiles;

  const ApkSizeBreakdown({
    required this.totalBytes,
    required this.nativeBytes,
    required this.dexBytes,
    required this.assetBytes,
    required this.resBytes,
    required this.otherBytes,
    required this.topFiles,
  });

  static ApkSizeBreakdown analyze(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      return const ApkSizeBreakdown(
        totalBytes: 0,
        nativeBytes: 0,
        dexBytes: 0,
        assetBytes: 0,
        resBytes: 0,
        otherBytes: 0,
        topFiles: [],
      );
    }

    final totalBytes = file.lengthSync();
    int nativeBytes = 0;
    int dexBytes = 0;
    int assetBytes = 0;
    int resBytes = 0;
    int otherBytes = 0;
    final entries = <ApkFileEntry>[];

    try {
      final inputStream = InputFileStream(filePath);
      final archive = ZipDecoder().decodeStream(inputStream);

      for (final f in archive.files) {
        final name = f.name;
        final size = f.size.toInt();
        entries.add(ApkFileEntry(path: name, size: size));

        if (name.startsWith('lib/')) {
          nativeBytes += size;
        } else if (name.endsWith('.dex')) {
          dexBytes += size;
        } else if (name.startsWith('assets/')) {
          assetBytes += size;
        } else if (name.startsWith('res/') ||
            name.contains('resources.arsc') ||
            name.contains('resources.pb')) {
          resBytes += size;
        } else {
          otherBytes += size;
        }
      }
      inputStream.close();
    } catch (e, st) {
      TalkerService.error('Failed to parse APK/AAB archive: $e', e, st);
    }

    entries.sort((a, b) => b.size.compareTo(a.size));
    final topFiles = entries.take(8).toList();

    return ApkSizeBreakdown(
      totalBytes: totalBytes,
      nativeBytes: nativeBytes,
      dexBytes: dexBytes,
      assetBytes: assetBytes,
      resBytes: resBytes,
      otherBytes: otherBytes,
      topFiles: topFiles,
    );
  }
}

class BuildCompletionDialog extends ConsumerStatefulWidget {
  final String artifactPath;
  final Duration? elapsed;

  const BuildCompletionDialog({
    super.key,
    required this.artifactPath,
    this.elapsed,
  });

  static Future<void> show(
    BuildContext context, {
    required String artifactPath,
    Duration? elapsed,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) =>
          BuildCompletionDialog(artifactPath: artifactPath, elapsed: elapsed),
    );
  }

  @override
  ConsumerState<BuildCompletionDialog> createState() =>
      _BuildCompletionDialogState();
}

class _BuildCompletionDialogState extends ConsumerState<BuildCompletionDialog> {
  late Future<ApkSizeBreakdown> _breakdownFuture;
  bool _isInstalling = false;
  String? _installStatus;

  @override
  void initState() {
    super.initState();
    _breakdownFuture = compute(ApkSizeBreakdown.analyze, widget.artifactPath);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m > 0) return '$mм $sс';
    return '$sс';
  }

  Future<void> _installApk() async {
    setState(() {
      _isInstalling = true;
      _installStatus = 'Установка APK...';
    });
    try {
      final installer = ref.read(androidAppInstallerServiceProvider);
      final result = await installer.installApk(widget.artifactPath);
      if (!mounted) return;
      setState(() {
        _isInstalling = false;
        _installStatus = result.success
            ? '✓ Успешно установлено'
            : 'Ошибка установки: ${result.message ?? "Неизвестно"}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInstalling = false;
        _installStatus = 'Ошибка: $e';
      });
    }
  }

  Future<void> _shareArtifact() async {
    try {
      await Share.shareXFiles([
        XFile(widget.artifactPath),
      ], text: 'Сборка QuantumIDE: ${p.basename(widget.artifactPath)}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось поделиться файлом: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAab = widget.artifactPath.endsWith('.aab');
    final fileName = p.basename(widget.artifactPath);
    final file = File(widget.artifactPath);
    final exists = file.existsSync();
    final fileSize = exists ? file.lengthSync() : 0;

    return Dialog(
      backgroundColor: const Color(0xFF0F121C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Icon(
                      isAab ? LucideIcons.package : LucideIcons.circle_check,
                      color: const Color(0xFF34D399),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAab
                              ? 'Google Play AppBundle готов'
                              : 'Сборка APK завершена',
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      LucideIcons.x,
                      size: 18,
                      color: Colors.white60,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // File stats pills
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _buildStatPill(
                    icon: LucideIcons.hard_drive,
                    label: 'Размер: ${_formatBytes(fileSize)}',
                    color: Colors.cyanAccent,
                  ),
                  if (widget.elapsed != null && widget.elapsed! > Duration.zero)
                    _buildStatPill(
                      icon: LucideIcons.timer,
                      label: 'Время: ${_formatDuration(widget.elapsed!)}',
                      color: Colors.amberAccent,
                    ),
                  _buildStatPill(
                    icon: isAab
                        ? LucideIcons.shield_check
                        : LucideIcons.smartphone,
                    label: isAab ? 'Play Store AAB' : 'Android APK',
                    color: isAab
                        ? const Color(0xFFA78BFA)
                        : const Color(0xFF34D399),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Path row with copy
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.folder,
                      size: 14,
                      color: Colors.white38,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.artifactPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: widget.artifactPath),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Путь скопирован в буфер'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          LucideIcons.copy,
                          size: 13,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_installStatus != null) ...[
                const SizedBox(height: 8),
                Text(
                  _installStatus!,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: _installStatus!.startsWith('✓')
                        ? const Color(0xFF34D399)
                        : Colors.amberAccent,
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Action buttons row
              Row(
                children: [
                  if (!isAab && Platform.isAndroid)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isInstalling ? null : _installApk,
                        icon: _isInstalling
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(LucideIcons.download, size: 15),
                        label: Text(
                          _isInstalling ? 'Установка...' : 'Установить APK',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  if (!isAab && Platform.isAndroid) const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _shareArtifact,
                      icon: const Icon(LucideIcons.share_2, size: 15),
                      label: Text(
                        'Поделиться',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // App Size Inspector Title
              Row(
                children: [
                  const Icon(
                    LucideIcons.chart_pie,
                    size: 14,
                    color: Color(0xFF818CF8),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Инспектор размера пакета (App Size Inspector)',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Size breakdown content
              Expanded(
                child: FutureBuilder<ApkSizeBreakdown>(
                  future: _breakdownFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF818CF8),
                              ),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Анализ состава архива...',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    if (snapshot.hasError || !snapshot.hasData) {
                      return Center(
                        child: Text(
                          'Не удалось проанализировать структуру пакета',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      );
                    }

                    final b = snapshot.data!;
                    final uncompressedTotal =
                        b.nativeBytes +
                        b.dexBytes +
                        b.assetBytes +
                        b.resBytes +
                        b.otherBytes;
                    final total = uncompressedTotal > 0 ? uncompressedTotal : 1;

                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Proportional colored bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              height: 12,
                              child: Row(
                                children: [
                                  if (b.nativeBytes > 0)
                                    Expanded(
                                      flex: (b.nativeBytes * 1000 ~/ total)
                                          .clamp(1, 1000),
                                      child: Container(
                                        color: const Color(0xFF6366F1),
                                      ),
                                    ),
                                  if (b.dexBytes > 0)
                                    Expanded(
                                      flex: (b.dexBytes * 1000 ~/ total).clamp(
                                        1,
                                        1000,
                                      ),
                                      child: Container(
                                        color: const Color(0xFF06B6D4),
                                      ),
                                    ),
                                  if (b.assetBytes > 0)
                                    Expanded(
                                      flex: (b.assetBytes * 1000 ~/ total)
                                          .clamp(1, 1000),
                                      child: Container(
                                        color: const Color(0xFFF59E0B),
                                      ),
                                    ),
                                  if (b.resBytes > 0)
                                    Expanded(
                                      flex: (b.resBytes * 1000 ~/ total).clamp(
                                        1,
                                        1000,
                                      ),
                                      child: Container(
                                        color: const Color(0xFF10B981),
                                      ),
                                    ),
                                  if (b.otherBytes > 0)
                                    Expanded(
                                      flex: (b.otherBytes * 1000 ~/ total)
                                          .clamp(1, 1000),
                                      child: Container(
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Breakdown categories
                          _buildCategoryRow(
                            'Нативные библиотеки (.so)',
                            b.nativeBytes,
                            total,
                            const Color(0xFF6366F1),
                            LucideIcons.cpu,
                          ),
                          _buildCategoryRow(
                            'Код DEX (байт-код)',
                            b.dexBytes,
                            total,
                            const Color(0xFF06B6D4),
                            LucideIcons.binary,
                          ),
                          _buildCategoryRow(
                            'Ассеты & AI модели',
                            b.assetBytes,
                            total,
                            const Color(0xFFF59E0B),
                            LucideIcons.boxes,
                          ),
                          _buildCategoryRow(
                            'Ресурсы (UI & картинки)',
                            b.resBytes,
                            total,
                            const Color(0xFF10B981),
                            LucideIcons.palette,
                          ),
                          _buildCategoryRow(
                            'Манифест и подпись',
                            b.otherBytes,
                            total,
                            const Color(0xFF64748B),
                            LucideIcons.file_text,
                          ),
                          const SizedBox(height: 14),

                          // Top heavy files
                          if (b.topFiles.isNotEmpty) ...[
                            Text(
                              'Самые крупные файлы внутри архива:',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 6),
                            for (final tf in b.topFiles)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2.5,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      LucideIcons.file,
                                      size: 12,
                                      color: Colors.white38,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        tf.path,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatBytes(tf.size),
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.amberAccent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 12),
                          ],

                          // Optimization recommendations
                          _buildOptimizationTips(b),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryRow(
    String title,
    int bytes,
    int total,
    Color color,
    IconData icon,
  ) {
    final pct = total > 0 ? (bytes / total * 100).toStringAsFixed(1) : '0.0';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 12, color: Colors.white54),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
            ),
          ),
          Text(
            '${_formatBytes(bytes)} ($pct%)',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptimizationTips(ApkSizeBreakdown b) {
    final tips = <String>[];
    if (b.nativeBytes > 30 * 1024 * 1024) {
      tips.add(
        'Разделите APK по ABI (`flutter build apk --split-per-abi`). Это уменьшит размер каждого APK на 50-65% за счёт исключения чужих процессоров.',
      );
    }
    if (b.dexBytes > 15 * 1024 * 1024) {
      tips.add(
        'Включите R8 минификацию (`minifyEnabled true`, `shrinkResources true`) в `build.gradle`, чтобы удалить неиспользуемый код плагинов.',
      );
    }
    if (b.assetBytes > 30 * 1024 * 1024) {
      tips.add(
        'Тяжёлые модели или ассеты обнаружены в assets/. Рекомендуется загружать нейросети по требованию или квантовать веса в INT8.',
      );
    }

    if (tips.isEmpty) {
      tips.add('Размер сборки находится в оптимальных пределах.');
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.lightbulb,
                size: 13,
                color: Color(0xFFA5B4FC),
              ),
              const SizedBox(width: 6),
              Text(
                'Советы по оптимизации размера:',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFC7D2FE),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $tip',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  height: 1.35,
                  color: Colors.white70,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
