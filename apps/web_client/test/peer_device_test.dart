import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yonfile_client/models/peer_device.dart';

void main() {
  test('peer metadata exposes platform-specific labels and icons', () {
    final android = PeerDevice.fromJson({
      'id': 'android-1',
      'name': 'Android',
      'deviceType': 'mobile',
      'operatingSystem': 'android',
      'scope': 'lan',
    });
    final mac = PeerDevice.fromJson({
      'id': 'mac-1',
      'name': 'Mac',
      'deviceType': 'desktop',
      'operatingSystem': 'macos',
      'scope': 'pin',
    });

    expect(android.operatingSystemLabel, 'Android');
    expect(android.operatingSystemIcon, Icons.android_rounded);
    expect(mac.operatingSystemLabel, 'macOS');
    expect(mac.operatingSystemIcon, Icons.laptop_mac_rounded);
  });

  test('legacy peers without OS metadata get a readable fallback', () {
    final peer = PeerDevice.fromJson({
      'id': 'legacy',
      'name': 'Legacy device',
      'deviceType': 'desktop',
      'scope': 'lan',
    });

    expect(peer.operatingSystem, PeerOperatingSystem.unknown);
    expect(peer.operatingSystemLabel, 'OS ບໍ່ລະບຸ');
  });
}
