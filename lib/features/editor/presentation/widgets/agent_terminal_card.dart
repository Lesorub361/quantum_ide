import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

/// Карточка вывода команды в стиле встроенного терминала VS Code:
/// заголовок с командой и статусом, ANSI-цвета, автопрокрутка, копирование,
/// сворачивание и остановка.
class AgentTerminalCard extends StatefulWidget {
  final String command;
  final String output;
  final bool isRunning;
  final int? exitCode;
  final Duration? duration;
  final bool canRun;
  final VoidCallback? onRun;
  final VoidCallback? onStop;

  const AgentTerminalCard({
    super.key,
    required this.command,
    required this.output,
    this.isRunning = false,
    this.exitCode,
    this.duration,
    this.canRun = false,
    this.onRun,
    this.onStop,
  });

  @override
  State<AgentTerminalCard> createState() => _AgentTerminalCardState();
}

class _AgentTerminalCardState extends State<AgentTerminalCard> {
  static const _bg = Color(0xFF181818);
  static const _bar = Color(0xFF1F1F1F);
  static const _maxCollapsedLines = 14;

  final _scroll = ScrollController();
  bool _collapsed = false;
  bool _expandedAll = false;

  @override
  void didUpdateWidget(covariant AgentTerminalCard old) {
    super.didUpdateWidget(old);
    if (widget.isRunning && widget.output.length != old.output.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Color get _accent {
    if (widget.isRunning) return const Color(0xFF60A5FA);
    if (widget.exitCode == null) return Colors.white38;
    return widget.exitCode == 0 ? const Color(0xFF34D399) : const Color(0xFFF87171);
  }

  String _fmtDuration(Duration d) {
    if (d.inSeconds < 1) return '${d.inMilliseconds} мс';
    if (d.inMinutes < 1) return '${(d.inMilliseconds / 1000).toStringAsFixed(1)} с';
    return '${d.inMinutes}м ${d.inSeconds % 60}с';
  }

  @override
  Widget build(BuildContext context) {
    final hasOutput = widget.output.trim().isNotEmpty;
    final lines = widget.output.trimRight().split('\n');
    final truncated = !_expandedAll && !widget.isRunning && lines.length > _maxCollapsedLines;
    final shownText = truncated
        ? lines.sublist(lines.length - _maxCollapsedLines).join('\n')
        : widget.output.trimRight();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Заголовок ──
          InkWell(
            onTap: hasOutput ? () => setState(() => _collapsed = !_collapsed) : null,
            child: Container(
              color: _bar,
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              child: Row(
                children: [
                  Icon(LucideIcons.terminal, size: 13, color: _accent),
                  const SizedBox(width: 7),
                  Text('bash',
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 10, color: Colors.white38, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.command,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _statusBadge(),
                  _iconBtn(LucideIcons.copy, 'Копировать вывод', () {
                    Clipboard.setData(ClipboardData(text: hasOutput ? widget.output : widget.command));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Скопировано'), duration: Duration(seconds: 1)),
                    );
                  }),
                  if (hasOutput)
                    _iconBtn(_collapsed ? LucideIcons.chevron_right : LucideIcons.chevron_down,
                        _collapsed ? 'Развернуть' : 'Свернуть', () => setState(() => _collapsed = !_collapsed)),
                ],
              ),
            ),
          ),
          if (widget.isRunning)
            LinearProgressIndicator(minHeight: 1.5, color: _accent, backgroundColor: Colors.transparent),

          // ── Вывод ──
          if (hasOutput && !_collapsed)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: _expandedAll ? 420 : 240),
              child: Scrollbar(
                controller: _scroll,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText.rich(
                      TextSpan(children: AnsiParser.parse(shownText)),
                      style: GoogleFonts.jetBrainsMono(fontSize: 10.5, height: 1.45, color: const Color(0xFFD1D5DB)),
                    ),
                  ),
                ),
              ),
            ),
          if (truncated && !_collapsed)
            InkWell(
              onTap: () => setState(() => _expandedAll = true),
              child: Container(
                color: _bar,
                padding: const EdgeInsets.symmetric(vertical: 5),
                alignment: Alignment.center,
                child: Text('Показать весь вывод (${lines.length} строк)',
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFFA78BFA))),
              ),
            ),

          // ── Действия ──
          if (widget.isRunning || widget.canRun)
            Container(
              color: _bar,
              padding: const EdgeInsets.all(6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.isRunning)
                    _actionBtn(LucideIcons.square, 'Остановить', const Color(0xFFF87171), widget.onStop)
                  else
                    _actionBtn(
                      widget.exitCode == null ? LucideIcons.play : LucideIcons.rotate_cw,
                      widget.exitCode == null ? 'Запустить' : 'Повторить',
                      const Color(0xFF34D399),
                      widget.onRun,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBadge() {
    final String label;
    final IconData icon;
    if (widget.isRunning) {
      label = 'выполняется';
      icon = LucideIcons.loader;
    } else if (widget.exitCode == null) {
      label = 'ожидает';
      icon = LucideIcons.circle_dot;
    } else if (widget.exitCode == 0) {
      label = widget.duration != null ? _fmtDuration(widget.duration!) : 'ok';
      icon = LucideIcons.circle_check;
    } else {
      label = 'exit ${widget.exitCode}';
      icon = LucideIcons.circle_x;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: _accent),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 9.5, color: _accent, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback onTap) => IconButton(
        icon: Icon(icon, size: 13, color: Colors.white54),
        tooltip: tip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 26, height: 24),
        onPressed: onTap,
      );

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback? onTap) => TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: color,
          backgroundColor: color.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        icon: Icon(icon, size: 12),
        label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        onPressed: onTap,
      );
}

