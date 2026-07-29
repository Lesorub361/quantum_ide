import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/dap_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

class DebuggerPanel extends ConsumerStatefulWidget {
  const DebuggerPanel({super.key});

  @override
  ConsumerState<DebuggerPanel> createState() => _DebuggerPanelState();
}

class _DebuggerPanelState extends ConsumerState<DebuggerPanel> {
  final TextEditingController _programController = TextEditingController();
  final List<DapStackFrame> _stackFrames = [];
  final List<DapVariable> _variables = [];
  int? _selectedFrameId;
  final List<String> _outputLines = [];

  @override
  void dispose() {
    _programController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dapState = ref.watch(dapServiceProvider).currentState;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        _buildHeader(l10n, dapState),
        const Divider(color: Colors.white10, height: 1),
        if (dapState == DapState.running) ...[
          _buildControlBar(l10n),
          const Divider(color: Colors.white10, height: 1),
        ],
        Expanded(
          child: dapState == DapState.idle
              ? _buildLaunchView(l10n)
              : _buildDebugView(l10n),
        ),
      ],
    );
  }

  Widget _buildHeader(AppLocalizations l10n, DapState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          const Icon(LucideIcons.bug, size: 14, color: Colors.orangeAccent),
          const SizedBox(width: 8),
          Text(
            l10n.debugger,
            style: GoogleFonts.inter(
              color: Colors.orangeAccent,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _getStateColor(state).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _getStateColor(state).withValues(alpha: 0.3)),
            ),
            child: Text(
              _getStateLabel(state),
              style: GoogleFonts.inter(
                fontSize: 8.5,
                color: _getStateColor(state),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          _buildControlButton(
            icon: LucideIcons.play,
            color: Colors.greenAccent,
            tooltip: l10n.continue_,
            onTap: () => ref.read(dapServiceProvider).continue_(),
          ),
          const SizedBox(width: 4),
          _buildControlButton(
            icon: LucideIcons.pause,
            color: Colors.amberAccent,
            tooltip: l10n.pause,
            onTap: () => ref.read(dapServiceProvider).pause(),
          ),
          const SizedBox(width: 4),
          _buildControlButton(
            icon: LucideIcons.arrow_down_to_line,
            color: Colors.cyanAccent,
            tooltip: l10n.stepOver,
            onTap: () => ref.read(dapServiceProvider).stepOver(),
          ),
          const SizedBox(width: 4),
          _buildControlButton(
            icon: LucideIcons.arrow_down,
            color: Colors.cyanAccent,
            tooltip: l10n.stepIn,
            onTap: () => ref.read(dapServiceProvider).stepIn(),
          ),
          const SizedBox(width: 4),
          _buildControlButton(
            icon: LucideIcons.arrow_up,
            color: Colors.cyanAccent,
            tooltip: l10n.stepOut,
            onTap: () => ref.read(dapServiceProvider).stepOut(),
          ),
          const Spacer(),
          _buildControlButton(
            icon: LucideIcons.square,
            color: Colors.redAccent,
            tooltip: l10n.stop,
            onTap: () async {
              await ref.read(dapServiceProvider).stop();
              setState(() {
                _stackFrames.clear();
                _variables.clear();
                _selectedFrameId = null;
                _outputLines.clear();
              });
            },
          ),
          const SizedBox(width: 4),
          _buildControlButton(
            icon: LucideIcons.rotate_ccw,
            color: Colors.orangeAccent,
            tooltip: l10n.restart,
            onTap: () => ref.read(dapServiceProvider).restart(),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }

  Widget _buildLaunchView(AppLocalizations l10n) {
    final activeFile = ref.watch(editorProvider.select((s) {
      if (s.openFiles.isEmpty) return null;
      int idx = s.activeTabIndex;
      if (idx < 0 || idx >= s.openFiles.length) idx = s.openFiles.length - 1;
      return s.openFiles[idx];
    }));

    if (activeFile != null && _programController.text.isEmpty) {
      _programController.text = activeFile.path.split('/').last;
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.launchConfiguration,
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _programController,
            style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText: l10n.programToDebug,
              hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.orangeAccent, width: 0.8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                if (_programController.text.isNotEmpty) {
                  await ref.read(dapServiceProvider).start(
                    program: _programController.text,
                  );
                }
              },
              icon: const Icon(LucideIcons.play, size: 14),
              label: Text(l10n.startDebugging),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent.withValues(alpha: 0.15),
                foregroundColor: Colors.orangeAccent,
                elevation: 0,
                side: BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_outputLines.isNotEmpty) ...[
            Text(
              l10n.output,
              style: GoogleFonts.inter(
                color: Colors.white38,
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: ListView.builder(
                  itemCount: _outputLines.length,
                  itemBuilder: (context, index) {
                    return Text(
                      _outputLines[index],
                      style: GoogleFonts.jetBrainsMono(
                        color: Colors.white60,
                        fontSize: 10,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDebugView(AppLocalizations l10n) {
    return Column(
      children: [
        Expanded(
          flex: 2,
          child: _buildStackFramesView(l10n),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          flex: 2,
          child: _buildVariablesView(l10n),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          flex: 1,
          child: _buildOutputView(l10n),
        ),
      ],
    );
  }

  Widget _buildStackFramesView(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
            l10n.callStack,
            style: GoogleFonts.inter(
              color: Colors.white38,
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(
          child: _stackFrames.isEmpty
              ? Center(
                  child: Text(
                    l10n.noStackFrames,
                    style: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
                  ),
                )
              : ListView.builder(
                  itemCount: _stackFrames.length,
                  itemBuilder: (context, index) {
                    final frame = _stackFrames[index];
                    final isSelected = frame.id == _selectedFrameId;
                    return InkWell(
                      onTap: () async {
                        setState(() => _selectedFrameId = frame.id);
                        final vars = await ref.read(dapServiceProvider).getVariables(frame.id);
                        setState(() {
                          _variables.clear();
                          _variables.addAll(vars);
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        color: isSelected
                            ? Colors.orangeAccent.withValues(alpha: 0.1)
                            : Colors.transparent,
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.corner_down_right,
                              size: 12,
                              color: isSelected ? Colors.orangeAccent : Colors.white24,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    frame.name,
                                    style: GoogleFonts.inter(
                                      color: isSelected ? Colors.white : Colors.white70,
                                      fontSize: 11,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${frame.source.split('/').last}:${frame.line}',
                                    style: GoogleFonts.jetBrainsMono(
                                      color: Colors.white24,
                                      fontSize: 9,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildVariablesView(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
            l10n.variables,
            style: GoogleFonts.inter(
              color: Colors.white38,
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(
          child: _variables.isEmpty
              ? Center(
                  child: Text(
                    l10n.noVariables,
                    style: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
                  ),
                )
              : ListView.builder(
                  itemCount: _variables.length,
                  itemBuilder: (context, index) {
                    final variable = _variables[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              variable.name,
                              style: GoogleFonts.jetBrainsMono(
                                color: Colors.cyanAccent,
                                fontSize: 10,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: Text(
                              variable.value,
                              style: GoogleFonts.jetBrainsMono(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildOutputView(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Text(
                l10n.output,
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (_outputLines.isNotEmpty)
                IconButton(
                  icon: const Icon(LucideIcons.trash_2, size: 12, color: Colors.white24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _outputLines.clear()),
                ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: _outputLines.isEmpty
                ? Center(
                    child: Text(
                      l10n.noOutput,
                      style: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
                    ),
                  )
                : ListView.builder(
                    itemCount: _outputLines.length,
                    itemBuilder: (context, index) {
                      return Text(
                        _outputLines[index],
                        style: GoogleFonts.jetBrainsMono(
                          color: Colors.white60,
                          fontSize: 10,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Color _getStateColor(DapState state) {
    switch (state) {
      case DapState.idle:
        return Colors.white38;
      case DapState.launching:
        return Colors.amberAccent;
      case DapState.running:
        return Colors.greenAccent;
      case DapState.stopped:
        return Colors.redAccent;
      case DapState.error:
        return Colors.redAccent;
    }
  }

  String _getStateLabel(DapState state) {
    switch (state) {
      case DapState.idle:
        return 'IDLE';
      case DapState.launching:
        return 'LAUNCHING';
      case DapState.running:
        return 'RUNNING';
      case DapState.stopped:
        return 'STOPPED';
      case DapState.error:
        return 'ERROR';
    }
  }
}
