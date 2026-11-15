import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shizuku/shizuku.dart';

class ShizukuBridge {
  static final ShizukuBridge instance = ShizukuBridge._();
  ShizukuBridge._();

  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

  Future<void> initialize() async {
    try {
      if (await Shizuku.pingBinder()) {
        final uid = await Shizuku.getUid();
        _isAvailable = (uid == 0 || uid == 2000);
        debugPrint('Shizuku initialized: available=$_isAvailable, uid=$uid');
      }
    } catch (e) {
      debugPrint('Shizuku init error: $e');
      _isAvailable = false;
    }
  }

  Future<ProcessResult> execute(String executable, List<String> args) async {
    if (!_isAvailable) throw Exception('Shizuku not available');

    final process = await Shizuku.newProcess(
      executable,
      args,
      environment: {'PATH': '/system/bin:/system/xbin'},
    );
    
    final stdout = await process.stdout.transform(utf8.decoder).join();
    final stderr = await process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;
    
    return ProcessResult(0, exitCode, stdout, stderr);
  }
}
