import 'package:flutter/material.dart';

enum PeerScope { lan, pin, local }

enum PeerDeviceType { mobile, tablet, desktop }

enum PeerOperatingSystem { android, ios, macos, windows, linux, web, unknown }

/// ອຸປະກອນປາຍທາງທີ່ເຫັນໃນເຄືອຂ່າຍ.
class PeerDevice {
  final String id;
  final String name;
  final PeerDeviceType deviceType;
  final PeerOperatingSystem operatingSystem;
  final PeerScope scope;

  const PeerDevice({
    required this.id,
    required this.name,
    required this.deviceType,
    this.operatingSystem = PeerOperatingSystem.unknown,
    required this.scope,
  });

  factory PeerDevice.fromJson(Map<String, dynamic> json) {
    return PeerDevice(
      id: json['id'] as String,
      name: (json['name'] as String?)?.trim() ?? 'ອຸປະກອນ YonFile',
      deviceType: _parseDeviceType(json['deviceType'] as String?),
      operatingSystem: _parseOperatingSystem(
        json['operatingSystem'] as String?,
      ),
      scope: switch (json['scope'] as String?) {
        'pin' => PeerScope.pin,
        'local' => PeerScope.local,
        _ => PeerScope.lan,
      },
    );
  }

  static PeerOperatingSystem _parseOperatingSystem(String? value) =>
      PeerOperatingSystem.values.firstWhere(
        (system) => system.name == value,
        orElse: () => PeerOperatingSystem.unknown,
      );

  static PeerOperatingSystem fromTargetPlatform(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return PeerOperatingSystem.android;
      case TargetPlatform.iOS:
        return PeerOperatingSystem.ios;
      case TargetPlatform.macOS:
        return PeerOperatingSystem.macos;
      case TargetPlatform.windows:
        return PeerOperatingSystem.windows;
      case TargetPlatform.linux:
        return PeerOperatingSystem.linux;
      case TargetPlatform.fuchsia:
        return PeerOperatingSystem.unknown;
    }
  }

  static PeerDeviceType _parseDeviceType(String? value) {
    switch (value) {
      case 'mobile':
        return PeerDeviceType.mobile;
      case 'tablet':
        return PeerDeviceType.tablet;
      default:
        return PeerDeviceType.desktop;
    }
  }

  IconData get icon {
    switch (deviceType) {
      case PeerDeviceType.mobile:
        return Icons.smartphone_rounded;
      case PeerDeviceType.tablet:
        return Icons.tablet_mac_rounded;
      case PeerDeviceType.desktop:
        return Icons.laptop_mac_rounded;
    }
  }

  String get typeLabel {
    switch (deviceType) {
      case PeerDeviceType.mobile:
        return 'ມືຖື';
      case PeerDeviceType.tablet:
        return 'ແທັບເລັດ';
      case PeerDeviceType.desktop:
        return 'ຄອມພິວເຕີ';
    }
  }

  String get operatingSystemLabel => switch (operatingSystem) {
    PeerOperatingSystem.android => 'Android',
    PeerOperatingSystem.ios => 'iOS',
    PeerOperatingSystem.macos => 'macOS',
    PeerOperatingSystem.windows => 'Windows',
    PeerOperatingSystem.linux => 'Linux',
    PeerOperatingSystem.web => 'Web',
    PeerOperatingSystem.unknown => 'OS ບໍ່ລະບຸ',
  };

  IconData get operatingSystemIcon => switch (operatingSystem) {
    PeerOperatingSystem.android => Icons.android_rounded,
    PeerOperatingSystem.ios => Icons.phone_iphone_rounded,
    PeerOperatingSystem.macos => Icons.laptop_mac_rounded,
    PeerOperatingSystem.windows => Icons.window_rounded,
    PeerOperatingSystem.linux => Icons.terminal_rounded,
    PeerOperatingSystem.web => Icons.language_rounded,
    PeerOperatingSystem.unknown => Icons.devices_other_rounded,
  };

  @override
  bool operator ==(Object other) => other is PeerDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
