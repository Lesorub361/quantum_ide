import 'package:flutter_riverpod/flutter_riverpod.dart';

class DevicePreset {
  final String id;
  final String name;
  final double width;
  final double height;
  final double devicePixelRatio;
  final String? brand;

  const DevicePreset({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.devicePixelRatio,
    this.brand,
  });
}

class DevicePreviewState {
  final String selectedDeviceId;
  final double customWidth;
  final double customHeight;
  final double scaleFactor;
  final bool useCustomSize;
  final bool isLandscape;
  final double textScaleFactor;
  final String localeCode;
  final bool showGrid;
  final bool showTouchArea;

  const DevicePreviewState({
    this.selectedDeviceId = 'iphone_14',
    this.customWidth = 390,
    this.customHeight = 844,
    this.scaleFactor = 0.5,
    this.useCustomSize = false,
    this.isLandscape = false,
    this.textScaleFactor = 1.0,
    this.localeCode = 'en',
    this.showGrid = false,
    this.showTouchArea = false,
  });

  DevicePreviewState copyWith({
    String? selectedDeviceId,
    double? customWidth,
    double? customHeight,
    double? scaleFactor,
    bool? useCustomSize,
    bool? isLandscape,
    double? textScaleFactor,
    String? localeCode,
    bool? showGrid,
    bool? showTouchArea,
  }) {
    return DevicePreviewState(
      selectedDeviceId: selectedDeviceId ?? this.selectedDeviceId,
      customWidth: customWidth ?? this.customWidth,
      customHeight: customHeight ?? this.customHeight,
      scaleFactor: scaleFactor ?? this.scaleFactor,
      useCustomSize: useCustomSize ?? this.useCustomSize,
      isLandscape: isLandscape ?? this.isLandscape,
      textScaleFactor: textScaleFactor ?? this.textScaleFactor,
      localeCode: localeCode ?? this.localeCode,
      showGrid: showGrid ?? this.showGrid,
      showTouchArea: showTouchArea ?? this.showTouchArea,
    );
  }

  double get effectiveWidth => useCustomSize ? customWidth : _selectedDevice.width;
  double get effectiveHeight => useCustomSize ? customHeight : _selectedDevice.height;
  double get displayWidth => effectiveWidth * scaleFactor;
  double get displayHeight => effectiveHeight * scaleFactor;

  DevicePreset get _selectedDevice => DevicePreviewService.knownDevices.firstWhere(
        (d) => d.id == selectedDeviceId,
        orElse: () => DevicePreviewService.knownDevices.first,
      );
}

class DevicePreviewService extends StateNotifier<DevicePreviewState> {
  static const knownDevices = [
    DevicePreset(id: 'iphone_14', name: 'iPhone 14', width: 390, height: 844, devicePixelRatio: 3.0, brand: 'Apple'),
    DevicePreset(id: 'iphone_14_pro_max', name: 'iPhone 14 Pro Max', width: 430, height: 932, devicePixelRatio: 3.0, brand: 'Apple'),
    DevicePreset(id: 'iphone_se', name: 'iPhone SE', width: 375, height: 667, devicePixelRatio: 2.0, brand: 'Apple'),
    DevicePreset(id: 'pixel_7', name: 'Pixel 7', width: 412, height: 915, devicePixelRatio: 2.625, brand: 'Google'),
    DevicePreset(id: 'pixel_7_pro', name: 'Pixel 7 Pro', width: 412, height: 892, devicePixelRatio: 3.5, brand: 'Google'),
    DevicePreset(id: 'pixel_5', name: 'Pixel 5', width: 393, height: 851, devicePixelRatio: 2.75, brand: 'Google'),
    DevicePreset(id: 'ipad_10', name: 'iPad 10th Gen', width: 810, height: 1080, devicePixelRatio: 2.0, brand: 'Apple'),
    DevicePreset(id: 'ipad_pro_11', name: 'iPad Pro 11"', width: 834, height: 1194, devicePixelRatio: 2.0, brand: 'Apple'),
    DevicePreset(id: 'ipad_air', name: 'iPad Air', width: 820, height: 1180, devicePixelRatio: 2.0, brand: 'Apple'),
    DevicePreset(id: 'galaxy_s23', name: 'Galaxy S23', width: 360, height: 780, devicePixelRatio: 3.0, brand: 'Samsung'),
    DevicePreset(id: 'galaxy_s23_ultra', name: 'Galaxy S23 Ultra', width: 384, height: 854, devicePixelRatio: 3.0, brand: 'Samsung'),
    DevicePreset(id: 'galaxy_fold', name: 'Galaxy Z Fold', width: 217, height: 512, devicePixelRatio: 2.6, brand: 'Samsung'),
    DevicePreset(id: 'galaxy_z_flip', name: 'Galaxy Z Flip', width: 360, height: 800, devicePixelRatio: 3.0, brand: 'Samsung'),
  ];

  static const knownLocales = [
    ('en', 'English'),
    ('ru', 'Русский'),
    ('es', 'Español'),
    ('de', 'Deutsch'),
    ('fr', 'Français'),
    ('ja', '日本語'),
    ('zh', '中文'),
    ('ko', '한국어'),
    ('pt', 'Português'),
    ('it', 'Italiano'),
    ('ar', 'العربية'),
    ('hi', 'हिन्दी'),
  ];

  DevicePreviewService() : super(const DevicePreviewState());

  void setDevice(String deviceId) {
    state = state.copyWith(selectedDeviceId: deviceId);
  }

  void setCustomSize(double width, double height) {
    state = state.copyWith(customWidth: width, customHeight: height);
  }

  void toggleCustomSize() {
    state = state.copyWith(useCustomSize: !state.useCustomSize);
  }

  void setScaleFactor(double scale) {
    state = state.copyWith(scaleFactor: scale.clamp(0.1, 1.0));
  }

  void toggleOrientation() {
    state = state.copyWith(isLandscape: !state.isLandscape);
  }

  void setTextScaleFactor(double factor) {
    state = state.copyWith(textScaleFactor: factor.clamp(0.5, 3.0));
  }

  void setLocale(String code) {
    state = state.copyWith(localeCode: code);
  }

  void toggleGrid() {
    state = state.copyWith(showGrid: !state.showGrid);
  }

  void toggleTouchArea() {
    state = state.copyWith(showTouchArea: !state.showTouchArea);
  }

  DevicePreset? get selectedDevice {
    if (state.useCustomSize) return null;
    try {
      return knownDevices.firstWhere((d) => d.id == state.selectedDeviceId);
    } catch (_) {
      return knownDevices.first;
    }
  }

  List<DevicePreset> get devicesByBrand {
    final grouped = <String, List<DevicePreset>>{};
    for (final device in knownDevices) {
      final brand = device.brand ?? 'Other';
      grouped.putIfAbsent(brand, () => []).add(device);
    }
    final sorted = <DevicePreset>[];
    for (final brand in ['Apple', 'Google', 'Samsung', 'Other']) {
      if (grouped.containsKey(brand)) sorted.addAll(grouped[brand]!);
    }
    return sorted;
  }
}

final devicePreviewProvider = StateNotifierProvider<DevicePreviewService, DevicePreviewState>((ref) {
  return DevicePreviewService();
});
