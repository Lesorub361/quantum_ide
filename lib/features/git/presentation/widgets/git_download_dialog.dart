import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/github_service.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';

class GitDownloadDialog extends StatefulWidget {
  final String workspacePath;
  final GitNotifier gitNotifier;

  const GitDownloadDialog({
    super.key,
    required this.workspacePath,
    required this.gitNotifier,
  });

  static Future<void> show(
    BuildContext context, {
    required String workspacePath,
    required GitNotifier gitNotifier,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => GitDownloadDialog(
        workspacePath: workspacePath,
        gitNotifier: gitNotifier,
      ),
    );
  }

  @override
  State<GitDownloadDialog> createState() => _GitDownloadDialogState();
}

class _GitDownloadDialogState extends State<GitDownloadDialog> {
  final _ghService = GitHubService();
  final _repoController = TextEditingController(text: '');
  final _branchController = TextEditingController(text: 'main');
  final _targetFolderController = TextEditingController(text: '');

  bool _isLoadingUserRepos = false;
  List<Map<String, dynamic>> _userRepos = [];

  bool _isExploring = false;
  List<dynamic> _currentContents = [];
  String _currentPath = '';
  String? _exploreError;

  bool _isDownloading = false;
  String _downloadStatus = '';

  @override
  void initState() {
    super.initState();
    _loadUserRepos();
  }

