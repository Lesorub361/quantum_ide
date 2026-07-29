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
}
