import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/project_sync_service.dart';
import 'package:share_plus/share_plus.dart';

class ProjectSyncFloatingBanner extends ConsumerWidget {
  const ProjectSyncFloatingBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(projectSyncProvider);
    if (!syncState.isPanelVisible) return const SizedBox.shrink();

    final isSyncing = syncState.isSyncing;
    final isSuccess = syncState.status == ProjectSyncStatus.success;
    final isError = syncState.status == ProjectSyncStatus.error;

    Color accentColor = Colors.cyanAccent;
    if (isSuccess) accentColor = Colors.greenAccent;
    if (isError) accentColor = Colors.redAccent;

    return Material(
      color: Colors.transparent,
      child: Center(
        child: InkWell(
          onTap: () {
            ref.read(projectSyncProvider.notifier).setActiveTab(0);
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF161925).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accentColor.withValues(alpha: 0.35), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSyncing)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    ),
                  )
                else
                  Icon(
                    isSuccess ? LucideIcons.circle_check : LucideIcons.triangle_alert,
                    size: 20,
                    color: accentColor,
                  ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        syncState.title,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        syncState.currentStep,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 16, color: Colors.white54),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    ref.read(projectSyncProvider.notifier).dismiss();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProjectSyncOutputPanel extends ConsumerStatefulWidget {
  const ProjectSyncOutputPanel({super.key});

  @override
  ConsumerState<ProjectSyncOutputPanel> createState() => _ProjectSyncOutputPanelState();
}

class _ProjectSyncOutputPanelState extends ConsumerState<ProjectSyncOutputPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(projectSyncProvider);
    if (!syncState.isPanelVisible) return const SizedBox.shrink();

    // Auto-scroll when logs change
    ref.listen<List<String>>(
      projectSyncProvider.select((s) => s.logs),
      (prev, next) {
        if (next.length != prev?.length) {
          _scrollToBottom();
        }
      },
    );

    final activeTab = syncState.activeTab;
    final isSyncing = syncState.isSyncing;

    List<String> currentLines = [];
    if (activeTab == 0) {
      currentLines = syncState.logs;
    } else if (activeTab == 1) {
      currentLines = syncState.problems;
    } else {
      currentLines = syncState.appLogs;
    }

    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: const Color(0xFF0F121C),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.12), width: 1),
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1. Вкладки: Вывод / Проблемы / Логи приложения ──────────────
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 10, right: 12),
                child: Row(
                  children: [
                    _buildTab(
                      index: 0,
                      title: 'Вывод',
                      isActive: activeTab == 0,
                      onTap: () => ref.read(projectSyncProvider.notifier).setActiveTab(0),
                    ),
                    const SizedBox(width: 8),
                    _buildTab(
                      index: 1,
                      title: 'Проблемы',
                      badge: syncState.problems.isNotEmpty ? '${syncState.problems.length}' : null,
                      isActive: activeTab == 1,
                      onTap: () => ref.read(projectSyncProvider.notifier).setActiveTab(1),
                    ),
                    const SizedBox(width: 8),
                    _buildTab(
                      index: 2,
                      title: 'Логи приложения',
                      isActive: activeTab == 2,
                      onTap: () => ref.read(projectSyncProvider.notifier).setActiveTab(2),
                    ),
                    const Spacer(),
                    if (isSyncing)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.cyanAccent),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Синхронизация...',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.cyanAccent),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // ── 2. Текущая подзадача и анимированный прогресс-бар ───────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      syncState.currentStep,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: isSyncing
                          ? const LinearProgressIndicator(
                              minHeight: 2.5,
                              backgroundColor: Color(0xFF1E2433),
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                            )
                          : Container(
                              height: 2.5,
                              color: syncState.status == ProjectSyncStatus.success
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                            ),
                    ),
                  ],
                ),
              ),

              // ── 3. Нумерованный лог в реальном времени ─────────────────────
              Expanded(
                child: Container(
                  color: const Color(0xFF090B12),
                  child: currentLines.isEmpty
                      ? Center(
                          child: Text(
                            activeTab == 1 ? 'Проблем не обнаружено' : 'Ожидание вывода...',
                            style: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 12),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(left: 10, right: 70, top: 6, bottom: 40),
                          itemCount: currentLines.length,
                          itemBuilder: (context, index) {
                            final lineNumber = index + 1;
                            final text = currentLines[index];
                            final color = _getLineColor(text);

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1.5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 32,
                                    child: Text(
                                      '$lineNumber',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        color: Colors.white30,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SelectableText(
                                      text,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11.5,
                                        color: color,
                                        height: 1.35,
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
            ],
          ),

          // ── 4. Плавающие кнопки справа внизу: Поделиться и Закрыть ─────────
          Positioned(
            right: 14,
            bottom: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Кнопка Share (фиолетовая)
                FloatingActionButton.small(
                  heroTag: 'sync_share_button',
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  elevation: 6,
                  onPressed: () {
                    final logText = currentLines.join('\n');
                    if (logText.isNotEmpty) {
                      Share.share(logText, subject: 'Quantum IDE - Лог синхронизации проекта');
                    }
                  },
                  child: const Icon(LucideIcons.share_2, size: 18),
                ),
                const SizedBox(height: 8),
                // Кнопка Close (тёмно-синяя с крестиком)
                FloatingActionButton.small(
                  heroTag: 'sync_close_button',
                  backgroundColor: const Color(0xFF253049),
                  foregroundColor: Colors.white,
                  elevation: 6,
                  onPressed: () {
                    ref.read(projectSyncProvider.notifier).dismiss();
                  },
                  child: const Icon(LucideIcons.x, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab({
    required int index,
    required String title,
    String? badge,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1E283D) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? Border.all(color: Colors.cyanAccent.withValues(alpha: 0.35), width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: isActive ? Colors.cyanAccent : Colors.white60,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getLineColor(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('error:') || lower.contains('failed') || lower.contains('exception:')) {
      return Colors.redAccent;
    }
    if (lower.contains('warning:')) {
      return Colors.amberAccent;
    }
    if (lower.contains('resolved plugin') ||
        lower.contains('starting build') ||
        lower.contains('got dependencies') ||
        lower.contains('✓')) {
      return Colors.cyanAccent;
    }
    return Colors.white70;
  }
}