  Future<void> _loadUserRepos() async {
    if (!_ghService.isAuthenticated) return;
    setState(() => _isLoadingUserRepos = true);
    try {
      final repos = await _ghService.listRepositories(sort: 'updated');
      if (mounted) {
        setState(() {
          _userRepos = repos;
          _isLoadingUserRepos = false;
          if (_repoController.text.isEmpty && repos.isNotEmpty) {
            _repoController.text = repos.first['full_name'] ?? '';
            final defBranch = repos.first['default_branch']?.toString();
            if (defBranch != null && defBranch.isNotEmpty) {
              _branchController.text = defBranch;
            }
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingUserRepos = false);
    }
  }

  @override
  void dispose() {
    _repoController.dispose();
    _branchController.dispose();
    _targetFolderController.dispose();
    super.dispose();
  }

  (String, String)? _parseOwnerRepo(String input) {
    var raw = input.trim();
    if (raw.endsWith('.git')) raw = raw.substring(0, raw.length - 4);
    if (raw.startsWith('https://github.com/')) {
      raw = raw.substring('https://github.com/'.length);
    } else if (raw.startsWith('git@github.com:')) {
      raw = raw.substring('git@github.com:'.length);
    }
    final parts = raw.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) {
      return (parts[0], parts[1]);
    }
    return null;
  }

  Future<void> _fetchContents(String path) async {
    final parsed = _parseOwnerRepo(_repoController.text);
    if (parsed == null) {
      setState(() => _exploreError = 'Введите репозиторий в формате «владелец/репозиторий»');
      return;
    }

    setState(() {
      _isExploring = true;
      _exploreError = null;
    });

    final (owner, repo) = parsed;
    final branch = _branchController.text.trim();
    final res = await _ghService.getContents(owner, repo, path: path, ref: branch);

    if (!mounted) return;
    setState(() {
      _isExploring = false;
      if (res is List) {
        _currentContents = res;
        _currentPath = path;
      } else if (res is Map && res['type'] == 'file') {
        _exploreError = 'Указанный путь является отдельным файлом, а не папкой';
      } else {
        _exploreError = _ghService.lastError ?? 'Не удалось загрузить содержимое репозитория';
      }
    });
  }

  Future<void> _downloadSingleFile(Map<String, dynamic> item) async {
    final parsed = _parseOwnerRepo(_repoController.text);
    if (parsed == null) return;

    final (owner, repo) = parsed;
    final branch = _branchController.text.trim();
    final remoteFilePath = item['path']?.toString() ?? item['name']?.toString() ?? '';
    final fileName = item['name']?.toString() ?? 'downloaded_file';

    final subDir = _targetFolderController.text.trim();
    final targetDir = subDir.isEmpty ? widget.workspacePath : p.join(widget.workspacePath, subDir);
    final targetPath = p.join(targetDir, fileName);

    setState(() {
      _isDownloading = true;
      _downloadStatus = 'Скачивание $fileName...';
    });

    final ok = await _ghService.downloadFile(owner, repo, remoteFilePath, targetPath, ref: branch);

    if (!mounted) return;
    setState(() => _isDownloading = false);

    if (ok) {
      await widget.gitNotifier.refreshStatus(silent: true, force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Файл $fileName успешно сохранён в $subDir/!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка скачивания: ${_ghService.lastError ?? "Не удалось скачать"}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _downloadFolder(Map<String, dynamic> item) async {
    final parsed = _parseOwnerRepo(_repoController.text);
    if (parsed == null) return;

    final (owner, repo) = parsed;
    final branch = _branchController.text.trim();
    final remoteFolderPath = item['path']?.toString() ?? item['name']?.toString() ?? '';
    final folderName = item['name']?.toString() ?? 'downloaded_folder';

    final subDir = _targetFolderController.text.trim();
    final targetBase = subDir.isEmpty ? widget.workspacePath : p.join(widget.workspacePath, subDir);
    final targetDir = p.join(targetBase, folderName);

    setState(() {
      _isDownloading = true;
      _downloadStatus = 'Скачивание папки $folderName...';
    });

    final count = await _ghService.downloadFolder(
      owner,
      repo,
      remoteFolderPath,
      targetDir,
      ref: branch,
      onProgress: (cur, c) {
        if (mounted) {
          setState(() {
            _downloadStatus = 'Скачано $c файлов ($cur)...';
          });
        }
      },
    );

    if (!mounted) return;
    setState(() => _isDownloading = false);

    if (count > 0) {
      await widget.gitNotifier.refreshStatus(silent: true, force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Папка $folderName ($count файлов) успешно сохранена!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка скачивания папки: ${_ghService.lastError ?? "Папка пуста или ошибка сети"}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF141824),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(LucideIcons.cloud_download, color: Color(0xFF10B981), size: 18),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Загрузить из Git (файл или папка)',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 18, color: Colors.white54),
            onPressed: () => Navigator.pop(context),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Repo selection & branch
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Репозиторий (owner/repo):',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _repoController,
                        style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11),
                        decoration: InputDecoration(
                          hintText: 'например: flutter/flutter или user/repo',
                          hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                          filled: true,
                          fillColor: Colors.black26,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.white12)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ветка:',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _branchController,
                        style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent, fontSize: 11),
                        decoration: InputDecoration(
                          hintText: 'main',
                          hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                          filled: true,
                          fillColor: Colors.black26,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.white12)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: ElevatedButton(
                    onPressed: _isExploring ? null : () => _fetchContents(''),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: _isExploring
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Text('Открыть', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),

            if (_userRepos.isNotEmpty) ...[
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text('Мои репозитории: ', style: TextStyle(color: Colors.white38, fontSize: 10)),
                    ..._userRepos.take(5).map((r) {
                      final fn = r['full_name']?.toString() ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text(fn, style: const TextStyle(fontSize: 10, color: Color(0xFF00F2FE))),
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          side: BorderSide.none,
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            _repoController.text = fn;
                            final def = r['default_branch']?.toString();
                            if (def != null && def.isNotEmpty) _branchController.text = def;
                            _fetchContents('');
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),

            // Target destination in current project
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.folder_input, size: 14, color: Colors.cyanAccent),
                  const SizedBox(width: 6),
                  const Text('Сохранять в папку проекта: ', style: TextStyle(color: Colors.white70, fontSize: 10)),
                  Expanded(
                    child: TextField(
                      controller: _targetFolderController,
                      style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11),
                      decoration: const InputDecoration(
                        hintText: 'корень проекта (или введите подпапку, напр. lib/models)',
                        hintStyle: TextStyle(color: Colors.white24, fontSize: 10),
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Breadcrumbs Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0F121C),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  if (_currentPath.isNotEmpty)
                    InkWell(
                      onTap: () {
                        final parent = p.dirname(_currentPath);
                        _fetchContents(parent == '.' ? '' : parent);
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.arrow_left, size: 12, color: Colors.cyanAccent),
                            SizedBox(width: 4),
                            Text('Назад', style: TextStyle(fontSize: 10, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  if (_currentPath.isNotEmpty) const SizedBox(width: 8),
                  const Icon(LucideIcons.folder_git_2, size: 12, color: Colors.white54),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _currentPath.isEmpty ? '/' : '/$_currentPath',
                      style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // Content Explorer
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1017),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: _isExploring
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                            SizedBox(height: 10),
                            Text('Загрузка файлов из GitHub...', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      )
                    : _exploreError != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(LucideIcons.circle_alert, color: Colors.redAccent, size: 24),
                                  const SizedBox(height: 8),
                                  Text(
                                    _exploreError!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _currentContents.isEmpty
                            ? Center(
                                child: Text(
                                  _repoController.text.isEmpty
                                      ? 'Введите репозиторий и нажмите «Открыть»'
                                      : 'Папка пуста или файлы ещё не загружены',
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _currentContents.length,
                                separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                                itemBuilder: (ctx, i) {
                                  final item = _currentContents[i];
                                  if (item is! Map) return const SizedBox.shrink();
                                  final type = item['type']?.toString();
                                  final isDir = type == 'dir';
                                  final name = item['name']?.toString() ?? '';
                                  final itemPath = item['path']?.toString() ?? name;
                                  final size = (item['size'] as num?)?.toInt() ?? 0;

                                  return ListTile(
                                    dense: true,
                                    leading: Icon(
                                      isDir ? LucideIcons.folder : LucideIcons.file_code,
                                      size: 16,
                                      color: isDir ? const Color(0xFFFBBF24) : const Color(0xFF00F2FE),
                                    ),
                                    title: Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isDir ? FontWeight.bold : FontWeight.normal,
                                        color: Colors.white,
                                      ),
                                    ),
                                    subtitle: isDir
                                        ? const Text('Папка', style: TextStyle(fontSize: 10, color: Colors.white38))
                                        : Text(
                                            size > 1024 * 1024
                                                ? '${(size / (1024 * 1024)).toStringAsFixed(1)} МБ'
                                                : '${(size / 1024).toStringAsFixed(1)} КБ',
                                            style: const TextStyle(fontSize: 10, color: Colors.white38),
                                          ),
                                    onTap: isDir ? () => _fetchContents(itemPath) : null,
                                    trailing: isDir
                                        ? ElevatedButton.icon(
                                            onPressed: _isDownloading
                                                ? null
                                                : () => _downloadFolder(item.cast<String, dynamic>()),
                                            icon: const Icon(LucideIcons.download, size: 12),
                                            label: const Text('Папку', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFFFBBF24),
                                              foregroundColor: Colors.black,
                                              visualDensity: VisualDensity.compact,
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                            ),
                                          )
                                        : ElevatedButton.icon(
                                            onPressed: _isDownloading
                                                ? null
                                                : () => _downloadSingleFile(item.cast<String, dynamic>()),
                                            icon: const Icon(LucideIcons.download, size: 12),
                                            label: const Text('Файл', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF10B981),
                                              foregroundColor: Colors.black,
                                              visualDensity: VisualDensity.compact,
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                            ),
                                          ),
                                  );
                                },
                              ),
              ),
            ),

            if (_isDownloading) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _downloadStatus,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}
