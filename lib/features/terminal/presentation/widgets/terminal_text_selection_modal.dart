import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:xterm/xterm.dart' as xt;

class TerminalTextSelectionModal extends StatefulWidget {
  final xt.Terminal terminal;
  final String title;

  const TerminalTextSelectionModal({
    super.key,
    required this.terminal,
    required this.title,
  });

  static Future<void> show(BuildContext context, xt.Terminal terminal, String title) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TerminalTextSelectionModal(
        terminal: terminal,
        title: title,
      ),
    );
  }

  @override
  State<TerminalTextSelectionModal> createState() => _TerminalTextSelectionModalState();
}

class _TerminalTextSelectionModalState extends State<TerminalTextSelectionModal> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _extractedText = '';
  List<String> _lines = [];
  String _searchQuery = '';
  int _matchCount = 0;

  @override
  void initState() {
    super.initState();
    _extractText();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _extractText() {
    final buffer = widget.terminal.buffer;
    final linesList = <String>[];
    for (var i = 0; i < buffer.lines.length; i++) {
      linesList.add(buffer.lines[i].toString().trimRight());
    }
    // Remove trailing empty lines
    while (linesList.isNotEmpty && linesList.last.isEmpty) {
      linesList.removeLast();
    }
    _lines = linesList;
    _extractedText = linesList.join('\n');
    _updateSearchMatches();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim();
      _updateSearchMatches();
    });
  }

  void _updateSearchMatches() {
    if (_searchQuery.isEmpty) {
      _matchCount = 0;
      return;
    }
    final q = _searchQuery.toLowerCase();
    int count = 0;
    for (final line in _lines) {
      int idx = 0;
      final lineLower = line.toLowerCase();
      while ((idx = lineLower.indexOf(q, idx)) != -1) {
        count++;
        idx += q.length;
      }
    }
    _matchCount = count;
  }

  Future<void> _copyAll() async {
    HapticFeedback.lightImpact();
    if (_extractedText.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: _extractedText));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(LucideIcons.check, color: Colors.greenAccent, size: 16),
                const SizedBox(width: 8),
                Text('Весь вывод скопирован (${_lines.length} строк)'),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
            backgroundColor: const Color(0xFF1E2230),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isDesktop = mediaQuery.size.width > 800;

    return Container(
      height: mediaQuery.size.height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFF0F1219),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        border: Border(
          top: BorderSide(color: Color(0x3322D3EE), width: 1),
          left: BorderSide(color: Color(0x1AFFFFFF), width: 0.5),
          right: BorderSide(color: Color(0x1AFFFFFF), width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 12, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.2)),
                    ),
                    child: const Icon(LucideIcons.text_cursor_input, size: 16, color: Colors.cyanAccent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Выделение текста терминала',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '${widget.title} • ${_lines.length} строк • Удерживайте для курсора выделения',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.copy, size: 16, color: Colors.cyanAccent),
                    tooltip: 'Скопировать всё',
                    onPressed: _copyAll,
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 18, color: Colors.white60),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Container(
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _searchQuery.isNotEmpty
                        ? Colors.cyanAccent.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(LucideIcons.search, size: 14, color: Colors.white38),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Поиск по тексту вывода...',
                          hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white24),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '$_matchCount совп.',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: _matchCount > 0 ? Colors.cyanAccent : Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          _searchController.clear();
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(LucideIcons.x, size: 14, color: Colors.white38),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Selectable Content Container
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF07090E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: _extractedText.isEmpty
                    ? Center(
                        child: Text(
                          'Терминал пуст',
                          style: GoogleFonts.inter(color: Colors.white24, fontSize: 13),
                        ),
                      )
                    : Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: isDesktop,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          physics: const BouncingScrollPhysics(),
                          scrollDirection: Axis.vertical,
                          child: SelectionArea(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: SelectableText(
                                _extractedText,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11.5,
                                  color: const Color(0xFFE2E8F0),
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            // Bottom quick toolbar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(LucideIcons.copy, size: 14, color: Colors.cyanAccent),
                      label: Text(
                        'Скопировать весь вывод',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.cyanAccent, fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _copyAll,
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Готово', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
