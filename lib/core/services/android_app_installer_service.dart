import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/shizuku_bridge.dart';

final androidAppInstallerServiceProvider = Provider<AndroidAppInstallerService>((ref) {
  return AndroidAppInstallerService();
});

class InstallResult {
  final bool success;
  final String? message;
  final String? packageName;
  final String? method;

  const InstallResult({
    required this.success,
    this.message,
    this.packageName,
    this.method,
  });
}

class AndroidAppInstallerService {
  static const _channel = MethodChannel('com.example.quantum_ide/native');

  /// Installs an APK using Shizuku silent `pm install` when available,
  /// otherwise falls back to Android's native PackageInstaller.
  Future<InstallResult> installApk(
    String apkPath, {
    bool launchAfterInstall = true,
  }) async {
    if (!Platform.isAndroid) {
      return const InstallResult(
        success: false,
        message: 'Direct APK installation is only supported on Android devices.',
      );
    }

    final file = File(apkPath);
    if (!file.existsSync()) {
      return InstallResult(
        success: false,
        message: 'APK file not found: $apkPath',
      );
    }

    final shizukuResult = await _tryInstallViaShizuku(file);
    if (shizukuResult != null) {
      return shizukuResult;
    }

    try {
      final res = await _channel.invokeMethod<Map>('installApk', {
        'apkPath': file.absolute.path,
        'launchAfterInstall': launchAfterInstall,
      });

      if (res != null) {
        return InstallResult(
          success: true,
          packageName: res['packageName']?.toString(),
          method: res['method']?.toString() ?? 'package_installer',
          message: 'Installation initiated successfully.',
        );
      }
      return const InstallResult(
        success: true,
        message: 'Installation session started.',
      );
    } on PlatformException catch (e) {
      debugPrint('AndroidAppInstallerService error: ${e.message}');
      return InstallResult(
        success: false,
        message: e.message ?? e.toString(),
      );
    } catch (e) {
      return InstallResult(
        success: false,
        message: e.toString(),
      );
    }
  }

  Future<InstallResult?> _tryInstallViaShizuku(File apkFile) async {
    try {
      if (!ShizukuBridge.instance.isAvailable) {
        await ShizukuBridge.instance.initialize();
      }
      if (!ShizukuBridge.instance.isAvailable) return null;

      String targetPath = apkFile.absolute.path;
      File? tempCopy;
      if (!targetPath.startsWith('/storage/emulated/0/') &&
          !targetPath.startsWith('/sdcard/')) {
        const tmpDir = '/storage/emulated/0/Download';
        final dir = Directory(tmpDir);
        if (dir.existsSync()) {
          final tmpPath =
              '$tmpDir/.quantum_install_${DateTime.now().millisecondsSinceEpoch}.apk';
          tempCopy = await apkFile.copy(tmpPath);
          targetPath = tempCopy.path;
        }
      }

      try {
        final procRes = await ShizukuBridge.instance.execute(
          'pm',
          ['install', '-r', '-t', targetPath],
        );
        final out = '${procRes.stdout}\n${procRes.stderr}'.trim();
        if (procRes.exitCode == 0 && out.contains('Success')) {
          return const InstallResult(
            success: true,
            method: 'Shizuku (pm install)',
            message: 'APK silently installed via Shizuku.',
          );
        }
        debugPrint('Shizuku pm install fallback: code=${procRes.exitCode} $out');
      } finally {
        if (tempCopy != null && tempCopy.existsSync()) {
          try {
            await tempCopy.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Shizuku install skipped: $e');
    }
    return null;
  }

  /// Launches an installed application by package name.
  Future<bool> launchApp(String packageName) async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('launchApp', {
        'packageName': packageName,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('AndroidAppInstallerService launchApp error: $e');
      return false;
    }
  }
}
