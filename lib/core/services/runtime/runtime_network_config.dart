import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Writes and repairs guest Linux network configuration files
/// (`hosts`, `nsswitch.conf`, `resolv.conf`), replacing broken symlinks first.
abstract final class RuntimeNetworkConfig {
  /// Writes a valid hosts file with `127.0.0.1 localhost`, replacing broken symlinks first.
  static Future<void> writeHostsFile(
    String path, {
    bool onlyIfMissingLocalhost = false,
  }) async {
    try {
      final dir = Directory(p.dirname(path));
      if (!await dir.exists()) await dir.create(recursive: true);

      final isLink = FileSystemEntity.typeSync(path, followLinks: false) ==
          FileSystemEntityType.link;
      if (isLink) {
        await Link(path).delete();
      } else if (onlyIfMissingLocalhost && await File(path).exists()) {
        final existing = await File(path).readAsString().catchError((_) => '');
        if (RegExp(r'127\.0\.0\.1\s+localhost').hasMatch(existing)) {
          return;
        }
      }

      await File(path).writeAsString(
        '127.0.0.1 localhost localhost.localdomain quantum-ide\n'
        '::1 localhost ip6-localhost ip6-loopback\n',
        flush: true,
      );
      await Process.run('chmod', ['644', path])
          .catchError((_) => ProcessResult(0, 0, '', ''));
    } catch (e) {
      debugPrint('Warning: Failed to write hosts at $path: $e');
    }
  }

  /// Writes an nsswitch.conf that prefers `files` before `dns` so `localhost` resolves locally.
  static Future<void> writeNsswitchConf(
    String path, {
    bool onlyIfMissingFiles = false,
  }) async {
    try {
      final dir = Directory(p.dirname(path));
      if (!await dir.exists()) await dir.create(recursive: true);

      final isLink = FileSystemEntity.typeSync(path, followLinks: false) ==
          FileSystemEntityType.link;
      if (isLink) {
        await Link(path).delete();
      } else if (onlyIfMissingFiles && await File(path).exists()) {
        final existing = await File(path).readAsString().catchError((_) => '');
        if (RegExp(r'^\s*hosts:\s*files\b', multiLine: true).hasMatch(existing)) {
          return;
        }
      }

      await File(path).writeAsString(
        'passwd: files\n'
        'group: files\n'
        'shadow: files\n'
        'hosts: files dns\n'
        'networks: files\n'
        'protocols: files\n'
        'services: files\n'
        'ethers: files\n'
        'rpc: files\n',
        flush: true,
      );
      await Process.run('chmod', ['644', path])
          .catchError((_) => ProcessResult(0, 0, '', ''));
    } catch (e) {
      debugPrint('Warning: Failed to write nsswitch.conf at $path: $e');
    }
  }

  /// Writes a correct resolv.conf, removing broken symlinks first.
  ///
  /// Ubuntu rootfs may ship with a symlink to `/run/systemd/resolve/stub-resolv.conf`
  /// which doesn't exist on Android, causing DNS resolution inside PRoot to fail.
  static Future<void> writeResolvConf(String path) async {
    try {
      final dir = Directory(p.dirname(path));
      if (!await dir.exists()) await dir.create(recursive: true);

      final link = Link(path);
      if (await link.exists() ||
          FileSystemEntity.typeSync(path) == FileSystemEntityType.link) {
        await link.delete();
        debugPrint('resolv.conf: removed broken symlink at $path');
      }

      await File(path).writeAsString(
        'nameserver 8.8.8.8\nnameserver 1.1.1.1\n',
        flush: true,
      );
      debugPrint('resolv.conf: written at $path');
    } catch (e) {
      debugPrint('Warning: Failed to write resolv.conf at $path: $e');
    }
  }
}
