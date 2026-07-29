import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<void> store(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> retrieve(String key) async {
    return await _storage.read(key: key);
  }

  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  Future<void> clear() async {
    await _storage.deleteAll();
  }

  Future<Map<String, String>> retrieveAll() async {
    return await _storage.readAll();
  }

  Future<void> storeJson(String key, Map<String, dynamic> data) async {
    await _storage.write(key: key, value: jsonEncode(data));
  }

  Future<Map<String, dynamic>?> retrieveJson(String key) async {
    final data = await _storage.read(key: key);
    if (data == null) return null;
    return jsonDecode(data) as Map<String, dynamic>;
  }
}
