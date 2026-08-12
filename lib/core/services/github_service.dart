import 'dart:convert';
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
  String? get token => _accessToken;

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
      final result = await Process.run('git', ['clone', url, destinationPath]);
      if (result.exitCode == 0) return destinationPath;
      return null;
    } catch (e) {
      return null;
    }
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

  // ─── In-app Build & Publish ───────────────────────────────────────────────

  /// Читает файл из репозитория (Contents API). Возвращает текст и sha для последующего коммита.
  Future<({String content, String sha})?> getFile(
    String owner,
    String repo,
    String path, {
    String ref = 'main',
  }) async {
    try {
      final resp = await _dio.get(
        '/repos/$owner/$repo/contents/$path',
        queryParameters: {'ref': ref},
      );
      final data = resp.data as Map<String, dynamic>;
      final encoded = data['content'] as String;
      final content = utf8.decode(base64.decode(encoded.replaceAll('\n', '')));
      return (content: content, sha: data['sha'] as String);
    } catch (e) {
      return null;
    }
  }

  /// Обновляет файл в репозитории (коммит через Contents API).
  Future<bool> updateFile(
    String owner,
    String repo,
    String path,
    String content,
    String message,
    String sha, {
    String branch = 'main',
  }) async {
    try {
      await _dio.put(
        '/repos/$owner/$repo/contents/$path',
        data: {
          'message': message,
          'content': base64.encode(utf8.encode(content)),
          'sha': sha,
          'branch': branch,
        },
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// SHA последнего коммита ветки (нужен для создания тега).
  Future<String?> getBranchHeadSha(String owner, String repo, String branch) async {
    try {
      final resp = await _dio.get('/repos/$owner/$repo/git/ref/heads/$branch');
      final obj = resp.data['object'] as Map<String, dynamic>;
      return obj['sha'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Создаёт git-тег (refs/tags/&lt;tag&gt;) на указанном коммите.
  Future<bool> createTag(String owner, String repo, String tag, String sha) async {
    try {
      await _dio.post(
        '/repos/$owner/$repo/git/refs',
        data: {
          'ref': 'refs/tags/$tag',
          'sha': sha,
        },
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Запускает workflow сборки/публикации (workflow_dispatch).
  Future<bool> triggerWorkflow({
    required String owner,
    required String repo,
    required String version,
    required String notes,
    String branch = 'main',
    String flutterVersion = '3.44.9',
  }) async {
    try {
      await _dio.post(
        '/repos/$owner/$repo/actions/workflows/build-apk.yml/dispatches',
        data: {
          'ref': branch,
          'inputs': {
            'flutter_version': flutterVersion,
            'create_release': 'true',
            'version': version,
            'release_notes': notes,
          }
        },
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> listWorkflowRuns(
    String owner,
    String repo, {
    int limit = 5,
  }) async {
    try {
      final resp = await _dio.get(
        '/repos/$owner/$repo/actions/runs',
        queryParameters: {'per_page': limit},
      );
      return ((resp.data['workflow_runs'] ?? []) as List)
          .cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getRun(String owner, String repo, int runId) async {
    try {
      final resp = await _dio.get('/repos/$owner/$repo/actions/runs/$runId');
      return resp.data;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getLatestRelease(String owner, String repo) async {
    try {
      final resp = await _dio.get('/repos/$owner/$repo/releases/latest');
      return resp.data;
    } catch (e) {
      return null;
    }
  }

  /// Текущая версия приложения из pubspec.yaml (имя до «+»).
  Future<String?> getCurrentVersion(String owner, String repo) async {
    final file = await getFile(owner, repo, 'pubspec.yaml');
    if (file == null) return null;
    final m = RegExp(
      r'^version:\s*([\d.]+)\+?\d*',
      multiLine: true,
    ).firstMatch(file.content);
    return m?.group(1);
  }
}
