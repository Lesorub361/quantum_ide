import 'package:chucker_flutter/chucker_flutter.dart';
import 'package:dio/dio.dart';

class NetworkInspectorService {
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    ChuckerFlutter.showOnRelease = true;
    ChuckerFlutter.showNotification = false;
    _initialized = true;
  }

  static Interceptor get dioInterceptor => ChuckerDioInterceptor();

  static void showInspector() {
    ChuckerFlutter.showChuckerScreen();
  }
}
