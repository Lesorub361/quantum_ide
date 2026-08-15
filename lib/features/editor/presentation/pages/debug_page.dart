import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:quantum_ide/core/services/dap_debugger_service.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

class DebugPage extends ConsumerStatefulWidget {
  const DebugPage({super.key});

  @override
  ConsumerState<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends ConsumerState<DebugPage> {
  final TextEditingController _connectionController = TextEditingController();
  final TextEditingController _expressionController = TextEditingController();
  String _activeTab = 'variables';
  int? _selectedFrameId;

  @override
  void dispose() {
    _connectionController.dispose();
    _expressionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(dapDebuggerServiceProvider);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Colors.orangeAccent.withValues(alpha: 0.12), Colors.transparent],
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
                    const Icon(LucideIcons.bug, size: 18, color: Colors.orangeAccent),
                    const SizedBox(width: 8),
                    ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        colors: [Colors.orangeAccent, Colors.deepOrangeAccent],
                      ).createShader(b),
                      child: Text(
                        l10n.debugger,
                        style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                actions: [
                  _buildStateChip(service.currentState),
                  const SizedBox(width: 16),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildDebugToolbar(service, l10n),
                    const SizedBox(height: 16),
                    _buildConnectionPanel(service, l10n),
                    const SizedBox(height: 16),
                    _buildBreakpointsPanel(service, l10n),
                    const SizedBox(height: 16),
                    _buildCallStackPanel(service, l10n),
                    const SizedBox(height: 16),
                    _buildInspectorTabs(service, l10n),
                    const SizedBox(height: 16),
                    _buildExpressionEvaluator(service, l10n),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStateChip(DapDebuggerState state) {
    final (color, label) = switch (state) {
      DapDebuggerState.connected => (Colors.greenAccent, 'Connected'),
      DapDebuggerState.connecting => (Colors.amberAccent, 'Connecting'),
      DapDebuggerState.paused => (Colors.orangeAccent, 'Paused'),
      DapDebuggerState.running => (Colors.cyanAccent, 'Running'),
      DapDebuggerState.stopped => (Colors.redAccent, 'Stopped'),
      DapDebuggerState.error => (Colors.red, 'Error'),
      DapDebuggerState.disconnected => (Colors.grey, 'Offline'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: GoogleFonts.inter(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildDebugToolbar(DapDebuggerService service, AppLocalizations l10n) {
    final isActive = service.currentState == DapDebuggerState.connected ||
        service.currentState == DapDebuggerState.running ||
        service.currentState == DapDebuggerState.paused;
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _toolButton(LucideIcons.play, Colors.greenAccent, 'Continue', isActive, () => service.step(StepType.continue_)),
          const SizedBox(width: 8),
          _toolButton(LucideIcons.pause, Colors.amberAccent, 'Pause', isActive, () => service.pause()),
          const SizedBox(width: 8),
          _toolButton(LucideIcons.skip_forward, Colors.cyanAccent, 'Step Over', isActive, () => service.step(StepType.over)),
          const SizedBox(width: 8),
          _toolButton(LucideIcons.arrow_down_to_line, Colors.purpleAccent, 'Step Into', isActive, () => service.step(StepType.into)),
          const SizedBox(width: 8),
          _toolButton(LucideIcons.arrow_up_to_line, Colors.pinkAccent, 'Step Out', isActive, () => service.step(StepType.out)),
          const SizedBox(width: 8),
          _toolButton(LucideIcons.rotate_ccw, Colors.orangeAccent, 'Restart', isActive, () => service.restart()),
          const SizedBox(width: 8),
          _toolButton(LucideIcons.square, Colors.redAccent, 'Stop', isActive, () => service.terminate()),
        ],
      ),
    );
  }

  Widget _toolButton(IconData icon, Color color, String tooltip, bool enabled, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: enabled ? color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: enabled ? color.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05)),
            ),
            child: Icon(icon, size: 18, color: enabled ? color : Colors.white24),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionPanel(DapDebuggerService service, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final isConnected = service.currentState == DapDebuggerState.connected ||
        service.currentState == DapDebuggerState.running ||
        service.currentState == DapDebuggerState.paused;
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.link, size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Connection', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _connectionController,
                  style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'ws://127.0.0.1:xxxxx/ws',
                    hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerLow,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: isConnected
                      ? () => service.disconnect()
                      : () => service.connect(_connectionController.text),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isConnected ? Colors.redAccent.withValues(alpha: 0.15) : Colors.greenAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isConnected ? Colors.redAccent.withValues(alpha: 0.3) : Colors.greenAccent.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      isConnected ? 'Disconnect' : 'Connect',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isConnected ? Colors.redAccent : Colors.greenAccent,
                      ),
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

  Widget _buildBreakpointsPanel(DapDebuggerService service, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final bps = service.breakpoints;
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.circle_dot, size: 14, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text('Breakpoints', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
              const Spacer(),
              if (bps.isNotEmpty)
                Text(
                  '${bps.length}',
                  style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                ),
              if (bps.isNotEmpty) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => service.clearAllBreakpoints(),
                  child: Text('Clear All', style: GoogleFonts.inter(fontSize: 11, color: Colors.redAccent)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (bps.isEmpty)
            Text('No breakpoints set', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 12))
          else
            ...bps.map((bp) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${bp.filePath.split('/').last}:${bp.line}',
                          style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurface),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => service.removeBreakpoint(bp.filePath, bp.line),
                        child: const Icon(LucideIcons.x, size: 12, color: Colors.redAccent),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildCallStackPanel(DapDebuggerService service, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final frames = service.stackFrames;
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.layers, size: 14, color: Colors.cyanAccent),
              const SizedBox(width: 8),
              Text('Call Stack', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
              const Spacer(),
              if (frames.isNotEmpty)
                Text('${frames.length} frames', style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          if (frames.isEmpty)
            Text('No stack frames', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 12))
          else
            SizedBox(
              height: 160,
              child: ListView.builder(
                itemCount: frames.length,
                itemBuilder: (context, i) {
                  final frame = frames[i];
                  final isSelected = _selectedFrameId == frame.id;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() => _selectedFrameId = frame.id);
                        service.selectFrame(frame.id);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.cyanAccent.withValues(alpha: 0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isSelected ? Colors.cyanAccent.withValues(alpha: 0.3) : Colors.transparent),
                        ),
                        child: Row(
                          children: [
                            Text('${i + 1}', style: GoogleFonts.inter(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(frame.name, style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                  Text(
                                    '${frame.source.split('/').last}:${frame.line}',
                                    style: GoogleFonts.inter(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInspectorTabs(DapDebuggerService service, AppLocalizations l10n) {
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _tabButton('variables', LucideIcons.list, 'Variables'),
              const SizedBox(width: 8),
              _tabButton('output', LucideIcons.terminal, 'Output'),
              const SizedBox(width: 8),
              _tabButton('watch', LucideIcons.eye, 'Watch'),
            ],
          ),
          const SizedBox(height: 12),
          if (_activeTab == 'variables') _buildVariablesList(service),
          if (_activeTab == 'output') _buildOutputStream(service),
          if (_activeTab == 'watch') _buildWatchSection(service),
        ],
      ),
    );
  }

  Widget _tabButton(String id, IconData icon, String label) {
    final isActive = _activeTab == id;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => setState(() => _activeTab = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? theme.colorScheme.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
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

  Widget _buildVariablesList(DapDebuggerService service) {
    final theme = Theme.of(context);
    final vars = service.variables;
    if (vars.isEmpty) {
      return Text('No variables in scope', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 12));
    }
    return SizedBox(
      height: 180,
      child: ListView.builder(
        itemCount: vars.length,
        itemBuilder: (context, i) {
          final v = vars[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(v.name, style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(v.value, style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurface), overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(v.type, style: GoogleFonts.inter(fontSize: 9, color: Colors.purpleAccent)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOutputStream(DapDebuggerService service) {
    final theme = Theme.of(context);
    return StreamBuilder<String>(
      stream: service.outputStream,
      initialData: '',
      builder: (context, snapshot) {
        final output = snapshot.data ?? '';
        if (output.isEmpty) {
          return Text('No output', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 12));
        }
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(output, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.greenAccent)),
        );
      },
    );
  }

  Widget _buildWatchSection(DapDebuggerService service) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _expressionController,
            style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Expression to evaluate...',
              hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerLow,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onSubmitted: (val) async {
              if (val.isNotEmpty) {
                final result = await service.evaluateExpression(val, frameId: _selectedFrameId);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(result, style: GoogleFonts.inter(fontSize: 12))),
                );
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              final val = _expressionController.text;
              if (val.isNotEmpty) {
                final result = await service.evaluateExpression(val, frameId: _selectedFrameId);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(result, style: GoogleFonts.inter(fontSize: 12))),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(LucideIcons.play, size: 16, color: theme.colorScheme.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpressionEvaluator(DapDebuggerService service, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final exception = service.lastException;
    if (exception == null) return const SizedBox.shrink();
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.triangle_alert, size: 14, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text('Exception', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.redAccent)),
            ],
          ),
          const SizedBox(height: 8),
          Text(exception.description, style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurface)),
          if (exception.details != null) ...[
            const SizedBox(height: 4),
            Text(exception.details!, style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
