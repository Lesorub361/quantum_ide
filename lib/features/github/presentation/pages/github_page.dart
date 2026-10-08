import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/github_service.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

class GitHubPage extends ConsumerStatefulWidget {
  const GitHubPage({super.key});

  @override
  ConsumerState<GitHubPage> createState() => _GitHubPageState();
}

class _GitHubPageState extends ConsumerState<GitHubPage> {
  final _githubService = GitHubService();
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _repos = [];
  bool _isLoading = false;
  bool _showSearch = false;
  String? _cloningRepoName;

  @override
  void initState() {
    super.initState();
    _loadRepos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRepos() async {
    if (!_githubService.isAuthenticated) return;
    setState(() => _isLoading = true);
    final repos = await _githubService.listRepositories(sort: 'updated');
    if (mounted) {
      setState(() {
        _repos = repos;
        _isLoading = false;
      });
    }
  }

  Future<void> _searchRepos() async {
    if (_searchController.text.trim().isEmpty) {
      _loadRepos();
      return;
    }
    setState(() => _isLoading = true);
    final repos = await _githubService.searchRepositories(_searchController.text.trim());
    if (mounted) {
      setState(() {
        _repos = repos;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (!_githubService.isAuthenticated) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.arrow_left, color: Colors.white70),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            'GitHub',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(28),
              constraints: const BoxConstraints(maxWidth: 440),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: const Icon(LucideIcons.git_branch, size: 48, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.signInWithGitHub,
                    style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.connectGitHubDesc,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white60, height: 1.45),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _showTokenDialog(context),
                    icon: const Icon(LucideIcons.key, size: 16),
                    label: Text(l10n.gitHubToken),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF238636),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final user = _githubService.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, color: Colors.white70),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          children: [
            if (user != null && user['avatar_url'] != null) ...[
              CircleAvatar(
                radius: 14,
                backgroundImage: NetworkImage(user['avatar_url']),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  user['login'] ?? 'GitHub',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ] else ...[
              const Icon(LucideIcons.git_branch, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              const Text('GitHub', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? LucideIcons.x : LucideIcons.search, size: 18, color: Colors.white70),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  _loadRepos();
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(LucideIcons.refresh_cw, size: 18, color: Colors.white70),
            onPressed: _loadRepos,
          ),
          IconButton(
            icon: const Icon(LucideIcons.log_out, size: 18, color: Colors.redAccent),
            onPressed: () async {
              await _githubService.logout();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSearch)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFF161B22),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search repositories...',
                  hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.3),
                  prefixIcon: const Icon(LucideIcons.search, size: 16, color: Colors.white54),
                  suffixIcon: IconButton(
                    icon: const Icon(LucideIcons.arrow_right, size: 16, color: Colors.cyanAccent),
                    onPressed: _searchRepos,
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: (_) => _searchRepos(),
              ),
            ),
          if (_cloningRepoName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.cyanAccent.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${l10n.cloningRepository} ($_cloningRepoName)',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.cyanAccent),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
                : _repos.isEmpty
                    ? Center(
                        child: Text(
                          'No repositories found',
                          style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _repos.length,
                        separatorBuilder: (context, _) => const Divider(color: Colors.white10, height: 1),
                        itemBuilder: (context, index) {
                          final repo = _repos[index];
                          final isPrivate = repo['private'] == true;
                          final name = repo['name'] ?? '';
                          final desc = repo['description'] ?? '';
                          final stars = repo['stargazers_count'] ?? 0;
                          final language = repo['language'] as String?;
                          final isThisCloning = _cloningRepoName == name;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isPrivate
                                    ? Colors.amberAccent.withValues(alpha: 0.1)
                                    : Colors.blueAccent.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isPrivate ? LucideIcons.lock : LucideIcons.folder_git_2,
                                size: 16,
                                color: isPrivate ? Colors.amberAccent : Colors.cyanAccent,
                              ),
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (isPrivate) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('Private', style: TextStyle(fontSize: 9, color: Colors.white60)),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (desc.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    desc,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white60),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (language != null) ...[
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Colors.cyanAccent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        language,
                                        style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white38),
                                      ),
                                      const SizedBox(width: 12),
                                    ],
                                    if (stars > 0) ...[
                                      const Icon(LucideIcons.star, size: 11, color: Colors.amberAccent),
                                      const SizedBox(width: 3),
                                      Text('$stars', style: const TextStyle(fontSize: 10, color: Colors.white38)),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                            trailing: isThisCloning
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                                  )
                                : ElevatedButton.icon(
                                    onPressed: _cloningRepoName != null ? null : () => _cloneAndOpenRepo(repo),
                                    icon: const Icon(LucideIcons.download, size: 13),
                                    label: Text(l10n.cloneAndOpen, style: const TextStyle(fontSize: 11.5)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF238636),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  void _showTokenDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokenController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(LucideIcons.key, size: 18, color: Colors.cyanAccent),
            const SizedBox(width: 8),
            Text(l10n.gitHubToken, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.gitHubTokenHint,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tokenController,
              obscureText: true,
              style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12.5),
              decoration: InputDecoration(
                hintText: 'ghp_xxxxxxxxxxxx',
                hintStyle: GoogleFonts.jetBrainsMono(color: Colors.white24, fontSize: 12),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(AppLocalizations.of(context)!.cancel, style: const TextStyle(color: Colors.white60)),
          ),
          FilledButton(
            onPressed: () async {
              final token = tokenController.text.trim();
              if (token.isNotEmpty) {
                Navigator.pop(dialogCtx);
                await _githubService.authenticateWithToken(token);
                if (mounted) {
                  _loadRepos();
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF238636),
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.signInWithGitHub),
          ),
        ],
      ),
    );
  }

  Future<void> _cloneAndOpenRepo(Map<String, dynamic> repo) async {
    final l10n = AppLocalizations.of(context)!;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final url = repo['clone_url'] as String? ?? repo['html_url'] as String?;
    final repoName = (repo['name'] as String?)?.trim() ?? 'repo';

    if (url == null || url.isEmpty) return;

    setState(() => _cloningRepoName = repoName);

    try {
      final runtime = ref.read(runtimeServiceProvider);
      // Destination directory inside projects folder
      final projectsDir = Directory('${runtime.appDirectory}/projects');
      if (!await projectsDir.exists()) {
        await projectsDir.create(recursive: true);
      }
      final destinationPath = '${projectsDir.path}/$repoName';

      final result = await _githubService.cloneRepository(url, destinationPath);

      if (result != null && mounted) {
        // Automatically setup Cloud APK workflow if not present
        await _githubService.setupCloudApkWorkflow(destinationPath);

        // Import and open project in workspace
        await ref.read(projectServiceProvider.notifier).importProject(destinationPath);
        await ref.read(workspaceProvider.notifier).setWorkspace(destinationPath);

        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(l10n.repoClonedSuccess(destinationPath)),
            backgroundColor: const Color(0xFF238636),
          ),
        );

        // Navigate to editor
        if (mounted) {
          context.go('/editor');
        }
      } else if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(l10n.cloneFailed),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('${l10n.cloneFailed}: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cloningRepoName = null);
      }
    }
  }
}
