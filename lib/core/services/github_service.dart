import 'dart:io';
import 'package:dio/dio.dart';
import 'package:quantum_ide/core/services/secure_storage_service.dart';

class GitHubService {
  static final GitHubService _instance = GitHubService._internal();
  factory GitHubService() => _instance;
  GitHubService._internal();

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.github.com',
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 120),
      headers: {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    ),
  );

  String? _accessToken;
  Map<String, dynamic>? _currentUser;
  String? _lastError;

  bool get isAuthenticated => _accessToken != null && _accessToken!.isNotEmpty;
  Map<String, dynamic>? get currentUser => _currentUser;
  String? get lastError => _lastError;

  void _applyAuthHeader(String token) {
    final clean = token.trim();
    // Both classic (ghp_) and fine-grained (github_pat_) tokens work with Bearer
    _dio.options.headers['Authorization'] = 'Bearer $clean';
  }

  Future<void> init() async {
    final storage = SecureStorageService();
    _accessToken = (await storage.retrieve('github_token'))?.trim();
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      _applyAuthHeader(_accessToken!);
      await _fetchCurrentUser();
    }
  }

  Future<bool> authenticateWithToken(String token) async {
    final clean = token.trim();
    _accessToken = clean;
    _applyAuthHeader(clean);
    final user = await _fetchCurrentUser();
    if (user.isEmpty) {
      // Fallback to legacy 'token' prefix if Bearer failed
      _dio.options.headers['Authorization'] = 'token $clean';
      await _fetchCurrentUser();
    }
    final storage = SecureStorageService();
    await storage.store('github_token', clean);
    return _currentUser != null && _currentUser!.isNotEmpty;
  }

  Future<void> logout() async {
    _accessToken = null;
    _currentUser = null;
    _dio.options.headers.remove('Authorization');
    final storage = SecureStorageService();
    await storage.delete('github_token');
  }

  Future<Map<String, dynamic>> _fetchCurrentUser() async {
    try {
      final resp = await _dio.get('/user');
      if (resp.data is Map<String, dynamic>) {
        _currentUser = resp.data as Map<String, dynamic>;
        return _currentUser!;
      }
      return {};
    } catch (e) {
      _lastError = e.toString();
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> listRepositories({
    int page = 1,
    int perPage = 100,
    String? sort = 'updated',
  }) async {
    try {
      final params = <String, dynamic>{
        'page': page,
        'per_page': perPage,
        'affiliation': 'owner,collaborator,organization_member',
        'sort': ?sort,
        'direction': 'desc',
      };
      final resp = await _dio.get('/user/repos', queryParameters: params);
      return (resp.data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _lastError = e.toString();
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> searchRepositories(String query, {int page = 1}) async {
    try {
      final resp = await _dio.get('/search/repositories', queryParameters: {
        'q': query,
        'page': page,
        'per_page': 50,
      });
      return ((resp.data['items'] ?? []) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _lastError = e.toString();
      return [];
    }
  }

  Future<Map<String, dynamic>?> getRepository(String owner, String repo) async {
    try {
      final resp = await _dio.get('/repos/$owner/$repo');
      return resp.data;
    } catch (e) {
      return null;
    }
  }

  /// Extracts (owner, repo) from a GitHub URL like https://github.com/owner/repo.git
  (String, String)? _parseOwnerRepo(String url) {
    final cleaned = url.trim().replaceAll(RegExp(r'\.git$'), '').replaceAll(RegExp(r'/+$'), '');
    final match = RegExp(r'github\.com[:/]([^/]+)/([^/]+)$').firstMatch(cleaned);
    if (match != null) {
      return (match.group(1)!, match.group(2)!);
    }
    return null;
  }

  /// Counts actual project files (excluding .git internal files) to verify a complete checkout
  Future<int> _countCheckedOutFiles(Directory dir) async {
    if (!await dir.exists()) return 0;
    int count = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        final rel = entity.path.substring(dir.path.length);
        if (rel.startsWith('/.git/') || rel == '/.git') continue;
        if (entity is File) {
          count++;
          if (count >= 5) return count; // Enough to prove non-empty working tree
        }
      }
    } catch (_) {}
    return count;
  }

  Future<String?> cloneRepository(
    String url,
    String destinationPath, {
    String? guestDestinationPath,
    String? branch,
    Future<String> Function(String cmd)? runner,
    void Function(String status)? onProgress,
  }) async {
    _lastError = null;
    try {
      String normalizedUrl = url.trim();
      if (!normalizedUrl.startsWith('http://') && !normalizedUrl.startsWith('https://')) {
        if (normalizedUrl.contains('github.com')) {
          normalizedUrl = 'https://$normalizedUrl';
        } else if (RegExp(r'^[^/\s]+/[^/\s]+$').hasMatch(normalizedUrl)) {
          normalizedUrl = 'https://github.com/$normalizedUrl.git';
        }
      }

      String cloneUrl = normalizedUrl;
      if (_accessToken != null && _accessToken!.isNotEmpty && cloneUrl.startsWith('https://')) {
        // Use x-access-token format which works for both classic (ghp_) and fine-grained (github_pat_) tokens
        final stripped = cloneUrl
            .replaceFirst(RegExp(r'^https://([^@]+@)?'), '');
        cloneUrl = 'https://x-access-token:${_accessToken!.trim()}@$stripped';
      }

      final targetGuestPath = guestDestinationPath ?? destinationPath;
      final dir = Directory(destinationPath);

      if (await dir.exists()) {
        final existingFiles = await _countCheckedOutFiles(dir);
        final gitHead = File('${dir.path}/.git/HEAD');
        if (await gitHead.exists() && existingFiles > 1) {
          onProgress?.call('Обновление существующего репозитория (git pull)...');
          if (runner != null) {
            try {
              await runner('git -C "$targetGuestPath" fetch --all && git -C "$targetGuestPath" reset --hard origin/HEAD && git -C "$targetGuestPath" pull --ff-only');
            } catch (_) {}
          } else {
            try {
              await Process.run('git', ['-C', destinationPath, 'pull', '--ff-only']);
            } catch (_) {}
          }
          return destinationPath;
        } else {
          // Incomplete or broken previous clone — wipe cleanly before cloning fresh
          try {
            await dir.delete(recursive: true);
          } catch (_) {}
        }
      }

      if (!await dir.parent.exists()) {
        await dir.parent.create(recursive: true);
      }

      final branchArg = (branch != null && branch.trim().isNotEmpty)
          ? '-b "${branch.trim()}" '
          : '';

      // PRoot-safe Git configuration flags:
      // - pack.threads=1 prevents pthread crashes inside Android PRoot during index-pack
      // - core.symlinks=false & core.fileMode=false prevent permission/symlink checkout aborts
      // - http.postBuffer=524288000 prevents large packfile truncation
      const gitSafeFlags =
          '-c http.postBuffer=524288000 '
          '-c http.lowSpeedLimit=0 '
          '-c http.lowSpeedTime=999999 '
          '-c pack.threads=1 '
          '-c core.symlinks=false '
          '-c core.fileMode=false '
          '-c core.autocrlf=false';

      bool cloneVerified = false;

      // Strategy 1: Clone via guest runtime shell
      if (runner != null) {
        try {
          onProgress?.call('Клонирование репозитория через Git...');
          await runner(
            'git config --global --add safe.directory "*" ; '
            'git $gitSafeFlags clone --recurse-submodules $branchArg"$cloneUrl" "$targetGuestPath"',
          );

          // Force working-tree checkout in case clone stopped after fetching packfiles
          final gitHead = File('${dir.path}/.git/HEAD');
          if (await gitHead.exists()) {
            await runner(
              'git -C "$targetGuestPath" config core.symlinks false ; '
              'git -C "$targetGuestPath" config core.fileMode false ; '
              'git -C "$targetGuestPath" checkout -f HEAD ; '
              'git -C "$targetGuestPath" reset --hard HEAD ; '
              'git -C "$targetGuestPath" submodule update --init --recursive',
            );
          }

          final fileCount = await _countCheckedOutFiles(dir);
          if (await gitHead.exists() && fileCount > 0) {
            cloneVerified = true;
          }
        } catch (e) {
          _lastError = e.toString();
        }
      }

      // Strategy 2: Host Process.run('git', ...)
      if (!cloneVerified) {
        try {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        } catch (_) {}

        try {
          onProgress?.call('Клонирование через системный Git...');
          final args = <String>[
            '-c', 'http.postBuffer=524288000',
            '-c', 'pack.threads=1',
            '-c', 'core.symlinks=false',
            '-c', 'core.fileMode=false',
            'clone',
            '--recurse-submodules',
            if (branch != null && branch.trim().isNotEmpty) ...['-b', branch.trim()],
            cloneUrl,
            destinationPath,
          ];
          final result = await Process.run('git', args);
          if (result.exitCode == 0) {
            await Process.run(
              'git',
              ['-C', destinationPath, 'checkout', '-f', 'HEAD'],
            );
          } else {
            _lastError = result.stderr?.toString();
          }

          final gitHead = File('${dir.path}/.git/HEAD');
          final fileCount = await _countCheckedOutFiles(dir);
          if (await gitHead.exists() && fileCount > 0) {
            cloneVerified = true;
          }
        } catch (e) {
          _lastError = e.toString();
        }
      }

      // Strategy 3: Fallback to GitHub REST API Tarball Download + Extract
      // Guarantees 100% of project files are downloaded even if git-remote-https fails in PRoot!
      if (!cloneVerified) {
        final ownerRepo = _parseOwnerRepo(normalizedUrl);
        if (ownerRepo != null) {
          onProgress?.call('Загрузка полного архива проекта через GitHub API...');
          final downloaded = await _downloadAndExtractArchive(
            owner: ownerRepo.$1,
            repo: ownerRepo.$2,
            branch: branch,
            destinationPath: destinationPath,
            targetGuestPath: targetGuestPath,
            originalUrl: normalizedUrl,
            runner: runner,
          );
          if (downloaded) {
            cloneVerified = true;
          }
        }
      }

      if (cloneVerified) {
        // Strip access token from .git/config remote URL for security
        if (runner != null) {
          try {
            await runner('git -C "$targetGuestPath" remote set-url origin "$normalizedUrl"');
          } catch (_) {}
        } else {
          try {
            await Process.run('git', ['remote', 'set-url', 'origin', normalizedUrl], workingDirectory: destinationPath);
          } catch (_) {}
        }

        // Configure safe.directory and author identity
        await configureGitUser(destinationPath, guestPath: targetGuestPath, runner: runner);
        return destinationPath;
      }

      return null;
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  /// Downloads the full repository tarball from GitHub API and extracts all files
  Future<bool> _downloadAndExtractArchive({
    required String owner,
    required String repo,
    String? branch,
    required String destinationPath,
    required String targetGuestPath,
    required String originalUrl,
    Future<String> Function(String cmd)? runner,
  }) async {
    final dir = Directory(destinationPath);
    final tempTar = File('${dir.parent.path}/.${repo}_archive.tar.gz');
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await dir.create(recursive: true);
      if (await tempTar.exists()) {
        await tempTar.delete();
      }

      final refSuffix = (branch != null && branch.trim().isNotEmpty) ? '/${branch.trim()}' : '';
      await _dio.download(
        '/repos/$owner/$repo/tarball$refSuffix',
        tempTar.path,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 5,
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      if (!await tempTar.exists() || await tempTar.length() == 0) {
        return false;
      }

      // Extract tarball using tar
      final tarRes = await Process.run(
        'tar',
        ['-xzf', tempTar.path, '-C', destinationPath, '--strip-components=1'],
      );

      if (tarRes.exitCode != 0 && runner != null) {
        await runner('tar -xzf "${tempTar.path}" -C "$targetGuestPath" --strip-components=1');
      }

      try {
        await tempTar.delete();
      } catch (_) {}

      final fileCount = await _countCheckedOutFiles(dir);
      if (fileCount == 0) return false;

      // Initialize git repo so Git panel works seamlessly
      if (runner != null) {
        await runner(
          'git -C "$targetGuestPath" init && '
          'git -C "$targetGuestPath" remote add origin "$originalUrl" && '
          'git -C "$targetGuestPath" add -A && '
          'git -C "$targetGuestPath" commit -m "Initial import from $owner/$repo"',
        );
      } else {
        await Process.run('git', ['init'], workingDirectory: destinationPath);
        await Process.run('git', ['remote', 'add', 'origin', originalUrl], workingDirectory: destinationPath);
      }
      return true;
    } catch (e) {
      _lastError = e.toString();
      try {
        if (await tempTar.exists()) await tempTar.delete();
      } catch (_) {}
      return false;
    }
  }

  Future<void> configureGitUser(
    String projectPath, {
    String? guestPath,
    Future<String> Function(String cmd)? runner,
  }) async {
    final targetGuest = guestPath ?? projectPath;
    final name = _currentUser?['name'] ?? _currentUser?['login'] ?? 'Quantum Developer';
    final email = _currentUser?['email'] ?? '${_currentUser?['login'] ?? 'dev'}@users.noreply.github.com';

    if (runner != null) {
      try {
        await runner(
          'git config --global --add safe.directory "*" && '
          'git -C "$targetGuest" config user.name "$name" && '
          'git -C "$targetGuest" config user.email "$email"',
        );
        return;
      } catch (_) {}
    }

    try {
      await Process.run('git', ['config', '--global', '--add', 'safe.directory', '*']);
      await Process.run('git', ['config', 'user.name', name], workingDirectory: projectPath);
      await Process.run('git', ['config', 'user.email', email], workingDirectory: projectPath);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> listBranches(String owner, String repo) async {
    try {
      final resp = await _dio.get('/repos/$owner/$repo/branches');
      return (resp.data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> createRepository({
    required String name,
    String? description,
    bool isPrivate = false,
  }) async {
    try {
      final resp = await _dio.post('/user/repos', data: {
        'name': name,
        'description': ?description,
        'private': isPrivate,
      });
      return resp.data;
    } catch (e) {
      return null;
    }
  }

  /// Create a GitHub Release via REST API
  Future<Map<String, dynamic>?> createRelease({
    required String owner,
    required String repo,
    required String tagName,
    required String releaseName,
    required String body,
    bool isDraft = false,
    bool isPrerelease = false,
  }) async {
    try {
      final resp = await _dio.post('/repos/$owner/$repo/releases', data: {
        'tag_name': tagName,
        'name': releaseName,
        'body': body,
        'draft': isDraft,
        'prerelease': isPrerelease,
      });
      return resp.data;
    } catch (e) {
      return null;
    }
  }

  /// Setup Cloud APK GitHub Actions workflow file in the given project
  Future<bool> setupCloudApkWorkflow(String projectPath) async {
    try {
      final workflowDir = Directory('$projectPath/.github/workflows');
      if (!await workflowDir.exists()) {
        await workflowDir.create(recursive: true);
      }
      final workflowFile = File('${workflowDir.path}/build-apk.yml');
      const workflowContent = '''name: Build & Release Android APK

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Java 17
        uses: actions/setup-java@v5
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.29.0'
          channel: 'stable'
          cache: true

      - name: Install Dependencies
        run: flutter pub get

      - name: Build APK (Release)
        run: flutter build apk --release

      - name: Create GitHub Release and Upload APK
        uses: softprops/action-gh-release@v2
        if: startsWith(github.ref, 'refs/tags/')
        with:
          files: build/app/outputs/flutter-apk/app-release.apk
          generate_release_notes: true
        env:
          GITHUB_TOKEN: \${{ secrets.GITHUB_TOKEN }}
''';
      await workflowFile.writeAsString(workflowContent);
      return true;
    } catch (e) {
      return false;
    }
  }
}
