import 'package:flutter/material.dart';

enum PeerScope { lan, pin }

enum PeerDeviceType { mobile, tablet, desktop }

/// ອຸປະກອນປາຍທາງທີ່ເຫັນໃນເຄືອຂ່າຍ.
class PeerDevice {
  final String id;
  final String name;
  final PeerDeviceType deviceType;
  final PeerScope scope;

  const PeerDevice({
    required this.id,
    required this.name,
    required this.deviceType,
    required this.scope,
  });

  factory PeerDevice.fromJson(Map<String, dynamic> json) {
    return PeerDevice(
      id: json['id'] as String,
      name: (json['name'] as String?)?.trim() ?? 'ອຸປະກອນ YonFile',
      deviceType: _parseDeviceType(json['deviceType'] as String?),
      scope: (json['scope'] as String?) == 'pin' ? PeerScope.pin : PeerScope.lan,
    );
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

  @override
  bool operator ==(Object other) => other is PeerDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
