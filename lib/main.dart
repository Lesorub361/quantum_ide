import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Global error handlers
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrintStack(stackTrace: details.stack, label: 'Flutter Error');
  };
  
  // Handle platform-specific initialization
  try {
    if (Platform.isAndroid) {
      await _initializeAndroid();
    } else if (Platform.isLinux) {
      await _initializeLinux();
    }
  } catch (e) {
    debugPrint('Platform initialization failed: $e');
  }
  
  runApp(
    const ProviderScope(
      child: QuantumApp(),
    ),
  );
}

/// Initialize Android-specific settings
Future<void> _initializeAndroid() async {
  try {
    // Request storage permissions for Android 11+
    if (await Permission.manageExternalStorage.isDenied) {
      final status = await Permission.manageExternalStorage.request();
      if (status.isDenied) {
        debugPrint('Storage permission denied by user');
      }
    }
    
    // Request camera permission if needed
    if (await Permission.camera.isDenied) {
      await Permission.camera.request();
    }
    
    debugPrint('Android initialization complete');
  } catch (e) {
    debugPrint('Android initialization error: $e');
  }
}

/// Initialize Linux-specific settings
Future<void> _initializeLinux() async {
  try {
    // Set up Linux-specific environment if needed
    debugPrint('Linux initialization complete');
  } catch (e) {
    debugPrint('Linux initialization error: $e');
  }
}
