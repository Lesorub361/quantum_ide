import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:quantum_ide/core/services/performance_profiler_service.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';

class PerformanceProfilerPage extends ConsumerStatefulWidget {
  const PerformanceProfilerPage({super.key});

  @override
  ConsumerState<PerformanceProfilerPage> createState() => _PerformanceProfilerPageState();
}

class _PerformanceProfilerPageState extends ConsumerState<PerformanceProfilerPage> {
  String _activeTab = 'fps';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(performanceProfilerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Colors.cyanAccent.withValues(alpha: 0.12), Colors.transparent],
                ),
              ),
            ),
          ),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: theme.scaffoldBackgroundColor,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(LucideIcons.arrow_left, color: theme.colorScheme.onSurface),
                  onPressed: () => context.go('/'),
                ),
                title: Row(
                  children: [
                    const Icon(LucideIcons.activity, size: 18, color: Colors.cyanAccent),
                    const SizedBox(width: 8),
                    ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        colors: [Colors.cyanAccent, Colors.blueAccent],
                      ).createShader(b),
                      child: Text(
                        'Performance Profiler',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                actions: [
                  if (state.isRecording)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent),
                          ),
                          const SizedBox(width: 6),
                          Text('REC', style: GoogleFonts.inter(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  const SizedBox(width: 16),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildRecordingControls(state),
                    const SizedBox(height: 16),
                    _buildMetricCards(state),
                    const SizedBox(height: 16),
                    _buildGraphTabs(state),
                    const SizedBox(height: 16),
                    _buildActiveGraph(state),
                    const SizedBox(height: 16),
                    _buildSessionHistory(state),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingControls(PerformanceProfilerState state) {
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (state.isRecording) {
                    ref.read(performanceProfilerProvider.notifier).stopRecording();
                  } else {
                    ref.read(performanceProfilerProvider.notifier).startRecording();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: state.isRecording
                        ? Colors.redAccent.withValues(alpha: 0.15)
                        : Colors.greenAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: state.isRecording
                          ? Colors.redAccent.withValues(alpha: 0.3)
                          : Colors.greenAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        state.isRecording ? LucideIcons.square : LucideIcons.circle,
                        size: 16,
                        color: state.isRecording ? Colors.redAccent : Colors.greenAccent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        state.isRecording ? 'Stop Recording' : 'Start Recording',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: state.isRecording ? Colors.redAccent : Colors.greenAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (state.currentSession != null) ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Samples', style: GoogleFonts.inter(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                Text(
                  '${state.currentSession!.samples.length}',
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricCards(PerformanceProfilerState state) {
    final samples = state.recentSamples;
    final fps = samples.isNotEmpty ? samples.last.fps : 0.0;
    final memory = samples.isNotEmpty ? samples.last.memoryMB : 0.0;
    final buildTime = samples.isNotEmpty ? samples.last.buildTimeMs : 0.0;

    return Row(
      children: [
        _metricCard('FPS', fps.toStringAsFixed(1), _getFpsColor(fps), LucideIcons.gauge),
        const SizedBox(width: 8),
        _metricCard('Memory', '${memory.toStringAsFixed(1)} MB', _getMemoryColor(memory), LucideIcons.memory_stick),
        const SizedBox(width: 8),
        _metricCard('Build', '${buildTime.toStringAsFixed(1)} ms', _getBuildColor(buildTime), LucideIcons.timer),
      ],
    );
  }

  Widget _metricCard(String label, String value, Color color, IconData icon) {
    final theme = Theme.of(context);
    return Expanded(
      child: GlassContainer(
        borderRadius: BorderRadius.circular(14),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(value, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: GoogleFonts.inter(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Color _getFpsColor(double fps) {
    if (fps >= 55) return Colors.greenAccent;
    if (fps >= 30) return Colors.amberAccent;
    return Colors.redAccent;
  }

  Color _getMemoryColor(double mb) {
    if (mb <= 100) return Colors.greenAccent;
    if (mb <= 300) return Colors.amberAccent;
    return Colors.redAccent;
  }

  Color _getBuildColor(double ms) {
    if (ms <= 16) return Colors.greenAccent;
    if (ms <= 32) return Colors.amberAccent;
    return Colors.redAccent;
  }

  Widget _buildGraphTabs(PerformanceProfilerState state) {
    return Row(
      children: [
        _graphTab('fps', LucideIcons.gauge, 'FPS'),
        const SizedBox(width: 8),
        _graphTab('memory', LucideIcons.memory_stick, 'Memory'),
        const SizedBox(width: 8),
        _graphTab('build', LucideIcons.timer, 'Build Time'),
      ],
    );
  }

  Widget _graphTab(String id, IconData icon, String label) {
    final isActive = _activeTab == id;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => setState(() => _activeTab = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? theme.colorScheme.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isActive ? theme.colorScheme.primary.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(label, style: GoogleFonts.inter(fontSize: 11, color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveGraph(PerformanceProfilerState state) {
    final samples = ref.read(performanceProfilerProvider.notifier).getLastSamples(count: 60);
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _activeTab == 'fps'
                ? 'Frame Rate (FPS)'
                : _activeTab == 'memory'
                    ? 'Memory Usage (MB)'
                    : 'Build Time (ms)',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: samples.isEmpty
                ? Center(
                    child: Text('Start recording to see data', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 12)),
                  )
                : CustomPaint(
                    painter: _GraphPainter(
                      values: samples.map((s) {
                        return switch (_activeTab) {
                          'fps' => s.fps,
                          'memory' => s.memoryMB,
                          'build' => s.buildTimeMs,
                          _ => s.fps,
                        };
                      }).toList(),
                      color: switch (_activeTab) {
                        'fps' => Colors.cyanAccent,
                        'memory' => Colors.purpleAccent,
                        'build' => Colors.amberAccent,
                        _ => Colors.cyanAccent,
                      },
                    ),
                    size: Size.infinite,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionHistory(PerformanceProfilerState state) {
    final theme = Theme.of(context);
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.history, size: 14, color: Colors.amberAccent),
              const SizedBox(width: 8),
              Text('Session History', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
              const Spacer(),
              if (state.sessions.isNotEmpty)
                GestureDetector(
                  onTap: () => ref.read(performanceProfilerProvider.notifier).clearHistory(),
                  child: Text('Clear', style: GoogleFonts.inter(fontSize: 11, color: Colors.redAccent)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (state.sessions.isEmpty)
            Text('No recorded sessions', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 12))
          else
            ...state.sessions.map((session) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.circle_play, size: 14, color: Colors.cyanAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(session.name, style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600)),
                            Text(
                              '${session.samples.length} samples · ${session.duration.inSeconds}s · avg ${session.avgFps.toStringAsFixed(1)} FPS',
                              style: GoogleFonts.inter(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => ref.read(performanceProfilerProvider.notifier).deleteSession(session.id),
                        child: const Icon(LucideIcons.trash_2, size: 12, color: Colors.redAccent),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _GraphPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final range = (maxVal - minVal).abs().clamp(1, double.infinity);

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final y = size.height - ((values[i] - minVal) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    if (values.isNotEmpty) {
      final lastX = size.width;
      final lastY = size.height - ((values.last - minVal) / range) * size.height;
      final dotPaint = Paint()..color = color;
      canvas.drawCircle(Offset(lastX, lastY), 4, dotPaint);
      canvas.drawCircle(Offset(lastX, lastY), 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) => values != oldDelegate.values || color != oldDelegate.color;
}
