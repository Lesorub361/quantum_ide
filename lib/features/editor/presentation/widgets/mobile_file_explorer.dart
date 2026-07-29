import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/file_tree_node.dart';
import 'package:quantum_ide/core/utils/file_icon_helper.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

/// Mobile-optimized file explorer using bottom sheet
/// Provides full-screen file browsing with large touch targets
class MobileFileExplorer extends ConsumerStatefulWidget {
  const MobileFileExplorer({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.95,
        minChildSize: 0.5,
        maxChildSize: 0.98,
        builder: (context, scrollController) => const MobileFileExplorer(),
      ),
    );
  }

  @override
  ConsumerState<MobileFileExplorer> createState() => _MobileFileExplorerState();
}

class _MobileFileExplorerState extends ConsumerState<MobileFileExplorer> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspacePath = ref.watch(workspaceProvider).currentPath ?? '';
    final l10n = AppLocalizations.of(context)!;
    final screenSize = MediaQuery.of(context).size;

    return Container(
      height: screenSize.height * 0.95,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0F14),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _buildHandle(),
          _buildHeader(l10n),
          _buildSearchBar(l10n),
          if (workspacePath.isNotEmpty)
            Expanded(
              child: _buildFileTree(workspacePath, l10n),
            )
          else
            _buildEmptyState(l10n),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.blue, Colors.cyan],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(LucideIcons.folder, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.explorer,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  ref.watch(workspaceProvider).currentPath?.split('/').last ?? '',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, color: Colors.white54, size: 24),
            onPressed: () => Navigator.pop(context),
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
            style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: l10n.searchFiles,
              hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 15),
              prefixIcon: const Icon(LucideIcons.search, color: Colors.white38, size: 18),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(LucideIcons.x, color: Colors.white38, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildMobileFilterChip('All', ''),
                const SizedBox(width: 6),
                _buildMobileFilterChip('Dart', '.dart'),
                const SizedBox(width: 6),
                _buildMobileFilterChip('YAML', '.yaml'),
                const SizedBox(width: 6),
                _buildMobileFilterChip('JSON', '.json'),
                const SizedBox(width: 6),
                _buildMobileFilterChip('Web', '.html'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileFilterChip(String label, String filter) {
    final isSelected = _searchQuery == filter;
    return InkWell(
      onTap: () {
        setState(() {
          _searchQuery = filter;
          _searchController.text = filter;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4CD7F6).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF4CD7F6).withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? const Color(0xFF4CD7F6) : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildFileTree(String workspacePath, AppLocalizations l10n) {
    return FileTreeNode(
      path: workspacePath,
      name: p.basename(workspacePath),
      isDirectory: true,
      depth: 0,
      ancestorIsLast: [],
      isLast: true,
      onRefreshParent: () => setState(() {}),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.folder_search,
              size: 64,
              color: Colors.white.withValues(alpha: 0.1),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.projectNotOpened,
              style: GoogleFonts.inter(
                color: Colors.white38,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.selectFileToStart,
              style: GoogleFonts.inter(
                color: Colors.white24,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Touch-optimized file tree node for mobile
class MobileFileTreeNode extends ConsumerStatefulWidget {
  final String path;
  final String name;
  final bool isDirectory;
  final int depth;
  final List<bool> ancestorIsLast;
  final bool isLast;
  final VoidCallback? onRefreshParent;

  const MobileFileTreeNode({
    super.key,
    required this.path,
    required this.name,
    required this.isDirectory,
    this.depth = 0,
    this.ancestorIsLast = const [],
    this.isLast = false,
    this.onRefreshParent,
  });

  @override
  ConsumerState<MobileFileTreeNode> createState() => _MobileFileTreeNodeState();
}

class _MobileFileTreeNodeState extends ConsumerState<MobileFileTreeNode> {
  List<FileSystemEntity>? _children;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    if (widget.isDirectory) {
      _loadChildren();
    }
  }

  Future<void> _loadChildren() async {
    if (!widget.isDirectory) return;
    try {
      final dir = Directory(widget.path);
      if (!await dir.exists()) return;

      final entities = <FileSystemEntity>[];
      await for (final entity in dir.list()) {
        final name = p.basename(entity.path);
        if (name == '.git' || name == 'node_modules' || name == '.dart_tool') continue;
        entities.add(entity);
      }

      entities.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });

      if (mounted) {
        setState(() => _children = entities);
      }
    } catch (e) {
      // Ignore errors
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isDirectory && _searchQuery.isNotEmpty) {
      if (!widget.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return const SizedBox.shrink();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTile(),
        if (_isExpanded && _children != null)
          ..._children!.map((entity) {
            final name = p.basename(entity.path);
            final isDir = entity is Directory;
            final index = _children!.indexOf(entity);

            return MobileFileTreeNode(
              path: entity.path,
              name: name,
              isDirectory: isDir,
              depth: widget.depth + 1,
              ancestorIsLast: [...widget.ancestorIsLast, widget.isLast],
              isLast: index == _children!.length - 1,
              onRefreshParent: widget.onRefreshParent,
            );
          }),
      ],
    );
  }

  Widget _buildTile() {
    final iconInfo = FileIconHelper.getIconInfo(widget.name, widget.isDirectory, _isExpanded);

    return InkWell(
      onTap: () {
        if (widget.isDirectory) {
          setState(() => _isExpanded = !_isExpanded);
          if (_isExpanded) _loadChildren();
        } else {
          ref.read(editorProvider.notifier).openFile(widget.path);
          Navigator.pop(context);
        }
      },
      onLongPress: () => _showContextMenu(),
      child: Container(
        padding: EdgeInsets.only(
          left: 16.0 + (widget.depth * 20.0),
          right: 16,
          top: 12,
          bottom: 12,
        ),
        child: Row(
          children: [
            if (widget.isDirectory)
              Icon(
                _isExpanded ? LucideIcons.chevron_down : LucideIcons.chevron_right,
                size: 16,
                color: Colors.white54,
              )
            else
              const SizedBox(width: 16),
            const SizedBox(width: 8),
            Icon(iconInfo.icon, size: 20, color: iconInfo.color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.name,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: widget.isDirectory ? FontWeight.w600 : FontWeight.normal,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1D27),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.name,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (!widget.isDirectory) ...[
                _buildContextAction(
                  icon: LucideIcons.file_code,
                  label: 'Open in Editor',
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(editorProvider.notifier).openFile(widget.path);
                    Navigator.pop(context);
                  },
                ),
              ],
              if (widget.isDirectory) ...[
                _buildContextAction(
                  icon: _isExpanded ? LucideIcons.folder_minus : LucideIcons.folder_plus,
                  label: _isExpanded ? 'Collapse' : 'Expand',
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _isExpanded = !_isExpanded);
                    if (_isExpanded) _loadChildren();
                  },
                ),
              ],
              _buildContextAction(
                icon: LucideIcons.info,
                label: 'Properties',
                onTap: () {
                  Navigator.pop(context);
                  _showProperties();
                },
                isDestructive: false,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContextAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        size: 22,
        color: isDestructive ? Colors.redAccent : Colors.white70,
      ),
      title: Text(
        label,
        style: GoogleFonts.inter(
          color: isDestructive ? Colors.redAccent : Colors.white,
          fontSize: 15,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      minLeadingWidth: 32,
    );
  }

  void _showProperties() {
    // Show file/folder properties
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1D27),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Properties',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildPropertyRow('Name', widget.name),
              _buildPropertyRow('Type', widget.isDirectory ? 'Folder' : 'File'),
              _buildPropertyRow('Path', widget.path),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPropertyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

String get _searchQuery => '';
