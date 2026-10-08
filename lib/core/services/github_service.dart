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
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  String? _accessToken;
  Map<String, dynamic>? _currentUser;

  bool get isAuthenticated => _accessToken != null && _accessToken!.isNotEmpty;
  Map<String, dynamic>? get currentUser => _currentUser;

  Future<void> init() async {
    final storage = SecureStorageService();
    _accessToken = await storage.retrieve('github_token');
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'token $_accessToken';
      await _fetchCurrentUser();
    }
  }

  Future<void> authenticateWithToken(String token) async {
    _accessToken = token;
    _dio.options.headers['Authorization'] = 'token $token';
    await _fetchCurrentUser();
    final storage = SecureStorageService();
    await storage.store('github_token', token);
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
      _currentUser = resp.data;
      return _currentUser!;
    } catch (e) {
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> listRepositories({int page = 1, int perPage = 30, String? sort}) async {
    try {
      final params = <String, dynamic>{
        'page': page,
        'per_page': perPage,
        'sort': ?sort,
      };
      final resp = await _dio.get('/user/repos', queryParameters: params);
      return (resp.data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> searchRepositories(String query, {int page = 1}) async {
    try {
      final resp = await _dio.get('/search/repositories', queryParameters: {
        'q': query,
        'page': page,
        'per_page': 30,
      });
      return ((resp.data['items'] ?? []) as List).cast<Map<String, dynamic>>();
    } catch (e) {
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

  Future<String?> cloneRepository(String url, String destinationPath) async {
    try {
      String cloneUrl = url;
      if (_accessToken != null && _accessToken!.isNotEmpty && cloneUrl.startsWith('https://')) {
        // Inject token for private or authenticated repo cloning
        final stripped = cloneUrl.replaceFirst('https://', '');
        cloneUrl = 'https://$_accessToken@$stripped';
      }
      
      // Ensure destination directory parent exists
      final dir = Directory(destinationPath);
      if (await dir.exists()) {
        final contents = dir.listSync();
        if (contents.isNotEmpty) {
          throw Exception('Destination directory is not empty');
        }
      } else {
        await dir.create(recursive: true);
      }

      final result = await Process.run('git', ['clone', cloneUrl, destinationPath]);
      if (result.exitCode == 0) {
        // Configure safe directory and author details if logged in
        await Process.run('git', ['config', '--global', '--add', 'safe.directory', '*']);
        if (_currentUser != null) {
          final name = _currentUser!['name'] ?? _currentUser!['login'] ?? 'Quantum Developer';
          final email = _currentUser!['email'] ?? '${_currentUser!['login']}@users.noreply.github.com';
          await Process.run('git', ['config', 'user.name', name], workingDirectory: destinationPath);
          await Process.run('git', ['config', 'user.email', email], workingDirectory: destinationPath);
        }
        return destinationPath;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> configureGitUser(String projectPath) async {
    try {
      await Process.run('git', ['config', '--global', '--add', 'safe.directory', '*']);
      if (_currentUser != null) {
        final name = _currentUser!['name'] ?? _currentUser!['login'] ?? 'Quantum Developer';
        final email = _currentUser!['email'] ?? '${_currentUser!['login']}@users.noreply.github.com';
        await Process.run('git', ['config', 'user.name', name], workingDirectory: projectPath);
        await Process.run('git', ['config', 'user.email', email], workingDirectory: projectPath);
      }
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
        uses: actions/setup-java@v4
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
