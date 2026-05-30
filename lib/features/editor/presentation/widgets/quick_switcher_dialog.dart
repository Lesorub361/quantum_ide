import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/services/symbol_indexer_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/core/utils/file_icon_helper.dart';

enum SwitcherMode { files, symbols }

class QuickSwitcherDialog extends ConsumerStatefulWidget {
  final SwitcherMode initialMode;
  const QuickSwitcherDialog({
    super.key,
    this.initialMode = SwitcherMode.files,
  });

  static void show(BuildContext context, {SwitcherMode initialMode = SwitcherMode.files}) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => QuickSwitcherDialog(initialMode: initialMode),
    );
  }

  @override
  ConsumerState<QuickSwitcherDialog> createState() => _QuickSwitcherDialogState();
}

class _QuickSwitcherDialogState extends ConsumerState<QuickSwitcherDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final FocusNode _keyboardFocus = FocusNode();
  
  SwitcherMode _mode = SwitcherMode.files;
  List<dynamic> _results = [];
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _controller.addListener(_onSearchChanged);
    _inputFocus.requestFocus();
    
    // Initial results loading
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateResults();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    _keyboardFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final text = _controller.text;
    SwitcherMode newMode = _mode;
    
    if (text.startsWith('#')) {
      newMode = SwitcherMode.symbols;
    } else {
      newMode = SwitcherMode.files;
    }

    if (newMode != _mode) {
      setState(() {
        _mode = newMode;
        _selectedIndex = 0;
      });
    }

    _updateResults();
  }

  void _updateResults() {
    final text = _controller.text;
    final query = text.startsWith('#') ? text.substring(1) : text;
    
    final indexer = ref.read(symbolIndexerProvider.notifier);
    
    setState(() {
      if (_mode == SwitcherMode.files) {
        _results = indexer.searchFiles(query);
      } else {
        _results = indexer.searchSymbols(query);
      }
      
      if (_selectedIndex >= _results.length) {
        _selectedIndex = 0;
      }
    });
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_results.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % _results.length;
        });
        _scrollToSelected();
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (_results.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex - 1 + _results.length) % _results.length;
        });
        _scrollToSelected();
      }
    } else if (key == LogicalKeyboardKey.enter) {
      _openSelected();
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
    }
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    const itemHeight = 44.0;
    final viewHeight = _scrollController.position.viewportDimension;
    final targetOffset = _selectedIndex * itemHeight;

    if (targetOffset < _scrollController.offset) {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    } else if (targetOffset + itemHeight > _scrollController.offset + viewHeight) {
      _scrollController.animateTo(
        targetOffset + itemHeight - viewHeight,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  void _openSelected() {
    if (_results.isEmpty || _selectedIndex >= _results.length) return;
    final item = _results[_selectedIndex];
    
    Navigator.pop(context);
    
    if (_mode == SwitcherMode.files) {
      final String path = item as String;
      ref.read(editorProvider.notifier).openFile(path);
    } else {
      final IndexSymbol symbol = item as IndexSymbol;
      ref.read(editorProvider.notifier).openFile(
        symbol.filePath,
        line: symbol.lineNumber - 1,
        column: 0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspaceRoot = ref.watch(workspaceProvider).currentPath ?? '';
    final l10n = AppLocalizations.of(context)!;

    return KeyboardListener(
      focusNode: _keyboardFocus,
      onKeyEvent: _handleKey,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
        child: Container(
          width: 500,
          constraints: const BoxConstraints(maxHeight: 450),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2230).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search Input Section
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  controller: _controller,
                  focusNode: _inputFocus,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    prefixIcon: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.purpleAccent, Colors.cyanAccent],
                      ).createShader(bounds),
                      child: Icon(
                        _mode == SwitcherMode.files ? LucideIcons.search : LucideIcons.list,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(LucideIcons.x, size: 14, color: Colors.white30),
                            onPressed: () => _controller.clear(),
                          )
                        : null,
                    hintText: _mode == SwitcherMode.files
                        ? l10n.searchFilesHint
                        : l10n.searchSymbolsHint,
                    hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
                    filled: true,
                    fillColor: Colors.black26,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFFF3C3C), width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                  ),
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              
              // Mode Indicator & Stats
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(
                  children: [
                    Text(
                      _mode == SwitcherMode.files
                          ? l10n.modeFiles
                          : l10n.modeSymbols,
                      style: GoogleFonts.inter(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: _mode == SwitcherMode.files ? Colors.cyanAccent : Colors.purpleAccent,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      l10n.resultsCount(_results.length),
                      style: GoogleFonts.inter(fontSize: 8.5, color: Colors.white30),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),

              // Search Results List
              Expanded(
                child: _results.isEmpty
                    ? Center(
                        child: Text(
                          l10n.noResults,
                          style: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _results.length,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemBuilder: (context, index) {
                          final isSelected = index == _selectedIndex;
                          final item = _results[index];
                          
                          Widget icon;
                          String title;
                          String subtitle;

                          if (_mode == SwitcherMode.files) {
                            final filePath = item as String;
                            final fileName = p.basename(filePath);
                            final iconInfo = FileIconHelper.getIconInfo(fileName, false);
                            
                            icon = Icon(iconInfo.icon, size: 14, color: iconInfo.color);
                            title = fileName;
                            subtitle = workspaceRoot.isNotEmpty && filePath.startsWith(workspaceRoot)
                                ? p.relative(filePath, from: workspaceRoot)
                                : filePath;
                          } else {
                            final symbol = item as IndexSymbol;
                            
                            IconData symIcon;
                            Color symColor;
                            switch (symbol.type) {
                              case 'class':
                                symIcon = LucideIcons.box;
                                symColor = Colors.blueAccent;
                                break;
                              case 'method':
                                symIcon = LucideIcons.braces;
                                symColor = Colors.purpleAccent;
                                break;
                              default:
                                symIcon = LucideIcons.key;
                                symColor = Colors.amberAccent;
                            }
                            
                            icon = Icon(symIcon, size: 14, color: symColor);
                            title = symbol.name;
                            
                            final relPath = workspaceRoot.isNotEmpty && symbol.filePath.startsWith(workspaceRoot)
                                ? p.relative(symbol.filePath, from: workspaceRoot)
                                : symbol.filePath;
                            subtitle = '$relPath : L${symbol.lineNumber}';
                          }

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedIndex = index;
                              });
                              _openSelected();
                            },
                            child: Container(
                              height: 44,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? const Color(0xFFFF3C3C).withValues(alpha: 0.12)
                                    : Colors.transparent,
                                border: Border(
                                  left: BorderSide(
                                    color: isSelected ? const Color(0xFFFF3C3C) : Colors.transparent,
                                    width: 3.5,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  icon,
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          title,
                                          style: GoogleFonts.inter(
                                            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.87),
                                            fontSize: 12.5,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          subtitle,
                                          style: GoogleFonts.inter(
                                            color: isSelected ? Colors.white60 : Colors.white30,
                                            fontSize: 9.5,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      LucideIcons.corner_down_left,
                                      size: 12,
                                      color: Color(0xFFFF3C3C),
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
        ),
      ),
    );
  }
}
