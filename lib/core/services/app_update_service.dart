import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppUpdateInfo {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String sha256;
  final int sizeBytes;
  final String notes;

  const AppUpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.notes,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final rootCode = json['versionCode'] is int
        ? json['versionCode'] as int
        : int.tryParse(json['versionCode']?.toString() ?? '0') ?? 0;
    final rootName = json['versionName']?.toString() ?? '$rootCode';
    final notes = json['notes']?.toString() ?? '';

    // Find artifact
    final artifacts = json['artifacts'] as Map<String, dynamic>?;
    final artifact = (artifacts != null ? (artifacts['online'] ?? artifacts['default'] ?? artifacts.values.firstOrNull) : null) ?? json;

    final url = (artifact['url'] ?? artifact['apkUrl'])?.toString() ?? '';
    final sha256 = (artifact['sha256'] ?? '')?.toString().toLowerCase() ?? '';
    final size = artifact['sizeBytes'] is int
        ? artifact['sizeBytes'] as int
        : int.tryParse(artifact['sizeBytes']?.toString() ?? '0') ?? 0;

    return AppUpdateInfo(
      versionCode: rootCode,
      versionName: rootName,
      apkUrl: url,
      sha256: sha256,
      sizeBytes: size,
      notes: notes,
    );
  }
}

class AppUpdateState {
  final bool isChecking;
  final AppUpdateInfo? updateInfo;
  final bool isDownloading;
  final double downloadProgress;
  final int downloadedBytes;
  final int totalBytes;
  final int speedBytesPerSec;
  final String? errorMessage;
  final String? statusMessage;
  final String? downloadedApkPath;

  const AppUpdateState({
    this.isChecking = false,
    this.updateInfo,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0,
    this.errorMessage,
    this.statusMessage,
    this.downloadedApkPath,
  });

  AppUpdateState copyWith({
    bool? isChecking,
    AppUpdateInfo? updateInfo,
    bool clearUpdateInfo = false,
    bool? isDownloading,
    double? downloadProgress,
    int? downloadedBytes,
    int? totalBytes,
    int? speedBytesPerSec,
    String? errorMessage,
    bool clearError = false,
    String? statusMessage,
    String? downloadedApkPath,
  }) {
    return AppUpdateState(
      isChecking: isChecking ?? this.isChecking,
      updateInfo: clearUpdateInfo ? null : (updateInfo ?? this.updateInfo),
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      statusMessage: statusMessage ?? this.statusMessage,
      downloadedApkPath: downloadedApkPath ?? this.downloadedApkPath,
    );
  }
}

class AppUpdateService extends StateNotifier<AppUpdateState> {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  static const String defaultManifestUrl =
      'https://raw.githubusercontent.com/Lesorub361/quantum_ide/main/quantum-ide-update.json';

  AppUpdateService() : super(const AppUpdateState());

  Future<AppUpdateInfo?> checkForUpdates({String? customManifestUrl}) async {
    state = state.copyWith(
      isChecking: true,
      clearError: true,
      statusMessage: 'Проверка обновлений приложения...',
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final manifestUrl = customManifestUrl ??
          prefs.getString('app_update_manifest_url') ??
          defaultManifestUrl;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(packageInfo.buildNumber) ?? 1;

      final response = await _dio.get(manifestUrl);
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : jsonDecode(response.data.toString()) as Map<String, dynamic>;

        final info = AppUpdateInfo.fromJson(data);
        if (info.versionCode > currentCode && info.apkUrl.isNotEmpty) {
          state = state.copyWith(
            isChecking: false,
            updateInfo: info,
            statusMessage: 'Доступна новая версия ${info.versionName} (сборка ${info.versionCode})',
          );
          return info;
        } else {
          state = state.copyWith(
            isChecking: false,
            clearUpdateInfo: true,
            statusMessage: 'Установлена последняя версия (${packageInfo.version}+${packageInfo.buildNumber})',
          );
          return null;
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Check update error: $e');
      state = state.copyWith(
        isChecking: false,
        errorMessage: 'Не удалось проверить обновления: $e',
        statusMessage: null,
      );
      return null;
    }
  }

  Future<void> downloadAndInstallUpdate(AppUpdateInfo info) async {
    state = state.copyWith(
      isDownloading: true,
      downloadProgress: 0.0,
      downloadedBytes: 0,
      totalBytes: info.sizeBytes,
      clearError: true,
      statusMessage: 'Загрузка обновления ${info.versionName}...',
    );

    try {
      final dir = await getApplicationDocumentsDirectory();
      final updatesDir = Directory(p.join(dir.path, 'updates'));
      if (!await updatesDir.exists()) {
        await updatesDir.create(recursive: true);
      }

      final targetFile = File(p.join(updatesDir.path, 'quantum-ide-${info.versionName}.apk'));
      final partFile = File('${targetFile.path}.part');

      if (await partFile.exists()) {
        await partFile.delete();
      }

      int lastSampleTime = DateTime.now().millisecondsSinceEpoch;
      int lastSampleBytes = 0;

      await _dio.download(
        info.apkUrl,
        partFile.path,
        onReceiveProgress: (received, total) {
          final effectiveTotal = total > 0 ? total : info.sizeBytes;
          final fraction = effectiveTotal > 0 ? (received / effectiveTotal).clamp(0.0, 1.0) : 0.0;
          final now = DateTime.now().millisecondsSinceEpoch;
          final elapsed = now - lastSampleTime;

          int speed = state.speedBytesPerSec;
          if (elapsed >= 500) {
            final bytesDelta = received - lastSampleBytes;
            speed = (bytesDelta * 1000 ~/ elapsed.clamp(1, 100000));
            lastSampleTime = now;
            lastSampleBytes = received;
          }

          state = state.copyWith(
            downloadProgress: fraction,
            downloadedBytes: received,
            totalBytes: effectiveTotal,
            speedBytesPerSec: speed,
            statusMessage: 'Загрузка: ${(fraction * 100).toStringAsFixed(1)}% (${(received / 1024 / 1024).toStringAsFixed(1)} MB)',
          );
        },
      );

      // Verify SHA256 if provided
      if (info.sha256.isNotEmpty) {
        state = state.copyWith(statusMessage: 'Проверка целостности SHA-256...');
        final bytes = await partFile.readAsBytes();
        final actualSha = sha256.convert(bytes).toString().toLowerCase();
        if (actualSha != info.sha256.toLowerCase()) {
          await partFile.delete();
          throw Exception('Ошибка проверки SHA-256 (ожидалось: ${info.sha256}, получено: $actualSha)');
        }
      }

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await partFile.rename(targetFile.path);

      state = state.copyWith(
        isDownloading: false,
        downloadProgress: 1.0,
        downloadedApkPath: targetFile.path,
        statusMessage: 'Обновление загружено. Открытие установщика...',
      );

      // Trigger installation via OpenFilex
      await OpenFilex.open(targetFile.path);
    } catch (e) {
      debugPrint('[AppUpdateService] Download update error: $e');
      state = state.copyWith(
        isDownloading: false,
        errorMessage: 'Ошибка загрузки обновления: $e',
        statusMessage: null,
      );
    }
  }
}

final appUpdateServiceProvider =
    StateNotifierProvider<AppUpdateService, AppUpdateState>((ref) {
  return AppUpdateService();
});
