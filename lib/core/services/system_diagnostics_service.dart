import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

class DiagnosticsInfo {
  final String appVersion;
  final String buildNumber;
  final String osVersion;
  final String deviceModel;
  final String flutterVersion;
  final DateTime capturedAt;
  final bool isAndroid;
  final bool isLinux;
  final int availableMemory; // in MB

  DiagnosticsInfo({
    required this.appVersion,
    required this.buildNumber,
    required this.osVersion,
    required this.deviceModel,
    required this.flutterVersion,
    required this.capturedAt,
    required this.isAndroid,
    required this.isLinux,
    required this.availableMemory,
  });

  @override
  String toString() => '''
DiagnosticsInfo:
  App Version: $appVersion ($buildNumber)
  OS: ${isAndroid ? 'Android' : isLinux ? 'Linux' : 'Unknown'} $osVersion
  Device: $deviceModel
  Flutter: $flutterVersion
  Available Memory: ${availableMemory}MB
  Captured: $capturedAt
''';
}

class SystemDiagnosticsService {
  static final _deviceInfoPlugin = DeviceInfoPlugin();

  static Future<DiagnosticsInfo> gatherDiagnostics() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final flutterVersion = _getFlutterVersion();

      String osVersion = 'Unknown';
      String deviceModel = 'Unknown';
      bool isAndroid = false;
      bool isLinux = false;
      int availableMemory = 0;

      if (Platform.isAndroid) {
        isAndroid = true;
        try {
          final androidInfo = await _deviceInfoPlugin.androidInfo;
          osVersion = 'Android ${androidInfo.version.release} (API ${androidInfo.version.sdkInt})';
          deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
        } catch (e) {
          debugPrint('Error getting Android info: $e');
        }
      } else if (Platform.isLinux) {
        isLinux = true;
        osVersion = _getLinuxVersion();
        deviceModel = 'Linux Desktop';
      } else if (Platform.isWindows) {
        osVersion = _getWindowsVersion();
        deviceModel = 'Windows Desktop';
      }

      return DiagnosticsInfo(
        appVersion: packageInfo.version,
        buildNumber: packageInfo.buildNumber,
        osVersion: osVersion,
        deviceModel: deviceModel,
        flutterVersion: flutterVersion,
        capturedAt: DateTime.now(),
        isAndroid: isAndroid,
        isLinux: isLinux,
        availableMemory: availableMemory,
      );
    } catch (e) {
      debugPrint('Error gathering diagnostics: $e');
      return DiagnosticsInfo(
        appVersion: 'Unknown',
        buildNumber: 'Unknown',
        osVersion: 'Unknown',
        deviceModel: 'Unknown',
        flutterVersion: 'Unknown',
        capturedAt: DateTime.now(),
        isAndroid: Platform.isAndroid,
        isLinux: Platform.isLinux,
        availableMemory: 0,
      );
    }
  }

  static String _getFlutterVersion() {
    // This should return the Flutter version from the environment
    // For now, return a placeholder
    return 'Flutter 3.x';
  }

  static String _getLinuxVersion() {
    try {
      final process = Process.runSync('cat', ['/etc/os-release']);
      if (process.exitCode == 0) {
        final output = process.stdout.toString();
        // Parse PRETTY_NAME from output
        final match = RegExp(r'PRETTY_NAME="([^"]+)"').firstMatch(output);
        if (match != null) {
          return match.group(1) ?? 'Linux';
        }
      }
    } catch (_) {}
    return 'Linux';
  }

  static String _getWindowsVersion() {
    try {
      final process = Process.runSync('ver', []);
      return process.stdout.toString().trim();
    } catch (_) {
      return 'Windows';
    }
  }
}

// Provider for diagnostics
final diagnosticsInfoProvider = FutureProvider((ref) {
  return SystemDiagnosticsService.gatherDiagnostics();
});
