import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:quantum_ide/core/services/github_service.dart';

class GitHubPage extends StatefulWidget {
  const GitHubPage({super.key});

  @override
  State<GitHubPage> createState() => _GitHubPageState();
}

class _GitHubPageState extends State<GitHubPage> {
  final _githubService = GitHubService();
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _repos = [];
  bool _isLoading = false;
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _loadRepos();
  }

  Future<void> _loadRepos() async {
    if (!_githubService.isAuthenticated) return;
    setState(() => _isLoading = true);
    final repos = await _githubService.listRepositories(sort: 'updated');
    setState(() {
      _repos = repos;
      _isLoading = false;
    });
  }

  Future<void> _searchRepos() async {
    if (_searchController.text.isEmpty) return;
    setState(() => _isLoading = true);
    final repos = await _githubService.searchRepositories(_searchController.text);
    setState(() {
      _repos = repos;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!_githubService.isAuthenticated) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.code, size: 64, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('GitHub', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Connect your GitHub account',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showTokenDialog(context),
              icon: const Icon(LucideIcons.key, size: 16),
              label: const Text('Sign in with Token'),
            ),
          ],
        ),
      );
    }

    final user = _githubService.currentUser;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Row(
            children: [
              if (user != null) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundImage: NetworkImage(user['avatar_url'] ?? ''),
                ),
                const SizedBox(width: 8),
                Text(user['login'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
              ],
              IconButton(
                icon: Icon(_showSearch ? LucideIcons.x : LucideIcons.search, size: 16),
                onPressed: () => setState(() => _showSearch = !_showSearch),
              ),
              IconButton(
                icon: const Icon(LucideIcons.log_out, size: 16),
                onPressed: () async {
                  await _githubService.logout();
                  setState(() {});
                },
              ),
            ],
          ),
        ),
        if (_showSearch)
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search repositories...',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                suffixIcon: IconButton(
                  icon: const Icon(LucideIcons.search, size: 16),
                  onPressed: _searchRepos,
                ),
              ),
              onSubmitted: (_) => _searchRepos(),
            ),
          ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _repos.length,
                  itemBuilder: (context, index) {
                    final repo = _repos[index];
                    return ListTile(
                      leading: Icon(
                        repo['private'] == true ? LucideIcons.lock : LucideIcons.globe,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      title: Text(repo['name'] ?? '', style: const TextStyle(fontSize: 14)),
                      subtitle: Text(
                        repo['description'] ?? 'No description',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (repo['stargazers_count'] != null)
                            Text('⭐ ${repo['stargazers_count']}', style: const TextStyle(fontSize: 11)),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(LucideIcons.download, size: 14),
                            onPressed: () => _cloneRepo(repo),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showTokenDialog(BuildContext context) {
    final tokenController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GitHub Token'),
        content: TextField(
          controller: tokenController,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'ghp_...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await _githubService.authenticateWithToken(tokenController.text);
              if (context.mounted) Navigator.pop(context);
              _loadRepos();
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  void _cloneRepo(Map<String, dynamic> repo) {
    final url = repo['clone_url'] as String? ?? repo['html_url'] as String?;
    if (url != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Clone: $url')),
      );
    }
  }
}
