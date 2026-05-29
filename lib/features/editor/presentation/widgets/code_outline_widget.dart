import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';

class OutlineItem {
  final String name;
  final String type; // 'class', 'method', 'field'
  final int lineNumber;

  OutlineItem({
    required this.name,
    required this.type,
    required this.lineNumber,
  });
}

class CodeOutlineWidget extends ConsumerStatefulWidget {
  const CodeOutlineWidget({super.key});

  @override
  ConsumerState<CodeOutlineWidget> createState() => _CodeOutlineWidgetState();
}

class _CodeOutlineWidgetState extends ConsumerState<CodeOutlineWidget> {
  List<OutlineItem> _outlineItems = [];
  String _activePath = '';
  bool _loading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _parseActiveFile());
  }

  Future<void> _parseActiveFile() async {
    final activeFile = ref.read(editorProvider).activeFilePath;
    if (activeFile == null || activeFile.isEmpty) {
      if (mounted) {
        setState(() {
          _outlineItems = [];
          _activePath = '';
          _errorMessage = 'Нет открытых файлов в редакторе';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = '';
        _activePath = activeFile;
      });
    }

    try {
      final file = File(activeFile);
      if (await file.exists()) {
        final content = await file.readAsString();
        final items = _parseContent(content, p.extension(activeFile));
        if (mounted) {
          setState(() {
            _outlineItems = items;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _outlineItems = [];
            _errorMessage = 'Файл не найден на диске';
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _outlineItems = [];
          _errorMessage = 'Ошибка парсинга: $e';
          _loading = false;
        });
      }
    }
  }

  List<OutlineItem> _parseContent(String content, String extension) {
    final lines = content.split('\n');
    final items = <OutlineItem>[];

    // Basic regex parsers for Dart/JS/TS files
    final classReg = RegExp(r'^\s*(?:abstract\s+|mixin\s+|extension\s+)?class\s+([A-Za-z0-9_]+)');
    final methodReg = RegExp(
      r'^\s*(?:(?:Future<[A-Za-z0-9_<>]+>|Stream<[A-Za-z0-9_<>]+>|void|[A-Za-z0-9_<>]+)\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*(?:async\s*)?[\{=>]'
    );
    final getSetReg = RegExp(r'^\s*(?:get|set)\s+([A-Za-z_][A-Za-z0-9_]*)');
    final jsFuncReg = RegExp(r'^\s*(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)');
    final jsMethodReg = RegExp(r'^\s*(?:async\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*\{');

    const keywords = {
      'if', 'for', 'switch', 'while', 'catch', 'return', 'assert', 'await',
      'import', 'export', 'part', 'library', 'else', 'super', 'this', 'throw', 'yield'
    };

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 1. Class detection
      final classMatch = classReg.firstMatch(line);
      if (classMatch != null) {
        items.add(OutlineItem(
          name: classMatch.group(1)!,
          type: 'class',
          lineNumber: i + 1,
        ));
        continue;
      }

      // 2. Getter/setter detection
      final getSetMatch = getSetReg.firstMatch(line);
      if (getSetMatch != null) {
        final name = getSetMatch.group(1)!;
        if (!keywords.contains(name)) {
          items.add(OutlineItem(
            name: name,
            type: 'field',
            lineNumber: i + 1,
          ));
        }
        continue;
      }

      // 3. JS/TS standard functions
      final jsFuncMatch = jsFuncReg.firstMatch(line);
      if (jsFuncMatch != null) {
        items.add(OutlineItem(
          name: jsFuncMatch.group(1)!,
          type: 'method',
          lineNumber: i + 1,
        ));
        continue;
      }

      // 4. Dart methods
      final methodMatch = methodReg.firstMatch(line);
      if (methodMatch != null) {
        final name = methodMatch.group(1)!;
        if (!keywords.contains(name) && name != 'Widget' && name != 'build') {
          items.add(OutlineItem(
            name: name,
            type: 'method',
            lineNumber: i + 1,
          ));
        }
        continue;
      }

      // 5. JS/TS methods inside classes
      final jsMethodMatch = jsMethodReg.firstMatch(line);
      if (jsMethodMatch != null) {
        final name = jsMethodMatch.group(1)!;
        if (!keywords.contains(name) && name != 'constructor') {
          items.add(OutlineItem(
            name: name,
            type: 'method',
            lineNumber: i + 1,
          ));
        }
      }
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    // Listen to editor tab change to re-parse outline
    ref.listen<int>(editorProvider.select((s) => s.activeTabIndex), (prev, next) {
      _parseActiveFile();
    });

    // Also listen to current path changes in editor
    ref.listen<String?>(editorProvider.select((s) => s.activeFilePath), (_, newPath) {
      if (newPath != _activePath) {
        _parseActiveFile();
      }
    });

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white30, fontSize: 12),
          ),
        ),
      );
    }

    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
        ),
      );
    }

    if (_outlineItems.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Структура кода пуста или не поддерживается',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          child: Row(
            children: [
              const Icon(LucideIcons.list, size: 14, color: Colors.white54),
              const SizedBox(width: 6),
              Text(
                'Структура: ${p.basename(_activePath)}',
                style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.refresh_cw, size: 12, color: Colors.white54),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _parseActiveFile,
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _outlineItems.length,
            itemBuilder: (context, index) {
              final item = _outlineItems[index];
              IconData icon;
              Color iconColor;

              switch (item.type) {
                case 'class':
                  icon = LucideIcons.box;
                  iconColor = Colors.blueAccent;
                  break;
                case 'method':
                  icon = LucideIcons.braces;
                  iconColor = Colors.purpleAccent;
                  break;
                case 'field':
                default:
                  icon = LucideIcons.key;
                  iconColor = Colors.amberAccent;
                  break;
              }

              return InkWell(
                onTap: () async {
                  await ref.read(editorProvider.notifier).openFile(
                    _activePath,
                    line: item.lineNumber - 1,
                    column: 0,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                  child: Row(
                    children: [
                      Icon(icon, size: 13, color: iconColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.name,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: item.type == 'class' ? Colors.white : Colors.white70,
                            fontWeight: item.type == 'class' ? FontWeight.w600 : FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        'L${item.lineNumber}',
                        style: const TextStyle(color: Colors.white24, fontSize: 9, fontFamily: 'monospace'),
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
}
