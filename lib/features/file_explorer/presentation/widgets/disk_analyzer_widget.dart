import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:fl_chart/fl_chart.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

class DiskAnalyzerWidget extends ConsumerStatefulWidget {
  const DiskAnalyzerWidget({super.key});

  @override
  ConsumerState<DiskAnalyzerWidget> createState() => _DiskAnalyzerWidgetState();
}

class _FolderSizeInfo {
  final String name;
  final String path;
  final int sizeInBytes;
  final Color color;

  _FolderSizeInfo({
    required this.name,
    required this.path,
    required this.sizeInBytes,
    required this.color,
  });
}

class _FileSizeInfo {
  final String name;
  final String path;
  final int sizeInBytes;

  _FileSizeInfo({
    required this.name,
    required this.path,
    required this.sizeInBytes,
  });
}

class _DiskAnalyzerWidgetState extends ConsumerState<DiskAnalyzerWidget> {
  bool _scanning = false;
  List<_FolderSizeInfo> _folderSizes = [];
  List<_FileSizeInfo> _largestFiles = [];
  int _totalSize = 0;
  String? _errorKey;
  String _errorDetail = '';
  int _touchedIndex = -1;

  final List<Color> _chartColors = [
    Colors.blueAccent,
    Colors.redAccent,
    Colors.orangeAccent,
    Colors.greenAccent,
    Colors.purpleAccent,
    Colors.cyanAccent,
    Colors.amberAccent,
    Colors.pinkAccent,
    Colors.tealAccent,
    Colors.indigoAccent,
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _runScan());
  }

  Future<void> _runScan() async {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null || workspacePath.isEmpty) {
      setState(() {
        _errorKey = 'projectNotOpened';
        _errorDetail = '';
      });
      return;
    }

    setState(() {
      _scanning = true;
      _errorKey = null;
      _errorDetail = '';
      _folderSizes = [];
      _largestFiles = [];
      _totalSize = 0;
    });

    try {
      final rootDir = Directory(workspacePath);
      if (!await rootDir.exists()) {
        setState(() {
          _errorKey = 'projectFolderNotFound';
          _errorDetail = '';
          _scanning = false;
        });
        return;
      }

      final Map<String, int> folderSizesMap = {};
      final List<_FileSizeInfo> allFiles = [];
      int rootFilesSize = 0;
      int calculatedTotal = 0;

      final entities = await rootDir.list(recursive: true, followLinks: false).toList();

      for (final entity in entities) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            final size = stat.size;
            calculatedTotal += size;

            // Track file size info
            allFiles.add(_FileSizeInfo(
              name: p.basename(entity.path),
              path: entity.path,
              sizeInBytes: size,
            ));

            // Determine direct subfolder in workspace root
            final relPath = p.relative(entity.path, from: workspacePath);
            final parts = p.split(relPath);
            if (parts.length > 1) {
              final rootSubdir = parts.first;
              folderSizesMap[rootSubdir] = (folderSizesMap[rootSubdir] ?? 0) + size;
            } else {
              rootFilesSize += size;
            }
          } catch (_) {
            // Ignore stats errors
          }
        }
      }

      // Convert folder sizes
      final List<_FolderSizeInfo> foldersList = [];
      int colorIndex = 0;
      folderSizesMap.forEach((subdirName, size) {
        foldersList.add(_FolderSizeInfo(
          name: subdirName,
          path: p.join(workspacePath, subdirName),
          sizeInBytes: size,
          color: _chartColors[colorIndex % _chartColors.length],
        ));
        colorIndex++;
      });

      if (rootFilesSize > 0) {
        foldersList.add(_FolderSizeInfo(
          name: '[root]',
          path: workspacePath,
          sizeInBytes: rootFilesSize,
          color: Colors.grey,
        ));
      }

      // Sort folders by size descending
      foldersList.sort((a, b) => b.sizeInBytes.compareTo(a.sizeInBytes));

      // Sort files by size descending, keep top 10
      allFiles.sort((a, b) => b.sizeInBytes.compareTo(a.sizeInBytes));
      final topFiles = allFiles.take(10).toList();

      if (mounted) {
        setState(() {
          _folderSizes = foldersList;
          _largestFiles = topFiles;
          _totalSize = calculatedTotal;
          _scanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorKey = 'scanningError';
          _errorDetail = e.toString();
          _scanning = false;
        });
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  void _showDeleteConfirm(BuildContext context, _FileSizeInfo fileInfo) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E2230),
        title: Text(l10n.deleteFileConfirmTitle, style: const TextStyle(color: Colors.white)),
        content: Text(
          l10n.deleteFileConfirmMessage(fileInfo.name, _formatSize(fileInfo.sizeInBytes)),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel, style: const TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              try {
                final file = File(fileInfo.path);
                if (await file.exists()) {
                  await file.delete();
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.fileDeletedSuccess)),
                  );
                  _runScan();
                }
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.deleteFileError(e.toString()))),
                );
              }
            },
            child: Text(l10n.delete, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    String? resolvedError;
    if (_errorKey != null) {
      if (_errorKey == 'projectNotOpened') {
        resolvedError = l10n.projectNotOpened;
      } else if (_errorKey == 'projectFolderNotFound') {
        resolvedError = l10n.projectFolderNotFound;
      } else if (_errorKey == 'scanningError') {
        resolvedError = l10n.scanningError(_errorDetail);
      }
    }

    if (resolvedError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            resolvedError,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      );
    }

    if (_scanning) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              l10n.diskSpaceAnalysis,
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_folderSizes.isEmpty) {
      return Center(
        child: Text(
          l10n.projectFolderEmpty,
          style: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
        ),
      );
    }

    return Column(
      children: [
        // Top stats bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          child: Row(
            children: [
              Icon(LucideIcons.chart_pie, size: 14, color: Colors.white54),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.projectSize,
                    style: const TextStyle(color: Colors.white38, fontSize: 9.5),
                  ),
                  Text(
                    _formatSize(_totalSize),
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.refresh_cw, size: 12, color: Colors.white54),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _runScan,
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 8),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              // 1. Chart section
              if (_folderSizes.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 130,
                  child: PieChart(
                    PieChartData(
                      pieTouchData: PieTouchData(
                        touchCallback: (FlTouchEvent event, pieTouchResponse) {
                          setState(() {
                            if (!event.isInterestedForInteractions ||
                                pieTouchResponse == null ||
                                pieTouchResponse.touchedSection == null) {
                              _touchedIndex = -1;
                              return;
                            }
                            _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                          });
                        },
                      ),
                      borderData: FlBorderData(show: false),
                      sectionsSpace: 2,
                      centerSpaceRadius: 30,
                      sections: _buildChartSections(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 2. Folder List
              Text(
                l10n.folderDistribution,
                style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              ..._folderSizes.map((folder) {
                final double percent = _totalSize > 0 
                    ? (folder.sizeInBytes / _totalSize) * 100 
                    : 0.0;
                
                final displayName = folder.name == '[root]' ? l10n.rootFiles : folder.name;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: folder.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          displayName,
                          style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatSize(folder.sizeInBytes),
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${percent.toStringAsFixed(1)}%',
                        style: const TextStyle(color: Colors.white30, fontSize: 10),
                      ),
                    ],
                  ),
                );
              }),

              const Divider(color: Colors.white10, height: 24),

              // 3. Top 10 heavy files
              Text(
                l10n.topHeavyFiles,
                style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              if (_largestFiles.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(l10n.noHeavyFiles, style: const TextStyle(color: Colors.white24, fontSize: 11)),
                )
              else
                ..._largestFiles.map((file) => _buildFileItemWidget(file)),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  List<PieChartSectionData> _buildChartSections() {
    return List.generate(_folderSizes.length, (i) {
      final isTouched = i == _touchedIndex;
      final fontSize = isTouched ? 12.0 : 8.0;
      final radius = isTouched ? 45.0 : 35.0;
      final folder = _folderSizes[i];
      final double percent = _totalSize > 0 
          ? (folder.sizeInBytes / _totalSize) * 100 
          : 0.0;

      // Only show text if the sector is large enough or touched
      final showText = percent > 8 || isTouched;

      return PieChartSectionData(
        color: folder.color,
        value: folder.sizeInBytes.toDouble(),
        title: showText ? '${percent.toStringAsFixed(0)}%' : '',
        radius: radius,
        titleStyle: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    });
  }

  Widget _buildFileItemWidget(_FileSizeInfo file) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.01),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04), width: 0.5),
      ),
      child: InkWell(
        onTap: () async {
          await ref.read(editorProvider.notifier).openFile(file.path);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              const Icon(LucideIcons.file, size: 14, color: Colors.white38),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1.5),
                    Text(
                      _formatSize(file.sizeInBytes),
                      style: const TextStyle(color: Colors.redAccent, fontSize: 9.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.trash_2, size: 13, color: Colors.redAccent),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _showDeleteConfirm(context, file),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
