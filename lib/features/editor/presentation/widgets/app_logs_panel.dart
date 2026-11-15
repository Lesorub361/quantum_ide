import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/log_service.dart';
import 'package:quantum_ide/core/services/system_stats_service.dart';

enum _LogLevel { error, warning, ok, info }

class AppLogsPanel extends ConsumerStatefulWidget {
  const AppLogsPanel({super.key});

  @override
  ConsumerState<AppLogsPanel> createState() => _AppLogsPanelState();
}

class _AppLogsPanelState extends ConsumerState<AppLogsPanel> {
  final List<String> _localLogs = [];
  StreamSubscription<String>? _subscription;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _autoScroll = true;
  _LogLevel? _filterLevel; // null = all
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _localLogs.addAll(LogService.logs);
    _subscription = LogService.logStream.listen((line) {
      if (!mounted) return;
      setState(() {
        _localLogs.add(line);
        if (_localLogs.length > 1000) {
          _localLogs.removeAt(0);
        }
      });
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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
    _searchController.dispose();
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

  _LogLevel _classifyLine(String line) {
    final lower = line.toLowerCase();
    if (line.contains('[ERR]') ||
        lower.contains('flutter error') ||
        lower.contains('platform error') ||
        lower.contains('uncaught async error') ||
        lower.contains('bad state:') ||
        lower.contains('exception') ||
        lower.contains('error:') ||
        lower.contains('failed') ||
        lower.contains('crash')) {
      return _LogLevel.error;
    }
    if (line.contains('[WARN]') ||
        lower.contains('warning') ||
        lower.contains('warn:') ||
        lower.contains('timeout') ||
        lower.contains('denied')) {
      return _LogLevel.warning;
    }
    if (line.contains('[OK]') ||
        lower.contains('initialized') ||
        lower.contains('successfully') ||
        lower.contains('connected') ||
        lower.contains('started')) {
      return _LogLevel.ok;
    }
    return _LogLevel.info;
  }

  void _showLogDetailsDialog(String line, _LogLevel level) {
    final color = switch (level) {
      _LogLevel.error => Colors.redAccent,
      _LogLevel.warning => Colors.amberAccent,
      _LogLevel.ok => const Color(0xFF4ADE80),
      _LogLevel.info => Colors.cyanAccent,
    };
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF141824),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(
              level == _LogLevel.error
                  ? LucideIcons.circle_alert
                  : level == _LogLevel.warning
                      ? LucideIcons.triangle_alert
                      : level == _LogLevel.ok
                          ? LucideIcons.circle_check
                          : LucideIcons.info,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Text(
              'Подробности лога',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              line,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: line));
              Navigator.of(dialogContext).pop();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Запись скопирована'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: const Text(
              'Копировать',
              style: TextStyle(color: Colors.cyanAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'Закрыть',
              style: TextStyle(color: Colors.white60),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int errCount = 0;
    int warnCount = 0;
    int okCount = 0;

    final classified = <({String line, _LogLevel level})>[];
    for (final line in _localLogs) {
      final level = _classifyLine(line);
      switch (level) {
        case _LogLevel.error:
          errCount++;
        case _LogLevel.warning:
          warnCount++;
        case _LogLevel.ok:
          okCount++;
        case _LogLevel.info:
          break;
      }
      if (_filterLevel != null && level != _filterLevel) continue;
      if (_searchQuery.isNotEmpty &&
          !line.toLowerCase().contains(_searchQuery.toLowerCase())) {
        continue;
      }
      classified.add((line: line, level: level));
    }

    return Container(
      color: const Color(0xFF090B0F),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Control Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  errCount > 0 ? LucideIcons.circle_alert : LucideIcons.activity,
                  size: 14,
                  color: errCount > 0 ? Colors.redAccent : const Color(0xFF4ADE80),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    errCount > 0
                        ? 'Логи • Ошибок: $errCount'
                        : 'Логи • Всё работает',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: errCount > 0 ? Colors.redAccent : Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Free RAM / kill idle background daemons
                Tooltip(
                  message: 'Освободить RAM (остановить фоновые демоны)',
                  child: InkWell(
                    onTap: () async {
                      await ref
                          .read(systemStatsProvider.notifier)
                          .freeBackgroundMemory(force: true);
                      LogService.log('[OK] Фоновые демоны остановлены, RAM освобождена');
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Фоновая память очищена'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(5),
                      child: Icon(
                        LucideIcons.zap,
                        size: 13,
                        color: Colors.amberAccent,
                      ),
                    ),
                  ),
                ),
                // Auto Scroll Toggle
                Tooltip(
                  message: 'Автопрокрутка',
                  child: InkWell(
                    onTap: () {
                      setState(() => _autoScroll = !_autoScroll);
                      if (_autoScroll) _scrollToBottom();
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: _autoScroll
                            ? Colors.cyanAccent.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        LucideIcons.arrow_down_to_line,
                        size: 13,
                        color: _autoScroll ? Colors.cyanAccent : Colors.white38,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Copy Button
                Tooltip(
                  message: 'Копировать логи',
                  child: InkWell(
                    onTap: () {
                      final text = classified.map((e) => e.line).join('\n');
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Логи скопированы в буфер'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(5),
                      child: Icon(
                        LucideIcons.copy,
                        size: 13,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
                // Full Talker Screen
                Tooltip(
                  message: 'Открыть полные логи (Talker)',
                  child: InkWell(
                    onTap: () => context.push('/logs'),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(5),
                      child: Icon(
                        LucideIcons.maximize_2,
                        size: 13,
                        color: Colors.cyanAccent,
                      ),
                    ),
                  ),
                ),
                // Clear Button
                Tooltip(
                  message: 'Очистить',
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _localLogs.clear();
                      });
                      LogService.clear();
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(5),
                      child: Icon(
                        LucideIcons.trash_2,
                        size: 13,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Health & Filter Chips ("Что работает / Что нет")
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'Все (${_localLogs.length})',
                    color: Colors.cyanAccent,
                    selected: _filterLevel == null,
                    onTap: () => setState(() => _filterLevel = null),
                  ),
                  const SizedBox(width: 5),
                  _FilterChip(
                    label: 'Ошибки ($errCount)',
                    color: Colors.redAccent,
                    selected: _filterLevel == _LogLevel.error,
                    onTap: () => setState(
                      () => _filterLevel =
                          _filterLevel == _LogLevel.error ? null : _LogLevel.error,
                    ),
                  ),
                  const SizedBox(width: 5),
                  _FilterChip(
                    label: 'Предупр. ($warnCount)',
                    color: Colors.amberAccent,
                    selected: _filterLevel == _LogLevel.warning,
                    onTap: () => setState(
                      () => _filterLevel = _filterLevel == _LogLevel.warning
                          ? null
                          : _LogLevel.warning,
                    ),
                  ),
                  const SizedBox(width: 5),
                  _FilterChip(
                    label: 'OK ($okCount)',
                    color: const Color(0xFF4ADE80),
                    selected: _filterLevel == _LogLevel.ok,
                    onTap: () => setState(
                      () => _filterLevel =
                          _filterLevel == _LogLevel.ok ? null : _LogLevel.ok,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Search Box
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  hintText: 'Поиск по логам...',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 10.5,
                    color: Colors.white30,
                  ),
                  prefixIcon: const Icon(
                    LucideIcons.search,
                    size: 12,
                    color: Colors.white38,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: const Icon(
                            LucideIcons.x,
                            size: 12,
                            color: Colors.white38,
                          ),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: Colors.cyanAccent.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Logs Output
          Expanded(
            child: classified.isEmpty
                ? Center(
                    child: Text(
                      _localLogs.isEmpty
                          ? 'Логов пока нет. Выполните действие в IDE.'
                          : 'Нет записей по выбранному фильтру.',
                      style: GoogleFonts.inter(
                        color: Colors.white24,
                        fontSize: 10.5,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: classified.length,
                    itemBuilder: (context, index) {
                      final entry = classified[index];
                      final (badge, color) = switch (entry.level) {
                        _LogLevel.error => ('ERR', Colors.redAccent),
                        _LogLevel.warning => ('WARN', Colors.amberAccent),
                        _LogLevel.ok => ('OK', const Color(0xFF4ADE80)),
                        _LogLevel.info => ('INFO', Colors.white54),
                      };

                      return InkWell(
                        onTap: () =>
                            _showLogDetailsDialog(entry.line, entry.level),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 1.5),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: entry.level == _LogLevel.error
                                ? Colors.redAccent.withValues(alpha: 0.08)
                                : entry.level == _LogLevel.warning
                                    ? Colors.amberAccent.withValues(alpha: 0.06)
                                    : Colors.transparent,
                            border: Border(
                              left: BorderSide(
                                color: color.withValues(alpha: 0.75),
                                width: 2,
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 1, right: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 0.5,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  badge,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  entry.line,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    color: entry.level == _LogLevel.error
                                        ? Colors.redAccent.shade100
                                        : Colors.white.withValues(alpha: 0.82),
                                    height: 1.25,
                                  ),
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
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.65)
                : Colors.white.withValues(alpha: 0.08),
            width: 0.7,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? color : Colors.white60,
          ),
        ),
      ),
    );
  }
}
