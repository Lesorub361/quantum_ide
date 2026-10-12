import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  /// Installs an APK directly using Android's native PackageInstaller (without ADB).
  ///
  /// On Android 12+, updates to already installed packages require no user action.
  /// On MIUI/HyperOS, falls back to the system package installer via FileProvider.
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
