enum AdbDeviceStatus {
  online,
  unauthorized,
  offline,
  authorizing,
  unknown;

  static AdbDeviceStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'device':
        return AdbDeviceStatus.online;
      case 'unauthorized':
        return AdbDeviceStatus.unauthorized;
      case 'offline':
        return AdbDeviceStatus.offline;
      case 'authorizing':
        return AdbDeviceStatus.authorizing;
      default:
        return AdbDeviceStatus.unknown;
    }
  }

  String get labelRu {
    switch (this) {
      case AdbDeviceStatus.online:
        return 'Онлайн';
      case AdbDeviceStatus.unauthorized:
        return 'Не авторизован';
      case AdbDeviceStatus.offline:
        return 'Оффлайн';
      case AdbDeviceStatus.authorizing:
        return 'Авторизация...';
      case AdbDeviceStatus.unknown:
        return 'Неизвестно';
    }
  }
}

enum AdbConnectionType {
  usb,
  wifi,
  emulator;

  String get labelRu {
    switch (this) {
      case AdbConnectionType.usb:
        return 'USB (OTG)';
      case AdbConnectionType.wifi:
        return 'Wi-Fi (Wireless)';
      case AdbConnectionType.emulator:
        return 'Эмулятор';
    }
  }
}

class AdbDevice {
  final String id;
  final AdbDeviceStatus status;
  final String model;
  final String product;
  final String device;
  final String? transportId;
  final AdbConnectionType connectionType;
  final String? androidVersion;
  final int? batteryLevel;

  const AdbDevice({
    required this.id,
    required this.status,
    this.model = '',
    this.product = '',
    this.device = '',
    this.transportId,
    required this.connectionType,
    this.androidVersion,
    this.batteryLevel,
  });

  bool get isOnline => status == AdbDeviceStatus.online;
  bool get isUsb => connectionType == AdbConnectionType.usb;
  bool get isWifi => connectionType == AdbConnectionType.wifi;

  String get displayName {
    if (model.isNotEmpty) {
      final cleanModel = model.replaceAll('_', ' ');
      return cleanModel;
    }
    if (product.isNotEmpty) {
      return product.replaceAll('_', ' ');
    }
    return id;
  }

  AdbDevice copyWith({
    String? id,
    AdbDeviceStatus? status,
    String? model,
    String? product,
    String? device,
    String? transportId,
    AdbConnectionType? connectionType,
    String? androidVersion,
    int? batteryLevel,
  }) {
    return AdbDevice(
      id: id ?? this.id,
      status: status ?? this.status,
      model: model ?? this.model,
      product: product ?? this.product,
      device: device ?? this.device,
      transportId: transportId ?? this.transportId,
      connectionType: connectionType ?? this.connectionType,
      androidVersion: androidVersion ?? this.androidVersion,
      batteryLevel: batteryLevel ?? this.batteryLevel,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status.name,
        'model': model,
        'product': product,
        'device': device,
        'transportId': transportId,
        'connectionType': connectionType.name,
        'displayName': displayName,
        'isOnline': isOnline,
        'isUsb': isUsb,
        'androidVersion': androidVersion,
        'batteryLevel': batteryLevel,
      };

  factory AdbDevice.fromAdbLine(String line) {
    final trimmed = line.trim();
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) {
      return AdbDevice(
        id: trimmed,
        status: AdbDeviceStatus.unknown,
        connectionType: AdbConnectionType.usb,
      );
    }

    final id = parts[0];
    final status = AdbDeviceStatus.fromString(parts[1]);

    String model = '';
    String product = '';
    String device = '';
    String? transportId;
    bool isUsbExplicit = false;

    for (int i = 2; i < parts.length; i++) {
      final part = parts[i];
      if (part.startsWith('model:')) {
        model = part.substring(6);
      } else if (part.startsWith('product:')) {
        product = part.substring(8);
      } else if (part.startsWith('device:')) {
        device = part.substring(7);
      } else if (part.startsWith('transport_id:')) {
        transportId = part.substring(13);
      } else if (part.startsWith('usb:')) {
        isUsbExplicit = true;
      }
    }

    AdbConnectionType connType;
    if (id.startsWith('emulator-')) {
      connType = AdbConnectionType.emulator;
    } else if (id.contains(':') && RegExp(r'^\d+\.\d+\.\d+\.\d+:\d+$').hasMatch(id)) {
      connType = AdbConnectionType.wifi;
    } else if (isUsbExplicit || !id.contains(':')) {
      connType = AdbConnectionType.usb;
    } else {
      connType = AdbConnectionType.wifi;
    }

    return AdbDevice(
      id: id,
      status: status,
      model: model,
      product: product,
      device: device,
      transportId: transportId,
      connectionType: connType,
    );
  }
}

class UsbHostInfo {
  final bool isSupported;
  final List<Map<String, dynamic>> attachedDevices;

  const UsbHostInfo({
    required this.isSupported,
    this.attachedDevices = const [],
  });

  bool get hasAttachedDevices => attachedDevices.isNotEmpty;
}
