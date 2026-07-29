import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/file_tree_node.dart';
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/file_explorer_notifier.dart';

class MobileExplorerDrawer extends ConsumerStatefulWidget {
  const MobileExplorerDrawer({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (_) => const MobileExplorerDrawer(),
    );
  }

  @override
  ConsumerState<MobileExplorerDrawer> createState() => _MobileExplorerDrawerState();
}

class _MobileExplorerDrawerState extends ConsumerState<MobileExplorerDrawer>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedTab = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final workspacePath = ref.watch(workspaceProvider).currentPath ?? '';

    return Container(
      height: screenHeight * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0F14),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _buildDragHandle(),
          _buildToolbar(workspacePath),
          Expanded(
            child: Row(
              children: [
                _buildActivityBar(),
                Expanded(
                  child: _selectedTab == 0
                      ? _buildFileTree(workspacePath)
                      : _selectedTab == 1
                          ? _buildSearchPanel()
                          : _buildBookmarksPanel(workspacePath),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildToolbar(String workspacePath) {
    final projectName = p.basename(workspacePath);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF13161E),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF00D4FF)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.folder, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  projectName.isNotEmpty ? projectName : 'No project',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  workspacePath,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: Colors.white38,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _toolbarIcon(LucideIcons.search, () => setState(() => _selectedTab = 1)),
          _toolbarIcon(LucideIcons.star, () => setState(() => _selectedTab = 2)),
          _toolbarIcon(LucideIcons.refresh_cw, () {
            ref.read(fileExplorerProvider.notifier).scanDirectory(workspacePath);
          }),
          _toolbarIcon(LucideIcons.x, () => Navigator.pop(context)),
        ],
      ),
    );
  }

  Widget _toolbarIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: Colors.white54),
      ),
    );
  }

  Widget _buildActivityBar() {
    return Container(
      width: 42,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0C12),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _activityIcon(LucideIcons.folder, 0, 'Files'),
          _activityIcon(LucideIcons.search, 1, 'Search'),
          _activityIcon(LucideIcons.star, 2, 'Bookmarks'),
          const Spacer(),
          _activityIcon(LucideIcons.arrow_down_to_line, -1, 'New file', onTap: () {
            Navigator.pop(context);
            _showCreateDialog(false);
          }),
          _activityIcon(LucideIcons.folder_plus, -2, 'New folder', onTap: () {
            Navigator.pop(context);
            _showCreateDialog(true);
          }),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _activityIcon(IconData icon, int index, String tooltip, {VoidCallback? onTap}) {
    final isActive = _selectedTab == index;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap ?? () => setState(() => _selectedTab = index),
        child: Container(
          width: 42,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isActive ? const Color(0xFF6C63FF) : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isActive ? const Color(0xFF6C63FF) : Colors.white38,
          ),
        ),
      ),
    );
  }

  Widget _buildFileTree(String workspacePath) {
    if (workspacePath.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.folder_search, size: 48, color: Colors.white.withValues(alpha: 0.1)),
            const SizedBox(height: 12),
            Text(
              'No project open',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }

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

  Widget _buildSearchPanel() {
    final controller = TextEditingController();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            controller: controller,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search files...',
              hintStyle: GoogleFonts.inter(color: Colors.white24),
              prefixIcon: const Icon(LucideIcons.search, size: 16, color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onSubmitted: (value) {
              ref.read(fileSearchQueryProvider.notifier).state = value;
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    final query = ref.watch(fileSearchQueryProvider);
    if (query.isEmpty) {
      return Center(
        child: Text(
          'Type to search files',
          style: GoogleFonts.inter(color: Colors.white24, fontSize: 13),
        ),
      );
    }
    return _buildFileTree(ref.read(workspaceProvider).currentPath ?? '');
  }

  Widget _buildBookmarksPanel(String workspacePath) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.star, size: 40, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
          Text(
            'Long-press a file to bookmark',
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(bool isDir) {
    final controller = TextEditingController();
    final workspacePath = ref.read(workspaceProvider).currentPath ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D27),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isDir ? 'New Folder' : 'New File',
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.inter(color: Colors.white),
          decoration: InputDecoration(
            hintText: isDir ? 'folder_name' : 'file.dart',
            hintStyle: GoogleFonts.inter(color: Colors.white24),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white10),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF6C63FF)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text;
              if (name.isNotEmpty) {
                final path = p.join(workspacePath, name);
                if (isDir) {
                  Directory(path).create();
                } else {
                  File(path).create();
                }
                ref.read(fileExplorerProvider.notifier).scanDirectory(workspacePath);
              }
              Navigator.pop(context);
            },
            child: Text('Create', style: GoogleFonts.inter(color: const Color(0xFF6C63FF), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
