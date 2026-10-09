import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  final Map<String, String> _memoryCache = {};

  Future<void> store(String key, String value) async {
    _memoryCache[key] = value;
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('SecureStorageService write error: $e');
    }
    // Also save to SharedPreferences as durable fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sec_$key', value);
    } catch (e) {
      debugPrint('SharedPreferences fallback write error: $e');
    }
  }

  Future<String?> retrieve(String key) async {
    if (_memoryCache.containsKey(key)) {
      return _memoryCache[key];
    }
    try {
      final val = await _storage.read(key: key);
      if (val != null && val.isNotEmpty) {
        _memoryCache[key] = val;
        return val;
      }
    } catch (e) {
      debugPrint('SecureStorageService read error: $e');
    }
    // Fallback to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getString('sec_$key');
      if (val != null && val.isNotEmpty) {
        _memoryCache[key] = val;
        return val;
      }
    } catch (e) {
      debugPrint('SharedPreferences fallback read error: $e');
    }
    return null;
  }

  Future<void> delete(String key) async {
    _memoryCache.remove(key);
    try {
      await _storage.delete(key: key);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('sec_$key');
    } catch (_) {}
  }

  Future<void> clear() async {
    _memoryCache.clear();
    try {
      await _storage.deleteAll();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('sec_')).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  Future<Map<String, String>> retrieveAll() async {
    final result = Map<String, String>.from(_memoryCache);
    try {
      final secure = await _storage.readAll();
      result.addAll(secure);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        if (k.startsWith('sec_')) {
          final cleanKey = k.substring(4);
          final val = prefs.getString(k);
          if (val != null && !result.containsKey(cleanKey)) {
            result[cleanKey] = val;
          }
        }
      }
    } catch (_) {}
    return result;
  }

  Future<void> storeJson(String key, Map<String, dynamic> data) async {
    await store(key, jsonEncode(data));
  }

  Future<Map<String, dynamic>?> retrieveJson(String key) async {
    final data = await retrieve(key);
    if (data == null) return null;
    return jsonDecode(data) as Map<String, dynamic>;
  }
}
