import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/core/utils/file_icon_helper.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

class GlobalSearchPanel extends ConsumerStatefulWidget {
  const GlobalSearchPanel({super.key});

  @override
  ConsumerState<GlobalSearchPanel> createState() => _GlobalSearchPanelState();
}

class _SearchMatch {
  final int lineNumber;
  final String lineContent;
  final int startOffset;
  final int endOffset;

  _SearchMatch({
    required this.lineNumber,
    required this.lineContent,
    required this.startOffset,
    required this.endOffset,
  });
}

class _FileSearchGroup {
  final String filePath;
  final String fileName;
  final List<_SearchMatch> matches;
  bool isExpanded;

  _FileSearchGroup({
    required this.filePath,
    required this.fileName,
    required this.matches,
  }) : isExpanded = true;
}

class _GlobalSearchPanelState extends ConsumerState<GlobalSearchPanel> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounceTimer;
  
  bool _caseSensitive = false;
  bool _useRegex = false;
  bool _wholeWord = false;
  
  bool _searching = false;
  List<_FileSearchGroup> _results = [];
  String? _statusKey;
  Map<String, dynamic>? _statusArgs;

  @override
  void dispose() {
    _controller.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _performSearch();
    });
  }

  Future<void> _performSearch() async {
    final query = _controller.text;
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _statusKey = null;
        _statusArgs = null;
        _searching = false;
      });
      return;
    }

    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null || workspacePath.isEmpty) {
      setState(() {
        _results = [];
        _statusKey = 'projectNotOpened';
        _statusArgs = null;
        _searching = false;
      });
      return;
    }

    setState(() {
      _searching = true;
      _statusKey = 'searchingInProgress';
      _statusArgs = null;
    });

    try {
      final List<_FileSearchGroup> searchResults = [];
      final dir = Directory(workspacePath);
      
      if (await dir.exists()) {
        final List<FileSystemEntity> entities = await dir.list(recursive: true).toList();
        
        // Prepare regex
        RegExp regex;
        if (_useRegex) {
          try {
            regex = RegExp(query, caseSensitive: _caseSensitive);
          } catch (e) {
            setState(() {
              _statusKey = 'searchInvalidRegex';
              _statusArgs = null;
              _searching = false;
            });
            return;
          }
        } else {
          String escapedQuery = RegExp.escape(query);
          if (_wholeWord) {
            escapedQuery = '\\b$escapedQuery\\b';
          }
          regex = RegExp(escapedQuery, caseSensitive: _caseSensitive);
        }

        for (final entity in entities) {
          if (entity is File) {
            final relPath = p.relative(entity.path, from: workspacePath);
            // Skip binary, lock, builds, or git folders
            if (relPath.startsWith('.git/') ||
                relPath.startsWith('.dart_tool/') ||
                relPath.startsWith('build/') ||
                relPath.contains('.flutter-plugins') ||
                relPath.endsWith('.png') ||
                relPath.endsWith('.jpg') ||
                relPath.endsWith('.jpeg') ||
                relPath.endsWith('.zip') ||
                relPath.endsWith('.apk') ||
                relPath.endsWith('.lock') ||
                relPath.endsWith('.exe')) {
              continue;
            }

            try {
              final content = await entity.readAsString();
              final lines = content.split('\n');
              final List<_SearchMatch> matchesInFile = [];

              for (int i = 0; i < lines.length; i++) {
                final line = lines[i];
                final iterable = regex.allMatches(line);
                for (final match in iterable) {
                  matchesInFile.add(_SearchMatch(
                    lineNumber: i + 1,
                    lineContent: line,
                    startOffset: match.start,
                    endOffset: match.end,
                  ));
                }
              }

              if (matchesInFile.isNotEmpty) {
                searchResults.add(_FileSearchGroup(
                  filePath: entity.path,
                  fileName: p.basename(entity.path),
                  matches: matchesInFile,
                ));
              }
            } catch (_) {
              // Ignore file read errors (e.g. invalid encoding)
            }
          }
        }
      }

      int totalMatches = searchResults.fold(0, (sum, group) => sum + group.matches.length);

      setState(() {
        _results = searchResults;
        _searching = false;
        if (searchResults.isEmpty) {
          _statusKey = 'searchNoMatches';
          _statusArgs = null;
        } else {
          _statusKey = 'searchMatchesFound';
          _statusArgs = {'matches': totalMatches, 'files': _results.length};
        }
      });
    } catch (e) {
      setState(() {
        _searching = false;
        _statusKey = 'searchError';
        _statusArgs = {'error': e.toString()};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    String resolvedStatus = '';
    if (_statusKey != null) {
      if (_statusKey == 'projectNotOpened') {
        resolvedStatus = l10n.projectNotOpened;
      } else if (_statusKey == 'searchingInProgress') {
        resolvedStatus = l10n.searchingInProgress;
      } else if (_statusKey == 'searchInvalidRegex') {
        resolvedStatus = l10n.searchInvalidRegex;
      } else if (_statusKey == 'searchNoMatches') {
        resolvedStatus = l10n.searchNoMatches;
      } else if (_statusKey == 'searchMatchesFound') {
        final matches = _statusArgs?['matches'] as int? ?? 0;
        final files = _statusArgs?['files'] as int? ?? 0;
        resolvedStatus = l10n.searchMatchesFound(matches, files);
      } else if (_statusKey == 'searchError') {
        final error = _statusArgs?['error'] as String? ?? '';
        resolvedStatus = l10n.searchError(error);
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                onChanged: (_) => _onSearchChanged(),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: l10n.searchPlaceholder,
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                  prefixIcon: const Icon(LucideIcons.search, size: 14, color: Colors.white30),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  filled: true,
                  suffixIcon: _controller.text.isNotEmpty ? IconButton(
                    icon: const Icon(LucideIcons.x, size: 12, color: Colors.white30),
                    onPressed: () {
                      _controller.clear();
                      _performSearch();
                    },
                  ) : null,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _buildToggleOption(
                    label: 'Aa',
                    tooltip: l10n.searchCaseSensitive,
                    value: _caseSensitive,
                    onTap: () {
                      setState(() => _caseSensitive = !_caseSensitive);
                      _performSearch();
                    },
                  ),
                  const SizedBox(width: 6),
                  _buildToggleOption(
                    label: '""',
                    tooltip: l10n.searchWholeWord,
                    value: _wholeWord,
                    onTap: () {
                      setState(() => _wholeWord = !_wholeWord);
                      _performSearch();
                    },
                  ),
                  const SizedBox(width: 6),
                  _buildToggleOption(
                    label: '.*',
                    tooltip: l10n.searchRegex,
                    value: _useRegex,
                    onTap: () {
                      setState(() => _useRegex = !_useRegex);
                      _performSearch();
                    },
                  ),
                  const Spacer(),
                  if (_searching)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.redAccent),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (resolvedStatus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                resolvedStatus,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ),
        const Divider(color: Colors.white10, height: 12),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Text(
                    _searching ? l10n.searchingInProgress : l10n.searchPrompt,
                    style: const TextStyle(color: Colors.white24, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final group = _results[index];
                    return _buildFileGroupWidget(group);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildToggleOption({
    required String label,
    required String tooltip,
    required bool value,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: value ? Colors.redAccent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: value ? Colors.redAccent.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.05),
              width: 0.8,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: value ? Colors.redAccent : Colors.white60,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileGroupWidget(_FileSearchGroup group) {
    final workspaceRoot = ref.read(workspaceProvider).currentPath ?? '';
    final relativePath = p.relative(group.filePath, from: workspaceRoot);
    final iconInfo = FileIconHelper.getIconInfo(group.fileName, false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              group.isExpanded = !group.isExpanded;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
            child: Row(
              children: [
                Icon(
                  group.isExpanded ? LucideIcons.chevron_down : LucideIcons.chevron_right,
                  size: 14,
                  color: Colors.white30,
                ),
                const SizedBox(width: 4),
                Icon(iconInfo.icon, size: 14, color: iconInfo.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        group.fileName,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.87),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          relativePath,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: Colors.white38,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${group.matches.length}',
                  style: const TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
        if (group.isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 18.0),
            child: Column(
              children: group.matches.map((match) => _buildMatchWidget(group.filePath, match)).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildMatchWidget(String filePath, _SearchMatch match) {
    // Break the matching line into parts to highlight the matching section
    final String content = match.lineContent;
    final int start = match.startOffset;
    final int end = match.endOffset;

    List<TextSpan> textSpans = [];

    if (start > 0 && start <= content.length) {
      String prefix = content.substring(0, start);
      // Trim start of long prefix to fit nicely
      if (prefix.length > 30) {
        prefix = '...${prefix.substring(prefix.length - 27)}';
      }
      textSpans.add(TextSpan(text: prefix, style: const TextStyle(color: Colors.white54)));
    }

    if (start < end && end <= content.length) {
      textSpans.add(TextSpan(
        text: content.substring(start, end),
        style: const TextStyle(
          color: Colors.white,
          backgroundColor: Color(0x7FFF3C3C), // Semi-transparent Mandy Red highlight
          fontWeight: FontWeight.bold,
        ),
      ));
    }

    if (end < content.length) {
      String suffix = content.substring(end);
      if (suffix.length > 40) {
        suffix = '${suffix.substring(0, 37)}...';
      }
      textSpans.add(TextSpan(text: suffix, style: const TextStyle(color: Colors.white54)));
    }

    return InkWell(
      onTap: () async {
        await ref.read(editorProvider.notifier).openFile(
          filePath,
          line: match.lineNumber - 1,
          column: 0,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              alignment: Alignment.centerRight,
              child: Text(
                '${match.lineNumber}:',
                style: const TextStyle(color: Colors.white30, fontSize: 10, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: GoogleFonts.inter(fontSize: 11),
                  children: textSpans,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