/// Минимальный разбор ANSI SGR-последовательностей в [TextSpan]
/// (цвета 16/256/truecolor, bold, dim, underline). Прочие escape-коды вырезаются.
class AnsiParser {
  static final _csi = RegExp(r'\x1B\[([0-9;?]*)([A-Za-z])');
  static final _osc = RegExp(r'\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)');

  static const _base = [
    Color(0xFF3B4252), Color(0xFFF87171), Color(0xFF34D399), Color(0xFFFBBF24),
    Color(0xFF60A5FA), Color(0xFFC084FC), Color(0xFF22D3EE), Color(0xFFE5E7EB),
  ];
  static const _bright = [
    Color(0xFF6B7280), Color(0xFFFCA5A5), Color(0xFF6EE7B7), Color(0xFFFDE68A),
    Color(0xFF93C5FD), Color(0xFFD8B4FE), Color(0xFF67E8F9), Color(0xFFFFFFFF),
  ];

  static Color _color256(int n) {
    if (n < 8) return _base[n];
    if (n < 16) return _bright[n - 8];
    if (n >= 232) {
      final v = 8 + (n - 232) * 10;
      return Color.fromARGB(255, v, v, v);
    }
    n -= 16;
    int c(int x) => x == 0 ? 0 : 55 + x * 40;
    return Color.fromARGB(255, c(n ~/ 36), c((n ~/ 6) % 6), c(n % 6));
  }

  static List<TextSpan> parse(String input) {
    final text = input.replaceAll(_osc, '').replaceAll('\r\n', '\n').replaceAll(RegExp(r'[^\n]*\r(?!\n)'), '');
    final spans = <TextSpan>[];
    Color? fg;
    var bold = false, dim = false, underline = false;
    var pos = 0;

    TextStyle? style() => (fg == null && !bold && !dim && !underline)
        ? null
        : TextStyle(
            color: fg == null ? null : (dim ? fg!.withValues(alpha: 0.6) : fg),
            fontWeight: bold ? FontWeight.w700 : null,
            decoration: underline ? TextDecoration.underline : null,
          );

    for (final m in _csi.allMatches(text)) {
      if (m.start > pos) spans.add(TextSpan(text: text.substring(pos, m.start), style: style()));
      pos = m.end;
      if (m.group(2) != 'm') continue;
      final codes = (m.group(1) ?? '').split(';').map((e) => int.tryParse(e) ?? 0).toList();
      if (codes.isEmpty) codes.add(0);
      for (var i = 0; i < codes.length; i++) {
        final c = codes[i];
        if (c == 0) {
          fg = null; bold = dim = underline = false;
        } else if (c == 1) {
          bold = true;
        } else if (c == 2) {
          dim = true;
        } else if (c == 4) {
          underline = true;
        } else if (c == 22) {
          bold = dim = false;
        } else if (c == 24) {
          underline = false;
        } else if (c >= 30 && c <= 37) {
          fg = _base[c - 30];
        } else if (c >= 90 && c <= 97) {
          fg = _bright[c - 90];
        } else if (c == 39) {
          fg = null;
        } else if (c == 38 && i + 1 < codes.length) {
          if (codes[i + 1] == 5 && i + 2 < codes.length) {
            fg = _color256(codes[i + 2]);
            i += 2;
          } else if (codes[i + 1] == 2 && i + 4 < codes.length) {
            fg = Color.fromARGB(255, codes[i + 2] & 255, codes[i + 3] & 255, codes[i + 4] & 255);
            i += 4;
          }
        }
      }
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos), style: style()));
    return spans;
  }
}
