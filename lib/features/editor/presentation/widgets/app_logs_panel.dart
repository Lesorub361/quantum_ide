import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/log_service.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';

class AppLogsPanel extends ConsumerStatefulWidget {
  const AppLogsPanel({super.key});

  @override
  ConsumerState<AppLogsPanel> createState() => _AppLogsPanelState();
}

class _AppLogsPanelState extends ConsumerState<AppLogsPanel> {
  final List<String> _localLogs = [];
  StreamSubscription<String>? _subscription;
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _localLogs.addAll(LogService.logs);
    _subscription = LogService.logStream.listen((line) {
      if (mounted) {
        setState(() {
          _localLogs.add(line);
          if (_localLogs.length > 1000) {
            _localLogs.removeAt(0);
          }
        });
        if (_autoScroll) {
          _scrollToBottom();
        }
      }
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 40.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF090B0F),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Control Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.terminal, size: 14, color: Colors.white54),
                const SizedBox(width: 6),
                Text(
                  'Application Logs',
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Auto Scroll Toggle
                GestureDetector(
                  onTap: () {
                    setState(() => _autoScroll = !_autoScroll);
                    if (_autoScroll) _scrollToBottom();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: _autoScroll ? Colors.cyanAccent.withValues(alpha: 0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      LucideIcons.arrow_down_to_line,
                      size: 13,
                      color: _autoScroll ? Colors.cyanAccent : Colors.white38,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Copy Button
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _localLogs.join('\n')));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Logs copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: const Icon(LucideIcons.copy, size: 13, color: Colors.white38),
                ),
                const SizedBox(width: 8),
                // Clear Button
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _localLogs.clear();
                    });
                    LogService.clear();
                  },
                  child: const Icon(LucideIcons.trash_2, size: 13, color: Colors.white38),
                ),
                const SizedBox(width: 10),
                // Send to AI Button
                GestureDetector(
                  onTap: () {
                    final recentLogs = _localLogs.length > 100
                        ? _localLogs.sublist(_localLogs.length - 100)
                        : _localLogs;
                    final logText = recentLogs.join('\n');
                    ref.read(aiProvider.notifier).askAI(
                      'Here are my application logs. Please analyze them and suggest a fix for any errors or crashes:\n\n```log\n$logText\n```'
                    );
                    ref.read(rightChatPanelOpenProvider.notifier).state = true;
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.sparkles, size: 10, color: Colors.purpleAccent),
                        const SizedBox(width: 4),
                        Text(
                          'Ask AI',
                          style: GoogleFonts.inter(
                            color: Colors.purpleAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Logs Output
          Expanded(
            child: _localLogs.isEmpty
                ? Center(
                    child: Text(
                      'No logs yet. Perform actions to see output.',
                      style: GoogleFonts.inter(color: Colors.white24, fontSize: 10.5),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _localLogs.length,
                    itemBuilder: (context, index) {
                      final line = _localLogs[index];
                      // Highlight errors in red/orange
                      final isError = line.contains('Error') || line.contains('Exception') || line.contains('fail');
                      final color = isError ? Colors.redAccent.withValues(alpha: 0.8) : Colors.white70;
                      
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          line,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            color: color,
                            height: 1.2,
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
}
